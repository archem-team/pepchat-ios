import Foundation
import UIKit
import Types
import Combine
import Alamofire
import SwiftUI

// Define an empty struct to use as a placeholder for empty parameters
struct EmptyParameters: Encodable {}

// No need to duplicate these methods since they are already defined in MessageableChannel.swift

// Add method to load messages after a specific message ID
extension MessageableChannelViewModel {
    // Flag to track if we've already loaded nearby messages
    private static var hasLoadedNearby = false
    // Timestamp when nearby was last called
    private static var nearbyLoadTimestamp: Date?
    // Delay in seconds before allowing before/after calls
    private static let delayAfterNearby: TimeInterval = 10.0
    
    // Combined method to load messages before or after a specific message ID
    func loadMoreMessages(before: String? = nil, after: String? = nil, sort: String? = nil) async -> FetchHistory? {
        // Exit early if in preview mode
        if isPreview { return nil }
        
        // TIMING: Start measuring API call duration
        let apiStartTime = Date()
        let callType = before != nil ? "BEFORE" : (after != nil ? "AFTER" : "INITIAL")
        
        // Get the server ID from the channel
        let serverId = channel.server
        
        // Log which type of call we're making
        if before != nil {
        } else if after != nil {
        } else {
        }
        
        
        // CRITICAL: Don't include the 'messages' parameter in the API call
        // as it's causing a 500 error
        // Fetch messages from API with reduced limit for faster response
        
        let apiResult = await viewState.http.fetchHistory(
            channel: channel.id,
            limit: 100, // Reduced from 100 to 50 for faster API response
            before: before,
            after: after,
            sort: sort ?? "Latest",
            server: serverId
        )
        
        
        // TIMING: Calculate API call duration
        let apiEndTime = Date()
        let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
        
        // Check if the result is success or failure
        let result: FetchHistory
        switch apiResult {
        case .success(let fetchHistory):
            result = fetchHistory
        case .failure(let error):
            return nil
        }
        
        
        // TIMING: Start processing time
        let processingStartTime = Date()
        
        // Add message IDs for debugging
        if !result.messages.isEmpty {
            let firstMsg = result.messages.first?.id ?? "unknown"
            let lastMsg = result.messages.last?.id ?? "unknown"
        }
        
        // Process all users from the response
        for user in result.users {
            viewState.users[user.id] = user
            // CRITICAL FIX: Also store in event users for permanent access
            viewState.allEventUsers[user.id] = user
        }
        
        // Process members if present
        if let members = result.members {
            for member in members {
                viewState.members[member.id.server, default: [:]][member.id.user] = member
            }
        }
        
        // Process messages
        for message in result.messages {
            viewState.messages[message.id] = message
            
            // CRITICAL FIX: Ensure message author is in users dictionary to prevent black messages
            if viewState.users[message.author] == nil {
                // Try to get from allEventUsers first
                if let storedUser = viewState.allEventUsers[message.author] {
                    viewState.users[message.author] = storedUser
                } else {
                    // Create placeholder user as last resort
                    let placeholderUser = Types.User(
                        id: message.author,
                        username: "Unknown User",
                        discriminator: "0000",
                        relationship: .None
                    )
                    viewState.users[message.author] = placeholderUser
                    viewState.allEventUsers[message.author] = placeholderUser
                }
            }
        }
        
        // CRITICAL FIX: After processing all messages, ensure ALL message authors are available
        for message in result.messages {
            if viewState.users[message.author] == nil {
                
                // Force creation of placeholder
                let emergencyPlaceholder = Types.User(
                    id: message.author,
                    username: "Loading...",
                    discriminator: "0000",
                    relationship: .None
                )
                viewState.users[message.author] = emergencyPlaceholder
                viewState.allEventUsers[message.author] = emergencyPlaceholder
            }
        }
        
        // Get the message IDs in the correct order
        let resultMessageIds = result.messages.map { $0.id }
        
        // Create a local copy of the sorted IDs to avoid direct reference issues
        var finalMessageIds: [String] = []
        
        // Update viewState and viewModel on the main thread to ensure thread safety
        await MainActor.run {
            if let after = after {
                // When loading newer messages (after), insert them at the beginning (newest-first order)
                var currentMessages = viewState.channelMessages[channel.id] ?? []
                
                // For each message in reverse order, insert at beginning if not already present
                for message in result.messages.reversed() {
                    if !currentMessages.contains(message.id) {
                        currentMessages.insert(message.id, at: 0)
                    }
                }
                
                // Update channel messages in viewState
                viewState.channelMessages[channel.id] = currentMessages
                
                // CRITICAL: Create a new explicit copy of the array to ensure value semantics
                finalMessageIds = Array(currentMessages)
                
                // CRITICAL: Update our local messages array to match
                self.messages = finalMessageIds
            } else {
                // When loading older messages (before) or initial messages
                
                // If we're loading older messages (before), put them at the beginning
                if before != nil && !resultMessageIds.isEmpty {
                    var existingMessages = viewState.channelMessages[channel.id] ?? []
                    
                    // Log the first few message IDs from API
                    if !resultMessageIds.isEmpty {
                        let firstFew = Array(resultMessageIds.prefix(min(3, resultMessageIds.count)))
                        
                        // Also log what we're requesting before
                        if let beforeId = before {
                            if let beforeIndex = existingMessages.firstIndex(of: beforeId) {
                            }
                        }
                    }
                    
                    // CRITICAL: Filter out duplicates before adding
                    let existingSet = Set(existingMessages)
                    let newUniqueMessages = resultMessageIds.filter { !existingSet.contains($0) }
                    
                    
                    // Declare updatedMessages before the if block so it's available later
                    var updatedMessages = existingMessages
                    
                    if !newUniqueMessages.isEmpty {
                        // Add new older messages to the end (API returns in Latest order, which matches our array)
                        updatedMessages = existingMessages + newUniqueMessages
                        viewState.channelMessages[channel.id] = updatedMessages
                    } else {
                        // Don't update the array if there are no new messages - keep existing
                    }
                    
                    // CRITICAL: Create a new explicit copy of the array to ensure value semantics
                    finalMessageIds = Array(updatedMessages)
                    
                    // CRITICAL: Update our local messages array to match viewState
                    self.messages = finalMessageIds
                } else {
                    // Initial load (both before and after are nil)
                    // Sort messages by timestamp to ensure reverse chronological order (newest first)
                    let sortedMessages = result.messages.sorted { msg1, msg2 in
                        let date1 = createdAt(id: msg1.id)
                        let date2 = createdAt(id: msg2.id)
                        return date1 > date2
                    }
                    
                    // Get IDs in sorted order
                    let sortedIds = sortedMessages.map { $0.id }
                    
                    // Update viewState
                    viewState.channelMessages[channel.id] = sortedIds
                    
                    // CRITICAL: Create a new explicit copy of the array to ensure value semantics
                    finalMessageIds = Array(sortedIds)
                    
                    // CRITICAL: Update our local messages array to match viewState with explicit assignment
                    self.messages = finalMessageIds
                }
            }
            
            // Double-check after assignment that messages are actually set
            if self.messages.isEmpty && !finalMessageIds.isEmpty {
                self.messages = Array(finalMessageIds)
            }
            
            // Notify that messages have changed
            self.notifyMessagesDidChange()
        }
        
        // TIMING: Calculate processing duration
        let processingEndTime = Date()
        let processingDuration = processingEndTime.timeIntervalSince(processingStartTime)
        
        // TIMING: Calculate total duration
        let totalDuration = processingEndTime.timeIntervalSince(apiStartTime)
        
        // Return the result for caller to use
        return result
    }
    
    // NOTE: createdAt(id:) and ULID struct moved to MessageableChannelViewModel+DataLoading.swift
    
    // Method to reset the nearby loading flag when navigating to a new channel
    func resetNearbyLoadingFlag() {
        MessageableChannelViewModel.hasLoadedNearby = false
        MessageableChannelViewModel.nearbyLoadTimestamp = nil
    }

    // Add debug helper to sync messages with viewState
    func syncMessagesWithViewState() {
        // Debug print for messages count
        
        // Make sure the channelMessages in viewState is synced with our local messages
        if messages.count > 0 {
            viewState.channelMessages[channel.id] = messages
        }
        
        // Call the existing notification method
        notifyMessagesDidChange()
    }

    func notifyMessagesDidChange() {
        NotificationCenter.default.post(name: NSNotification.Name("MessagesDidChange"), object: self)
    }
//    
    // New method to force synchronization between viewState and viewModel messages
    @MainActor
    func forceMessagesSynchronization() {
        // Get channel messages from viewState
        if let channelMessages = viewState.channelMessages[channel.id] {
            // Check if we actually need to synchronize
            if messages.count != channelMessages.count || messages != channelMessages {
                
                // Create a completely new array to avoid any reference issues
                let forcedCopy = Array(channelMessages)
                
                // Force assign directly to messages with self to ensure property setter is called
                self.messages = forcedCopy
                
                
                // Notify observers of the change
                notifyMessagesDidChange()
            } else {
            }
        } else if !messages.isEmpty {
            // If viewState has no messages but viewModel does, update viewState
            viewState.channelMessages[channel.id] = Array(messages)
        }
    }

    // Helper method to get member by userId
    func getMember(userId: String) -> Binding<Member?> {
        guard let server = server else {
            return .constant(nil)
        }
        
        return Binding(
            get: { self.viewState.members[server.id]?[userId] },
            set: { newValue in
                if let newValue = newValue {
                    self.viewState.members[server.id, default: [:]][userId] = newValue
                } else {
                    self.viewState.members[server.id]?.removeValue(forKey: userId)
                }
            }
        )
    }
    
    // MARK: - Reactive Data Loading
    // Data loading methods moved to MessageableChannelViewModel+DataLoading.swift
}
