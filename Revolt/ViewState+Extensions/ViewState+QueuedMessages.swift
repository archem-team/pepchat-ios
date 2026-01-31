//
//  ViewState+QueuedMessages.swift
//  Revolt
//
//  Created by Akshat Srivastava on 31/01/26.
//

import Foundation
import Combine
import SwiftUI
import Alamofire
import ULID
import Collections
import Sentry
@preconcurrency import Types
import UserNotifications
import KeychainAccess
import Darwin
import Network

extension ViewState {
    func queueMessage(channel: String, replies: [Reply], content: String, attachments: [(Data, String)]) async {
        var queue = self.queuedMessages[channel]
        
        if queue == nil {
            queue = []
            self.queuedMessages[channel] = queue
        }
        
        let nonce = UUID().uuidString
        
        let r: [Revolt.ApiReply] = replies.map { reply in
            Revolt.ApiReply(id: reply.message.id, mention: reply.mention)
        }
        
        queue?.append(QueuedMessage(nonce: nonce, replies: r, content: content, author: currentUser?.id ?? "", channel: channel, timestamp: Date(), hasAttachments: !attachments.isEmpty, attachmentData: attachments))
        
        let _ = await http.sendMessage(channel: channel, replies: r, content: content, attachments: attachments, nonce: nonce)
    }
    
    // Function to send the queuing of messages
    func trySendingQueuedMessages() {
        print("👍🏻 Entered trySendingQueuedMessages")
        guard InternetMonitor.shared.isConnected else {
            print("❌ Not connected, aborting queue send")
            return
        }

        print("📌 queuedMessages count:", queuedMessages.count)
        
        // Get a snapshot of channels to process (avoid concurrent modification)
        let channelsToProcess = Array(queuedMessages.keys)
        
        // Process each channel sequentially with concurrency guard
        for channelId in channelsToProcess {
            // Skip if already processing this channel
            if isProcessingQueue[channelId] == true {
                print("⏭️ Skipping channel \(channelId) - already processing")
                continue
            }
            
            // Create a task for this channel to maintain message order
            Task {
                // Mark channel as being processed
                await MainActor.run {
                    self.isProcessingQueue[channelId] = true
                }
                
                defer {
                    // Always clear the processing flag when done
                    Task { @MainActor in
                        self.isProcessingQueue[channelId] = false
                    }
                }
                
                var sentCount = 0
                
                // Keep sending from the front of the queue until it's empty or send fails
                while await MainActor.run(body: { self.queuedMessages[channelId]?.isEmpty == false }) {
                    // Safely get and remove the first message atomically
                    let msg = await MainActor.run { () -> QueuedMessage? in
                        guard let first = self.queuedMessages[channelId]?.first else {
                            return nil
                        }
                        // Remove it immediately to prevent duplicate sends
                        self.queuedMessages[channelId]?.removeFirst()
                        return first
                    }
                    
                    guard let msg = msg else {
                        break
                    }
                    
                    sentCount += 1
                    print("📌 Sending queued message \(sentCount) for channel \(channelId) - nonce: \(msg.nonce)")
                    
                    do {
                        print("👍🏻 Sending message: \(msg.content)")
                        let _ = try await http.sendMessage(
                            channel: channelId,
                            replies: msg.replies,
                            content: msg.content,
                            attachments: [],
                            nonce: msg.nonce
                        ).get()
                        print("📤 Sent queued message \(sentCount) successfully - nonce: \(msg.nonce)")
                    } catch {
                        print("❌ Failed to send queued message - nonce: \(msg.nonce), error: \(error)")
                        // Re-add the message back to the front of the queue on failure
                        await MainActor.run {
                            self.queuedMessages[channelId]?.insert(msg, at: 0)
                        }
                        // Stop trying to send remaining messages in this channel if one fails
                        break
                    }
                }
                
                // Clean up empty queue entries
                await MainActor.run {
                    if self.queuedMessages[channelId]?.isEmpty == true {
                        self.queuedMessages.removeValue(forKey: channelId)
                    }
                    print("👍🏻 Finished processing channel \(channelId) - sent \(sentCount) messages")
                }
            }
        }
        print("👍🏻 Exiting trySendingQueueMessage")
    }
}
