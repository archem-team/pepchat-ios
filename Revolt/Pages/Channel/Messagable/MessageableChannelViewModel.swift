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
    
    nonisolated private static func cacheTrace(_ message: String) {
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        print("CACHE_TRACE t=\(timestamp) \(message)")
    }

    // Combined method to load messages before or after a specific message ID
    func loadMoreMessages(before: String? = nil, after: String? = nil, sort: String? = nil) async -> FetchHistory? {
        // Exit early if in preview mode
        if isPreview { return nil }
        Self.cacheTrace("loadMoreMessages enter channel=\(channel.id) before=\(before ?? "nil") after=\(after ?? "nil") sort=\(sort ?? "Latest")")
        
        // TIMING: Start measuring API call duration
        let apiStartTime = Date()
        let callType = before != nil ? "BEFORE" : (after != nil ? "AFTER" : "INITIAL")
        // print("⏱️ API_CALL_START [\(callType)]: \(apiStartTime.timeIntervalSince1970)")
        
        // Get the server ID from the channel
        let serverId = channel.server
        
        // Log which type of call we're making
        if before != nil {
            // print("🧠 VIEW_MODEL: Making BEFORE API call for messageId=\(before!)")
        } else if after != nil {
            // print("🧠 VIEW_MODEL: Making AFTER API call for messageId=\(after!)")
        } else {
            // print("🧠 VIEW_MODEL: Making INITIAL API call (no before/after)")
        }
        
        // print("🧠 VIEW_MODEL: Loading messages from API")
        // print("   - Channel ID: \(channel.id)")
        // print("   - Before: \(before ?? "nil")")
        // print("   - After: \(after ?? "nil")")
        // print("   - Sort: \(sort ?? "Latest")")
        
        // CRITICAL: Don't include the 'messages' parameter in the API call
        // as it's causing a 500 error
        // Fetch messages from API with reduced limit for faster response
        let result = try? await viewState.http.fetchHistory(
            channel: channel.id,
            limit: 10, // Reduced from 100 to 50 for faster API response
            before: before,
            after: after,
            sort: sort ?? "Latest",
            server: serverId
        ).get()
        
        // TIMING: Calculate API call duration
        let apiEndTime = Date()
        let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
        // print("⏱️ API_CALL_END [\(callType)]: \(apiEndTime.timeIntervalSince1970)")
        // print("⏱️ API_CALL_DURATION [\(callType)]: \(String(format: "%.2f", apiDuration)) seconds")
        
        // Early return if we didn't get a result
        guard let result = result else {
            Self.cacheTrace("loadMoreMessages - API returned nil, cannot cache")
            // print("❌ VIEW_MODEL: API request failed or returned nil after \(String(format: "%.2f", apiDuration))s")
            return nil
        }
        
        Self.cacheTrace("loadMoreMessages - Got result with \(result.messages.count) messages, proceeding to cache")
        
        // print("✅ VIEW_MODEL: Received \(result.messages.count) messages from API in \(String(format: "%.2f", apiDuration))s")
        Self.cacheTrace("loadMoreMessages - Got result with \(result.messages.count) messages, proceeding to process")
        
        // TIMING: Start processing time
        let processingStartTime = Date()
        // print("⏱️ PROCESSING_START [\(callType)]: \(processingStartTime.timeIntervalSince1970)")
        
        // Add message IDs for debugging
        if !result.messages.isEmpty {
            let firstMsg = result.messages.first?.id ?? "unknown"
            let lastMsg = result.messages.last?.id ?? "unknown"
            // print("📝 VIEW_MODEL: Message range from \(firstMsg) to \(lastMsg)")
        }
        
        // Process all users from the response
        // print("📥 LOADING_USERS: Processing \(result.users.count) users from fetchHistory response")
        for user in result.users {
            viewState.users[user.id] = user
            // CRITICAL FIX: Also store in event users for permanent access
            viewState.allEventUsers[user.id] = user
            // print("📥 LOADING_USERS: Added user \(user.username) (ID: \(user.id)) to both users and allEventUsers")
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
                    // print("📥 MESSAGE_AUTHOR: Restored author \(storedUser.username) from allEventUsers for message \(message.id)")
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
                    // print("⚠️ MESSAGE_AUTHOR: Created placeholder for missing author \(message.author) of message \(message.id)")
                }
            }
        }
        
        // CRITICAL FIX: After processing all messages, ensure ALL message authors are available
        // print("🔄 FINAL_CHECK: Ensuring all \(result.messages.count) message authors are in users dictionary")
        for message in result.messages {
            if viewState.users[message.author] == nil {
                // print("🚨 MISSING_USER: Found missing user \(message.author) for message \(message.id) after processing!")
                
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
                // When loading newer messages (after), append them to the end
                var currentMessages = viewState.channelMessages[channel.id] ?? []
                
                // For each message, add it if not already present
                for message in result.messages {
                    if !currentMessages.contains(message.id) {
                        currentMessages.append(message.id)
                    }
                }
                
                // Update channel messages in viewState
                viewState.channelMessages[channel.id] = currentMessages
                
                // CRITICAL: Create a new explicit copy of the array to ensure value semantics
                finalMessageIds = Array(currentMessages)
                
                // CRITICAL: Update our local messages array to match
                self.messages = finalMessageIds
                // print("✅ VIEW_MODEL: Messages updated (after)")
                // print("   - ViewState messages count: \(currentMessages.count)")
                // print("   - Final IDs count: \(finalMessageIds.count)")
                // print("   - ViewModel messages count: \(self.messages.count)")
                // print("   - Are ViewModel and final IDs identical: \(self.messages == finalMessageIds)")
            } else {
                // When loading older messages (before) or initial messages
                
                // If we're loading older messages (before), put them at the beginning
                if before != nil && !resultMessageIds.isEmpty {
                    var existingMessages = viewState.channelMessages[channel.id] ?? []
                    // print("📊 VIEW_MODEL: Current existingMessages: \(existingMessages.count), new messages: \(resultMessageIds.count)")
                    
                    // Create a reversed copy for better logging
                    let reversedNewMessages = resultMessageIds.reversed()
                    
                    // Log the first few message IDs
                    if !reversedNewMessages.isEmpty {
                        let firstFew = Array(reversedNewMessages.prefix(min(3, reversedNewMessages.count)))
                        // print("📊 VIEW_MODEL: Adding these messages at beginning: \(firstFew)")
                    }
                    
                    // Add new messages before existing ones (but reverse them for chronological order)
                    let updatedMessages = reversedNewMessages + existingMessages
                    viewState.channelMessages[channel.id] = updatedMessages
                    
                    // CRITICAL: Create a new explicit copy of the array to ensure value semantics
                    finalMessageIds = Array(updatedMessages)
                    
                    // CRITICAL: Update our local messages array to match viewState
                    self.messages = finalMessageIds
                    // print("✅ VIEW_MODEL: Messages updated (before)")
                    // print("   - ViewState messages count: \(updatedMessages.count)")
                    // print("   - Final IDs count: \(finalMessageIds.count)")
                    // print("   - ViewModel messages count: \(self.messages.count)")
                    // print("   - Are ViewModel and final IDs identical: \(self.messages == finalMessageIds)")
                } else {
                    // Initial load (both before and after are nil)
                    // Sort messages by timestamp to ensure correct order
                    let sortedMessages = result.messages.sorted { msg1, msg2 in
                        let date1 = createdAt(id: msg1.id)
                        let date2 = createdAt(id: msg2.id)
                        return date1 < date2
                    }
                    
                    // Get IDs in sorted order
                    let sortedIds = sortedMessages.map { $0.id }
                    
                    // Update viewState
                    viewState.channelMessages[channel.id] = sortedIds
                    
                    // CRITICAL: Create a new explicit copy of the array to ensure value semantics
                    finalMessageIds = Array(sortedIds)
                    
                    // CRITICAL: Update our local messages array to match viewState with explicit assignment
                    self.messages = finalMessageIds
                    // print("✅ VIEW_MODEL: Messages updated (initial)")
                    // print("   - ViewState messages count: \(sortedIds.count)")
                    // print("   - Final IDs count: \(finalMessageIds.count)")
                    // print("   - ViewModel messages count: \(self.messages.count)")
                    // print("   - Are ViewModel and final IDs identical: \(self.messages == finalMessageIds)")
                }
            }
            
            // Double-check after assignment that messages are actually set
            if self.messages.isEmpty && !finalMessageIds.isEmpty {
                // print("⚠️ WARNING: Messages array is still empty after assignment! Forcing direct array copy...")
                self.messages = Array(finalMessageIds)
            }
            
            // Notify that messages have changed
            self.notifyMessagesDidChange()
        }
        
        // TIMING: Calculate processing duration
        let processingEndTime = Date()
        let processingDuration = processingEndTime.timeIntervalSince(processingStartTime)
        // print("⏱️ PROCESSING_END [\(callType)]: \(processingEndTime.timeIntervalSince1970)")
        // print("⏱️ PROCESSING_DURATION [\(callType)]: \(String(format: "%.2f", processingDuration)) seconds")
        
        // TIMING: Calculate total duration
        let totalDuration = processingEndTime.timeIntervalSince(apiStartTime)
        // print("⏱️ TOTAL_DURATION [\(callType)]: \(String(format: "%.2f", totalDuration)) seconds")
        // print("⏱️ BREAKDOWN [\(callType)]: API=\(String(format: "%.2f", apiDuration))s, Processing=\(String(format: "%.2f", processingDuration))s")
        
        Self.cacheTrace("loadMoreMessages - Finished processing, about to cache messages")
        
        // MARK: - Cache Messages After API Response
        // Cache messages and users in background (non-blocking)
        // Capture values before detached task to avoid main actor isolation issues
        Self.cacheTrace("About to check cache params - userId=\(viewState.currentUser?.id ?? "nil") baseURL=\(viewState.baseURL ?? "nil")")
        
        guard let userId = viewState.currentUser?.id,
              let baseURL = viewState.baseURL else {
            Self.cacheTrace("cache skip in loadMoreMessages channel=\(channel.id) userId=\(viewState.currentUser?.id ?? "nil") baseURL=\(viewState.baseURL ?? "nil")")
            // Return early if we don't have required values
            return result
        }
        
        let channelId = channel.id
        let messagesToCache = result.messages
        let usersToCache = result.users
        Self.cacheTrace("Creating Task.detached to cache \(messagesToCache.count) messages for channel \(channelId)")
        
        Task.detached {
            MessageableChannelViewModel.cacheTrace("Task.detached started for channel \(channelId)")
            // Determine if this response includes newest messages (for last_message_id update)
            // Only update when initial/latest fetch (no before/after) or when fetching with 'after' (newer messages)
            // DO NOT update when fetching with 'before' (older messages) or 'nearby' (may not include newest)
            let shouldUpdateLastMessageId = (before == nil && after == nil) || (after != nil)
            
            let serverLastMessageId = shouldUpdateLastMessageId ? messagesToCache.map({ $0.id }).max() : nil
            MessageableChannelViewModel.cacheTrace("cacheMessagesAndUsers call channel=\(channelId) messages=\(messagesToCache.count) users=\(usersToCache.count) shouldUpdateLastMessageId=\(shouldUpdateLastMessageId)")
            MessageCacheManager.shared.cacheMessagesAndUsers(
                messagesToCache,
                users: usersToCache,
                channelId: channelId,
                userId: userId,
                baseURL: baseURL,
                lastMessageId: serverLastMessageId
            )
            MessageableChannelViewModel.cacheTrace("Task.detached completed for channel \(channelId)")
        }
        
        Self.cacheTrace("Task.detached created (fire-and-forget) for channel \(channelId)")
        
        // Return the result for caller to use
        return result
    }
    
    // Helper function to get created timestamp from message ID
    internal func createdAt(id: String) -> Date {
        // Try ULID first (what Revolt uses)
        if let ulid = ULID(ulidString: id) {
            return ulid.timestamp
        }
        
        // Fallback to Snowflake ID parsing
        // Snowflake IDs are 64-bit integers where the first 42 bits are timestamp
        if let snowflakeId = UInt64(id) {
            let timestamp = (snowflakeId >> 22) + 1420070400000 // Discord epoch
            return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        }
        
        // If all else fails, return current date
        return Date()
    }
    
    // Simple ULID structure to handle message timestamp conversion
    private struct ULID {
        let value: String
        let timestamp: Date
        
        init?(ulidString: String) {
            guard ulidString.count == 26 else { return nil }
            self.value = ulidString
            
            // ULIDs have timestamp in the first 10 characters (48 bits in base32)
            let timestampPart = String(ulidString.prefix(10))
            
            // Convert base32 timestamp to milliseconds since epoch
            if let timestampMillis = ULID.decodeBase32(timestampPart) {
                self.timestamp = Date(timeIntervalSince1970: Double(timestampMillis) / 1000.0)
            } else {
                self.timestamp = Date()
            }
        }
        
        // Simplified base32 decoder for ULIDs
        static func decodeBase32(_ value: String) -> UInt64? {
            let base32Chars = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
            var result: UInt64 = 0
            
            for char in value.uppercased() {
                if let value = base32Chars.firstIndex(of: char) {
                    let index = base32Chars.distance(from: base32Chars.startIndex, to: value)
                    result = result * 32 + UInt64(index)
                } else {
                    return nil
                }
            }
            
            return result
        }
    }
    
    // Method to reset the nearby loading flag when navigating to a new channel
    func resetNearbyLoadingFlag() {
        MessageableChannelViewModel.hasLoadedNearby = false
        MessageableChannelViewModel.nearbyLoadTimestamp = nil
        // print("🔄 Reset nearby loading flag for new channel navigation")
    }

    // Add debug helper to sync messages with viewState
    func syncMessagesWithViewState() {
        // Debug print for messages count
        // print("🔄 Syncing messages with viewState, messages count: \(messages.count)")
        
        // Make sure the channelMessages in viewState is synced with our local messages
        if messages.count > 0 {
            viewState.channelMessages[channel.id] = messages
            // print("📋 Synced with viewState.channelMessages[\(channel.id)]")
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
                // print("🔄 FORCE SYNC: Detected mismatch between viewModel messages and viewState")
                // print("   - viewModel.messages count: \(messages.count)")
                // print("   - viewState.channelMessages[\(channel.id)] count: \(channelMessages.count)")
                
                // Create a completely new array to avoid any reference issues
                let forcedCopy = Array(channelMessages)
                
                // Force assign directly to messages with self to ensure property setter is called
                self.messages = forcedCopy
                
                // print("✅ FORCE SYNC: Completed synchronization")
                // print("   - Now viewModel messages count: \(messages.count)")
                
                // Notify observers of the change
                notifyMessagesDidChange()
            } else {
                // print("✓ Messages already in sync. No action needed.")
            }
        } else if !messages.isEmpty {
            // If viewState has no messages but viewModel does, update viewState
            // print("🔄 FORCE SYNC: viewState has no messages but viewModel does. Updating viewState.")
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
}
