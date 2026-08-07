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
        // print("🚫 Disabling auto-acknowledgment for \(autoAckDisableDuration) seconds")
        isAutoAckDisabled = true
        autoAckDisableTime = Date()
    }

    internal func isAutoAcknowledgmentProtectionActive() -> Bool {
        guard let disableTime = autoAckDisableTime else { return false }

        if Date().timeIntervalSince(disableTime) < autoAckDisableDuration {
            return true
        }

        isAutoAckDisabled = false
        autoAckDisableTime = nil
        return false
    }

    // Mark the last message as seen by the user - with rate limiting
    func markLastMessageAsSeen() {
        if unreadSeparatorMessageId != nil || unreadAnchorLastReadMessageId != nil || hasUnreadMessages {
            return
        }

        // Check if auto-acknowledgment is temporarily disabled
        if isAutoAcknowledgmentProtectionActive() {
            // print("🚫 Auto-acknowledgment disabled - skipping markLastMessageAsSeen")
            return
        }

        // Only mark as seen if there are messages and we're not already doing it
        guard let lastMessageId = latestAutomaticAcknowledgementId(),
              !isAcknowledgingMessage else {
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

        // ACK cursors must only move forwards. A delayed retry for an older message
        // must not overwrite a newer ACK that has already succeeded.
        if let acknowledgedId = viewModel.viewState.unreads[channelId]?.last_id,
           acknowledgedId >= messageId {
            return
        }

        retryQueue.removeAll {
            $0.channelId == channelId && $0.messageId <= messageId
        }
        if retryQueue.contains(where: {
            $0.channelId == channelId && $0.messageId > messageId
        }) {
            return
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

            if let acknowledgedId = viewModel.viewState.unreads[nextTask.channelId]?.last_id,
               acknowledgedId >= nextTask.messageId {
                processRetryQueue()
                return
            }

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

    private func captureUnreadAnchor(lastReadId: String, acknowledgeLatest: Bool) {
        unreadAnchorLastReadMessageId = lastReadId
        unreadSeparatorMessageId = localMessages.first { $0 > lastReadId }
        didPositionAtUnreadSeparator = false
        didRequestUnreadContextLoad = false
        didRequestUnreadStateRefresh = false

        if acknowledgeLatest {
            acknowledgeLatestMessageImmediately(messageId: viewModel.channel.last_message_id ?? localMessages.last)
        }

        if unreadSeparatorMessageId == nil {
            loadUnreadMessagesAfterLastReadIfNeeded()
        }
    }

    internal func refreshUnreadSeparatorFromServerState() {
        guard !isAutoAcknowledgmentProtectionActive() else { return }
        guard unreadAnchorLastReadMessageId == nil, unreadSeparatorMessageId == nil else { return }
        guard let unread = viewModel.viewState.unreads[viewModel.channel.id] else {
            refreshUnreadStateFromServerIfNeeded()
            return
        }
        let latestMessageId = viewModel.channel.last_message_id ?? localMessages.last

        if let lastReadId = unread.last_id {
            if let latestMessageId {
                guard lastReadId < latestMessageId else { return }
            }
            captureUnreadAnchor(lastReadId: lastReadId, acknowledgeLatest: true)
        } else {
            unreadSeparatorMessageId = localMessages.first
            didPositionAtUnreadSeparator = false
            didRequestUnreadContextLoad = false
            didRequestUnreadStateRefresh = false
            if unreadSeparatorMessageId != nil {
                acknowledgeLatestMessageImmediately(messageId: latestMessageId)
            }
        }
    }

    internal func captureUnreadSeparatorForIncomingMessages(previousMessages: [String]) {
        if unreadAnchorLastReadMessageId == nil, unreadSeparatorMessageId == nil {
            let previousIds = Set(previousMessages)
            unreadAnchorLastReadMessageId = previousMessages.last
            unreadSeparatorMessageId = localMessages.first { !previousIds.contains($0) }
            didPositionAtUnreadSeparator = false
            didRequestUnreadContextLoad = false
            didRequestUnreadStateRefresh = false
            if unreadSeparatorMessageId != nil {
                acknowledgeLatestMessageImmediately(messageId: viewModel.channel.last_message_id ?? localMessages.last)
            }
        }
        updateLiveUnreadMessageBadge()
    }

    internal func markMessageAsUnreadFromContextMenu(_ message: Message) {
        syncLocalMessagesWithViewState()

        guard let selectedIndex = localMessages.firstIndex(of: message.id) else { return }
        let previousMessageId = selectedIndex > 0 ? localMessages[selectedIndex - 1] : nil
        let ackMessageId = previousMessageId ?? message.id

        disableAutoAcknowledgment()
        unreadAnchorLastReadMessageId = previousMessageId
        unreadSeparatorMessageId = message.id
        didPositionAtUnreadSeparator = true
        didRequestUnreadContextLoad = false
        didRequestUnreadStateRefresh = false
        didManuallyMarkUnreadInCurrentSession = true
        didRequestLatestPositionFromButton = false
        hasUnreadMessages = true

        if let localDataSource = dataSource as? LocalMessagesDataSource {
            localDataSource.updateMessages(localMessages)
            localDataSource.invalidateMessageCache(forMessageId: message.id)
        }
        cellHeightCache.invalidate(messageId: message.id)
        continuationCache.removeValue(forKey: message.id)
        acknowledgeLatestMessageImmediately(messageId: ackMessageId, allowOlderMessage: true)
        updateLiveUnreadMessageBadge()
        showNewMessageButton(markUnread: false)

        UIView.performWithoutAnimation {
            tableView.reloadData()
            tableView.layoutIfNeeded()
        }

        let indexPath = IndexPath(row: selectedIndex, section: 0)
        if tableView.numberOfSections > 0,
           selectedIndex < tableView.numberOfRows(inSection: 0) {
            UIView.performWithoutAnimation {
                tableView.reloadRows(at: [indexPath], with: .none)
                tableView.layoutIfNeeded()
            }
            if let cell = tableView.cellForRow(at: indexPath) as? MessageCell {
                cell.setUnreadSeparatorVisible(true)
                cell.contentView.setNeedsLayout()
                cell.contentView.layoutIfNeeded()
            }
            UIView.performWithoutAnimation {
                tableView.performBatchUpdates(nil)
                tableView.layoutIfNeeded()
            }
        }
    }

    private func scrollToUnreadSeparator(row: Int, animated: Bool) {
        tableView.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: animated)
        didPositionAtUnreadSeparator = true
    }

    internal func shouldShowUnreadSeparator(for messageId: String) -> Bool {
        unreadSeparatorMessageId == messageId
    }

    internal func isAtAbsoluteBottomOfChat() -> Bool {
        guard !localMessages.isEmpty else { return false }

        let visibleRows = tableView.indexPathsForVisibleRows?.map(\.row) ?? []
        guard visibleRows.contains(localMessages.count - 1) else { return false }

        let visibleBottom =
            tableView.contentOffset.y + tableView.bounds.height - tableView.adjustedContentInset.bottom
        let distanceFromBottom = tableView.contentSize.height - visibleBottom
        return distanceFromBottom <= 12
    }

    internal func isUnreadSeparatorVisibleInViewport() -> Bool {
        guard let separatorId = unreadSeparatorMessageId,
              let separatorRow = localMessages.firstIndex(of: separatorId) else {
            return false
        }
        let visibleRows = tableView.indexPathsForVisibleRows?.map(\.row) ?? []
        return visibleRows.contains(separatorRow)
    }

    internal func shouldClearUnreadMarkerAtBottom() -> Bool {
        guard unreadSeparatorMessageId != nil || unreadAnchorLastReadMessageId != nil else {
            return false
        }
        guard isAtAbsoluteBottomOfChat() else { return false }
        // Keep the pointer while the user can still see the NEW MESSAGES divider.
        if isUnreadSeparatorVisibleInViewport() {
            return false
        }
        return true
    }

    internal func hasPendingUnreadSeparatorPosition() -> Bool {
        unreadSeparatorMessageId != nil || unreadAnchorLastReadMessageId != nil
    }

    internal func tryClearUnreadMarkerIfAtAbsoluteBottom() {
        guard !didManuallyMarkUnreadInCurrentSession else { return }
        guard !isAutoAcknowledgmentProtectionActive() else { return }
        guard shouldClearUnreadMarkerAtBottom() else { return }
        clearUnreadMarkerAndAcknowledgeLatest()
    }

    internal func positionAtUnreadSeparatorIfNeeded(force: Bool = false) -> Bool {
        if shouldLoadUnreadContextBeforePositioning() {
            loadUnreadMessagesAfterLastReadIfNeeded()
            return false
        }

        guard !didRequestLatestPositionFromButton,
              (force || !didPositionAtUnreadSeparator),
              let markerId = unreadSeparatorMessageId,
              let row = localMessages.firstIndex(of: markerId),
              tableView.dataSource != nil,
              tableView.numberOfSections > 0,
              row < tableView.numberOfRows(inSection: 0) else {
            return false
        }

        tableView.layoutIfNeeded()
        scrollToUnreadSeparator(row: row, animated: false)
        didPositionAtUnreadSeparator = true
        showNewMessageButton(markUnread: false)
        loadUnreadMessagesAfterLastReadIfNeeded()
        return true
    }

    private func shouldLoadUnreadContextBeforePositioning() -> Bool {
        unreadAnchorLastReadMessageId != nil
            && !didRequestUnreadContextLoad
            && !didManuallyMarkUnreadInCurrentSession
            && !didRequestLatestPositionFromButton
    }

    internal func clearUnreadMarkerAndAcknowledgeLatest(messageId: String? = nil) {
        clearUnreadMarkerState()
        hideNewMessageButton()
        acknowledgeLatestMessageImmediately(messageId: messageId)
        tableView?.reloadData()
    }

    internal func clearUnreadMarkerState() {
        unreadAnchorLastReadMessageId = nil
        unreadSeparatorMessageId = nil
        liveUnreadMessageIds.removeAll()
        didPositionAtUnreadSeparator = false
        didRequestUnreadContextLoad = false
        didRequestUnreadStateRefresh = false
        didManuallyMarkUnreadInCurrentSession = false
        didRequestLatestPositionFromButton = false
        updateLiveUnreadMessageBadge()
    }

    private func latestAutomaticAcknowledgementId(requestedId: String? = nil) -> String? {
        [
            requestedId,
            viewModel.channel.last_message_id,
            localMessages.max(),
            viewModel.messages.max(),
            viewModel.viewState.unreads[viewModel.channel.id]?.last_id
        ]
        .compactMap { $0 }
        .max()
    }

    internal func acknowledgeLatestMessageImmediately(
        messageId: String? = nil,
        allowOlderMessage: Bool = false
    ) {
        let resolvedMessageId = allowOlderMessage
            ? messageId
            : latestAutomaticAcknowledgementId(requestedId: messageId)
        guard let latestMessageId = resolvedMessageId else { return }
        let channelId = viewModel.channel.id

        if var unread = viewModel.viewState.unreads[channelId] {
            unread.last_id = latestMessageId
            unread.mentions = []
            viewModel.viewState.unreads[channelId] = unread
        } else if let currentUserId = viewModel.viewState.currentUser?.id {
            let unreadId = Unread.Id(channel: channelId, user: currentUserId)
            viewModel.viewState.unreads[channelId] = Unread(
                id: unreadId,
                last_id: latestMessageId,
                mentions: []
            )
        }

        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.viewModel.viewState.http.ackMessage(
                channel: channelId,
                message: latestMessageId
            ).get()
            await MainActor.run {
                self.viewModel.viewState.updateAppBadgeCount()
            }
        }
    }

    internal func refreshUnreadStateFromServerIfNeeded() {
        guard !isAutoAcknowledgmentProtectionActive() else { return }
        guard !didRequestUnreadStateRefresh else { return }
        guard !localMessages.isEmpty else { return }
        didRequestUnreadStateRefresh = true
        let channelId = viewModel.channel.id

        Task { [weak self] in
            guard let self else { return }
            guard let remoteUnreads = try? await self.viewModel.viewState.http.fetchUnreads().get() else { return }
            guard let currentUnread = remoteUnreads.first(where: { $0.id.channel == channelId }) else { return }

            await MainActor.run {
                guard self.canApplyLoadResult(for: channelId), !self.isViewDisappearing else { return }
                self.viewModel.viewState.unreads[channelId] = currentUnread
                self.refreshUnreadSeparatorFromServerState()
                guard self.unreadSeparatorMessageId != nil else { return }
                UIView.performWithoutAnimation {
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()
                }
                _ = self.positionAtUnreadSeparatorIfNeeded()
            }
        }
    }

    internal func loadUnreadMessagesAfterLastReadIfNeeded() {
        guard !didRequestUnreadContextLoad else { return }
        guard let lastReadId = unreadAnchorLastReadMessageId else { return }
        if let latestMessageId = viewModel.channel.last_message_id ?? localMessages.last {
            guard lastReadId < latestMessageId else { return }
        }

        didRequestUnreadContextLoad = true
        let channelId = viewModel.channel.id
        let serverId = viewModel.channel.server

        Task { [weak self] in
            guard let self else { return }
            let result = await self.viewModel.viewState.http.fetchHistory(
                channel: channelId,
                limit: 100,
                after: lastReadId,
                sort: "Oldest",
                server: serverId,
                include_users: true
            )

            guard case .success(let history) = result, !history.messages.isEmpty else {
                await MainActor.run {
                    guard self.canApplyLoadResult(for: channelId), !self.isViewDisappearing else { return }
                    if !self.didRequestLatestPositionFromButton {
                        _ = self.positionAtUnreadSeparatorIfNeeded()
                    }
                    self.hideSkeletonView()
                    self.tableView.tableFooterView = nil
                    self.tableView.alpha = 1.0
                }
                return
            }

            await MainActor.run {
                guard self.canApplyLoadResult(for: channelId), !self.isViewDisappearing else { return }

                for user in history.users {
                    self.viewModel.viewState.users[user.id] = user
                    self.viewModel.viewState.allEventUsers[user.id] = user
                }
                if let members = history.members {
                    for member in members {
                        self.viewModel.viewState.members[member.id.server, default: [:]][member.id.user] = member
                    }
                }
                for message in history.messages {
                    self.viewModel.viewState.messages[message.id] = message
                }

                let newIds = history.messages.map { $0.id }
                let deleted = self.viewModel.viewState.deletedMessageIds[channelId] ?? []
                let mergedIds = Array(Set(self.localMessages + newIds))
                    .filter { !deleted.contains($0) }
                    .sorted()

                self.localMessages = mergedIds
                self.viewModel.messages = mergedIds
                self.viewModel.viewState.channelMessages[channelId] = mergedIds
                self.unreadSeparatorMessageId = mergedIds.first { $0 > lastReadId }
                if !self.didRequestLatestPositionFromButton {
                    self.didPositionAtUnreadSeparator = false
                }

                if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                    localDataSource.updateMessages(mergedIds)
                } else {
                    self.dataSource = LocalMessagesDataSource(
                        viewModel: self.viewModel,
                        viewController: self,
                        localMessages: mergedIds
                    )
                    self.tableView.dataSource = self.dataSource
                }

                UIView.performWithoutAnimation {
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()
                }
                if self.didRequestLatestPositionFromButton {
                    self.scrollToLatestMessageFromButton()
                } else {
                    _ = self.positionAtUnreadSeparatorIfNeeded(force: self.didPositionAtUnreadSeparator)
                }
                self.hideSkeletonView()
                self.tableView.tableFooterView = nil
                self.tableView.alpha = 1.0
                self.updateTableViewBouncing()
            }
        }
    }
}
