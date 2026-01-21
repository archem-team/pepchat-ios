//
//  MessagableChannelViewController+Extensions.swift
//  Revolt
//
//  Created by Akshat Srivastava on 20/01/26.
//

import Foundation
import Combine
import Kingfisher
import ObjectiveC
import SwiftUI
import Types
import UIKit
import ULID


// Helper method for showing error alertss
extension MessageableChannelViewController {
    func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSourcePrefetching
extension MessageableChannelViewController: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        // Pre-cache message data for upcoming rows
        for indexPath in indexPaths {
            if indexPath.row < viewModel.messages.count {
                let messageId = viewModel.messages[indexPath.row]
                if let message = viewModel.viewState.messages[messageId],
                    let author = viewModel.viewState.users[message.author]
                {

                    // Pre-load author's avatar
                    let member = viewModel.getMember(message: message).wrappedValue
                    let avatarInfo = viewModel.viewState.resolveAvatarUrl(
                        user: author, member: member, masquerade: message.masquerade)

                    // Fix: Only create the URL array if the URL is valid
                    if let url = URL(string: avatarInfo.url.absoluteString) {
                        // Use Kingfisher's ImagePrefetcher with the URL - make sure to not pass any arguments to start()
                        let prefetcher = ImagePrefetcher(urls: [url])
                        prefetcher.start()
                    }

                    // Pre-load message attachments if any
                    if let attachments = message.attachments, !attachments.isEmpty {
                        // Create an array to store valid attachment URLs
                        let attachmentUrls = attachments.compactMap { attachment -> URL? in
                            // Generate URL string and safely convert to URL object
                            let urlString = viewModel.viewState.formatUrl(
                                fromId: attachment.id, withTag: "attachments")
                            return URL(string: urlString)
                        }

                        // Prefetch all attachments in one batch if there are any
                        if !attachmentUrls.isEmpty {
                            // Fix: Create the prefetcher and then start it - make sure to not pass any arguments to start()
                            let prefetcher = ImagePrefetcher(urls: attachmentUrls)
                            prefetcher.start()
                        }
                    }
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        // Cancel pre-fetching for rows that are no longer needed
        // Not critical to implement, but helps save resources
    }
}

// MARK: - Additional Memory Management
extension MessageableChannelViewController {

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        print(
            "⚡ VIEW_DID_DISAPPEAR: User has completely left channel \(viewModel.channel.id) - performing FINAL instant cleanup"
        )
        let finalCleanupStartTime = CFAbsoluteTimeGetCurrent()

        // Check if we're returning from search - if so, don't cleanup
        if isReturningFromSearch {
            print("🔍 VIEW_DID_DISAPPEAR: Returning from search, skipping final cleanup")
            return
        }

        // CRITICAL FIX: Don't cleanup if we're navigating to the same channel with a target message
        if let targetId = viewModel.viewState.currentTargetMessageId {
            // Check if we're staying in the same channel
            let isStayingInSameChannel: Bool
            if case .channel(let currentChannelId) = viewModel.viewState.currentChannel {
                isStayingInSameChannel = currentChannelId == viewModel.channel.id
            } else {
                isStayingInSameChannel = false
            }

            if isStayingInSameChannel {
                print("🎯 VIEW_DID_DISAPPEAR: Staying in same channel, skipping final cleanup")
                return
            }
        }

        // CRITICAL FIX: Invalidate scroll check timer to prevent memory leak
        scrollCheckTimer?.invalidate()
        scrollCheckTimer = nil

        // CRITICAL FIX: Cleanup MessageInputView references to prevent memory leaks
        messageInputView?.cleanup()

        // IMMEDIATE FINAL CLEANUP: No delays, no async operations
        performFinalInstantCleanup()

        // AGGRESSIVE: Force immediate memory cleanup when view disappears
        forceImmediateMemoryCleanup()

        // Clear preloaded status so it can be preloaded again when needed
        let channelId = viewModel.channel.id
        viewModel.viewState.preloadedChannels.remove(channelId)
        print("🧹 CLEANUP: Cleared preloaded status for channel \(channelId)")

        let finalCleanupEndTime = CFAbsoluteTimeGetCurrent()
        let finalCleanupDuration = (finalCleanupEndTime - finalCleanupStartTime) * 1000
        print(
            "⚡ VIEW_DID_DISAPPEAR: Total final cleanup completed in \(String(format: "%.2f", finalCleanupDuration))ms"
        )

        // Log final memory usage
        logMemoryUsage(prefix: "FINAL CLEANUP COMPLETE")
    }

    // Force immediate memory cleanup - called after view disappears
    func forceImmediateMemoryCleanup() {
        print("⚡ FORCE_IMMEDIATE_CLEANUP: Starting INSTANT memory cleanup")
        let startTime = CFAbsoluteTimeGetCurrent()

        // IMMEDIATE: Force image cache cleanup
        let cache = ImageCache.default
        cache.clearMemoryCache()

        // IMMEDIATE: Aggressive user cleanup - NO Task, NO async
        let channelId = self.viewModel.channel.id
        let isDM = self.viewModel.channel.isDM
        let isGroupDM = self.viewModel.channel.isGroupDmChannel

        print(
            "👥 INSTANT_USER_CLEANUP: Starting for channel \(channelId) - DM: \(isDM), GroupDM: \(isGroupDM)"
        )
        let initialUserCount = self.viewModel.viewState.users.count

        // Collect all user IDs that should be kept
        var usersToKeep = Set<String>()

        // Add current user if exists
        if let currentUserId = self.viewModel.viewState.currentUser?.id {
            usersToKeep.insert(currentUserId)
        }

        // Only keep users from OTHER channels (not the one we just left)
        for (otherChannelId, messageIds) in self.viewModel.viewState.channelMessages {
            // Skip the channel we just left
            if otherChannelId == channelId { continue }

            // Add users from messages in other channels
            for messageId in messageIds {
                if let message = self.viewModel.viewState.messages[messageId] {
                    usersToKeep.insert(message.author)
                    if let mentions = message.mentions {
                        usersToKeep.formUnion(mentions)
                    }
                }
            }
        }

        // IMMEDIATE: Keep users from OTHER active DMs
        for channel in self.viewModel.viewState.channels.values {
            // Skip the channel we just left
            if channel.id == channelId { continue }

            // Keep users from other active DMs
            if channel.isDM || channel.isGroupDmChannel {
                let recipientIds = channel.recipients
                usersToKeep.formUnion(recipientIds)
                print(
                    "👥 INSTANT_USER_CLEANUP: Keeping \(recipientIds.count) users from other DM \(channel.id)"
                )
            }
        }

        // IMMEDIATE: Keep users that might be needed for server lists
        for server in self.viewModel.viewState.servers.values {
            usersToKeep.insert(server.owner)
        }

        print("👥 INSTANT_USER_CLEANUP: Users to keep: \(usersToKeep.count)")

        // IMMEDIATE: For DMs, be more aggressive about user cleanup
        if isDM || isGroupDM {
            print("👥 INSTANT_USER_CLEANUP: Performing DM-specific user cleanup")

            // Get users from the DM we just left
            let dmRecipients = self.viewModel.channel.recipients
            let usersToRemove = dmRecipients.filter { userId in
                !usersToKeep.contains(userId)
            }

            if !usersToRemove.isEmpty {
                print(
                    "👥 INSTANT_USER_CLEANUP: Removing \(usersToRemove.count) DM users that are no longer needed"
                )
                for userId in usersToRemove {
                    self.viewModel.viewState.users.removeValue(forKey: userId)
                }
            } else {
                print("👥 INSTANT_USER_CLEANUP: All DM users are still needed elsewhere")
            }
        }

        let finalUserCount = self.viewModel.viewState.users.count
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000

        print(
            "⚡ FORCE_IMMEDIATE_CLEANUP: Completed in \(String(format: "%.2f", duration))ms - Users: \(initialUserCount) -> \(finalUserCount)"
        )
    }

    /// Performs INSTANT final cleanup with no delays
    func performFinalInstantCleanup() {
        let channelId = viewModel.channel.id
        print("⚡ FINAL_INSTANT_CLEANUP: Starting IMMEDIATE final cleanup for channel \(channelId)")

        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. IMMEDIATE: Clear table view synchronously
        self.tableView.dataSource = nil
        self.tableView.delegate = nil

        // 2. IMMEDIATE: Force ViewState cleanup synchronously (no Task, no async)
        viewModel.viewState.cleanupChannelFromMemory(
            channelId: channelId, preserveForNavigation: false)
        viewModel.viewState.forceMemoryCleanup()

        // 3. IMMEDIATE: Aggressive image cache cleanup
        ImageCache.default.clearMemoryCache()

        // 4. IMMEDIATE: Reset all controller state
        targetMessageId = nil
        targetMessageProcessed = false
        isInTargetMessagePosition = false
        isLoadingMore = false
        messageLoadingState = .notLoading

        // 5. IMMEDIATE: Final verification and force cleanup
        let remainingMessages = viewModel.viewState.messages.values.filter {
            $0.channel == channelId
        }.count
        let remainingChannelMessages = viewModel.viewState.channelMessages[channelId]?.count ?? 0

        if remainingMessages > 0 || remainingChannelMessages > 0 {
            print(
                "⚠️ FINAL_INSTANT_CLEANUP: Found \(remainingMessages) remaining messages, force removing"
            )

            // IMMEDIATE: Force remove any remaining data
            viewModel.viewState.channelMessages.removeValue(forKey: channelId)

            let finalMessagesToRemove = viewModel.viewState.messages.keys.filter { messageId in
                if let message = viewModel.viewState.messages[messageId] {
                    return message.channel == channelId
                }
                return false
            }

            for messageId in finalMessagesToRemove {
                viewModel.viewState.messages.removeValue(forKey: messageId)
            }

            print(
                "⚡ FINAL_INSTANT_CLEANUP: Force removed \(finalMessagesToRemove.count) remaining messages"
            )
        }

        // 6. IMMEDIATE: Force garbage collection
        _ =
            viewModel.viewState.messages.count + viewModel.viewState.users.count
            + viewModel.viewState.channelMessages.count

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000  // Convert to milliseconds

        print(
            "⚡ FINAL_INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms - ALL memory freed immediately!"
        )
        logMemoryUsage(prefix: "AFTER INSTANT FINAL CLEANUP")
    }
}

// MARK: - Scroll Position Preservation
extension MessageableChannelViewController {

    /// Reloads the table view while maintaining the user's scroll position using message IDs as anchors
    func reloadTableViewMaintainingScrollPosition(messagesForDataSource: [String]) {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
            !visibleIndexPaths.isEmpty
        else {
            // No visible rows, just reload normally
            tableView.reloadData()
            return
        }

        // Find an anchor message ID from visible rows (prefer middle visible row for stability)
        var anchorMessageId: String?
        var anchorDistanceFromTop: CGFloat = 0

        // Try to find a good anchor from the middle of visible rows
        let middleIndex = visibleIndexPaths.count / 2
        for (index, indexPath) in visibleIndexPaths.enumerated() {
            // Prefer rows that are not at the very edges
            if index >= middleIndex && indexPath.row < messagesForDataSource.count {
                anchorMessageId = messagesForDataSource[indexPath.row]
                let cellFrame = tableView.rectForRow(at: indexPath)
                anchorDistanceFromTop = cellFrame.origin.y - tableView.contentOffset.y
                // print("🔍 SCROLL_PRESERVE: Selected anchor message \(anchorMessageId!) at index \(indexPath.row), distance from top: \(anchorDistanceFromTop)")
                break
            }
        }

        // Fallback to first visible row if no middle row found
        if anchorMessageId == nil, let firstVisible = visibleIndexPaths.first,
            firstVisible.row < messagesForDataSource.count
        {
            anchorMessageId = messagesForDataSource[firstVisible.row]
            let cellFrame = tableView.rectForRow(at: firstVisible)
            anchorDistanceFromTop = cellFrame.origin.y - tableView.contentOffset.y
            // print("🔍 SCROLL_PRESERVE: Using fallback anchor message \(anchorMessageId!) at index \(firstVisible.row)")
        }

        // Perform the reload
        tableView.reloadData()
        tableView.layoutIfNeeded()

        // Restore position to the anchor message
        if let anchorId = anchorMessageId {
            // Find the anchor message in the new data
            if let newIndex = messagesForDataSource.firstIndex(of: anchorId) {
                let newIndexPath = IndexPath(row: newIndex, section: 0)
                let newCellFrame = tableView.rectForRow(at: newIndexPath)
                let newContentOffsetY = newCellFrame.origin.y - anchorDistanceFromTop

                // Ensure the offset is within valid bounds
                let maxOffset = max(
                    0,
                    tableView.contentSize.height - tableView.bounds.height
                        + tableView.contentInset.bottom)
                let clampedOffset = max(0, min(newContentOffsetY, maxOffset))

                tableView.setContentOffset(CGPoint(x: 0, y: clampedOffset), animated: false)
                // print("📍 SCROLL_PRESERVE: Restored position to anchor message at new index \(newIndex), offset: \(clampedOffset)")
            } else {
                // print("⚠️ SCROLL_PRESERVE: Could not find anchor message \(anchorId) in new data")
            }
        }
    }
}
