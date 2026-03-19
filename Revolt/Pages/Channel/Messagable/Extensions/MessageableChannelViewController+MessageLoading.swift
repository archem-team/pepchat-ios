//
//  MessageableChannelViewController+MessageLoading.swift
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
    /// Merges two pre-sorted lists of message IDs, dedupes, preserving sort order.
    /// ULIDs are lexicographically sortable by timestamp, so plain string comparison is correct
    /// and avoids expensive ULID→Date parsing on every comparison.
    /// O(n) two-pointer merge instead of O(n log n) re-sort.
    private func mergeAndSortMessageIds(existing: [String], new: [String]) -> [String] {
        // Fast paths
        guard !existing.isEmpty else { return new }
        guard !new.isEmpty else { return existing }

        // Sort inputs to guarantee the two-pointer merge is correct.
        // Still faster than main's approach: plain string comparison vs ULID→Date parsing.
        let sortedExisting = existing.sorted()
        let sortedNew = new.sorted()

        let newSet = Set(sortedNew)
        // Remove duplicates from existing that also appear in new
        let dedupedExisting = sortedExisting.filter { !newSet.contains($0) }

        var result: [String] = []
        result.reserveCapacity(dedupedExisting.count + sortedNew.count)

        var i = dedupedExisting.startIndex
        var j = sortedNew.startIndex
        while i < dedupedExisting.endIndex && j < sortedNew.endIndex {
            if dedupedExisting[i] <= sortedNew[j] {
                result.append(dedupedExisting[i])
                i += 1
            } else {
                result.append(sortedNew[j])
                j += 1
            }
        }
        // Append remaining
        if i < dedupedExisting.endIndex { result.append(contentsOf: dedupedExisting[i...]) }
        if j < sortedNew.endIndex { result.append(contentsOf: sortedNew[j...]) }
        return result
    }

    /// When loading from cache, prefer ViewState over cached if ViewState has a newer edit (e.g. from a message_update WebSocket event) so edits from other users are not overwritten by stale cache.
    private func isViewStateMessageNewerThanCached(existing: Message, cached: Message) -> Bool {
        guard existing.edited != nil else { return false }
        if cached.edited == nil { return true }
        return (existing.edited ?? "") >= (cached.edited ?? "")
    }

    internal func loadInitialMessages() async {
        let channelId = viewModel.channel.id

        // CRITICAL FIX: Reset empty response time when loading initial messages
        lastEmptyResponseTime = nil
        print("🔄 LOAD_INITIAL: Reset lastEmptyResponseTime for initial load")

        // CRITICAL FIX: Don't reload if user is in target message position
        if isInTargetMessagePosition && targetMessageId == nil {
            print(
                "🎯 LOAD_INITIAL: User is in target message position, skipping reload to preserve position"
            )
            return
        }

        // MARK: - Cache check first (instant show when we have cache)
        let currentChannelId = channelId
        activeChannelId = currentChannelId
        cachedMessageOffset = 0
        let hasCache: Bool
        if let userId = viewModel.viewState.currentUser?.id, let baseURL = viewModel.viewState.baseURL {
            hasCache = await MessageCacheManager.shared.hasCachedMessages(for: channelId, userId: userId, baseURL: baseURL)
            print("📂 [MessageCache] hasCachedMessages(\(channelId)) = \(hasCache)")
        } else {
            hasCache = false
        }
        if let userId = viewModel.viewState.currentUser?.id,
           let baseURL = viewModel.viewState.baseURL,
           hasCache {
            let cached = await MessageCacheManager.shared.loadCachedMessages(
                for: channelId,
                userId: userId,
                baseURL: baseURL,
                limit: cachePageSize,
                offset: 0
            )
            if !cached.isEmpty {
                print("📂 [MessageCache] UI: showing first page (\(cached.count) messages) from cache for channel \(channelId)")
                let authorIds = Set(cached.map { $0.author })
                let cachedUsers = await MessageCacheManager.shared.loadCachedUsers(
                    for: Array(authorIds),
                    currentUserId: userId,
                    baseURL: baseURL
                )
                cachedMessageTotal = await MessageCacheManager.shared.cachedMessageCount(
                    for: channelId,
                    userId: userId,
                    baseURL: baseURL
                )
                await MainActor.run {
                    guard activeChannelId == currentChannelId else { return }
                    for (uid, user) in cachedUsers {
                        viewModel.viewState.users[uid] = user
                    }
                    for message in cached {
                        let existing = viewModel.viewState.messages[message.id]
                        if let existing = existing, isViewStateMessageNewerThanCached(existing: existing, cached: message) {
                            continue
                        }
                        viewModel.viewState.messages[message.id] = message
                    }
                    let deleted = viewModel.viewState.deletedMessageIds[channelId] ?? []
                    let ids = cached.map { $0.id }.filter { !deleted.contains($0) }
                    viewModel.viewState.channelMessages[channelId] = ids
                    viewModel.messages = ids
                    localMessages = ids
                    cachedMessageOffset = ids.count
                    dataSource = LocalMessagesDataSource(viewModel: viewModel, viewController: self, localMessages: localMessages)
                    tableView.dataSource = dataSource
                    tableView.reloadData()
                    hideSkeletonView()
                    tableView.alpha = 1.0
                    updateTableViewBouncing()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.updateTableViewBouncing()
                    }
                }
            }
        }

        // Check if already loading to prevent duplicate calls
        MessageableChannelViewController.loadingMutex.lock()
        if MessageableChannelViewController.loadingChannels.contains(channelId) {
            print("⚠️ Channel \(channelId) is already being loaded, skipping duplicate request")
            MessageableChannelViewController.loadingMutex.unlock()
            return
        } else {
            print("🚀 LOAD_INITIAL: Starting API call for channel \(channelId)")
            MessageableChannelViewController.loadingChannels.insert(channelId)
            messageLoadingState = .loading
            print("🎯 Set messageLoadingState to .loading for initial load")
            MessageableChannelViewController.loadingMutex.unlock()
        }

        // CRITICAL FIX: Hide empty state immediately when loading starts (especially for cross-channel)
        DispatchQueue.main.async {
            self.hideEmptyStateView()
            print("🚫 LOAD_INITIAL: Hidden empty state at start of loading")
        }

        // Ensure cleanup when done
        defer {
            MessageableChannelViewController.loadingMutex.lock()
            MessageableChannelViewController.loadingChannels.remove(channelId)
            MessageableChannelViewController.loadingMutex.unlock()

            // CRITICAL FIX: Reset loading state when done
            messageLoadingState = .notLoading
            print("🎯 Reset messageLoadingState to .notLoading - loadInitialMessages complete")

            DispatchQueue.main.async {
                self.tableView.alpha = 1.0
            }
        }

        // OPTIMIZED: Don't clear existing messages immediately - keep them visible while loading
        // Only clear if we're switching to a completely different channel

        // Check if we have existing messages for this channel
        let hasExistingMessages = viewModel.viewState.channelMessages[channelId]?.isEmpty == false

        if hasExistingMessages {
            // print("📊 Found existing messages for channel: \(channelId), keeping them visible while loading new ones")

            // Keep existing messages visible, just show loading indicator
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Display a loading indicator without clearing messages
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                spinner.frame = CGRect(x: 0, y: 0, width: self.tableView.bounds.width, height: 44)
                self.tableView.tableFooterView = spinner
            }
        } else {
            // print("🧹 No existing messages for channel: \(channelId), starting fresh")

            // Only clear if there are no existing messages
            viewModel.viewState.channelMessages[channelId] = []
            self.localMessages = []

            // Force DataSource refresh immediately to show loading state
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.dataSource = LocalMessagesDataSource(
                    viewModel: self.viewModel,
                    viewController: self,
                    localMessages: self.localMessages)
                self.tableView.dataSource = self.dataSource
                self.tableView.reloadData()

                // Display loading indicator
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                spinner.frame = CGRect(x: 0, y: 0, width: self.tableView.bounds.width, height: 44)
                self.tableView.tableFooterView = spinner
            }
        }

        // Log loading states
        // print("📱 Current ViewState: channelMessages entries = \(viewModel.viewState.channelMessages.count)")
        // print("📱 Current LocalMessages: count = \(self.localMessages.count)")

        // Load messages from the server
        // print("📱 Starting initial message load for channel: \(viewModel.channel.id)")

        if let targetId = self.targetMessageId {
            // We have a specific target message to load
            print("📜 Loading channel with target message ID: \(targetId)")

            // CRITICAL FIX: Use nearby API directly for target messages
            // This ensures we get the target message and surrounding context immediately
            print("🎯 Target message specified, using nearby API directly")

            // CRITICAL FIX: Set strong protection flag BEFORE API call to prevent any other loading
            messageLoadingState = .loading
            isInTargetMessagePosition = true
            lastTargetMessageHighlightTime = Date()
            print("🎯 NEARBY_PROTECTION: Set all protection flags BEFORE nearby API call")

            do {
                // Use the API to fetch messages near the specified message
                print(
                    "🌐 API CALL: fetchHistory (nearby) - Channel: \(viewModel.channel.id), Target: \(targetId), Limit: 100"
                )
                let result = try await viewModel.viewState.http.fetchHistory(
                    channel: viewModel.channel.id,
                    limit: 100,  // Get context around the target message
                    nearby: targetId
                ).get()
                print(
                    "✅ API RESPONSE: fetchHistory (nearby) - Received \(result.messages.count) messages, \(result.users.count) users"
                )

                // print("✅ Nearby API Response received with \(result.messages.count) messages")

                // Fetch reply message content for messages that have replies BEFORE MainActor.run
                print(
                    "🔗 CALLING fetchReplyMessagesContent (nearby API - first call) with \(result.messages.count) messages"
                )
                await self.fetchReplyMessagesContent(for: result.messages)

                // Process and merge the nearby messages with existing channel history
                await MainActor.run {
                    if !result.messages.isEmpty {
                        // print("📊 Processing \(result.messages.count) nearby messages to merge with existing history")

                        // Process users from the response
                        for user in result.users {
                            viewModel.viewState.users[user.id] = user
                        }

                        // Process members if present
                        if let members = result.members {
                            for member in members {
                                viewModel.viewState.members[member.id.server, default: [:]][
                                    member.id.user] = member
                            }
                        }

                        // Process messages - add them to the messages dictionary
                        for message in result.messages {
                            viewModel.viewState.messages[message.id] = message
                        }

                        // Get existing channel messages
                        let existingMessages = viewModel.viewState.channelMessages[channelId] ?? []

                        // Create a set of existing message IDs for quick lookup
                        let existingMessageIds = Set(existingMessages)

                        // Filter out messages that are already in the channel history
                        let newMessages = result.messages.filter {
                            !existingMessageIds.contains($0.id)
                        }

                        if !newMessages.isEmpty {
                            // Sort new messages by timestamp
                            let sortedNewMessages = newMessages.sorted { msg1, msg2 in
                                let date1 = createdAt(id: msg1.id)
                                let date2 = createdAt(id: msg2.id)
                                return date1 < date2
                            }

                            // Merge new messages with existing messages and sort the combined list
                            var allMessages: [Types.Message] = []

                            // Add existing messages
                            for messageId in existingMessages {
                                if let message = viewModel.viewState.messages[messageId] {
                                    allMessages.append(message)
                                }
                            }

                            // Add new messages
                            allMessages.append(contentsOf: sortedNewMessages)

                            // Sort the combined list by timestamp
                            let sortedAllMessages = allMessages.sorted { msg1, msg2 in
                                let date1 = createdAt(id: msg1.id)
                                let date2 = createdAt(id: msg2.id)
                                return date1 < date2
                            }

                            // Create the final list of message IDs
                            let mergedIds = sortedAllMessages.map { $0.id }

                            // Update all message arrays with the merged list
                            self.localMessages = mergedIds
                            self.viewModel.viewState.channelMessages[channelId] = mergedIds
                            self.viewModel.messages = mergedIds

                            // print("🔄 Merged \(newMessages.count) new messages with \(existingMessages.count) existing messages")
                            // print("🔄 Total messages after merge: \(mergedIds.count)")
                        } else {
                            // print("ℹ️ All nearby messages were already in channel history")
                        }

                        // Update UI with the merged message list
                        DispatchQueue.main.async {
                            // Remove loading spinner
                            self.tableView.tableFooterView = nil

                            // Re-create the data source with updated messages
                            self.dataSource = LocalMessagesDataSource(
                                viewModel: self.viewModel,
                                viewController: self,
                                localMessages: self.localMessages)
                            self.tableView.dataSource = self.dataSource
                            self.tableView.reloadData()

                            // Update table view bouncing behavior
                            self.updateTableViewBouncing()

                            // CRITICAL FIX: Keep loading state until target message is scrolled to
                            // This prevents any other loading from interfering
                            print(
                                "🎯 NEARBY_SUCCESS: Keeping messageLoadingState = .loading until scroll completes"
                            )

                            // Instead, trigger scrollToTargetMessage properly
                            if let targetId = self.targetMessageId {
                                print(
                                    "🎯 loadInitialMessages: Found target message \(targetId), triggering scroll"
                                )

                                // Check if target message is actually loaded
                                let targetInLocalMessages = self.localMessages.contains(targetId)
                                let targetInViewState =
                                    self.viewModel.viewState.messages[targetId] != nil

                                print(
                                    "🎯 loadInitialMessages: Target message \(targetId) loaded check:"
                                )
                                print("   - In localMessages: \(targetInLocalMessages)")
                                print("   - In viewState: \(targetInViewState)")

                                if targetInLocalMessages && targetInViewState {
                                    print("✅ Target message is loaded, scrolling to it")
                                    self.scrollToTargetMessage()

                                    // CRITICAL FIX: Only reset loading state AFTER successful scroll
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        self.messageLoadingState = .notLoading
                                        print(
                                            "🎯 NEARBY_COMPLETE: Reset messageLoadingState after scroll completion"
                                        )
                                    }
                                } else {
                                    print(
                                        "❌ Target message NOT loaded, keeping targetMessageId for later"
                                    )
                                    // Reset loading state since we couldn't scroll
                                    self.messageLoadingState = .notLoading
                                }
                            } else {
                                // No target message, reset loading state
                                self.messageLoadingState = .notLoading
                            }

                            // Ensure table is visible
                            self.tableView.alpha = 1.0

                            // Update empty state visibility
                            self.updateEmptyStateVisibility()
                        }
                    } else {
                        // print("⚠️ No messages found nearby target")
                        DispatchQueue.main.async {
                            self.tableView.tableFooterView = nil

                            // CRITICAL FIX: Reset loading state if nearby call returned no messages
                            self.messageLoadingState = .notLoading
                            self.isInTargetMessagePosition = false
                            self.lastTargetMessageHighlightTime = nil
                            print(
                                "🎯 NEARBY_EMPTY: Reset protection flags after empty nearby response"
                            )

                            // Still try to scroll to target in case it was loaded by regular loading
                            self.scrollToTargetMessage()
                        }
                    }
                }
            } catch {
                // If nearby loading fails, fall back to regular loading
                print("⚠️ Failed to load messages nearby target: \(error)")

                DispatchQueue.main.async {
                    self.tableView.tableFooterView = nil

                    // CRITICAL FIX: Reset loading state if nearby call failed
                    self.messageLoadingState = .notLoading
                    self.isInTargetMessagePosition = false
                    self.lastTargetMessageHighlightTime = nil
                    print("🎯 NEARBY_ERROR: Reset protection flags after nearby call error")

                    // Clear target message from ViewState if it failed to load
                    self.viewModel.viewState.currentTargetMessageId = nil
                    self.targetMessageId = nil

                    // Show table view and hide empty state
                    self.tableView.alpha = 1.0
                    self.hideEmptyStateView()
                }

                // Fall back to regular loading
                print("🔄 FALLBACK: Falling back to regular loading after target message failure")
                await loadRegularMessages()
            }
        } else {
            // No target message ID, load regular messages (force fetch so cache is refreshed with server messages that arrived while app was closed)
            await loadRegularMessages(forceFetchFromServer: true)
        }
    }
    
    /// - Parameter forceFetchFromServer: When true (e.g. initial channel open), always fetch from server and merge with existing (cache). When false, use in-memory messages if present.
    private func loadRegularMessages(forceFetchFromServer: Bool = false) async {
        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            print("🎯 LOAD_REGULAR: Target message protection active, skipping regular load")
            return
        }

        // CRITICAL FIX: Set loading state and hide empty state for regular loading
        messageLoadingState = .loading
        DispatchQueue.main.async {
            self.hideEmptyStateView()
            print("🚫 LOAD_REGULAR: Hidden empty state for regular loading")
        }

        // Ensure cleanup when done
        defer {
            messageLoadingState = .notLoading
            print("🎯 LOAD_REGULAR: Reset loading state - complete")
        }

        // print("📜 Loading regular messages")
        let channelId = viewModel.channel.id
        let existingCount = viewModel.viewState.channelMessages[channelId]?.count ?? 0

        // When opening channel (initial load), always fetch from server to get messages that arrived while app was closed; only skip fetch when we have in-memory messages and are not forcing refresh
        let shouldUseMemoryOnly = !forceFetchFromServer && existingCount > 0

        // FIX (Loading message placeholder): Only use memory-only path when we actually have message
        // bodies for these IDs. Otherwise we show "Loading message..." forever (IDs in list but no
        // Message in viewState). If we don't have enough bodies, fall through to fetch from server.
        // See docs/Fix/LoadingMessagePlaceholder.md
        if let existingMessages = viewModel.viewState.channelMessages[channelId],
            !existingMessages.isEmpty,
            shouldUseMemoryOnly
        {
            // print("📊 Found \(existingMessages.count) existing messages in memory - using cached data")

            let hasEnoughMessageBodies = existingMessages.contains {
                viewModel.viewState.messages[$0] != nil
            }

            if hasEnoughMessageBodies {
                // CRITICAL FIX: Create an explicit copy to avoid reference issues
                let messagesCopy = Array(existingMessages)
                
                // Update our local messages array directly
                self.localMessages = messagesCopy
                
                // print("🔄 Updated localMessages with \(messagesCopy.count) messages from viewState")

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.tableView.tableFooterView = nil

                    // Create data source with local messages
                    self.dataSource = LocalMessagesDataSource(
                        viewModel: self.viewModel,
                        viewController: self,
                        localMessages: self.localMessages)
                    self.tableView.dataSource = self.dataSource

                    // Reload table data
                    self.tableView.reloadData()
                    // print("📊 TABLE_VIEW reloaded with \(self.localMessages.count) messages")

                    // Check if user has manually scrolled up recently
                    let hasManuallyScrolledUp =
                        self.lastManualScrollUpTime != nil
                        && Date().timeIntervalSince(self.lastManualScrollUpTime!) < 10.0

                    // FIXED: Always position at bottom when loading initial messages from memory
                    // Only skip if user has manually scrolled up
                    if !hasManuallyScrolledUp {
                        // CRITICAL FIX: Don't auto-position if target message was recently highlighted
                                if let highlightTime = self.lastTargetMessageHighlightTime,
                                    Date().timeIntervalSince(highlightTime) < 10.0
                                {
                                    // Just show table without positioning
                                    self.tableView.alpha = 1.0
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        self.adjustTableInsetsForMessageCount()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                                        self?.updateTableViewBouncing()
                                    }
                                } else {
                            // Position at bottom and show table
                            self.positionTableAtBottomBeforeShowing()

                            // Ensure table is visible
                            self.tableView.alpha = 1.0

                            // Adjust table insets after positioning
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.adjustTableInsetsForMessageCount()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                                self?.updateTableViewBouncing()
                            }
                        }
                    } else {
                        // print("👆 User has manually scrolled up, showing table without auto-positioning")
                        // Just show table and adjust insets
                        self.showTableViewWithFade()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.adjustTableInsetsForMessageCount()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            self?.updateTableViewBouncing()
                        }
                    }
                }
            }
        } else {
            // No messages in memory, fetch from server
            // print("🔄 No existing messages, fetching from server")

            // Show skeleton only when we have no messages on screen (when force-fetching we already show cache + footer spinner)
            if existingCount == 0 {
                DispatchQueue.main.async {
                    self.showSkeletonView()
                }
            }

            // TIMING: Start measuring API call duration
            let apiStartTime = Date()
            // print("⏱️ API_CALL_START: \(apiStartTime.timeIntervalSince1970)")

            do {
                // Call API with proper error handling
                print("🌐 API CALL: loadMoreMessages (initial) - Channel: \(viewModel.channel.id)")
                let result = await viewModel.loadMoreMessages(before: nil)
                print(
                    "✅ API RESPONSE: loadMoreMessages (initial) - Result: \(result != nil ? "Success with \(result!.messages.count) messages" : "Nil")"
                )

                // DEBUG: Check if any messages have replies
                if let fetchResult = result {
                    let messagesWithReplies = fetchResult.messages.filter {
                        $0.replies?.isEmpty == false
                    }
                    print(
                        "🔗 API_DEBUG: Out of \(fetchResult.messages.count) messages, \(messagesWithReplies.count) have replies"
                    )
                    for message in messagesWithReplies {
                        print(
                            "🔗 API_DEBUG: Message \(message.id) has replies: \(message.replies ?? [])"
                        )
                    }
                }

                // TIMING: Calculate API call duration
                let apiEndTime = Date()
                let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
                // print("⏱️ API_CALL_END: \(apiEndTime.timeIntervalSince1970)")
                // print("⏱️ API_CALL_DURATION: \(String(format: "%.2f", apiDuration)) seconds")

                // Process the result
                if let fetchResult = result, !fetchResult.messages.isEmpty {
                    // Enqueue cache write from VC so it runs when we have result (ViewModel enqueue path never fired in logs)
                    if let userId = viewModel.viewState.currentUser?.id, let baseURL = viewModel.viewState.baseURL {
                        let lastId = fetchResult.messages.first?.id
                        MessageCacheWriter.shared.enqueueCacheMessagesAndUsers(fetchResult.messages, users: fetchResult.users, channelId: channelId, userId: userId, baseURL: baseURL, lastMessageId: lastId)
                    }

                    // TIMING: Start processing time
                    let processingStartTime = Date()
                    // print("⏱️ PROCESSING_START: \(processingStartTime.timeIntervalSince1970)")

                    // Process users from the response
                    for user in fetchResult.users {
                        viewModel.viewState.users[user.id] = user
                    }

                    // Process members if present
                    if let members = fetchResult.members {
                        for member in members {
                            viewModel.viewState.members[member.id.server, default: [:]][
                                member.id.user] = member
                        }
                    }

                    // Process messages - save to both viewState
                    for message in fetchResult.messages {
                        viewModel.viewState.messages[message.id] = message
                    }

                    // Fetch reply message content for messages that have replies
                    print(
                        "🔗 CALLING fetchReplyMessagesContentAndRefreshUI with \(fetchResult.messages.count) messages"
                    )
                    await fetchReplyMessagesContentAndRefreshUI(for: fetchResult.messages)

                    // CRITICAL FIX: Also check for any preloaded messages that might have replies
                    let allCurrentMessages = localMessages.compactMap { messageId in
                        viewModel.viewState.messages[messageId]
                    }
                    print(
                        "🔗 PRELOAD_CHECK: Checking \(allCurrentMessages.count) total messages for missing replies after regular load"
                    )
                    await fetchReplyMessagesContentAndRefreshUI(for: allCurrentMessages)

                    // Merge with existing (e.g. from cache): union IDs, dedupe, sort by canonical order.
                    // Single MainActor.run to read state, then sort/filter off main thread, then one more to write back.
                    let (existingIds, deleted, userId, baseURL) = await MainActor.run {
                        (self.viewModel.viewState.channelMessages[channelId] ?? [],
                         self.viewModel.viewState.deletedMessageIds[channelId] ?? Set<String>(),
                         self.viewModel.viewState.currentUser?.id,
                         self.viewModel.viewState.baseURL)
                    }
                    let apiIds = fetchResult.messages.map { $0.id }

                    // Reconcile with server: messages we had locally (e.g. from cache) in the same
                    // time window as the API page but not returned by the API are treated as deleted.
                    // Only reconcile when the API returned a full page — a short page means we've
                    // reached the top of history so "missing" IDs are just older, not deleted.
                    let apiIdSet = Set(apiIds)
                    let deletedByServer: [String]
                    if apiIds.count >= 100 {  // fetchHistory limit (see MessageableChannelViewModel)
                        let oldestApiId = apiIds.min() ?? ""
                        deletedByServer = existingIds.filter { $0 >= oldestApiId && !apiIdSet.contains($0) }
                    } else {
                        deletedByServer = []
                    }

                    // Sort and filter off main thread
                    let sortedIds = self.mergeAndSortMessageIds(existing: existingIds, new: apiIds)
                    let allDeleted = deleted.union(deletedByServer)
                    let filteredIds = allDeleted.isEmpty ? sortedIds : sortedIds.filter { !allDeleted.contains($0) }

                    // Single MainActor.run to write all results back
                    await MainActor.run {
                        if !deletedByServer.isEmpty, let userId, let baseURL {
                            for id in deletedByServer {
                                self.viewModel.viewState.deletedMessageIds[channelId, default: Set()].insert(id)
                                MessageCacheWriter.shared.enqueueDeleteMessage(id: id, channelId: channelId, userId: userId, baseURL: baseURL)
                            }
                        }
                        self.localMessages = filteredIds
                        self.viewModel.viewState.channelMessages[channelId] = filteredIds
                        self.viewModel.messages = filteredIds
                    }

                    // TIMING: Calculate processing duration
                    let processingEndTime = Date()
                    let processingDuration = processingEndTime.timeIntervalSince(
                        processingStartTime)
                    // print("⏱️ PROCESSING_END: \(processingEndTime.timeIntervalSince1970)")
                    // print("⏱️ PROCESSING_DURATION: \(String(format: "%.2f", processingDuration)) seconds")

                    // TIMING: Start UI update time
                    let uiStartTime = Date()
                    // print("⏱️ UI_UPDATE_START: \(uiStartTime.timeIntervalSince1970)")

                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }

                        // Hide skeleton and show messages
                        self.hideSkeletonView()
                        self.tableView.tableFooterView = nil

                        // print("📊 localMessages now has \(self.localMessages.count) messages")

                        // CRITICAL: Mark data source as updating before changes
                        self.isDataSourceUpdating = true
                        print("📊 DATA_SOURCE: Marking as updating for loadInitialMessages")

                        // Create data source with local messages
                        self.dataSource = LocalMessagesDataSource(
                            viewModel: self.viewModel,
                            viewController: self,
                            localMessages: self.localMessages)
                        self.tableView.dataSource = self.dataSource

                        // Reload table data
                        self.tableView.reloadData()

                        // CRITICAL: Reset flag after changes complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                            self?.isDataSourceUpdating = false
                            print("📊 DATA_SOURCE: Marking as stable after loadInitialMessages")
                        }
                        // print("📊 TABLE_VIEW reloaded with \(self.localMessages.count) messages")

                        // Check if user has manually scrolled up recently
                        let hasManuallyScrolledUp =
                            self.lastManualScrollUpTime != nil
                            && Date().timeIntervalSince(self.lastManualScrollUpTime!) < 10.0

                        // FIXED: Always position at bottom when loading initial messages from API
                        // Only skip if user has manually scrolled up
                        if !hasManuallyScrolledUp {
                            // CRITICAL FIX: Don't auto-position if target message was recently highlighted
                            if let highlightTime = self.lastTargetMessageHighlightTime,
                                Date().timeIntervalSince(highlightTime) < 10.0
                            {
                                // Just show table without positioning
                                self.tableView.alpha = 1.0
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    self.adjustTableInsetsForMessageCount()
                                }
                            } else {
                                self.positionTableAtBottomBeforeShowing()

                                // Adjust table insets after positioning
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    self.adjustTableInsetsForMessageCount()
                                }
                            }
                        } else {
                            // print("👆 User has manually scrolled up, showing table without auto-positioning")
                            // Just show table and adjust insets
                            self.showTableViewWithFade()

                            // Ensure table is visible
                            self.tableView.alpha = 1.0

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.adjustTableInsetsForMessageCount()
                            }
                        }

                        // TIMING: Calculate UI update duration
                        let uiEndTime = Date()
                        let uiDuration = uiEndTime.timeIntervalSince(uiStartTime)
                        // print("⏱️ UI_UPDATE_END: \(uiEndTime.timeIntervalSince1970)")
                        // print("⏱️ UI_UPDATE_DURATION: \(String(format: "%.2f", uiDuration)) seconds")

                        // TIMING: Calculate total duration
                        let totalDuration = uiEndTime.timeIntervalSince(apiStartTime)
                        // print("⏱️ TOTAL_LOAD_DURATION: \(String(format: "%.2f", totalDuration)) seconds")
                        // print("⏱️ BREAKDOWN: API=\(String(format: "%.2f", apiDuration))s, Processing=\(String(format: "%.2f", processingDuration))s, UI=\(String(format: "%.2f", uiDuration))s")
                    }
                } else {
                    // TIMING: Calculate failed API call duration
                    let apiEndTime = Date()
                    let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
                    // print("⏱️ API_CALL_FAILED_DURATION: \(String(format: "%.2f", apiDuration)) seconds")
                    // print("⚠️ No messages returned from API after \(String(format: "%.2f", apiDuration))s")

                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }

                        // Hide skeleton and show empty state
                        self.hideSkeletonView()
                        self.tableView.tableFooterView = nil

                        // Show empty state
                        self.updateEmptyStateVisibility()
                    }
                }
            } catch {
                // TIMING: Calculate error duration
                let apiEndTime = Date()
                let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
                // print("⏱️ API_CALL_ERROR_DURATION: \(String(format: "%.2f", apiDuration)) seconds")
                // print("❌ Error loading messages after \(String(format: "%.2f", apiDuration))s: \(error)")

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    // Remove loading spinner
                    self.tableView.tableFooterView = nil

                    // Show empty state
                    self.updateEmptyStateVisibility()
                }
            }
        }
    }
    
    internal func loadInitialMessagesImmediate() async {
        let channelId = viewModel.channel.id
        print("⚡ IMMEDIATE_LOAD: Starting FASTEST possible API call for channel \(channelId)")

        // Ensure table is visible at the end
        defer {
            DispatchQueue.main.async {
                self.tableView.alpha = 1.0
                self.tableView.tableFooterView = nil
            }
        }

        // FASTEST POSSIBLE API CALL - NO CHECKS, NO DELAYS
        let apiStartTime = Date()
        print("⚡ IMMEDIATE_API_START: \(apiStartTime.timeIntervalSince1970)")

        do {
            // Get server ID if this is a server channel
            let serverId = viewModel.channel.server

            // SMART LIMIT: Use 10 for specific channel in specific server, 50 for others
            let messageLimit =
                (channelId == "01J7QTT66242A7Q26A2FH5TD48"
                    && serverId == "01J544PT4T3WQBVBSDK3TBFZW7") ? 10 : 50

            // IMMEDIATE API CALL
            print(
                "⚡ API CALL: fetchHistory IMMEDIATE - Channel: \(channelId), Limit: \(messageLimit)"
            )
            let result = try await viewModel.viewState.http.fetchHistory(
                channel: channelId,
                limit: messageLimit,
                sort: "Latest",
                server: serverId,
                include_users: true
            ).get()

            let apiEndTime = Date()
            let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
            print(
                "⚡ API_RESPONSE_IMMEDIATE: Received \(result.messages.count) messages in \(String(format: "%.2f", apiDuration))s"
            )

            // IMMEDIATE PROCESSING
            let processingStartTime = Date()

            // Process users immediately
            for user in result.users {
                viewModel.viewState.users[user.id] = user
            }

            // Process members immediately
            if let members = result.members {
                for member in members {
                    viewModel.viewState.members[member.id.server, default: [:]][member.id.user] =
                        member
                }
            }

            // Process messages immediately
            for message in result.messages {
                viewModel.viewState.messages[message.id] = message
            }

            // Fetch reply message content for messages that have replies
            print(
                "🔗 CALLING fetchReplyMessagesContentAndRefreshUI (immediate load) with \(result.messages.count) messages"
            )
            await fetchReplyMessagesContentAndRefreshUI(for: result.messages)

            // Sort messages immediately
            let sortedIds = result.messages.map { $0.id }.sorted { id1, id2 in
                let date1 = createdAt(id: id1)
                let date2 = createdAt(id: id2)
                return date1 < date2
            }

            let processingEndTime = Date()
            let processingDuration = processingEndTime.timeIntervalSince(processingStartTime)
            print(
                "⚡ PROCESSING_IMMEDIATE: Processed \(sortedIds.count) messages in \(String(format: "%.2f", processingDuration))s"
            )

            // IMMEDIATE UI UPDATE
            let uiStartTime = Date()

            await MainActor.run {
                // Hide skeleton first
                self.hideSkeletonView()

                // Update all data immediately
                self.localMessages = sortedIds
                self.viewModel.viewState.channelMessages[channelId] = sortedIds
                self.viewModel.messages = sortedIds

                // Update data source immediately
                if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                    localDataSource.updateMessages(sortedIds)
                }

                // Reload table immediately
                self.tableView.reloadData()

                // Position at bottom immediately
                if !sortedIds.isEmpty {
                    self.positionTableAtBottomBeforeShowing()
                }

                let uiEndTime = Date()
                let uiDuration = uiEndTime.timeIntervalSince(uiStartTime)
                let totalDuration = uiEndTime.timeIntervalSince(apiStartTime)

                print("⚡ UI_UPDATE_IMMEDIATE: Updated UI in \(String(format: "%.2f", uiDuration))s")
                print("⚡ TOTAL_IMMEDIATE_DURATION: \(String(format: "%.2f", totalDuration))s")
                print(
                    "⚡ BREAKDOWN: API=\(String(format: "%.2f", apiDuration))s, Processing=\(String(format: "%.2f", processingDuration))s, UI=\(String(format: "%.2f", uiDuration))s"
                )
            }

        } catch {
            print("❌ IMMEDIATE_LOAD_ERROR: \(error)")

            DispatchQueue.main.async {
                self.hideSkeletonView()
                self.updateEmptyStateVisibility()
            }
        }
    }

    /// Load one page of older messages from cache if available; merge with localMessages and preserve scroll. Returns true if a page was loaded.
    private func loadOlderMessagesFromCacheIfAvailable(channelId: String, oldContentOffset: CGPoint, oldContentHeight: CGFloat) async -> Bool {
        guard let userId = viewModel.viewState.currentUser?.id,
              let baseURL = viewModel.viewState.baseURL else { return false }
        let totalCount = await MessageCacheManager.shared.cachedMessageCount(for: channelId, userId: userId, baseURL: baseURL)
        cachedMessageTotal = totalCount
        let currentOffset = cachedMessageOffset
        guard totalCount > currentOffset else { return false }
        let cached = await MessageCacheManager.shared.loadCachedMessages(
            for: channelId,
            userId: userId,
            baseURL: baseURL,
            limit: cachePageSize,
            offset: currentOffset
        )
        guard !cached.isEmpty else { return false }
        print("📂 [MessageCache] UI: loading older page from cache for channel \(channelId) (offset \(currentOffset), \(cached.count) messages)")
        let authorIds = Set(cached.map { $0.author })
        let cachedUsers = await MessageCacheManager.shared.loadCachedUsers(for: Array(authorIds), currentUserId: userId, baseURL: baseURL)
        await MainActor.run {
            for (uid, user) in cachedUsers {
                viewModel.viewState.users[uid] = user
            }
            for message in cached {
                let existing = viewModel.viewState.messages[message.id]
                if let existing = existing, isViewStateMessageNewerThanCached(existing: existing, cached: message) {
                    continue
                }
                viewModel.viewState.messages[message.id] = message
            }
            let newIds = cached.map { $0.id }
            let merged = mergeAndSortMessageIds(existing: localMessages, new: newIds)
            let deleted = viewModel.viewState.deletedMessageIds[channelId] ?? []
            let filtered = merged.filter { !deleted.contains($0) }
            viewModel.viewState.channelMessages[channelId] = filtered
            viewModel.messages = filtered
            localMessages = filtered
            cachedMessageOffset = min(totalCount, currentOffset + cached.count)
            if let ds = dataSource as? LocalMessagesDataSource {
                ds.updateMessages(localMessages)
            } else {
                dataSource = LocalMessagesDataSource(viewModel: viewModel, viewController: self, localMessages: localMessages)
                tableView.dataSource = dataSource
            }
            tableView.reloadData()
            let newHeight = tableView.contentSize.height
            let delta = newHeight - oldContentHeight
            tableView.contentOffset = CGPoint(x: oldContentOffset.x, y: oldContentOffset.y + delta)
            loadingHeaderView.isHidden = true
            messageLoadingState = .notLoading
            lastSuccessfulLoadTime = Date()
        }
        return true
    }
    
    // New method for loading older messages
    func loadMoreMessages(before messageId: String?, server: String? = nil, messages: [String] = [])
    {
        // Set the 'before' message ID
        self.lastBeforeMessageId = messageId

        // Check current loading state
        switch messageLoadingState {
        case .loading:
            // print("⚠️ BEFORE_CALL: Message loading is already in progress, ignoring new request")
            return

        case .notLoading:
            // If less than 1.5 seconds since last load, ignore
            let timeSinceLastLoad = Date().timeIntervalSince(lastSuccessfulLoadTime)
            if timeSinceLastLoad < 0.5 {
                // print("⏱️ BEFORE_CALL: Only \(String(format: "%.1f", timeSinceLastLoad)) seconds since last load, waiting")
                return
            }

            print(
                "🌐 API CALL: loadMoreMessages (before) - Channel: \(viewModel.channel.id), Before: \(messageId ?? "nil")"
            )

            // CRITICAL FIX: Set flag to prevent memory cleanup during older message loading
            isLoadingOlderMessages = true

            // Save scroll position before API call
            let oldContentOffset = self.tableView.contentOffset
            let oldContentHeight = self.tableView.contentSize.height

            // Remember exact information about current scroll position for more precise adjustment
            var firstVisibleIndexPath: IndexPath? = nil
            var firstVisibleRowFrame: CGRect = .zero
            var contentOffsetRelativeToRow: CGFloat = 0

            // Get the first completely visible row (not just partially visible)
            if let visibleRows = self.tableView.indexPathsForVisibleRows, !visibleRows.isEmpty {
                firstVisibleIndexPath = visibleRows.first
                if let indexPath = firstVisibleIndexPath {
                    firstVisibleRowFrame = self.tableView.rectForRow(at: indexPath)
                    contentOffsetRelativeToRow = oldContentOffset.y - firstVisibleRowFrame.origin.y
                    // print("🔍 BEFORE_CALL: Saving position - row \(indexPath.row) at y-offset \(firstVisibleRowFrame.origin.y), content offset \(oldContentOffset.y), relative offset \(contentOffsetRelativeToRow)")
                }
            }

            // Show loading indicator
            DispatchQueue.main.async {
                self.loadingHeaderView.isHidden = false
                // Make sure the header view is visible
                let headRect = self.tableView.rect(forSection: 0)
                if headRect.origin.y < self.tableView.contentOffset.y {
                    self.tableView.scrollRectToVisible(
                        CGRect(x: 0, y: self.tableView.contentOffset.y - 60, width: 1, height: 1),
                        animated: true)
                }
            }

            // Save count of messages before loading
            let initialMessagesCount = viewModel.messages.count

            // Create a new Task for loading messages
            let loadTask = Task<Void, Never>(priority: .userInitiated) {
                do {
                    var apiMessageId = messageId
                    var curOffset = oldContentOffset
                    var curHeight = oldContentHeight
                    let chId = self.viewModel.channel.id
                    for _ in 0..<50 {
                        let loaded = await self.loadOlderMessagesFromCacheIfAvailable(channelId: chId, oldContentOffset: curOffset, oldContentHeight: curHeight)
                        if !loaded { break }
                        guard let uid = self.viewModel.viewState.currentUser?.id,
                              let baseURL = self.viewModel.viewState.baseURL else { break }
                        let total = await MessageCacheManager.shared.cachedMessageCount(for: chId, userId: uid, baseURL: baseURL)
                        if await MainActor.run(body: { self.cachedMessageOffset }) >= total { break }
                        let msgs = await MainActor.run { self.viewModel.messages }
                        guard let first = msgs.first else { break }
                        apiMessageId = first
                        curOffset = await MainActor.run { self.tableView.contentOffset }
                        curHeight = await MainActor.run { self.tableView.contentSize.height }
                    }

                    print(
                        "⏳ BEFORE_CALL: Waiting for API response for messageId=\(apiMessageId ?? "nil"), channelId=\(self.viewModel.channel.id)"
                    )
                    print(
                        "⏳ BEFORE_CALL: Calling viewModel.loadMoreMessages with before=\(apiMessageId ?? "nil")"
                    )
                    let loadResult = await self.viewModel.loadMoreMessages(
                        before: apiMessageId
                    )

                    print("✅ BEFORE_CALL: API call completed, result is nil? \(loadResult == nil)")

                    // If result is not nil, log more details
                    if let result = loadResult {
                        // print("✅ BEFORE_CALL: Received \(result.messages.count) messages from API")
                        if !result.messages.isEmpty {
                            let firstMsgId = result.messages.first?.id ?? "unknown"
                            let lastMsgId = result.messages.last?.id ?? "unknown"
                            // print("✅ BEFORE_CALL: First message ID: \(firstMsgId), Last message ID: \(lastMsgId)")
                        }
                    }

                    // Check result on main thread
                    await MainActor.run {
                        // Hide loading indicator
                        self.loadingHeaderView.isHidden = true

                        // Always update lastSuccessfulLoadTime to prevent repeated calls
                        self.lastSuccessfulLoadTime = Date()

                        // If we got a response with messages
                        if let result = loadResult {
                            // Log message counts for debugging
                            // print("🧮 BEFORE_CALL: Current message counts:")
                            // print("   ViewModel: \(self.viewModel.messages.count) messages")
                            // print("   ViewState: \(self.viewModel.viewState.channelMessages[self.viewModel.channel.id]?.count ?? 0) messages")
                            // print("   TableView: \(self.tableView.numberOfRows(inSection: 0)) rows")

                            // CRITICAL: If viewModel.messages is empty but viewState has messages, sync them
                            if self.viewModel.messages.isEmpty
                                && !(self.viewModel.viewState.channelMessages[
                                    self.viewModel.channel.id]?.isEmpty ?? true)
                            {
                                // print("⚠️ BEFORE_CALL: ViewModel messages is empty but viewState has \(self.viewModel.viewState.channelMessages[self.viewModel.channel.id]?.count ?? 0) messages - syncing")
                                self.viewModel.messages =
                                    self.viewModel.viewState.channelMessages[
                                        self.viewModel.channel.id] ?? []
                            }
                            // CRITICAL: Also ensure localMessages is synced with viewModel.messages
                            if self.localMessages.isEmpty && !self.viewModel.messages.isEmpty {
                                // print("⚠️ BEFORE_CALL: LocalMessages is empty but viewModel has \(self.viewModel.messages.count) messages - syncing")
                                self.localMessages = self.viewModel.messages
                            }
                            // CRITICAL: Always sync all three arrays after loading more
                            if let synced = self.viewModel.viewState.channelMessages[
                                self.viewModel.channel.id], !synced.isEmpty
                            {
                                self.viewModel.messages = synced
                                self.localMessages = synced
                                // print("🔄 BEFORE_CALL: Synced viewModel.messages and localMessages with viewState.channelMessages after loadMoreMessages")
                            } else {
                                // print("⚠️ BEFORE_CALL: Tried to sync but channelMessages was empty, skipping sync to avoid clearing arrays")
                            }

                            // CRITICAL: Make sure we're using the correct messages array
                            let messagesForDataSource =
                                !self.viewModel.messages.isEmpty
                                ? self.viewModel.messages
                                : (self.viewModel.viewState.channelMessages[
                                    self.viewModel.channel.id] ?? [])

                            // Calculate how many messages were actually added
                            let addedMessagesCount =
                                self.viewModel.messages.count - initialMessagesCount
                            // print("✅ BEFORE_CALL: Loaded \(result.messages.count) messages, added \(addedMessagesCount) new messages")

                            // CRITICAL FIX: Restore any missing users after loading older messages
                            self.viewModel.viewState.restoreMissingUsersForMessages()

                            // CRITICAL FIX: Load users specifically for this channel's messages
                            self.viewModel.viewState.loadUsersForVisibleMessages(
                                channelId: self.viewModel.channel.id)

                            // EMERGENCY FIX: Force restore all users for this channel
                            self.viewModel.viewState.forceRestoreUsersForChannel(
                                channelId: self.viewModel.channel.id)

                            // FINAL CHECK: Ensure all loaded messages have their authors
                            let finalMessageIds =
                                self.viewModel.viewState.channelMessages[self.viewModel.channel.id]
                                ?? []
                            var missingAuthors = 0
                            for messageId in finalMessageIds {
                                if let message = self.viewModel.viewState.messages[messageId] {
                                    if self.viewModel.viewState.users[message.author] == nil {
                                        missingAuthors += 1
                                        // Create emergency placeholder
                                        let placeholder = Types.User(
                                            id: message.author,
                                            username: "User \(String(message.author.suffix(4)))",
                                            discriminator: "0000",
                                            relationship: .None
                                        )
                                        self.viewModel.viewState.users[message.author] = placeholder
                                        // print("🚨 EMERGENCY_PLACEHOLDER: Created for author \(message.author)")
                                    }
                                }
                            }

                            if missingAuthors > 0 {
                                // print("🚨 FINAL_CHECK: Created \(missingAuthors) emergency placeholders for missing authors")
                            } else {
                                // print("✅ FINAL_CHECK: All message authors are present in users dictionary")
                            }

                            if addedMessagesCount > 0 {
                                // print("✅ BEFORE_CALL: Added \(addedMessagesCount) new messages, implementing precise reference scroll")

                                // CRITICAL: Save the reference message ID before any updates
                                let referenceMessageId = self.lastBeforeMessageId
                                // print("🎯 REFERENCE_MSG: Saved reference ID '\(referenceMessageId ?? "nil")' before data updates")

                                // CRITICAL: Mark data source as updating before changes
                                self.isDataSourceUpdating = true
                                print("📊 DATA_SOURCE: Marking as updating for loadMoreMessages")

                                // Update data source
                                self.dataSource = LocalMessagesDataSource(
                                    viewModel: self.viewModel,
                                    viewController: self,
                                    localMessages: messagesForDataSource
                                )
                                self.tableView.dataSource = self.dataSource

                                // Force layout update first
                                self.tableView.layoutIfNeeded()

                                // Reload data
                                self.tableView.reloadData()

                                // CRITICAL: Reset flag after changes complete
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    [weak self] in
                                    self?.isDataSourceUpdating = false
                                    print("📊 DATA_SOURCE: Marking as stable after loadMoreMessages")
                                }

                                // Multiple attempts to ensure precise scrolling
                                self.scrollToReferenceMessageWithRetry(
                                    referenceId: referenceMessageId,
                                    messagesArray: messagesForDataSource,
                                    maxRetries: 3
                                )

                                // print("📢 BEFORE_CALL: Added \(addedMessagesCount) older messages, initiated reference scroll")
                            } else {
                                // If no messages were added, just update data source without reload
                                self.dataSource = LocalMessagesDataSource(
                                    viewModel: self.viewModel,
                                    viewController: self,
                                    localMessages: messagesForDataSource
                                )
                                self.tableView.dataSource = self.dataSource

                                // If no new messages were loaded, show a notification to the user
                                // if result.messages.isEmpty {
                                //     // CRITICAL FIX: Update lastEmptyResponseTime when API returns empty messages
                                //     self.lastEmptyResponseTime = Date()
                                //     DispatchQueue.main.async {
                                //         let banner = NotificationBanner(message: "You have reached the beginning of the conversation.")
                                //         banner.show(duration: 2.0)
                                //     }
                                // }
                            }
                        } else {
                            // print("❌ BEFORE_CALL: API response was empty")

                            // CRITICAL FIX: Update lastEmptyResponseTime when API returns empty response
                            self.lastEmptyResponseTime = Date()

                            // // Show notification that there are no more messages
                            // DispatchQueue.main.async {
                            //     let banner = NotificationBanner(message: "You have reached the beginning of the conversation.")
                            //     banner.show(duration: 2.0)
                            // }
                        }

                        // Change state to not loading
                        self.messageLoadingState = .notLoading
                        self.isLoadingMore = false

                        // Update table view bouncing behavior after loading completes
                        self.updateTableViewBouncing()

                        // CRITICAL FIX: Reset the older messages loading flag
                        self.isLoadingOlderMessages = false
                    }
                } catch {
                    // Handle errors
                    // print("❗️ BEFORE_CALL: Error loading messages: \(error)")

                    // Change state to not loading on main thread
                    await MainActor.run {
                        // Hide loading indicator
                        self.loadingHeaderView.isHidden = true

                        // Always update lastSuccessfulLoadTime to prevent repeated calls
                        self.lastSuccessfulLoadTime = Date()

                        self.messageLoadingState = .notLoading
                        self.isLoadingMore = false

                        // Update table view bouncing behavior after loading error
                        self.updateTableViewBouncing()

                        // CRITICAL FIX: Reset the older messages loading flag
                        self.isLoadingOlderMessages = false

                        // Show error to user
                        DispatchQueue.main.async {
                            //                            let banner = NotificationBanner(message: "Error loading messages")
                            //                            banner.show(duration: 2.0)
                        }
                    }
                }
            }

            // Store task in state
            messageLoadingState = .loading
            loadingTask = loadTask
            isLoadingMore = true

            // Safety timer to prevent state lock
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                guard let self = self else { return }

                // Hide loading indicator
                self.loadingHeaderView.isHidden = true

                if self.messageLoadingState == .loading {
                    // print("⚠️ BEFORE_CALL: Loading time exceeded maximum duration - cancelling task")
                    self.loadingTask?.cancel()
                    self.loadingTask = nil
                    self.messageLoadingState = .notLoading
                    self.isLoadingMore = false
                    self.lastSuccessfulLoadTime = Date()  // Update to prevent immediate retries

                    // Update table view bouncing behavior after timeout
                    self.updateTableViewBouncing()

                    // CRITICAL FIX: Reset the older messages loading flag
                    self.isLoadingOlderMessages = false

                    // Show timeout message
                    //                    let banner = NotificationBanner(message: "Loading time exceeded. Please try again.")
                    //                    banner.show(duration: 2.0)
                }
            }
        }
    }
    
    func loadMoreMessagesIfNeeded(for indexPath: IndexPath) {
        // CRITICAL CHANGE: Only load more messages when we're exactly at the first message
        // This prevents premature API calls when user isn't at the very top

        // Safety check - try viewModel.messages first, then fall back to localMessages
        let messages = !viewModel.messages.isEmpty ? viewModel.messages : localMessages

        // If both are empty, can't load more
        guard !messages.isEmpty else {
            return
        }

        // CRITICAL FIX: Check if we recently received an empty response (reached beginning)
        if let lastEmpty = lastEmptyResponseTime,
            Date().timeIntervalSince(lastEmpty) < 60.0
        {  // Don't retry for 1 minute
            print("⏹️ LOAD_BLOCKED: Reached beginning of conversation recently, skipping load")
            return
        }

        // If message count is less than the specified threshold, don't send API request
        if messages.count < 12 {
            // print("📊 Few messages (\(messages.count)), not sending request to load more messages")
            return
        }

        // STRICT CONDITION: ONLY when we're at the very first message (row 0)
        // No threshold - must be exactly at the top
        if (indexPath.row == 0) && !isLoadingMore {
            // Check loading state separately
            if case .loading = messageLoadingState {
                // Already loading, no need to restart
                // print("⏳ Already in loading state, skipping request")
                return
            }

            // Get the first message ID from whichever array has data
            let firstMessageId = messages.first!
            // print("🔄🔄 LOAD_TRIGGERED: At or near top row \(indexPath.row), loading more history, current first message: \(firstMessageId)")

            // Show loading indicator
            DispatchQueue.main.async {
                self.loadingHeaderView.isHidden = false
                let headRect = self.tableView.rect(forSection: 0)
                // Make sure loading indicator is visible
                if headRect.origin.y < self.tableView.contentOffset.y {
                    self.tableView.scrollRectToVisible(
                        CGRect(x: 0, y: self.tableView.contentOffset.y - 60, width: 1, height: 1),
                        animated: true)
                }

                // Show notification to user
                //                let banner = NotificationBanner(message: "Loading older messages...")
                //                banner.show(duration: 1.5)
            }

            // Only set loading state for indexPath.row == 0 to prioritize top-row loading
            isLoadingMore = true
            loadMoreMessages(before: firstMessageId)
        }
    }
    
    // Load newer messages (when scrolling to bottom)
    func loadNewerMessages(after messageId: String) {
        // Only if we have messages and not already loading
        guard !localMessages.isEmpty && !isLoadingMore else {
            // print("🛑 AFTER: Skipping - no messages or already loading")
            return
        }

        // Set loading state to prevent multiple calls
        isLoadingMore = true
        messageLoadingState = .loading

        // print("📥📥 AFTER_CALL: Starting to load newer messages after ID: \(messageId)")

        // Show loading indicator at bottom
        DispatchQueue.main.async {
            // You can add a loading indicator at the bottom if needed
            // print("⏳ AFTER: Loading newer messages...")
        }

        // Create task to load messages
        Task {
            do {
                // Save count of messages before loading
                let initialCount = localMessages.count
                // print("📥📥 AFTER_CALL: Initial message count: \(initialCount)")

                // Call the API through the viewModel with after parameter
                let result = await viewModel.loadMoreMessages(
                    before: nil,
                    after: messageId
                )

                // print("📥📥 AFTER_CALL: API call completed. Result is nil? \(result == nil)")

                // Process results on main thread
                await MainActor.run {
                    // Always reset loading flags first
                    isLoadingMore = false
                    messageLoadingState = .notLoading

                    // Process the new messages
                    if let fetchResult = result, !fetchResult.messages.isEmpty {
                        // print("📥📥 AFTER_CALL: Processing \(fetchResult.messages.count) new messages")

                        // Process all messages
                        for message in fetchResult.messages {
                            // Add to viewState messages dictionary
                            viewModel.viewState.messages[message.id] = message
                        }

                        // Get IDs of new messages
                        let newMessageIds = fetchResult.messages.map { $0.id }
                        let existingIds = Set(localMessages)
                        let messagesToAdd = newMessageIds.filter { !existingIds.contains($0) }

                        // Add new messages if there are any to add
                        if !messagesToAdd.isEmpty {
                            // print("📥📥 AFTER_CALL: Adding \(messagesToAdd.count) new messages to arrays")

                            // Create new arrays to avoid reference issues
                            var updatedMessages = localMessages
                            updatedMessages.append(contentsOf: messagesToAdd)

                            // Update all message arrays
                            viewModel.messages = updatedMessages
                            localMessages = updatedMessages
                            viewModel.viewState.channelMessages[viewModel.channel.id] =
                                updatedMessages

                            // Final verification
                            // print("📥📥 AFTER_CALL: Arrays updated: viewModel.messages=\(viewModel.messages.count), localMessages=\(localMessages.count)")

                            // Update UI
                            refreshMessages()

                            // Show success notification
                            // print("✅ AFTER_CALL: Successfully loaded \(messagesToAdd.count) newer messages")
                        } else {
                            // print("📥📥 AFTER_CALL: No new unique messages to add (duplicates)")
                        }
                    } else {
                        // print("📥📥 AFTER_CALL: API returned empty result or no new messages")
                    }
                }
            } catch {
                // print("❌ AFTER_CALL: Error loading newer messages: \(error)")

                // Reset loading state on main thread
                await MainActor.run {
                    isLoadingMore = false
                    messageLoadingState = .notLoading
                }
            }
        }
    }
    
    // Load messages near a specific message ID
    internal func loadMessagesNearby(messageId: String) async -> Bool {
        do {
            print("🔍 NEARBY_API: Fetching messages nearby \(messageId) using nearby API")
            print("🌐 NEARBY_API: Channel: \(viewModel.channel.id), Target: \(messageId)")

            // Use the nearby API to fetch messages around the target message with timeout
            let result = try await withThrowingTaskGroup(of: FetchHistory.self) { group in
                // Add the actual API call
                group.addTask {
                    try await self.viewModel.viewState.http.fetchHistory(
                        channel: self.viewModel.channel.id,
                        limit: 100,
                        nearby: messageId
                    ).get()
                }

                // Add timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: 8_000_000_000)  // 8 seconds
                    throw TimeoutError()
                }

                // Return the first result (either API response or timeout)
                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            print(
                "✅ NEARBY_API: Response received with \(result.messages.count) messages, \(result.users.count) users"
            )

            // DEBUG: Check if any messages have replies
            let messagesWithReplies = result.messages.filter { $0.replies?.isEmpty == false }
            print(
                "🔗 NEARBY_DEBUG: Out of \(result.messages.count) messages, \(messagesWithReplies.count) have replies"
            )
            for message in messagesWithReplies {
                print("🔗 NEARBY_DEBUG: Message \(message.id) has replies: \(message.replies ?? [])")
            }

            // Check if we got messages and the target message is included
            if !result.messages.isEmpty {
                let targetFound = result.messages.contains { $0.id == messageId }
                print(
                    "🎯 NEARBY_API: Target message \(messageId) found in nearby results: \(targetFound)"
                )

                // Debug: Print all message IDs we got
                let messageIds = result.messages.map { $0.id }
                print(
                    "🔍 NEARBY_API: Returned message IDs: \(messageIds.prefix(5))...\(messageIds.suffix(5))"
                )

                if !targetFound {
                    print(
                        "⚠️ NEARBY_API: Target message not found in nearby results, trying direct fetch"
                    )
                    // Try to fetch the target message directly
                    do {
                        print("🌐 DIRECT_FETCH: Attempting to fetch target message directly")
                        let targetMessage = try await viewModel.viewState.http.fetchMessage(
                            channel: viewModel.channel.id,
                            message: messageId
                        ).get()

                        print(
                            "✅ DIRECT_FETCH: Successfully fetched target message directly: \(targetMessage.id)"
                        )
                        // Store it in viewState
                        viewModel.viewState.messages[targetMessage.id] = targetMessage
                    } catch {
                        print("❌ DIRECT_FETCH: Could not fetch target message directly: \(error)")
                        // Return false since we couldn't get the target message
                        return false
                    }
                }
            } else {
                print("❌ NEARBY_API: No messages returned from nearby API")
                return false
            }

            // Process and update the view model with new messages
            return await MainActor.run {
                if !result.messages.isEmpty {
                    // print("📊 Processing \(result.messages.count) messages from nearby API")

                    // Process all users
                    for user in result.users {
                        viewModel.viewState.users[user.id] = user
                    }

                    // Process members if present
                    if let members = result.members {
                        for member in members {
                            viewModel.viewState.members[member.id.server, default: [:]][
                                member.id.user] = member
                        }
                    }

                    // Process all messages
                    for message in result.messages {
                        viewModel.viewState.messages[message.id] = message
                    }

                    // Fetch reply message content for messages that have replies
                    Task {
                        await self.fetchReplyMessagesContent(for: result.messages)
                    }

                    // Sort messages by timestamp to ensure chronological order
                    let sortedMessages = result.messages.sorted { msg1, msg2 in
                        let date1 = createdAt(id: msg1.id)
                        let date2 = createdAt(id: msg2.id)
                        return date1 < date2
                    }

                    // Create a list of message IDs in sorted order
                    let sortedIds = sortedMessages.map { $0.id }

                    // CRITICAL FIX: Explicitly check for target message ID
                    if !sortedIds.contains(messageId) {
                        // print("⚠️ Target message missing from nearby results! This should not happen with nearby API.")
                        // If target message is missing, the API call probably failed
                        return false
                    } else {
                        // CRITICAL FIX: Merge nearby messages with existing channel history instead of replacing
                        let existingMessages =
                            viewModel.viewState.channelMessages[viewModel.channel.id] ?? []
                        let existingMessageIds = Set(existingMessages)

                        // Filter out messages that are already in the channel history
                        let newMessageIds = sortedIds.filter { !existingMessageIds.contains($0) }

                        if !newMessageIds.isEmpty {
                            // Merge new messages with existing messages and sort the combined list
                            var allMessageIds = existingMessages + newMessageIds

                            // Sort the combined list by timestamp
                            allMessageIds.sort { id1, id2 in
                                let date1 = createdAt(id: id1)
                                let date2 = createdAt(id: id2)
                                return date1 < date2
                            }

                            // Update all message arrays with the merged list
                            viewModel.messages = allMessageIds
                            viewModel.viewState.channelMessages[viewModel.channel.id] =
                                allMessageIds
                        } else {
                            // All nearby messages were already in channel history, no need to update arrays
                            // But ensure viewModel.messages is synced with channelMessages
                            viewModel.messages = existingMessages
                        }
                    }

                    // CRITICAL: Force synchronization to ensure that viewModel.messages and viewState are in sync
                    viewModel.forceMessagesSynchronization()

                    // print("✅ Successfully processed messages - ViewModel now has \(viewModel.messages.count) messages")

                    // Verify the target message is included
                    if viewModel.messages.contains(messageId) {
                        // print("✅ Target message \(messageId) is in the messages array at index: \(viewModel.messages.firstIndex(of: messageId) ?? -1)")
                    } else {
                        // print("⚠️ Target message \(messageId) is missing from the messages array!")
                    }

                    // CRITICAL FIX: Reset loading states to ensure we can load more messages when scrolling
                    self.messageLoadingState = .notLoading
                    self.isLoadingMore = false
                    // Update lastSuccessfulLoadTime to prevent immediate subsequent loads
                    self.lastSuccessfulLoadTime = Date()

                    // Notify observers of changes to update the UI
                    viewModel.notifyMessagesDidChange()

                    // Force a UI refresh to make sure everything is displayed properly
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }

                        // Recreate the data source to ensure it has the latest data
                        self.dataSource = LocalMessagesDataSource(
                            viewModel: self.viewModel, viewController: self,
                            localMessages: self.localMessages)

                        // Update the local messages in the data source
                        if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                            localDataSource.updateMessages(self.localMessages)
                        }

                        self.tableView.dataSource = self.dataSource

                        // Reload the table view
                        self.tableView.reloadData()

                        // Don't call positionTableAtBottomBeforeShowing when we have a target message
                        // The scrollToTargetMessage will handle positioning
                        if self.targetMessageId == nil {
                            self.positionTableAtBottomBeforeShowing()
                        }

                        // print("📊 TABLE_VIEW after nearby reload: \(self.tableView.numberOfRows(inSection: 0)) rows")

                        // Update localMessages to ensure consistency with the view model
                        self.localMessages = self.viewModel.messages
                    }

                    return true
                } else {
                    // print("⚠️ No messages found nearby target ID")

                    // Even if no messages were found, reset loading states
                    self.messageLoadingState = .notLoading
                    self.isLoadingMore = false
                    self.lastSuccessfulLoadTime = Date()

                    return false
                }
            }
        } catch {
            print("❌ NEARBY_API: Error loading messages nearby target: \(error)")

            // Check if it's a specific error type
            if let revoltError = error as? RevoltError {
                print("❌ NEARBY_API: Revolt error details: \(revoltError)")
            } else if let httpError = error as? HTTPError {
                print("❌ NEARBY_API: HTTP error details: \(httpError)")
            } else {
                print("❌ NEARBY_API: Unknown error type: \(type(of: error))")
            }

            // Reset loading states in case of error
            await MainActor.run {
                self.messageLoadingState = .notLoading
                self.isLoadingMore = false
                self.lastSuccessfulLoadTime = Date()
            }

            return false
        }
    }
    
    // Load only necessary users for visible messages
    private func loadUsersForVisibleMessages() {
        Task { @MainActor in
            // Get visible message IDs
            let visibleRows = tableView.indexPathsForVisibleRows ?? []
            var neededUserIds = Set<String>()

            for indexPath in visibleRows {
                if indexPath.row < localMessages.count {
                    let messageId = localMessages[indexPath.row]
                    if let message = viewModel.viewState.messages[messageId] {
                        neededUserIds.insert(message.author)
                        // Add mentioned users if any
                        if let mentions = message.mentions {
                            neededUserIds.formUnion(mentions)
                        }
                    }
                }
            }

            // print("👥 LOAD: Need to load \(neededUserIds.count) users for visible messages")

            // Load only missing users
            var usersToLoad = [String]()
            for userId in neededUserIds {
                if viewModel.viewState.users[userId] == nil {
                    usersToLoad.append(userId)
                }
            }

            if !usersToLoad.isEmpty {
                // print("👥 LOAD: Loading \(usersToLoad.count) missing users")
                // Here you would call API to load specific users
                // For now, we'll just log it
            }
        }
    }
}
