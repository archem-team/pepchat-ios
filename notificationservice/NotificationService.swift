//
//  NotificationService.swift
//  NotificationService
//
//  Created by Angelo Manca on 2024-07-12.
//

import UserNotifications
import os
import Intents
import Types

// Logger for debugging and tracing within the notification service
let logger = Logger(subsystem: "app.peptide.chat", category: "notificationd")

/**
 Retrieves a `INSendMessageIntent` based on the push notification content.

 This method attempts to extract message information from the notification's `userInfo`, then builds and returns a `INSendMessageIntent` that can be used to create actionable notifications with Siri integration.

 - Parameter notification: The content of the notification from which the message intent will be extracted.
 - Returns: An optional `INSendMessageIntent` if the message can be properly decoded and parsed from the notification content.
 */
func getMessageIntent(_ notification: UNNotificationContent) -> INSendMessageIntent? {
    let info = notification.userInfo
    
    // Serialize notification user info to JSON for decoding into the Message model
    let data = try? JSONSerialization.data(withJSONObject: info["message"] as Any, options: [])
    guard let data = data else { return nil }
    
    // Decode JSON data into the Message model
    let message = try? JSONDecoder().decode(Message.self, from: data)
    guard let message = message else { return nil }
    
    #if DEBUG
    debugPrint(message)
    #endif
    
    // Construct sender and group/channel information
    let name: String
    if let authorDisplayName = info["authorDisplayName"] as? String, let channelName = info["channelName"] as? String {
        name = "\(authorDisplayName) (\(channelName))"
    } else {
        name = info["authorDisplayName"] as? String ?? "Unknown User"
    }
    
    // Build sender details using INPersonHandle and INPerson
    let handle = INPersonHandle(value: message.author, type: .unknown)
    let avatar = INImage(url: URL(string: info["authorAvatar"] as! String)!)
    let sender = INPerson(
        personHandle: handle,
        nameComponents: nil,
        displayName: info["authorDisplayName"] as? String,
        image: avatar,
        contactIdentifier: nil,
        customIdentifier: nil
    )
    
    // Build group name for conversations
    var speakableGroupName: INSpeakableString? = nil
    if let groupName = info["channelName"] as? String {
        speakableGroupName = INSpeakableString(spokenPhrase: groupName)
    }
    
    let displayedAttachment: INSendMessageAttachment? = nil
    
    if let attachments = message.attachments {
        // TODO: Implement attachment handling by retrieving instance config and generating URLs.
    }
    
    var content = message.content
    
    // Construct the message intent
    let intent = INSendMessageIntent(
        recipients: nil,
        outgoingMessageType: .outgoingMessageText,
        content: content,
        speakableGroupName: speakableGroupName,
        conversationIdentifier: message.channel,
        serviceName: nil,
        sender: sender,
        attachments: (displayedAttachment != nil) ? [displayedAttachment!] : nil
    )
        
    // TODO: Set custom avatars for direct message groups if applicable.
    
    return intent
}

func loadSharedUsers() -> [String: User]? {
    guard let sharedURL = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.pepchat.shared.data")?
        .appendingPathComponent("users.json") else {
        print("❌ Shared container not found")
        return nil
    }

    guard let data = try? Data(contentsOf: sharedURL) else {
        print("❌ No users.json found")
        return nil
    }

    return try? JSONDecoder().decode([String: User].self, from: data)
}

// NotificationService class handles push notification modification
class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    /**
     Handles the reception of the notification and modifies its content if necessary.

     This method is invoked when a push notification is received. If the notification belongs to the "ALERT_MESSAGE" category, the content is modified to display message-specific details. It also integrates with SiriKit by donating the `INSendMessageIntent`.

     - Parameters:
        - request: The notification request that triggered the service extension.
        - contentHandler: A closure to modify and return the notification content.
     */
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        #if DEBUG
        logger.trace("Invoked service extension")
        debugPrint(request)
        #endif
        
        print("🔔 Notification badge from server: \(request.content.badge?.intValue ?? -1)")
        
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        // Proceed if mutable notification content is available
        if let bestAttemptContent = bestAttemptContent {
            // Handle only messages categorized as "ALERT_MESSAGE"
            if request.content.categoryIdentifier != "ALERT_MESSAGE" {
                #if DEBUG
                logger.debug("Received non-alert-message with category: \(request.content.categoryIdentifier)")
                #endif
                
                // CRITICAL FIX: Set badge to 0 for non-alert messages too
                bestAttemptContent.setValue(NSNumber(value: 0), forKey: "badge")
                
                contentHandler(bestAttemptContent)
                return
            }
            
            // Generate a message intent using the notification content
            let intent = getMessageIntent(request.content)
            guard let intent = intent else {
                #if DEBUG
                logger.debug("Failed to retrieve message intent.")
                #endif
                
                // CRITICAL FIX: Set badge to 0 even when intent fails
                bestAttemptContent.setValue(NSNumber(value: 0), forKey: "badge")
                
                contentHandler(bestAttemptContent)
                return
            }
            
            // Donate the interaction to Siri for actionable notifications
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming
            
            do {
                // Donate the intent and update the notification content
                try interaction.donate()
                
                let originalTitle = bestAttemptContent.title
                let updated = try bestAttemptContent.updating(from: intent)
                updated.setValue(originalTitle, forKey: "title") // Preserve original title
                
                // CRITICAL FIX: Set badge to 0 to let app handle it internally
                // This prevents the server's badge count from overriding our internal calculation
                updated.setValue(NSNumber(value: 0), forKey: "badge")
                print("🔔 Set notification badge to 0 (was: \(request.content.badge?.intValue ?? -1))")
                
                contentHandler(updated)
                
            } catch {
                // Log any error that occurs and return the original notification content
                logger.error("\(error.localizedDescription)")
                bestAttemptContent.subtitle = error.localizedDescription
                
                // CRITICAL FIX: Set badge to 0 even in error case
                bestAttemptContent.setValue(NSNumber(value: 0), forKey: "badge")
                
                contentHandler(bestAttemptContent)
                return
            }
        }
    }
    
    /**
     This method is called when the system is about to terminate the extension.

     Use this method to ensure that the best attempt content is delivered if the service is running out of time.

     - If the system does not terminate the extension before this method is called, the original push payload will be used.
     */
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension is terminated by the system.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    // Called to load the users
    func loadSharedUsers() -> [String: User]? {
        guard let sharedURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.pepchat.shared.data")?
            .appendingPathComponent("users.json") else {
            print("❌ Shared container not found")
            return nil
        }

        guard let data = try? Data(contentsOf: sharedURL) else {
            print("❌ No users.json found")
            return nil
        }

        return try? JSONDecoder().decode([String: User].self, from: data)
    }
}
