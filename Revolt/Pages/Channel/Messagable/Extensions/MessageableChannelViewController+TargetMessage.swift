//
//  MessageableChannelViewController+TargetMessage.swift
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
    // Scroll to the target message if it exists
    internal func scrollToTargetMessage() {
        // CRITICAL FIX: Reset processed flag when we have a target message to scroll to
        if let targetId = self.targetMessageId {
            print(
                "🎯 scrollToTargetMessage called for target: \(targetId), resetting processed flag")
            targetMessageProcessed = false
        }

        // CRITICAL FIX: Check if already processed to prevent multiple highlighting
        if targetMessageProcessed {
            print("🎯 Target message already processed, skipping to prevent multiple highlights")
            return
        }

        // CRITICAL FIX: Reset processed flag for new target message
        if let targetId = self.targetMessageId {
            print("🎯 scrollToTargetMessage called for target: \(targetId)")
        }

        guard let targetId = self.targetMessageId else {
            // If no target message, scroll to bottom
            print("🚫 No target message ID, scrolling to bottom")
            scrollToBottom(animated: false)
            return
        }

        print("🎯 Attempting to scroll to target message: \(targetId)")
        print("📊 Current message count in localMessages: \(localMessages.count)")

        // Debug - print some message IDs to help diagnose
        if !localMessages.isEmpty {
            let firstMsg = localMessages[0]
            let lastMsg = localMessages[localMessages.count - 1]
            print("📑 First message ID: \(firstMsg)")
            print("📑 Last message ID: \(lastMsg)")
        }

        // Debug: Check current state
        let isInViewState = self.viewModel.viewState.messages[targetId] != nil
        let isInLocalMessages = self.localMessages.contains(targetId)
        let isInViewModelMessages = self.viewModel.messages.contains(targetId)
        let channelMessages = self.viewModel.viewState.channelMessages[self.viewModel.channel.id]
        let isInChannelMessages = channelMessages?.contains(targetId) ?? false

        print("🔍 Target message \(targetId) status:")
        print("   - In viewState.messages: \(isInViewState)")
        print("   - In localMessages: \(isInLocalMessages)")
        print("   - In viewModel.messages: \(isInViewModelMessages)")
        print("   - In channelMessages: \(isInChannelMessages)")
        print("   - LocalMessages count: \(localMessages.count)")
        print("   - ViewModelMessages count: \(viewModel.messages.count)")
        print("   - ChannelMessages count: \(channelMessages?.count ?? 0)")

        // Check if target message exists in localMessages but not in viewState.messages
        if isInLocalMessages && !isInViewState {
            // print("🔄 Target message exists in localMessages but not in viewState.messages")
            // This shouldn't happen, but let's handle it by syncing localMessages with current messages
            self.syncLocalMessagesWithViewState()
        }

        // First, make sure we have the target message in our arrays
        guard self.viewModel.viewState.messages[targetId] != nil else {
            // print("⚠️ Target message not in viewState.messages, fetching it first")

            // Fetch the message and nearby messages
            Task {
                let success = await self.loadMessagesNearby(messageId: targetId)

                DispatchQueue.main.async {
                    if success {
                        // print("✅ Successfully loaded target message, trying to scroll again")
                        self.scrollToTargetMessage()  // Recursive call after loading
                    } else {
                        // print("❌ Failed to load target message")
                        self.scrollToBottom(animated: false)  // Fallback
                    }
                }
            }

            return
        }

        // CRITICAL FIX: Force sync before finding index to prevent wrong scroll position
        print("🔄 SYNC_CHECK: Ensuring all message arrays are synced before scrolling")
        self.syncLocalMessagesWithViewState()

        // CRITICAL FIX: Use the most reliable source for finding index
        let referenceMessages: [String]
        if let channelMessages = self.viewModel.viewState.channelMessages[
            self.viewModel.channel.id], !channelMessages.isEmpty
        {
            referenceMessages = channelMessages
            print(
                "🔍 Using viewState.channelMessages as reference (\(channelMessages.count) messages)"
            )
        } else if !self.localMessages.isEmpty {
            referenceMessages = self.localMessages
            print("🔍 Using localMessages as reference (\(self.localMessages.count) messages)")
        } else {
            print("❌ No reference messages available for scrolling")
            self.scrollToBottom(animated: false)
            return
        }

        // CRITICAL FIX: Ensure localMessages matches reference for table view
        if self.localMessages != referenceMessages {
            print("⚠️ SYNC_FIX: localMessages was out of sync, updating from reference")
            self.localMessages = referenceMessages

            // Update data source to match
            if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                localDataSource.updateMessages(self.localMessages)
            }
        }

        // Find the target message in reference messages
        if let index = referenceMessages.firstIndex(of: targetId) {
            print(
                "✅ Found target message at index \(index) in reference messages (total: \(referenceMessages.count))"
            )
            print("🎯 Target message ID: \(targetId)")

            // VALIDATION: Verify the message at this index is actually our target
            if index < referenceMessages.count && referenceMessages[index] == targetId {
                print("✅ VALIDATION: Confirmed message at index \(index) is target \(targetId)")
            } else {
                print("❌ VALIDATION: Message at index \(index) is NOT target \(targetId)")
                // Try to find it again or fallback
                if let correctIndex = referenceMessages.firstIndex(of: targetId) {
                    print("🔄 CORRECTION: Found target at correct index \(correctIndex)")
                    // Update index variable (but can't reassign let, so we'll use correctIndex below)
                } else {
                    print("❌ CORRECTION: Could not find target message, falling back to bottom")
                    self.scrollToBottom(animated: false)
                    return
                }
            }

            // Use the validated index
            let validatedIndex = referenceMessages.firstIndex(of: targetId) ?? index

            // Ensure the table has been reloaded with data
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // CRITICAL FIX: Force complete data source recreation with correct messages
                print(
                    "🔄 DATASOURCE_FIX: Recreating data source with \(referenceMessages.count) messages"
                )
                self.dataSource = LocalMessagesDataSource(
                    viewModel: self.viewModel,
                    viewController: self,
                    localMessages: referenceMessages)
                self.tableView.dataSource = self.dataSource

                // CRITICAL FIX: Use the new force update method
                if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                    localDataSource.forceUpdateMessages(referenceMessages)
                }

                // Force table view to reload and layout subviews to ensure cells are available
                self.tableView.reloadData()
                self.tableView.layoutIfNeeded()

                // CRITICAL FIX: Check row count immediately and retry if mismatch
                let initialRowCount = self.tableView.numberOfRows(inSection: 0)
                print(
                    "📊 Initial table row count: \(initialRowCount), expected: \(referenceMessages.count)"
                )

                if initialRowCount != referenceMessages.count {
                    print(
                        "⚠️ MISMATCH: Table rows (\(initialRowCount)) don't match messages (\(referenceMessages.count)), forcing fix"
                    )

                    // Force another complete reload
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()

                    // Check again
                    let secondRowCount = self.tableView.numberOfRows(inSection: 0)
                    print("📊 Second attempt row count: \(secondRowCount)")

                    if secondRowCount != referenceMessages.count {
                        print("⚠️ STILL_MISMATCH: Forcing data source update")
                        if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                            localDataSource.forceUpdateMessages(referenceMessages)
                        }
                        self.tableView.reloadData()
                        self.tableView.layoutIfNeeded()
                    }
                }

                // The UI might need a moment to update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // CRITICAL FIX: Force another reload to ensure table is completely updated
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()

                    // Get current row count - IMPORTANT for avoiding index out of bounds
                    let rowCount = self.tableView.numberOfRows(inSection: 0)
                    print(
                        "📊 Final table row count: \(rowCount), trying to scroll to index \(validatedIndex)"
                    )

                    // CRITICAL FIX: If still mismatched, retry with delay
                    if rowCount != referenceMessages.count {
                        print(
                            "❌ CRITICAL_MISMATCH: Table rows (\(rowCount)) still don't match messages (\(referenceMessages.count))"
                        )
                        print("🔄 RETRY: Will retry scroll after fixing data source")

                        // Force sync again
                        self.localMessages = referenceMessages
                        if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                            localDataSource.forceUpdateMessages(referenceMessages)
                        }
                        self.tableView.reloadData()

                        // Retry scroll after another delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.scrollToTargetMessage()
                        }
                        return
                    }

                    // Make sure the index is valid
                    if rowCount > 0 && validatedIndex < rowCount {
                        print("🔍 Scrolling to validated row \(validatedIndex)")
                        // Create an index path and scroll to it
                        let indexPath = IndexPath(row: validatedIndex, section: 0)

                        // Use try-catch to handle any potential crashes
                        do {
                            // CRITICAL FIX: Cancel any existing scroll animations first
                            if self.tableView.layer.animationKeys()?.contains("position") == true {
                                self.tableView.layer.removeAllAnimations()
                            }

                            // Scroll to the message WITHOUT animation for instant positioning - this is TARGET MESSAGE scroll, should not be blocked
                            print(
                                "🎯 SCROLL_TO_TARGET: Scrolling to target message at index \(validatedIndex)"
                            )
                            self.tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
                            // print("📍 scrollToRow completed")

                            // CRITICAL FIX: Force immediate layout update to prevent any delay
                            self.tableView.layoutIfNeeded()

                            // Remove excess contentInset that might cause empty space
                            if self.tableView.contentInset.top > 0 {
                                self.tableView.contentInset = .zero
                                // print("📏 Removed excess contentInset.top in scrollToTargetMessage")
                            }

                            // CRITICAL FIX: Small delay to ensure scroll position is stable
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                // print("📍 Scroll completed, highlighting immediately")
                                // Highlight immediately without delay for instant feedback
                                self.highlightTargetMessage(at: indexPath)
                            }

                            // print("✅ Successfully scrolled to target message")
                        } catch {
                            // print("❌ Error scrolling to target message: \(error)")
                            // Fall back to just scrolling to the bottom as a last resort
                            self.scrollToBottom(animated: false)
                        }
                    } else {
                        print(
                            "⚠️ Index \(validatedIndex) is out of bounds or table is empty (rowCount: \(rowCount))"
                        )
                        if !self.localMessages.isEmpty {
                            // If we have messages but table is not ready, try again in a moment
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.scrollToTargetMessage()
                            }
                        } else {
                            // No messages, just scroll to bottom
                            self.scrollToBottom(animated: false)
                        }
                    }
                }
            }
        } else {
            print("⚠️ Target message ID not found in reference messages array")
            print("🔍 Debugging: reference messages contains \(referenceMessages.count) messages")

            // Debug: Check if target message is in any of the loaded messages
            print("🔍 Target message ID: \(targetId)")
            print("🔍 Reference messages: \(referenceMessages)")

            // Check if the target message exists in viewState.messages but not in reference messages
            if viewModel.viewState.messages[targetId] != nil {
                print(
                    "✅ Target message found in viewState.messages but missing from reference messages"
                )
            } else {
                print("❌ Target message not found in viewState.messages either")
            }
            // Debug: Print first and last 3 message IDs to help diagnose ordering issues
            if referenceMessages.count > 0 {
                let firstMessages = Array(referenceMessages.prefix(3))
                let lastMessages = Array(referenceMessages.suffix(3))
                print("🔍 First 3 messages: \(firstMessages)")
                print("🔍 Last 3 messages: \(lastMessages)")
                print("🔍 Target message ID: \(targetId)")
            }

            // If not in localMessages but in viewState.messages, add it to localMessages
            if self.viewModel.viewState.messages[targetId] != nil {
                // print("🔄 Adding target message to localMessages array")

                // Add to beginning or end based on timestamp
                let targetMessage = self.viewModel.viewState.messages[targetId]!
                let targetDate = createdAt(id: targetId)

                if !localMessages.isEmpty {
                    let firstMsgDate = createdAt(id: localMessages[0])
                    let lastMsgDate = createdAt(id: localMessages[localMessages.count - 1])

                    if targetDate < firstMsgDate {
                        // Add to beginning
                        self.localMessages.insert(targetId, at: 0)
                    } else if targetDate > lastMsgDate {
                        // Add to end
                        self.localMessages.append(targetId)
                    } else {
                        // Insert in sorted position
                        var insertIndex = 0
                        for (i, msgId) in self.localMessages.enumerated() {
                            let msgDate = createdAt(id: msgId)
                            if targetDate < msgDate {
                                insertIndex = i
                                break
                            }
                            insertIndex = i + 1
                        }
                        self.localMessages.insert(targetId, at: insertIndex)
                    }
                } else {
                    // If empty, just add it
                    self.localMessages.append(targetId)
                }

                // Update data source and reload
                DispatchQueue.main.async {
                    self.dataSource = LocalMessagesDataSource(
                        viewModel: self.viewModel,
                        viewController: self,
                        localMessages: self.localMessages)
                    self.tableView.dataSource = self.dataSource

                    // CRITICAL FIX: Force complete table reload and layout
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()

                    // CRITICAL FIX: Multiple reload attempts to ensure UI is updated
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.tableView.reloadData()
                        self.tableView.layoutIfNeeded()

                        // Try scrolling again after ensuring table is updated - ONLY if not processed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if !self.targetMessageProcessed {
                                self.scrollToTargetMessage()
                            } else {
                                print(
                                    "🎯 Skipping duplicate scrollToTargetMessage call - already processed"
                                )
                            }
                        }
                    }
                }
            } else {
                // Try loading nearby messages
                Task {
                    let success = await self.loadMessagesNearby(messageId: targetId)

                    DispatchQueue.main.async {
                        if success {
                            // print("✅ Successfully loaded messages nearby target")
                            self.scrollToTargetMessage()  // Try again after loading
                        } else {
                            // print("❌ Unable to load messages near target")
                            self.scrollToBottom(animated: false)  // Fallback
                        }
                    }
                }
            }
        }
    }
    
    // Enhanced version of scrollToTargetMessage that handles black screen issues
    private func scrollToTargetMessage(_ messageId: String? = nil, animated: Bool = false) {
        // Use the provided message ID or the target message ID from properties
        let targetMessageId = messageId ?? self.targetMessageId

        guard let targetId = targetMessageId,
            let targetIndex = viewModel.messages.firstIndex(of: targetId)
        else {
            // print("⚠️ Target message not found for scrolling")
            // Apply global fix if table is empty but we have messages
            if tableView.numberOfRows(inSection: 0) == 0,
                let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id],
                !channelMessages.isEmpty
            {
                applyGlobalFix()
            } else {
                scrollToBottom(animated: false)
            }
            return
        }

        // Reset contentInset to avoid empty space
        if tableView.contentInset != .zero {
            UIView.animate(withDuration: 0.2) {
                self.tableView.contentInset = .zero
            }
            // print("📏 Reset content insets before scrolling to target message")
        }

        // Calculate a safety target index within bounds of table view
        let tableRows = tableView.numberOfRows(inSection: 0)

        // If tableView has no rows but we have messages, apply global fix
        if tableRows == 0 && !viewModel.messages.isEmpty {
            // print("⚠️ Table has 0 rows but viewModel has \(viewModel.messages.count) messages - applying fix")
            applyGlobalFix()
            // Try scrolling again after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.scrollToTargetMessage(targetId, animated: animated)
            }
            return
        }

        let safeTargetIndex = min(targetIndex, tableRows - 1)
        if safeTargetIndex >= 0 && safeTargetIndex < tableRows {
            // Scroll to the target message
            let indexPath = IndexPath(row: safeTargetIndex, section: 0)
            tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
            // print("🎯 Scrolled to target message at index \(safeTargetIndex)")

            // For emphasis, highlight the message temporarily
            if let cell = tableView.cellForRow(at: indexPath) as? MessageCell {
                UIView.animate(
                    withDuration: 0.3,
                    animations: {
                        cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
                    }
                ) { _ in
                    UIView.animate(withDuration: 0.5) {
                        cell.backgroundColor = .clear
                    }
                }
            }
        } else {
            // print("⚠️ Target index \(safeTargetIndex) is out of bounds (0..\(tableRows-1))")
            scrollToBottom(animated: false)
        }
    }
    
    // Public method to refresh messages with a specific target message ID
    func refreshWithTargetMessage(_ messageId: String) async {
        print("🚀 ========== refreshWithTargetMessage CALLED ==========")
        print("🎯 refreshWithTargetMessage called with messageId: \(messageId)")
        print("🎯 Current channel: \(viewModel.channel.id)")
        print("🎯 Current targetMessageId: \(targetMessageId ?? "nil")")
        print(
            "🎯 ViewState currentTargetMessageId: \(viewModel.viewState.currentTargetMessageId ?? "nil")"
        )
        print("🔍 This is where API calls should happen for fetching the target message!")

        // CRITICAL FIX: Set loading state to prevent premature cleanup
        messageLoadingState = .loading
        print("🎯 Set messageLoadingState to .loading for target message")

        // CRITICAL FIX: Add timeout protection to prevent infinite loading
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds (reduced for better UX)
            print("⏰ TIMEOUT: refreshWithTargetMessage took too long, forcing cleanup")
            await MainActor.run {
                self.messageLoadingState = .notLoading
                self.hideEmptyStateView()
                self.tableView.alpha = 1.0
                self.tableView.tableFooterView = nil
                self.loadingHeaderView.isHidden = true
                self.targetMessageId = nil
                self.viewModel.viewState.currentTargetMessageId = nil

                // Show user-friendly error message
                print("⏰ TIMEOUT: Could not load the message. It may have been deleted.")
            }
        }

        // CRITICAL FIX: Ensure loading state is always reset when function exits
        defer {
            timeoutTask.cancel()
            Task { @MainActor in
                // Ensure all loading states are cleaned up
                self.messageLoadingState = .notLoading
                self.loadingHeaderView.isHidden = true

                // Only clear target message if it wasn't successfully loaded
                if !self.localMessages.contains(messageId) {
                    self.targetMessageId = nil
                    self.viewModel.viewState.currentTargetMessageId = nil
                }

                print("🎯 Reset all loading states - refreshWithTargetMessage complete")
            }
        }

        // CRITICAL FIX: Check if this message ID is already being processed
        if targetMessageProcessed && targetMessageId == messageId {
            print(
                "🎯 Target message \(messageId) already processed, skipping to prevent duplicate highlights"
            )
            return
        }

        // Validate that the message belongs to current channel (if already loaded)
        if let existingMessage = viewModel.viewState.messages[messageId] {
            if existingMessage.channel != viewModel.channel.id {
                print(
                    "❌ Target message \(messageId) belongs to channel \(existingMessage.channel), but current channel is \(viewModel.channel.id)"
                )
                await MainActor.run {
                    self.viewModel.viewState.currentTargetMessageId = nil
                    self.targetMessageId = nil
                }
                return
            }
            print("✅ Message \(messageId) exists and belongs to current channel")
        } else {
            print("⚠️ Message \(messageId) not found in loaded messages - will try to fetch")
        }

        // Set the target message ID
        self.targetMessageId = messageId
        // print("🎯 Set targetMessageId to: \(messageId)")

        // Show loading indicator
        DispatchQueue.main.async {
            self.loadingHeaderView.isHidden = false
            // print("📱 Loading indicator shown")
        }

        // Check if the message ID is already loaded in any of our stores
        let isInViewModelMessages = viewModel.messages.contains(messageId)
        let isInViewStateMessages = viewModel.viewState.messages[messageId] != nil
        let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id]
        let isInChannelMessages = channelMessages?.contains(messageId) ?? false

        print("🔍 refreshWithTargetMessage - checking for message \(messageId):")
        print("   - In viewModel.messages: \(isInViewModelMessages)")
        print("   - In viewState.messages: \(isInViewStateMessages)")
        print("   - In channelMessages: \(isInChannelMessages)")

        // CRITICAL FIX: Check if message is in localMessages (actually visible) not just in viewState
        let isInLocalMessages = localMessages.contains(messageId)

        // First check if the message ID is already loaded AND visible in localMessages
        if (isInViewModelMessages || isInChannelMessages) && isInLocalMessages {
            // Message is already loaded AND visible, just scroll to it
            DispatchQueue.main.async {
                print(
                    "✅ Target message \(messageId) already exists and is visible, scrolling to it")

                // Ensure all arrays are in sync
                self.syncLocalMessagesWithViewState()

                self.scrollToTargetMessage()
                // After scrolling to the target message, make sure the loading indicator is hidden
                self.loadingHeaderView.isHidden = true

                // Change the loading state so we can load older messages in the future
                self.messageLoadingState = .notLoading
                self.isLoadingMore = false
                self.lastSuccessfulLoadTime = Date()
            }
            return
        }

        // CRITICAL FIX: If message exists in viewState but NOT in localMessages, we need nearby API
        if isInViewStateMessages && !isInLocalMessages {
            print("⚠️ Target message exists in viewState but not in localMessages - need nearby API")
        }

        // Message not loaded, load it using nearby API
        print(
            "🔄 REPLY_TARGET: Target message not found in loaded messages, loading nearby messages")
        print("🌐 REPLY_TARGET: About to call loadMessagesNearby API for messageId: \(messageId)")
        let result = await loadMessagesNearby(messageId: messageId)

        if result {
            // Message successfully loaded, scroll to it
            DispatchQueue.main.async {
                print("✅ REPLY_TARGET: Successfully loaded messages nearby target, scrolling to it")
                // After loading messages, hide the loading indicator
                self.loadingHeaderView.isHidden = true

                self.messageLoadingState = .notLoading
                self.isLoadingMore = false
                self.lastSuccessfulLoadTime = Date()

                self.scrollToTargetMessage()
            }
        } else {
            // Failed to load target message, try a direct fetch
            print("⚠️ REPLY_TARGET: Failed to load messages around target, attempting direct fetch")

            // Show loading indicator
            DispatchQueue.main.async {
                self.loadingHeaderView.isHidden = false
            }

            // Try to fetch the target message directly with timeout
            let fetchResult = try? await withThrowingTaskGroup(of: Types.Message.self) { group in
                // Add the actual API call
                group.addTask {
                    try await self.viewModel.viewState.http.fetchMessage(
                        channel: self.viewModel.channel.id,
                        message: messageId
                    ).get()
                }

                // Add timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
                    throw TimeoutError()
                }

                // Return the first result
                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            if let message = fetchResult {
                // Validate that the fetched message belongs to current channel
                if message.channel != viewModel.channel.id {
                    print(
                        "❌ DIRECT_TARGET: Fetched message \(messageId) belongs to channel \(message.channel), but current channel is \(viewModel.channel.id)"
                    )
                    await MainActor.run {
                        self.viewModel.viewState.currentTargetMessageId = nil
                        self.targetMessageId = nil
                        self.loadingHeaderView.isHidden = true
                        self.messageLoadingState = .notLoading
                        self.isLoadingMore = false
                    }
                    return
                }

                print(
                    "✅ DIRECT_TARGET: Successfully fetched target message directly: \(message.id)")

                await MainActor.run {
                    // Add the fetched message to the view model
                    viewModel.viewState.messages[message.id] = message

                    // CRITICAL FIX: Always load surrounding context when we get a single message
                    // This ensures the user sees more than just one message
                    print("🔄 DIRECT_TARGET: Loading surrounding context for better user experience")

                    // Check for existing messages and insert in correct position
                    // If we can't determine proper order, just add it
                    if !viewModel.messages.isEmpty {
                        // Get message creation timestamp to determine position
                        let targetDate = createdAt(id: messageId)

                        // Find where to insert the message based on timestamp
                        var insertIndex = 0
                        for (index, msgId) in viewModel.messages.enumerated() {
                            let msgDate = createdAt(id: msgId)
                            if targetDate < msgDate {
                                insertIndex = index
                                break
                            }

                            if index == viewModel.messages.count - 1 {
                                insertIndex = viewModel.messages.count
                            }
                        }

                        // Insert at the determined position
                        viewModel.messages.insert(messageId, at: insertIndex)
                        print(
                            "📍 DIRECT_TARGET: Inserted message at index \(insertIndex) of \(viewModel.messages.count)"
                        )
                    } else {
                        // If no messages yet, just add it
                        viewModel.messages = [messageId]
                        print("📍 DIRECT_TARGET: Added as first message")
                    }

                    // Update channel messages in viewState
                    viewModel.viewState.channelMessages[viewModel.channel.id] = viewModel.messages

                    // Also update localMessages
                    self.localMessages = viewModel.messages

                    // Refresh UI and scroll to message
                    print(
                        "🔄 DIRECT_TARGET: Refreshing UI with \(self.localMessages.count) messages")
                    self.refreshMessages()

                    // After loading messages, hide the loading indicator
                    self.loadingHeaderView.isHidden = true

                    // Reset loading states
                    self.messageLoadingState = .notLoading
                    self.isLoadingMore = false
                    self.lastSuccessfulLoadTime = Date()

                    // After a short delay, scroll to the target message and load surrounding context
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("🎯 DIRECT_TARGET: Scrolling to target message")
                        self.scrollToTargetMessage()

                        // IMPORTANT: Load more context around this message for better UX
                        print("🔄 DIRECT_TARGET: Loading surrounding context")
                        Task {
                            let contextResult = await self.loadMessagesNearby(messageId: messageId)
                            if contextResult {
                                print("✅ DIRECT_TARGET: Successfully loaded surrounding context")
                            } else {
                                print("⚠️ DIRECT_TARGET: Could not load surrounding context")
                            }
                        }
                    }
                }
            } else {
                // Failed to fetch target message directly - message likely deleted
                print(
                    "❌ DIRECT_TARGET: Failed to fetch target message directly - likely deleted or inaccessible"
                )

                await MainActor.run {
                    // Clean up loading states immediately
                    self.messageLoadingState = .notLoading
                    self.loadingHeaderView.isHidden = true
                    self.targetMessageId = nil
                    self.viewModel.viewState.currentTargetMessageId = nil

                    // Show user-friendly error message
                    print("❌ DIRECT_TARGET: Showing error message to user - message likely deleted")
                }

                // Exit early since message couldn't be loaded
                return
            }
        }

        // If target message is not found after all attempts, show an error message
        let finalCheck =
            viewModel.messages.contains(messageId) || viewModel.viewState.messages[messageId] != nil
            || (viewModel.viewState.channelMessages[viewModel.channel.id]?.contains(messageId)
                ?? false)

        if !finalCheck {
            // print("⚠️ Target message was not found even after loading nearby messages")
            DispatchQueue.main.async {
                // Display a message with more detail
                print("❌ FINAL_CHECK: Message not found or may have been deleted")

                // Clear target message ID since we failed to find it
                self.targetMessageId = nil

                // Ensure loading states are reset
                self.messageLoadingState = .notLoading
                self.isLoadingMore = false
                self.lastSuccessfulLoadTime = Date()
            }
        } else {
            // print("✅ Final check passed - target message \(messageId) was found")
        }
    }
    
    // Precise scroll to reference message with retry mechanism
    internal func scrollToReferenceMessageWithRetry(
        referenceId: String?, messagesArray: [String], maxRetries: Int
    ) {
        guard let referenceId = referenceId else {
            // print("⚠️ REFERENCE_SCROLL: No reference ID provided")
            return
        }

        // print("🎯 REFERENCE_SCROLL: Starting scroll to reference message '\(referenceId)'")

        // Attempt to scroll with retry logic
        attemptScrollToReference(
            referenceId: referenceId, messagesArray: messagesArray, attempt: 1,
            maxRetries: maxRetries)
    }

    
    private func attemptScrollToReference(
        referenceId: String, messagesArray: [String], attempt: Int, maxRetries: Int
    ) {
        guard attempt <= maxRetries else {
            // print("❌ REFERENCE_SCROLL: Failed to scroll after \(maxRetries) attempts")
            // Clear the reference ID since we've exhausted retries
            self.lastBeforeMessageId = nil
            return
        }

        // print("🎯 REFERENCE_SCROLL: Attempt \(attempt)/\(maxRetries) to find and scroll to '\(referenceId)'")

        // Find the reference message in the array
        if let targetIndex = messagesArray.firstIndex(of: referenceId) {
            // print("✅ REFERENCE_SCROLL: Found reference message at index \(targetIndex)")

            // Verify table view has the expected number of rows
            let tableRowCount = self.tableView.numberOfRows(inSection: 0)
            // print("📊 REFERENCE_SCROLL: Table has \(tableRowCount) rows, array has \(messagesArray.count) items")

            // Make sure the index is valid for the table
            if targetIndex < tableRowCount {
                let indexPath = IndexPath(row: targetIndex, section: 0)

                // Calculate delay based on attempt number
                let delay = Double(attempt - 1) * 0.2  // 0s, 0.2s, 0.4s

                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    // Double-check the table state before scrolling
                    let currentRowCount = self.tableView.numberOfRows(inSection: 0)
                    if targetIndex < currentRowCount {
                        // Force layout before scrolling
                        self.tableView.layoutIfNeeded()

                        // Perform the scroll
                        self.tableView.scrollToRow(at: indexPath, at: .top, animated: false)

                        // print("🎯 REFERENCE_SCROLL: Successfully scrolled to reference message at index \(targetIndex) (attempt \(attempt))")

                        // Verify scroll position after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let visibleIndexPaths = self.tableView.indexPathsForVisibleRows ?? []
                            let isVisible = visibleIndexPaths.contains(indexPath)

                            if isVisible {
                                // print("✅ REFERENCE_SCROLL: Reference message is now visible, clearing reference ID")
                                self.lastBeforeMessageId = nil
                            } else {
                                // print("⚠️ REFERENCE_SCROLL: Reference message not visible after scroll, retrying...")
                                // Retry with next attempt
                                self.attemptScrollToReference(
                                    referenceId: referenceId, messagesArray: messagesArray,
                                    attempt: attempt + 1, maxRetries: maxRetries)
                            }
                        }
                    } else {
                        // print("⚠️ REFERENCE_SCROLL: Index \(targetIndex) out of bounds (table has \(currentRowCount) rows), retrying...")
                        // Retry with next attempt
                        self.attemptScrollToReference(
                            referenceId: referenceId, messagesArray: messagesArray,
                            attempt: attempt + 1, maxRetries: maxRetries)
                    }
                }
            } else {
                // print("⚠️ REFERENCE_SCROLL: Index \(targetIndex) out of bounds for table with \(tableRowCount) rows, retrying...")
                // Retry with next attempt
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.attemptScrollToReference(
                        referenceId: referenceId, messagesArray: messagesArray,
                        attempt: attempt + 1, maxRetries: maxRetries)
                }
            }
        } else {
            // print("⚠️ REFERENCE_SCROLL: Reference message '\(referenceId)' not found in array, retrying...")

            // print some debug info about the array
            if messagesArray.count > 0 {
                let first5 = Array(messagesArray.prefix(5))
                let last5 = Array(messagesArray.suffix(5))
                // print("🔍 REFERENCE_SCROLL: Array first 5: \(first5)")
                // print("🔍 REFERENCE_SCROLL: Array last 5: \(last5)")
            }

            // Retry with next attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Get fresh messages array in case it changed
                let freshArray =
                    !self.viewModel.messages.isEmpty
                    ? self.viewModel.messages
                    : (self.viewModel.viewState.channelMessages[self.viewModel.channel.id] ?? [])
                self.attemptScrollToReference(
                    referenceId: referenceId, messagesArray: freshArray, attempt: attempt + 1,
                    maxRetries: maxRetries)
            }
        }
    }
    
    /// Scroll to a specific message that's already loaded
    internal func scrollToMessage(messageId: String) {
        guard let index = localMessages.firstIndex(of: messageId) else {
            print("❌ SCROLL_TO_MESSAGE: Message \(messageId) not found in local messages")
            return
        }

        let indexPath = IndexPath(row: index, section: 0)

        // Make sure the index is valid
        guard index < tableView.numberOfRows(inSection: 0) else {
            print("❌ SCROLL_TO_MESSAGE: Index \(index) out of bounds")
            return
        }

        print("🎯 SCROLL_TO_MESSAGE: Scrolling to message at index \(index)")

        // Scroll to the message
        safeScrollToRow(
            at: indexPath, at: .middle, animated: true, reason: "scroll to specific message")

        // Highlight the message briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let cell = self.tableView.cellForRow(at: indexPath) as? MessageCell {
                self.highlightMessageBriefly(cell: cell)
            }
        }
    }
    
    // Method to safely activate target message protection to prevent jumping
    internal func activateTargetMessageProtection(reason: String) {
        print("🛡️ ACTIVATE_PROTECTION: Activating target message protection - reason: \(reason)")
        isInTargetMessagePosition = true
        lastTargetMessageHighlightTime = Date()
        targetMessageProcessed = false

        // Clear any existing timer to prevent premature clearing
        clearTargetMessageTimer?.invalidate()
        clearTargetMessageTimer = nil

        // IMPROVED: Set a very long fallback timer (5 minutes) to eventually clear protection
        // This gives user plenty of time to explore chat context freely
        clearTargetMessageTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: false) {
            [weak self] _ in
            self?.clearTargetMessageProtection(reason: "5-minute fallback timer")
        }
    }
    
    // Method to safely clear target message protection when user explicitly interacts
    internal func clearTargetMessageProtection(reason: String) {
        print("🎯 CLEAR_PROTECTION: Clearing target message protection - reason: \(reason)")
        print(
            "🎯 CLEAR_PROTECTION: Previous state - targetMessageId: \(targetMessageId ?? "nil"), isInPosition: \(isInTargetMessagePosition), processed: \(targetMessageProcessed)"
        )
        targetMessageId = nil
        isInTargetMessagePosition = false
        lastTargetMessageHighlightTime = nil
        targetMessageProcessed = false
        clearTargetMessageTimer?.invalidate()
        clearTargetMessageTimer = nil
        viewModel.viewState.currentTargetMessageId = nil
        print("🎯 CLEAR_PROTECTION: Protection successfully cleared")
    }
    
    // Debug function to check protection status
    internal func debugTargetMessageProtection() {
        print("🔍 TARGET_MESSAGE_DEBUG:")
        print("   - targetMessageId: \(targetMessageId ?? "nil")")
        print("   - isInTargetMessagePosition: \(isInTargetMessagePosition)")
        print("   - targetMessageProcessed: \(targetMessageProcessed)")
        print("   - protectionActive: \(targetMessageProtectionActive)")
        print("   - timer active: \(clearTargetMessageTimer != nil)")
        if let timer = clearTargetMessageTimer {
            print("   - timer remaining: \(timer.fireDate.timeIntervalSinceNow)s")
        }
    }
    
    // ULTIMATE PROTECTION: Override scrollToRow to block ALL unwanted auto-scrolls
    internal func safeScrollToRow(
        at indexPath: IndexPath, at position: UITableView.ScrollPosition, animated: Bool,
        reason: String
    ) {
        print(
            "🔍 SCROLL_ATTEMPT: \(reason) - target row: \(indexPath.row), position: \(position), animated: \(animated)"
        )
        debugTargetMessageProtection()

        // Allow target message navigation and user-initiated scrolls
        let allowedReasons = ["target message", "scroll to specific message", "user interaction"]
        let isAllowedReason = allowedReasons.contains {
            reason.lowercased().contains($0.lowercased())
        }

        if targetMessageProtectionActive && !isAllowedReason {
            print("🛡️ BLOCKED_SCROLL: scrollToRow blocked by protection - reason: \(reason)")
            print(
                "🛡️ BLOCKED_SCROLL: attempted scroll to row \(indexPath.row), position: \(position), animated: \(animated)"
            )
            return
        }

        if isAllowedReason {
            print("✅ ALLOWED_SCROLL: scrollToRow allowed (whitelisted reason) - \(reason)")
        } else {
            print("✅ ALLOWED_SCROLL: scrollToRow allowed (no protection) - \(reason)")
        }
        tableView.scrollToRow(at: indexPath, at: position, animated: animated)
    }
    
    // Enhanced scrollToBottom with protection debugging
    func logScrollToBottomAttempt(animated: Bool, reason: String) {
        print("🔍 SCROLL_TO_BOTTOM_ATTEMPT: \(reason) - animated: \(animated)")
        debugTargetMessageProtection()
    }
    
}
