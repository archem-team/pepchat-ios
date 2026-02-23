//
//  MessageableChannelViewController+Lifecycle.swift
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
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        isViewDisappearing = false

        // CRITICAL FIX: Check if we have a target message from ViewState that we need to restore
        if targetMessageId == nil,
            let targetFromViewState = viewModel.viewState.currentTargetMessageId
        {
            print(
                "🎯 VIEW_DID_APPEAR: Restoring target message from ViewState: \(targetFromViewState)"
            )
            targetMessageId = targetFromViewState
            targetMessageProcessed = false
        }

        // Check if we're returning from search - if so, reload messages and skip scroll-related operations
        if isReturningFromSearch {
            print("🔍 VIEW_DID_APPEAR: Returning from search, reloading messages")

            // Re-register observer
            NotificationCenter.default.removeObserver(
                self, name: NSNotification.Name("MessagesDidChange"), object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(messagesDidChange),
                name: NSNotification.Name("MessagesDidChange"),
                object: nil
            )

            // Check if we have messages in ViewState
            let channelId = viewModel.channel.id
            let hasMessages = !(viewModel.viewState.channelMessages[channelId]?.isEmpty ?? true)

            if hasMessages {
                // Reload messages to show them again
                refreshMessages()

                // Show table view if hidden
                if tableView.alpha == 0.0 {
                    tableView.alpha = 1.0
                }

                // Scroll to bottom if messages exist
                if !localMessages.isEmpty {
                    scrollToBottom(animated: false)
                }
            } else {
                // No messages in ViewState, need to reload from API
                print("🔍 VIEW_DID_APPEAR: No messages in ViewState, reloading from API")

                // Show loading indicator
                tableView.alpha = 0.0
                let spinner = UIActivityIndicatorView(style: .large)
                spinner.startAnimating()
                spinner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
                tableView.tableFooterView = spinner

                // Reload messages from API
                Task {
                    await loadInitialMessages()
                }
            }

            // Reset the flag after processing
            isReturningFromSearch = false
            print("🔍 VIEW_DID_APPEAR: Cleared isReturningFromSearch flag")

            return
        }

        // CRITICAL FIX: Don't apply global fix during cross-channel target message navigation
        if targetMessageId == nil && !targetMessageProtectionActive {
            // Apply Global Fix to ensure message display and fix black screen issues
            applyGlobalFix()

            // Update table view bouncing behavior when view appears
            updateTableViewBouncing()
        } else {
            print("🎯 VIEW_DID_APPEAR: Skipping global fix - target message navigation in progress")
        }

        // // print("🔄 VIEW_DID_APPEAR: View appeared, checking notification observers")

        // Ensure notification observer is registered for all MessagesDidChange notifications
        NotificationCenter.default.removeObserver(
            self, name: NSNotification.Name("MessagesDidChange"), object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(messagesDidChange),
            name: NSNotification.Name("MessagesDidChange"),
            object: nil  // Set to nil to receive all notifications with this name
        )
        // // print("🔄 VIEW_DID_APPEAR: Re-registered MessagesDidChange observer")

        if !contentSizeObserverRegistered {
            tableView.addObserver(
                self, forKeyPath: "contentSize", options: [.new, .old], context: nil)
            contentSizeObserverRegistered = true
        }

        // Check if we're already loading this channel
        let channelId = viewModel.channel.id

        // If we don't have a specific target message and table is hidden, show it properly positioned
        if targetMessageId == nil && !viewModel.messages.isEmpty && tableView.alpha == 0.0 {
            print("📱 VIEW_DID_APPEAR: Positioning table at bottom and showing")
            positionTableAtBottomBeforeShowing()

            // Adjust table insets after positioning
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.adjustTableInsetsForMessageCount()
            }
        }

        // Note: Automatic preloading is controlled by ViewState.enableAutomaticPreloading
        // When disabled, messages are loaded only when user explicitly enters the channel
        print(
            "📵 PRELOAD_CONTROLLED: Automatic preloading controlled by ViewState setting for channel \(channelId)"
        )

        // CRITICAL FIX: Check if user is in target message position to prevent reload
        if isInTargetMessagePosition {
            print("🎯 VIEW_DID_APPEAR: User is in target message position, preserving current view")
            return
        }

        // CRITICAL FIX: Always prioritize target message handling over existing messages
        if targetMessageId != nil {
            print(
                "🎯 VIEW_DID_APPEAR: Target message found, using nearby API (prioritized over existing messages)"
            )

            // CRITICAL FIX: Don't trigger loading if already in progress
            if messageLoadingState == .loading {
                print("🎯 VIEW_DID_APPEAR: Loading already in progress, skipping duplicate trigger")
                return
            }

            // CRITICAL FIX: Set loading state and hide empty state before starting
            messageLoadingState = .loading
            DispatchQueue.main.async {
                self.hideEmptyStateView()
                print("🚫 VIEW_DID_APPEAR: Hidden empty state before target message loading")
            }

            // Show loading spinner and trigger target message loading
            tableView.alpha = 0.0
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.startAnimating()
            spinner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
            tableView.tableFooterView = spinner

            // Trigger target message loading which will use nearby API
            Task {
                print("🎯 VIEW_DID_APPEAR: Triggering target message loading")
                await loadInitialMessages()

                // Adjust table insets after loading messages
                DispatchQueue.main.async {
                    self.adjustTableInsetsForMessageCount()

                    // CRITICAL FIX: Check for missing reply content after initial load with delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        Task {
                            print(
                                "🔗 VIEW_APPEARED: Checking for missing replies after delay (first case)"
                            )
                            await self.checkAndFetchMissingReplies()
                        }
                    }
                }
            }
        } else {
            // SMART LOADING: Check if we have actual message objects, not just IDs (only when no target message)
            let hasActualMessages =
                !(viewModel.viewState.channelMessages[channelId]?.isEmpty ?? true)
                && viewModel.viewState.channelMessages[channelId]?.first(where: {
                    viewModel.viewState.messages[$0] != nil
                }) != nil

            if hasActualMessages {
                print("✅ VIEW_DID_APPEAR: Messages already loaded, showing immediately")
                // Messages exist, show them immediately without loading
                tableView.alpha = 1.0
                tableView.tableFooterView = nil
                refreshMessages()

                // Adjust table insets and check for missing replies
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                    await MainActor.run {
                        self.adjustTableInsetsForMessageCount()
                    }
                    await self.checkAndFetchMissingReplies()
                }
            } else {
                // No messages in memory: use loadInitialMessages() so we get cache check + cache write.
                // Previously we called loadInitialMessagesImmediate() which bypassed cache entirely.
                print("🚀 VIEW_DID_APPEAR: No messages found, loading via loadInitialMessages (cache-first + API)")

                // Show skeleton loading view; loadInitialMessages() will hide it when cache or API result is ready
                showSkeletonView()

                Task {
                    await loadInitialMessages()

                    // Same follow-up as target-message path: adjust insets and check missing replies
                    DispatchQueue.main.async {
                        self.adjustTableInsetsForMessageCount()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            Task {
                                print(
                                    "🔗 VIEW_APPEARED: Checking for missing replies after delay (no-target path)"
                                )
                                await self.checkAndFetchMissingReplies()
                            }
                        }
                    }
                }
            }
        }

        // Check if the channel is NSFW
        if viewModel.channel.nsfw && !self.over18HasSeen {
            self.over18HasSeen = true
            showNSFWOverlay()
        }

        // Apply global fix after view appears to ensure messages are visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            // Only apply fix if table is empty but we have messages
            if self.tableView.numberOfRows(inSection: 0) == 0
                && !(self.viewModel.viewState.channelMessages.isEmpty)
            {
                self.applyGlobalFix()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isViewDisappearing = true
        
        scrollToBottomWorkItem?.cancel()
        scrollToBottomWorkItem = nil
        scrollPositionManager.cancelScrollToBottom()
        
        // Show navigation bar when leaving this view
        navigationController?.setNavigationBarHidden(false, animated: animated)

        // Restore tab bar if needed
        tabBarController?.tabBar.isHidden = false

        // Dismiss keyboard if visible
        view.endEditing(true)

        // Safety: remove MessagesDidChange observer (re-added in viewDidAppear)
        NotificationCenter.default.removeObserver(
            self, name: NSNotification.Name("MessagesDidChange"), object: nil)

        // Safety: remove tableView contentSize observer and re-register on appear
        if contentSizeObserverRegistered {
            tableView.removeObserver(self, forKeyPath: "contentSize")
            contentSizeObserverRegistered = false
        }

        print(
            "🚀 IMMEDIATE_CLEANUP: Starting INSTANT memory cleanup for channel \(viewModel.channel.id)"
        )
        let cleanupStartTime = CFAbsoluteTimeGetCurrent()

        // IMMEDIATE: Cancel all pending operations first
        scrollToBottomWorkItem?.cancel()
        scrollToBottomWorkItem = nil
        scrollProtectionTimer?.invalidate()
        scrollProtectionTimer = nil
        loadingTask?.cancel()
        loadingTask = nil
        pendingAPICall?.cancel()
        pendingAPICall = nil

        // CRITICAL FIX: Don't clear target message ID if it's for a different channel (navigation to new channel)
        if let targetId = viewModel.viewState.currentTargetMessageId {
            // Check if target message is for the current (old) channel or a different (new) channel
            if let targetMessage = viewModel.viewState.messages[targetId] {
                if targetMessage.channel == viewModel.channel.id {
                    // Target message is for THIS (old) channel - we can clear it safely
                    print(
                        "🎯 IMMEDIATE_CLEANUP: Target message is for current channel \(viewModel.channel.id), clearing it"
                    )
                    viewModel.viewState.currentTargetMessageId = nil
                    targetMessageId = nil
                    targetMessageProcessed = false
                } else {
                    // Target message is for DIFFERENT (new) channel - preserve it!
                    print(
                        "🎯 IMMEDIATE_CLEANUP: Target message is for different channel \(targetMessage.channel), preserving it"
                    )
                }
            } else {
                // Target message not loaded yet - this means we're navigating to find it, so preserve it
                print(
                    "🎯 IMMEDIATE_CLEANUP: Target message not loaded yet, preserving for navigation")
            }
        }

        // Stop automatic memory cleanup timer
        stopMemoryCleanupTimer()

        // CRITICAL FIX: Don't cleanup if we're returning from search
        if isReturningFromSearch {
            print("🔍 IMMEDIATE_CLEANUP: Returning from search, skipping ALL cleanup")
            return
        }

        // IMMEDIATE CLEANUP: Always perform instant cleanup regardless of navigation
        performInstantMemoryCleanup()

        let cleanupEndTime = CFAbsoluteTimeGetCurrent()
        let cleanupDuration = (cleanupEndTime - cleanupStartTime) * 1000
        print(
            "🚀 IMMEDIATE_CLEANUP: Total viewWillDisappear cleanup completed in \(String(format: "%.2f", cleanupDuration))ms"
        )
    }
    
    // Override observeValue to detect content size changes
    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard !isViewDisappearing else {
            return
        }
        if keyPath == "contentSize" && object as? UITableView === tableView {
            // Update bouncing behavior whenever content size changes
            updateTableViewBouncing()

            // ContentSize changed - check if it's larger than before
            if let oldSize = change?[.oldKey] as? CGSize,
                let newSize = change?[.newKey] as? CGSize,
                newSize.height > oldSize.height + 20
            {  // Significant increase in height

                // If user is near bottom and scrolling is enabled, scroll to show new content
                if isUserNearBottom() && !isLoadingMore && tableView.isScrollEnabled {
                    // print("📏 TableView content size increased significantly while user near bottom - scrolling")
                    scrollToBottom(animated: true)
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}
