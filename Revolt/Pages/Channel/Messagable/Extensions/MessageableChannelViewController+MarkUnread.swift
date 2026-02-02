//
//  MessageableChannelViewController+MarkUnread.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import Combine
import Kingfisher
import ObjectiveC
import SwiftUI
import Types
import UIKit
import ULID

extension MessageableChannelViewController {
    
    // Define a struct to handle retry tasks
    internal struct RetryTask {
        let messageId: String
        let channelId: String
        let retryCount: Int
        let nextRetryTime: Date
    }
    
    // MARK: - Public Methods for Mark Unread
    
    /// Temporarily disable automatic acknowledgment after marking as unread
    func disableAutoAcknowledgment() {
        print("🚫 Disabling auto-acknowledgment for \(autoAckDisableDuration) seconds")
        isAutoAckDisabled = true
        autoAckDisableTime = Date()
    }

    // Mark the last message as seen by the user - with rate limiting
    func markLastMessageAsSeen() {
        // Check if auto-acknowledgment is temporarily disabled
        if let disableTime = autoAckDisableTime {
            let now = Date()
            if now.timeIntervalSince(disableTime) < autoAckDisableDuration {
                print("🚫 Auto-acknowledgment disabled - skipping markLastMessageAsSeen")
                return
            } else {
                // Disable period has expired, re-enable auto-ack
                print("✅ Auto-acknowledgment re-enabled after disable period")
                isAutoAckDisabled = false
                autoAckDisableTime = nil
            }
        }

        // Only mark as seen if there are messages and we're not already doing it
        guard let lastMessageId = viewModel.messages.last, !isAcknowledgingMessage else {
            return
        }

        // Check if enough time has passed since last acknowledgment
        let now = Date()
        if now.timeIntervalSince(lastMessageSeenTime) < messageSeenThrottleInterval {
            // Not enough time has passed, add to retry queue instead
            let retryTime = lastMessageSeenTime.addingTimeInterval(messageSeenThrottleInterval)
            addToRetryQueue(
                messageId: lastMessageId, channelId: viewModel.channel.id, retryTime: retryTime)
            return
        }

        isAcknowledgingMessage = true
        lastMessageSeenTime = now

        Task {
            do {
                // Use the HTTP API to acknowledge the message
                _ = try await viewModel.viewState.http.ackMessage(
                    channel: viewModel.channel.id,
                    message: lastMessageId
                ).get()

                // Update local unread state if needed
                if var unread = viewModel.viewState.unreads[viewModel.channel.id] {
                    unread.last_id = lastMessageId
                    viewModel.viewState.unreads[viewModel.channel.id] = unread
                } else if let currentUserId = viewModel.viewState.currentUser?.id {
                    // Create a new unread entry if one doesn't exist
                    let unreadId = Unread.Id(channel: viewModel.channel.id, user: currentUserId)
                    viewModel.viewState.unreads[viewModel.channel.id] = Unread(
                        id: unreadId, last_id: lastMessageId)
                }

                DispatchQueue.main.async {
                    self.isAcknowledgingMessage = false
                    self.processRetryQueue()

                    // Update app badge count after acknowledging message
                    self.viewModel.viewState.updateAppBadgeCount()
                }
            } catch let error as HTTPError {
                // print("Failed to mark message as seen: \(error)")

                // Check for rate limiting
                if case .failure(429, let data) = error,
                    let retryAfter = extractRetryAfter(from: data)
                {
                    // print("Rate limited for \(retryAfter) seconds")

                    // Adjust our throttle interval based on server response
                    self.messageSeenThrottleInterval = max(
                        self.messageSeenThrottleInterval, min(Double(retryAfter), 60.0))

                    // Add to retry queue with the server's suggested delay
                    let retryTime = Date().addingTimeInterval(Double(retryAfter))
                    addToRetryQueue(
                        messageId: lastMessageId, channelId: viewModel.channel.id,
                        retryTime: retryTime)
                } else {
                    // For other errors, retry with exponential backoff
                    addToRetryQueue(
                        messageId: lastMessageId, channelId: viewModel.channel.id, retryCount: 1)
                }

                DispatchQueue.main.async {
                    self.isAcknowledgingMessage = false
                }
            } catch {
                // print("Failed to mark message as seen with unknown error: \(error)")
                DispatchQueue.main.async {
                    self.isAcknowledgingMessage = false
                }
            }
        }
    }

    // Helper method to extract retry-after value from API response
    private func extractRetryAfter(from errorData: String?) -> Int? {
        guard let data = errorData else { return nil }

        if let dataObj = try? JSONSerialization.jsonObject(with: Data(data.utf8), options: [])
            as? [String: Any],
            let retryAfter = dataObj["retry_after"] as? Int
        {
            return retryAfter
        }
        return nil
    }

    // Add a task to the retry queue
    private func addToRetryQueue(
        messageId: String, channelId: String, retryCount: Int = 0, retryTime: Date? = nil
    ) {
        // Calculate next retry time using exponential backoff if not provided
        let nextRetryTime: Date
        if let time = retryTime {
            nextRetryTime = time
        } else {
            // Exponential backoff: 2^retryCount seconds with a max of 30 seconds
            let delay = min(pow(2.0, Double(retryCount)), 30.0)
            nextRetryTime = Date().addingTimeInterval(delay)
        }

        // Add to retry queue
        let task = RetryTask(
            messageId: messageId, channelId: channelId, retryCount: retryCount,
            nextRetryTime: nextRetryTime)
        retryQueue.append(task)

        // Schedule processing of the queue
        let delay = nextRetryTime.timeIntervalSinceNow
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.processRetryQueue()
            }
        } else {
            processRetryQueue()
        }
    }

    // Process the retry queue
    private func processRetryQueue() {
        guard !isAcknowledgingMessage else { return }

        let now = Date()

        // Find tasks that are ready to be retried
        if let nextTask = retryQueue.first(where: { $0.nextRetryTime <= now }) {
            // Remove this task from the queue
            retryQueue.removeAll(where: {
                $0.messageId == nextTask.messageId && $0.channelId == nextTask.channelId
            })

            // Only retry if we're not already acknowledging and enough time has passed
            if now.timeIntervalSince(lastMessageSeenTime) >= messageSeenThrottleInterval {
                isAcknowledgingMessage = true
                lastMessageSeenTime = now

                Task {
                    do {
                        _ = try await viewModel.viewState.http.ackMessage(
                            channel: nextTask.channelId,
                            message: nextTask.messageId
                        ).get()

                        DispatchQueue.main.async {
                            self.isAcknowledgingMessage = false
                            self.processRetryQueue()  // Process the next task if any
                        }
                    } catch let error as HTTPError {
                        // print("Retry failed to mark message as seen: \(error)")

                        // Check for rate limiting
                        if case .failure(429, let data) = error,
                            let retryAfter = extractRetryAfter(from: data)
                        {
                            // print("Rate limited for \(retryAfter) seconds during retry")

                            // Adjust our throttle interval based on server response
                            self.messageSeenThrottleInterval = max(
                                self.messageSeenThrottleInterval, min(Double(retryAfter), 60.0))

                            // Add back to retry queue with server's delay
                            let retryTime = Date().addingTimeInterval(Double(retryAfter))
                            addToRetryQueue(
                                messageId: nextTask.messageId, channelId: nextTask.channelId,
                                retryCount: nextTask.retryCount + 1, retryTime: retryTime)
                        } else {
                            // For other errors, retry with increased backoff
                            addToRetryQueue(
                                messageId: nextTask.messageId, channelId: nextTask.channelId,
                                retryCount: nextTask.retryCount + 1)
                        }

                        DispatchQueue.main.async {
                            self.isAcknowledgingMessage = false
                        }
                    } catch {
                        // print("Retry failed with unknown error: \(error)")
                        DispatchQueue.main.async {
                            self.isAcknowledgingMessage = false
                        }
                    }
                }
            } else {
                // Not enough time has passed, re-add to queue with updated time
                let retryTime = lastMessageSeenTime.addingTimeInterval(messageSeenThrottleInterval)
                addToRetryQueue(
                    messageId: nextTask.messageId, channelId: nextTask.channelId,
                    retryCount: nextTask.retryCount, retryTime: retryTime)
            }
        }
    }

    
    
}
