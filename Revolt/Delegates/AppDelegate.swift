import Foundation
import SwiftUI
import Sentry
import UserNotificationsUI

#if os(macOS)
import AppKit
import UserNotifications
#endif

/// Declares notification category types, such as message notifications with custom actions (e.g., replying to messages).
///
/// This function creates and registers notification categories with actions for handling user interactions, such as replying
/// to a message directly from the notification banner. It sets up these categories with the `UNUserNotificationCenter`.
func declareNotificationCategoryTypes() {
    // Define a reply action for notifications, allowing users to reply directly from the notification.
    let replyAction = UNTextInputNotificationAction(
        identifier: "REPLY",
        title: "Reply",
        options: [.authenticationRequired],
        textInputButtonTitle: "Done",
        textInputPlaceholder: "Reply to this message..."
    )
    
    // Create a notification category for messages, which includes the reply action.
    let messageCategory = UNNotificationCategory(
        identifier: "ALERT_MESSAGE",
        actions: [replyAction],
        intentIdentifiers: [],
        options: []
    )
    
    // Register the notification category with the current notification center.
    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.setNotificationCategories([messageCategory])
}

#if os(iOS)

/// The `AppDelegate` class for iOS-specific behavior, managing app lifecycle events, notifications, and error handling.
///
/// This class conforms to `UIApplicationDelegate` and manages the app's initialization, handling of notification
/// registration, and Sentry error reporting for iOS platforms.
class AppDelegate: NSObject, UIApplicationDelegate {
    
    /// Called when the app has finished launching. It sets up notification handling and Sentry SDK.
    ///
    /// - Parameters:
    ///   - application: The `UIApplication` object that represents the app.
    ///   - launchOptions: A dictionary containing the reasons the app was launched, if available.
    /// - Returns: `true` if the app successfully launched, otherwise `false`.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Set the notification center's delegate to handle notifications within the app.
        UNUserNotificationCenter.current().delegate = self
        
        // Initialize ViewState with the application instance for app-wide state management.
        ViewState.application = application
        
        // Register the notification categories, including actions like "Reply".
        declareNotificationCategoryTypes()
        
        // Initialize audio session manager for proper audio handling
        _ = AudioSessionManager.shared
        
        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
                handleInitialNotification(notification: notification)
        }
            
        return true
    }
    
    
    private func handleInitialNotification(notification: [AnyHashable: Any]) {
        let viewState = ViewState.shared ?? ViewState()
        
            let message = notification["message"] as? [String: Any]
            let channelId = message?["channel"] as? String
            let member = message?["member"] as? [String: Any]
            let memberId = member?["_id"] as? [String: Any]
            let serverId = memberId?["server"] as? String

            if let channelId = channelId {
                let state = ViewState.shared ?? ViewState()
                state.launchNotificationChannelId = channelId
                state.launchNotificationServerId = serverId
                state.launchNotificationHandled = false
            }
        
    }
    
    /// Called when the app fails to register for remote notifications.
    ///
    /// Captures the error using Sentry for remote diagnostics. This can help track issues related to push notifications.
    ///
    /// - Parameters:
    ///   - application: The `UIApplication` object.
    ///   - error: The error that occurred while registering for remote notifications.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Check if Sentry is enabled before capturing
        if SentrySDK.isEnabled {
            SentrySDK.capture(message: "Failed to register for remote notification. Error \(error)")
        }
        print("Failed to register for remote notifications: \(error)")
        // Future implementation may include notifying the user or retrying the registration.
    }
    
    /// Called when the app successfully registers for remote notifications.
    ///
    /// This function processes the device token received from Apple Push Notification Service (APNS) and uploads it to the app's backend.
    ///
    /// - Parameters:
    ///   - application: The `UIApplication` object.
    ///   - deviceToken: The device token provided by APNS.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let state = ViewState.shared ?? ViewState()
        
        // Convert the device token to a hex string.
        let token = deviceToken.reduce("", {$0 + String(format: "%02x", $1)})
        
        debugPrint("received notification token: \(token)")

        // Store the device notification token
        state.deviceNotificationToken = token
        
        // If the app's session token is valid, upload the notification token to the backend.
        if state.http.token != nil {
            Task {
                let response = await state.http.uploadNotificationToken(token: token)
                switch response {
                    case .success:
                        debugPrint("uploading notification token")
                        // Clear any pending token on success
                        state.pendingNotificationToken = nil
                        UserDefaults.standard.removeObject(forKey: "pendingNotificationToken")
                    case .failure(let error):
                        debugPrint("******failure uploading notification token******")
                        debugPrint("Error details: \(error)")
                        // Store token for later retry
                        state.storePendingNotificationToken(token)
                }
            }
        } else {
            // Check if Sentry is enabled before capturing
            if SentrySDK.isEnabled {
                SentrySDK.capture(message: "Received notification token without available session token")
            }
            print("Received notification token without available session token")
            fatalError("Received notification token without available session token")
        }
    }
    
    // CRITICAL: Handle app going to background - ensure data is saved
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("📱 APP: Entering background - ensuring data persistence")
        
        // Get the current ViewState
        if let state = ViewState.shared {
            // Force save all important data to UserDefaults immediately
            // DISABLED: Don't cache servers and channels to force refresh from backend on app launch
            // print("💾 BACKGROUND: Saving servers (\(state.servers.count)) to UserDefaults")
            // if let serversData = try? JSONEncoder().encode(state.servers) {
            //     UserDefaults.standard.set(serversData, forKey: "servers")
            // }
            
            // print("💾 BACKGROUND: Saving channels (\(state.channels.count)) to UserDefaults")
            // if let channelsData = try? JSONEncoder().encode(state.channels) {
            //     UserDefaults.standard.set(channelsData, forKey: "channels")
            // }
            
            print("💾 BACKGROUND: Saving users (\(state.users.count)) to UserDefaults")
            if let usersData = try? JSONEncoder().encode(state.users) {
                UserDefaults.standard.set(usersData, forKey: "users")
            }
            
            // DISABLED: Don't cache members to force refresh from backend
            // print("💾 BACKGROUND: Saving members to UserDefaults")
            // if let membersData = try? JSONEncoder().encode(state.members) {
            //     UserDefaults.standard.set(membersData, forKey: "members")
            // }
            
            // DISABLED: Don't cache DMs to force refresh from backend
            // print("💾 BACKGROUND: Saving DMs (\(state.dms.count)) to UserDefaults")
            // if let dmsData = try? JSONEncoder().encode(state.dms) {
            //     UserDefaults.standard.set(dmsData, forKey: "dms")
            // }
            
            // Force synchronize UserDefaults
            UserDefaults.standard.synchronize()
            print("✅ BACKGROUND: All data saved to UserDefaults")
        }
    }
    
    // Handle app returning from background
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("📱 APP: Returning from background")
        
        // Ensure ViewState is properly initialized
        if ViewState.shared == nil {
            print("⚠️ FOREGROUND: ViewState was nil, creating new instance")
            let _ = ViewState()
        } else {
            print("✅ FOREGROUND: ViewState still exists")
        }
    }
    
    // Handle app becoming active
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("📱 APP: Became active")
        
        // Log current data state
        if let state = ViewState.shared {
            print("📊 ACTIVE: Current data state:")
            print("   - Servers: \(state.servers.count)")
            print("   - Channels: \(state.channels.count)")
            print("   - Users: \(state.users.count)")
            print("   - DMs: \(state.dms.count)")
            
            // Update app badge count to sync with internal state
            state.updateAppBadgeCount()
        }
    }
    
    // Handle app termination
    func applicationWillTerminate(_ application: UIApplication) {
        print("📱 APP: Will terminate - final save")
        
        // Force save users data immediately before termination
        if let state = ViewState.shared {
            state.forceSaveUsers()
        }
        
        // Perform final save
        applicationDidEnterBackground(application)
    }
}

#elseif os(macOS)

/// The `AppDelegate` class for macOS-specific behavior, managing app lifecycle events and notifications.
///
/// This class conforms to `NSApplicationDelegate` and manages initialization, notification handling, and error logging for macOS platforms.
class AppDelegate: NSObject, NSApplicationDelegate {
    
    /// Called when the app has finished launching on macOS. It sets up notification handling and initializes the app.
    ///
    /// - Parameter notification: The notification indicating that the app has finished launching.
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        declareNotificationCategoryTypes()  // Register notification categories.
    }

    /// Called when the app fails to register for remote notifications on macOS.
    ///
    /// Logs the error and can be extended to propagate the error to the user interface.
    ///
    /// - Parameters:
    ///   - application: The `NSApplication` object.
    ///   - error: The error that occurred during registration.
    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notification. Error \(error)")
    }

    /// Called when the app successfully registers for remote notifications on macOS.
    ///
    /// Similar to iOS, this method processes the device token and uploads it to the backend for push notification functionality.
    ///
    /// - Parameters:
    ///   - application: The `NSApplication` object.
    ///   - deviceToken: The device token provided by APNS.
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let state = ViewState.shared ?? ViewState()
        let token = deviceToken.reduce("", {$0 + String(format: "%02x", $1)})

        // Store the device notification token
        state.deviceNotificationToken = token
        
        if state.http.token != nil {
            Task {
                let response = await state.http.uploadNotificationToken(token: token)
                switch response {
                    case .success:
                        print("✅ Uploading notification token")
                        // Clear any pending token on success
                        state.pendingNotificationToken = nil
                        UserDefaults.standard.removeObject(forKey: "pendingNotificationToken")
                    case .failure(let error):
                        print("❌ Failure uploading notification token: \(error)")
                        // Store token for later retry
                        state.storePendingNotificationToken(token)
                }
            }
        } else {
            // Check if Sentry is enabled before capturing
            if SentrySDK.isEnabled {
                SentrySDK.capture(message: "Received notification token without available session token")
            }
            print("Received notification token without available session token")
            // Store token for later instead of fatal error
            state.storePendingNotificationToken(token)
        }
    }
}
#endif

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    /// Handles incoming notifications when the app is in the foreground or background, including user actions like replying.
    ///
    /// - Parameters:
    ///   - center: The `UNUserNotificationCenter` that received the notification.
    ///   - response: The user's response to the notification, which could include text input or a default tap action.
    ///   - completionHandler: The closure to call when the method finishes processing
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let state = ViewState.shared ?? ViewState()

        if state.sessionToken == nil {
            return
        }
        

        // CRITICAL FIX: Update our badge count when user interacts with notification
        // This ensures our internal calculation is used instead of server badge count
        state.updateAppBadgeCount()
        
        let userinfo = response.notification.request.content.userInfo
        let message = userinfo["message"] as? [String: Any]
        
        let channelId = message?["channel"] as? String ?? ""
        //let messageId = message?["_id"] as? String ?? ""

        let member = message?["member"] as? [String: Any]
        let memberId = member?["_id"] as? [String: Any]
        let serverId = memberId?["server"] as? String ?? ""

    
        if state.pathContainsMaybeChannelView(){
            
            DispatchQueue.main.async {
                
                withAnimation{
                    state.path =  []
                    
                    state.channelMessages[channelId] = []
                    state.atTopOfChannel.remove(channelId)

                    
                    if !serverId.isEmpty {
                        state.selectServer(withId: serverId)
                        state.selectChannel(inServer: serverId, withId: channelId)
                    } else {
                        state.selectDm(withId: channelId)
                    }
                    state.path.append(NavigationDestination.maybeChannelView)
                }
               
            }

        } else {
            
            DispatchQueue.main.async {
                
                withAnimation{
                    state.channelMessages[channelId] = []
                    state.atTopOfChannel.remove(channelId)

                    if !serverId.isEmpty {
                        state.selectServer(withId: serverId)
                        state.selectChannel(inServer: serverId, withId: channelId)
                    } else {
                        state.selectDm(withId: channelId)
                    }
                    state.path.append(NavigationDestination.maybeChannelView)
                }
                
               
            }
            
        }
        
        
        /*switch response.actionIdentifier {
        case "REPLY":
            // Handle "Reply" action by sending the user's reply to the server.
            let response = response as! UNTextInputNotificationResponse
            Task {
                await state.http.sendMessage(
                    channel: channelId,
                    replies: [ApiReply(id: messageId, mention: false)],
                    content: response.userText,
                    attachments: [],
                    nonce: ""
                )
            }
        default:
            // Handle default notification tap by navigating to the relevant channel and server.
            state.currentChannel = .channel(channelId)
            state.currentSelection = .server(serverId)
        }*/
    }
    
    /// Handles the display of notifications while the app is in the foreground.
    ///
    /// - Parameters:
    ///   - center: The `UNUserNotificationCenter` that received the notification.
    ///   - notification: The notification to be displayed.
    ///   - completionHandler: The closure to call with the desired notification presentation options.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task {
            let viewState = ViewState.shared ?? ViewState()
            
            // CRITICAL FIX: Update our own badge count when notification is received
            // This ensures our internal calculation takes precedence over server badge count
            viewState.updateAppBadgeCount()
            
            // Check if the user wants notifications even while the app is running.
            
            
            let userinfo = notification.request.content.userInfo
            let message = userinfo["message"] as? [String: Any]
            let channelId = message?["channel"] as? String ?? ""
            
                        
            if /*viewState.userSettingsStore.store.notifications.wantsNotificationsWhileAppRunning*/ viewState.shouldPerformAction(for: channelId) {
                completionHandler([.list, .banner, .sound])  // Display the notification as a banner with sound.
            } else {
                completionHandler([])  // Suppress notifications.
            }
        }
    }
    
    /// Opens notification settings when the user interacts with notification preferences.
    ///
    /// - Parameters:
    ///   - center: The `UNUserNotificationCenter` managing the notifications.
    ///   - notification: The notification for which the settings were requested (if available).
    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        print("notification settings")
        guard let notification = notification else { return }
        
        let state = ViewState.shared ?? ViewState()
        if state.sessionToken == nil {
            return
        }
        // Per-channel notification settings could be opened here.
    }
    
    
    
}
