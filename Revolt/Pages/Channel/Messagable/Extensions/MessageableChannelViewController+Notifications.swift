//
//  MessageableChannelViewController+Notifications.swift
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
    // Update handleNewMessages to only scroll if user is near bottom
    @objc internal func handleNewMessages(_ notification: Notification) {
        // CRITICAL FIX: Don't handle new messages during nearby loading
        if messageLoadingState == .loading {
            print("📬 BLOCKED: handleNewMessages blocked - nearby loading in progress")
            return
        }

        // CRITICAL FIX: Don't handle if target message protection is active
        if targetMessageProtectionActive {
            print("📬 BLOCKED: handleNewMessages blocked - target message protection active")
            return
        }

        let currentMessageCount = viewModel.messages.count
        let storedMessageCount = UserDefaults.standard.integer(
            forKey: "LastMessageCount_\(viewModel.channel.id)")

        // Only scroll if there are actual new messages
        if currentMessageCount > storedMessageCount {
            // print("📬 Direct notification of new messages - found \(currentMessageCount - storedMessageCount) new messages")
            // Update stored count
            UserDefaults.standard.set(
                currentMessageCount, forKey: "LastMessageCount_\(viewModel.channel.id)")

            // Check if user has manually scrolled up recently
            let hasManuallyScrolledUp =
                lastManualScrollUpTime != nil
                && Date().timeIntervalSince(lastManualScrollUpTime!) < 10.0

            // COMPREHENSIVE TARGET MESSAGE PROTECTION
            // Only scroll if user is near bottom AND hasn't manually scrolled up recently AND no target message protection
            if isUserNearBottom() && !hasManuallyScrolledUp && !targetMessageProtectionActive {
                // First scroll immediately
                scrollToBottom(animated: true)
                // Then schedule multiple scrolls with delays to ensure we catch the UI update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.scrollToBottom(animated: true)
                    // One more scroll after a bit longer delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.scrollToBottom(animated: false)
                    }
                }
            } else {
                // print("👆 User is not near bottom or has manually scrolled up, not auto-scrolling")
                // Do NOT show new message button here anymore
                // showNewMessageButton() // <-- REMOVE THIS LINE
            }
        } else {
            // print("📬 Message notification received but no new messages found. Ignoring scroll request.")
        }
    }
    
    // Add new method to handle network errors
    @objc internal func handleNetworkError(_ notification: Notification) {
        // print("⚠️ Network error detected, preventing automatic scrolls for 5 seconds")

        // Temporarily increase the debounce time after network error
        let errorDebounceTime = Date().addingTimeInterval(5.0)
        lastScrollToBottomTime = errorDebounceTime

        // Block new message notifications from causing scrolls for a while
        UserDefaults.standard.set(
            viewModel.messages.count, forKey: "LastMessageCount_\(viewModel.channel.id)")
    }
    
    // Handle channel search closed to detect returning from search
    @objc internal func handleChannelSearchClosed(_ notification: Notification) {
        // Check if the notification is for this channel
        guard let channelId = notification.object as? String,
            channelId == viewModel.channel.id
        else {
            return
        }

        // Set flag to prevent unwanted scrolling when returning from search
        isReturningFromSearch = true
        wasInSearch = false
        // print("🔍 SEARCH_CLOSED: Channel search closed for channel \(channelId), setting flag to prevent scroll")

        // Reset the flag after a short delay to ensure it doesn't interfere with future navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isReturningFromSearch = false
        }
    }

    // Handle video player dismiss to ensure navigation bar is hidden
    @objc internal func handleVideoPlayerDismiss(_ notification: Notification) {
        // print("🎬 MessageableChannelViewController: Video player dismissed, ensuring navigation bar is hidden")

        // Force hide navigation bar
        navigationController?.setNavigationBarHidden(true, animated: false)

        // Force layout update
        view.setNeedsLayout()
        view.layoutIfNeeded()

        // Double-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.navigationController?.setNavigationBarHidden(true, animated: false)
        }
    }
    
    // New: Only show new message button if a new message is received from socket and user is not at bottom
    @objc internal func handleNewSocketMessage(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
            let channelId = userInfo["channelId"] as? String,
            channelId == viewModel.channel.id
        else { return }

        // print debug info for socket message
        // print("🔔 SOCKET: Received socket message for channel \(channelId)")

        let hasManuallyScrolledUp =
            lastManualScrollUpTime != nil
            && Date().timeIntervalSince(lastManualScrollUpTime!) < 10.0

        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if !isUserNearBottom() || hasManuallyScrolledUp || targetMessageProtectionActive {
            // This is the ONLY place where showNewMessageButton should be called
            showNewMessageButton()
            // print("🔔 SOCKET: Showing new message button because user is not at bottom or target highlighted")
        } else {
            // print("🔔 SOCKET: User is at bottom, auto-scrolling instead of showing button")
            // Use proper scrolling method that considers keyboard state
            if isKeyboardVisible && !localMessages.isEmpty {
                let lastIndex = localMessages.count - 1
                if lastIndex >= 0 && lastIndex < tableView.numberOfRows(inSection: 0) {
                    let indexPath = IndexPath(row: lastIndex, section: 0)
                    safeScrollToRow(
                        at: indexPath, at: .bottom, animated: true,
                        reason: "socket message with keyboard")
                }
            } else {
                scrollToBottom(animated: true)
            }
        }
    }
    
    // Handle channel search closing notification
    @objc internal func handleChannelSearchClosing(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
            let channelId = userInfo["channelId"] as? String,
            let isReturning = userInfo["isReturning"] as? Bool
        else {
            return
        }

        // Check if this notification is for our channel
        if channelId == viewModel.channel.id && isReturning {
            print("🔍 SEARCH_CLOSING: User is returning from search to channel \(channelId)")
            isReturningFromSearch = true

            // Don't clear the flag here - let viewDidAppear handle it
        }
    }
    
    // Handle system memory warnings
    @objc internal func handleMemoryWarning() {
        // DISABLED: Memory cleanup was causing UI freezes while in the channel
        // Don't perform any aggressive cleanup while user is actively viewing messages
        // Messages will be cleared when leaving the channel
        // print("⚠️ MEMORY WARNING: Received memory warning but deferring cleanup until channel exit")
        return
    }
    
    // Handle system log messages
    @objc internal func handleSystemLog(_ notification: Notification) {
        if let logMessage = notification.object as? String {
            checkForNetworkErrors(in: logMessage)
        }
    }
    
    @objc internal func checkForScrollNeeded() {
        // Skip checks if tableView is nil or user is actively scrolling or we're loading more messages
        guard let tableView = tableView else { return }
        if tableView.isDragging || tableView.isDecelerating || isLoadingMore {
            return
        }

        // Add a variable to track user's last manual scroll time
        if let lastManualScrollTime = lastManualScrollTime,
            Date().timeIntervalSince(lastManualScrollTime) < 10.0
        {
            // If less than 10 seconds have passed since the last manual scroll, do nothing
            return
        }

        // Only check if we have messages and the app is active
        guard !viewModel.messages.isEmpty,
            UIApplication.shared.applicationState == .active
        else {
            return
        }

        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            return
        }

        // Only scroll if we're near bottom already AND not showing last message
        // If we're in the middle or top of chat, don't auto-scroll
        if isUserNearBottom(threshold: 100) {
            // Check if the last visible row is already the last message or close to it
            if let lastVisibleRow = tableView.indexPathsForVisibleRows?.last?.row,
                lastVisibleRow >= viewModel.messages.count - 2
            {
                // Already showing the last message or very close, don't scroll
                return
            }

            // Check if enough time has passed since the last message update
            let timeSinceLastUpdate = Date().timeIntervalSince(lastMessageUpdateTime)
            if timeSinceLastUpdate < minimumUpdateInterval {
                // Too soon after a message update, skip scrolling
                return
            }

            // Only scroll if we're already near bottom but not showing last message
            // // print("⏱️ Timer check - auto-scrolling since user is near bottom but not showing last message")
            scrollToBottom(animated: true)
        } else {
            // // print("👆 [Timer] User is not near bottom, skipping auto-scroll")
        }
    }
    
    
    
}
