//
//  MessageableChannelViewController+Utilities.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//

import UIKit
import Types

// MARK: - Utility Methods
extension MessageableChannelViewController {
    /// Shows an error alert to the user
    func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    /// Public accessor for ViewState to be used by ReplyItemView
    func getViewState() -> ViewState {
        return viewModel.viewState
    }
    
    /// Temporarily disable automatic acknowledgment after marking as unread
    func disableAutoAcknowledgment() {
        print("🚫 Disabling auto-acknowledgment for \(autoAckDisableDuration) seconds")
        isAutoAckDisabled = true
        autoAckDisableTime = Date()
    }
    
    /// Mark the last message as seen by the user - with rate limiting
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
            addToRetryQueue(messageId: lastMessageId, channelId: viewModel.channel.id, retryTime: retryTime)
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
                    viewModel.viewState.unreads[viewModel.channel.id] = Unread(id: unreadId, last_id: lastMessageId)
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
                if case .failure(429, let data) = error, let retryAfter = extractRetryAfter(from: data) {
                    // print("Rate limited for \(retryAfter) seconds")
                    
                    // Adjust our throttle interval based on server response
                    self.messageSeenThrottleInterval = max(self.messageSeenThrottleInterval, min(Double(retryAfter), 60.0))
                    
                    // Add to retry queue with the server's suggested delay
                    let retryTime = Date().addingTimeInterval(Double(retryAfter))
                    addToRetryQueue(messageId: lastMessageId, channelId: viewModel.channel.id, retryTime: retryTime)
                } else {
                    // For other errors, retry with exponential backoff
                    addToRetryQueue(messageId: lastMessageId, channelId: viewModel.channel.id, retryCount: 1)
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
    
    /// Reset loading state if it appears to be stuck
    func resetLoadingStateIfNeeded() {
        // Get time since last load attempt
        let now = Date()
        let timeSinceLastLoad = now.timeIntervalSince(lastSuccessfulLoadTime)
        
        // If loading state is stuck for more than 10 seconds, reset it
        if isLoadingMore && timeSinceLastLoad > 10.0 {
            // print("⚠️ Loading state appears to be stuck for \(Int(timeSinceLastLoad)) seconds - resetting")
            isLoadingMore = false
            messageLoadingState = .notLoading
            lastSuccessfulLoadTime = now
        }
        
        // Also check for inconsistency between isLoadingMore and messageLoadingState
        if isLoadingMore && messageLoadingState == .notLoading {
            // print("⚠️ Loading state inconsistency detected - isLoadingMore is true but messageLoadingState is notLoading")
            isLoadingMore = false
        }
    }
    
    /// Extract retry-after value from error data
    func extractRetryAfterValue(from errorData: String?) -> Int? {
        guard let data = errorData else { return nil }
        
        do {
            // Try to parse the error data as JSON
            if let dataObj = try JSONSerialization.jsonObject(with: Data(data.utf8), options: []) as? [String: Any],
               let retryAfter = dataObj["retry_after"] as? Int {
                // print("📊 Extracted retry_after: \(retryAfter)")
                return retryAfter
            }
        } catch {
            // print("❌ Error parsing JSON from error data: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Private Helper Methods
    
    /// Helper method to extract retry-after value from API response
    func extractRetryAfter(from errorData: String?) -> Int? {
        guard let data = errorData else { return nil }
        
        if let dataObj = try? JSONSerialization.jsonObject(with: Data(data.utf8), options: []) as? [String: Any],
           let retryAfter = dataObj["retry_after"] as? Int {
            return retryAfter
        }
        return nil
    }
}
