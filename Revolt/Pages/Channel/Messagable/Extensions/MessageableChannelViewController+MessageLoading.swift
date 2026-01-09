//
//  MessageableChannelViewController+MessageLoading.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//  Phase 4: High-Risk Extensions - Message Loading

import UIKit
import Types

// MARK: - Message Loading
extension MessageableChannelViewController {

    func loadMoreMessages(before messageId: String?, server: String? = nil, messages: [String] = []) {
        // Set the 'before' message ID
        self.lastBeforeMessageId = messageId
        
        // Check current loading state
        switch messageLoadingState {
        case .loading:
            // print("⚠️ BEFORE_CALL: Message loading is already in progress, ignoring new request")
            // CRITICAL FIX: Reset isLoadingMore if we're already loading to prevent stuck state
            isLoadingMore = false
            return
            
        case .notLoading:
            // If less than 1.5 seconds since last load, ignore
            let timeSinceLastLoad = Date().timeIntervalSince(lastSuccessfulLoadTime)
            if timeSinceLastLoad < 0.5 {
                // print("⏱️ BEFORE_CALL: Only \(String(format: "%.1f", timeSinceLastLoad)) seconds since last load, waiting")
                // CRITICAL FIX: Reset isLoadingMore if we're throttling to prevent stuck state
                isLoadingMore = false
                return
            }
            
            print("🌐 API CALL: loadMoreMessages (before) - Channel: \(viewModel.channel.id), Before: \(messageId ?? "nil")")
            
            // CRITICAL FIX: Set loading state BEFORE cache check to ensure proper state management
            messageLoadingState = .loading
            
            // CRITICAL FIX: Set flag to prevent memory cleanup during older message loading
            isLoadingOlderMessages = true
            
            // Save scroll position before API call
            var oldContentOffset = self.tableView.contentOffset
            var oldContentHeight = self.tableView.contentSize.height
            
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
            
            // Show loading indicator (without scrolling to avoid UI jumps)
            DispatchQueue.main.async {
                // Add header if not already added
                if self.tableView.tableHeaderView == nil {
                    self.tableView.tableHeaderView = self.loadingHeaderView
                }
                // Only show if not already visible to prevent jumping
                if self.loadingHeaderView.isHidden {
                    self.loadingHeaderView.isHidden = false
                }
                // CRITICAL FIX: Removed scrollRectToVisible call that was causing UI jumps
                // The header will be visible naturally when messages are added at the top
            }
            
            // Save count of messages before loading
            let initialMessagesCount = viewModel.messages.count
            
            // Create a new Task for loading messages
            let loadTask = Task<Void, Never>(priority: .userInitiated) {
                var apiMessageId = messageId
                var cacheExhausted = false
                
                // CRITICAL FIX: Keep loading from cache in a loop until cache is exhausted
                // This ensures we load all available cached messages before hitting the server
                var cacheLoadAttempts = 0
                let maxCacheLoadAttempts = 50 // Safety limit to prevent infinite loops
                
                while cacheLoadAttempts < maxCacheLoadAttempts {
                    let cacheLoaded = await self.loadOlderMessagesFromCacheIfAvailable(
                        channelId: self.viewModel.channel.id,
                        oldContentOffset: oldContentOffset,
                        oldContentHeight: oldContentHeight
                    )
                    
                    cacheLoadAttempts += 1
                    print("🔄 CACHE_CHECK_RESULT [attempt \(cacheLoadAttempts)]: cacheLoaded=\(cacheLoaded), cachedMessageOffset=\(self.cachedMessageOffset), messageId=\(apiMessageId ?? "nil")")
                    
                    if !cacheLoaded {
                        // No more cache available, proceed to API
                        print("🔄 NO_CACHE: No more cache available after \(cacheLoadAttempts) attempts, proceeding to API call with messageId=\(apiMessageId ?? "nil")")
                        cacheExhausted = true
                        break
                    }
                    
                    // Cache loaded successfully, check if cache is exhausted
                    let totalCount = await MessageCacheManager.shared.cachedMessageCount(
                        for: self.viewModel.channel.id,
                        userId: self.viewModel.viewState.currentUser?.id ?? "",
                        baseURL: self.viewModel.viewState.baseURL ?? ""
                    )
                    
                    // Get the new first message ID after cache load
                    let messages = await MainActor.run {
                        !self.viewModel.messages.isEmpty ? self.viewModel.messages : self.localMessages
                    }
                    
                    guard let newFirstMessageId = messages.first else {
                        // No messages after cache load, something went wrong
                        await MainActor.run {
                            self.messageLoadingState = .notLoading
                            self.isLoadingMore = false
                        }
                        return
                    }
                    
                    // Update messageId to use the new first message (oldest after cache load)
                    apiMessageId = newFirstMessageId
                    
                    if self.cachedMessageOffset >= totalCount {
                        // Cache exhausted, proceed to API call
                        print("🔄 CACHE_EXHAUSTED: Cache offset \(self.cachedMessageOffset) >= total \(totalCount), loading from API with messageId=\(apiMessageId)")
                        cacheExhausted = true
                        break
                    } else {
                        // Cache still has more messages, continue loading
                        print("🔄 CACHE_MORE_AVAILABLE: Cache offset \(self.cachedMessageOffset) < total \(totalCount), loading more from cache...")
                        // Update oldContentOffset and oldContentHeight for next iteration
                        let updatedOffset = await MainActor.run {
                            self.tableView.contentOffset
                        }
                        let updatedHeight = await MainActor.run {
                            self.tableView.contentSize.height
                        }
                        oldContentOffset = updatedOffset
                        oldContentHeight = updatedHeight
                        // Continue loop to load more from cache
                    }
                }
                
                if !cacheExhausted {
                    // Reached max attempts, proceed to API anyway
                    print("🔄 CACHE_MAX_ATTEMPTS: Reached max cache load attempts (\(maxCacheLoadAttempts)), proceeding to API call with messageId=\(apiMessageId ?? "nil")")
                }
                
                // API call path (either cache exhausted or no cache available)
                print("🔄 PROCEEDING_TO_API: About to make API call with messageId=\(apiMessageId ?? "nil")")
                
                do {
                    // Display request information - ADD DETAILED LOGGING
                    print("⏳ BEFORE_CALL: Waiting for API response for messageId=\(apiMessageId ?? "nil"), channelId=\(self.viewModel.channel.id)")
                    
                    // CRITICAL: Ensure we're using the right method for Before calls
                    print("⏳ BEFORE_CALL: Calling viewModel.loadMoreMessages with before=\(apiMessageId ?? "nil")")
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
                            // CRITICAL FIX: If we got a full batch (50 messages), clear atTopOfChannel
                            // This allows loading more messages if user scrolls up again
                            if result.messages.count >= 50 {
                                self.viewModel.viewState.atTopOfChannel.remove(self.viewModel.channel.id)
                                print("🔄 BEFORE_CALL: Got full batch (\(result.messages.count) messages), cleared atTopOfChannel to allow more loads")
                            } else if result.messages.isEmpty {
                                // Empty response means we've reached the beginning
                                self.viewModel.viewState.atTopOfChannel.insert(self.viewModel.channel.id)
                                self.lastEmptyResponseTime = Date()
                                print("⏹️ BEFORE_CALL: Empty response, reached beginning of channel")
                            }
                            
                            // Log message counts for debugging
                            // print("🧮 BEFORE_CALL: Current message counts:")
                            // print("   ViewModel: \(self.viewModel.messages.count) messages")
                            // print("   ViewState: \(self.viewModel.viewState.channelMessages[self.viewModel.channel.id]?.count ?? 0) messages")
                            // print("   TableView: \(self.tableView.numberOfRows(inSection: 0)) rows")
                            
                            // CRITICAL: If viewModel.messages is empty but viewState has messages, sync them
                            if self.viewModel.messages.isEmpty && !(self.viewModel.viewState.channelMessages[self.viewModel.channel.id]?.isEmpty ?? true) {
                                // print("⚠️ BEFORE_CALL: ViewModel messages is empty but viewState has \(self.viewModel.viewState.channelMessages[self.viewModel.channel.id]?.count ?? 0) messages - syncing")
                                self.viewModel.messages = self.viewModel.viewState.channelMessages[self.viewModel.channel.id] ?? []
                            }
                            // CRITICAL: Also ensure localMessages is synced with viewModel.messages
                            if self.localMessages.isEmpty && !self.viewModel.messages.isEmpty {
                                // print("⚠️ BEFORE_CALL: LocalMessages is empty but viewModel has \(self.viewModel.messages.count) messages - syncing")
                                self.localMessages = self.viewModel.messages
                            }
                            // CRITICAL: Always sync all three arrays after loading more
                            if let synced = self.viewModel.viewState.channelMessages[self.viewModel.channel.id], !synced.isEmpty {
                                self.viewModel.messages = synced
                                self.localMessages = synced
                                // print("🔄 BEFORE_CALL: Synced viewModel.messages and localMessages with viewState.channelMessages after loadMoreMessages")
                            } else {
                                // print("⚠️ BEFORE_CALL: Tried to sync but channelMessages was empty, skipping sync to avoid clearing arrays")
                            }
                            
                            // CRITICAL FIX: When loading older messages, keep the most recent (latest) messages
                            // Don't trim the latest messages - we want to preserve them!
                            self.enforceMessageWindow(keepingMostRecent: true)
                            
                            // MEMORY MANAGEMENT: Aggressive cleanup after loading older messages
                            // CRITICAL FIX: Keep most recent messages when trimming after loading older messages
                            if self.localMessages.count > Int(Double(MessageableChannelConstants.maxMessagesInMemory) * 1.2) {
                                self.enforceMessageWindow(keepingMostRecent: true)
                                // Also trigger ViewState cleanup if total messages are high
                                let totalMessages = self.viewModel.viewState.messages.count
                                if totalMessages > 1500 {
                                    Task.detached(priority: .background) {
                                        await MainActor.run {
                                            self.viewModel.viewState.enforceMemoryLimits()
                                        }
                                    }
                                }
                            }
                            
                            // CRITICAL: Make sure we're using the correct messages array
                            let messagesForDataSource = !self.viewModel.messages.isEmpty ? 
                                self.viewModel.messages : 
                                (self.viewModel.viewState.channelMessages[self.viewModel.channel.id] ?? [])
                            
                            // Calculate how many messages were actually added
                            let addedMessagesCount = self.viewModel.messages.count - initialMessagesCount
                            // print("✅ BEFORE_CALL: Loaded \(result.messages.count) messages, added \(addedMessagesCount) new messages")
                            
                            // CRITICAL FIX: Restore any missing users after loading older messages
                            self.viewModel.viewState.restoreMissingUsersForMessages()
                            
                            // CRITICAL FIX: Load users specifically for this channel's messages
                            self.viewModel.viewState.loadUsersForVisibleMessages(channelId: self.viewModel.channel.id)
                            
                            // EMERGENCY FIX: Force restore all users for this channel
                            self.viewModel.viewState.forceRestoreUsersForChannel(channelId: self.viewModel.channel.id)
                            
                            // FINAL CHECK: Ensure all loaded messages have their authors
                            let finalMessageIds = self.viewModel.viewState.channelMessages[self.viewModel.channel.id] ?? []
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
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
                        
                        // CRITICAL FIX: Reset debounce timer after loading completes
                        // This allows subsequent loads after a reasonable delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.lastOlderMessagesLoadTriggerTime = nil
                        }
                        
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
                        
                        // CRITICAL FIX: Reset debounce timer after loading error
                        // This allows retries after a reasonable delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.lastOlderMessagesLoadTriggerTime = nil
                        }
                        
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
                    self.lastSuccessfulLoadTime = Date() // Update to prevent immediate retries
                    
                    // CRITICAL FIX: Reset debounce timer after timeout
                    self.lastOlderMessagesLoadTriggerTime = nil
                    
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
    private func loadOlderMessagesFromCacheIfAvailable(
        channelId: String,
        oldContentOffset: CGPoint,
        oldContentHeight: CGFloat
    ) async -> Bool {
        guard let userId = viewModel.viewState.currentUser?.id,
              let baseURL = viewModel.viewState.baseURL else {
            return false
        }
        
        let totalCount = await MessageCacheManager.shared.cachedMessageCount(
            for: channelId,
            userId: userId,
            baseURL: baseURL
        )
        cachedMessageTotal = totalCount
        let currentOffset = cachedMessageOffset
        print("🔄 CACHE_CHECK: totalCount=\(totalCount), currentOffset=\(currentOffset), willLoad=\(totalCount > currentOffset)")
        guard totalCount > currentOffset else {
            print("🔄 CACHE_EXHAUSTED_EARLY: totalCount (\(totalCount)) <= currentOffset (\(currentOffset)), returning false")
            return false
        }
        
        let cachedMessages = await MessageCacheManager.shared.loadCachedMessages(
            for: channelId,
            userId: userId,
            baseURL: baseURL,
            limit: cachePageSize,
            offset: currentOffset
        )
        
        guard !cachedMessages.isEmpty else {
            return false
        }
        
        let authorIds = Set(cachedMessages.map { $0.author })
        let cachedUsers = await MessageCacheManager.shared.loadCachedUsers(
            for: Array(authorIds),
            currentUserId: userId,
            baseURL: baseURL
        )
        
        await MainActor.run {
            print("CACHE_TRACE t=\(String(format: "%.3f", Date().timeIntervalSince1970)) cachePageLoaded channel=\(channelId) offset=\(currentOffset) count=\(cachedMessages.count) total=\(totalCount)")
            for (userId, user) in cachedUsers {
                self.viewModel.viewState.users[userId] = user
            }
            
            for message in cachedMessages {
                self.viewModel.viewState.messages[message.id] = message
            }
            
            let existingSet = Set(self.localMessages)
            let newIds = cachedMessages.map { $0.id }.filter { !existingSet.contains($0) }
            let merged = newIds + self.localMessages
            
            self.viewModel.viewState.channelMessages[channelId] = merged
            self.viewModel.messages = merged
            self.localMessages = merged
            // CRITICAL FIX: When loading from cache, keep the most recent messages
            // Don't trim the latest messages - we want to preserve them!
            self.enforceMessageWindow(keepingMostRecent: true)
            self.cachedMessageOffset = min(totalCount, currentOffset + cachedMessages.count)
            
            if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                localDataSource.updateMessages(self.localMessages)
            } else {
                self.dataSource = LocalMessagesDataSource(
                    viewModel: self.viewModel,
                    viewController: self,
                    localMessages: self.localMessages
                )
                self.tableView.dataSource = self.dataSource
            }
            
            self.tableView.reloadData()
            
            let newContentHeight = self.tableView.contentSize.height
            let delta = newContentHeight - oldContentHeight
            self.tableView.contentOffset = CGPoint(
                x: oldContentOffset.x,
                y: oldContentOffset.y + delta
            )
            
            self.loadingHeaderView.isHidden = true
            self.messageLoadingState = .notLoading
            self.isLoadingOlderMessages = false
            self.isLoadingMore = false  // CRITICAL FIX: Reset isLoadingMore when cache loading succeeds
            self.lastSuccessfulLoadTime = Date()
        }
        
        return true
    }
    func loadInitialMessages() async {
        let channelId = viewModel.channel.id
        let currentChannelId = channelId
        
        // Set active channel ID for cache loading
        activeChannelId = currentChannelId
        cachedMessageOffset = 0
        
        // CRITICAL FIX: Reset empty response time when loading initial messages
        lastEmptyResponseTime = nil
        print("🔄 LOAD_INITIAL: Reset lastEmptyResponseTime for initial load")
        
        // CRITICAL FIX: Don't reload if user is in target message position
        if isInTargetMessagePosition && targetMessageId == nil {
            print("🎯 LOAD_INITIAL: User is in target message position, skipping reload to preserve position")
            return
        }
        
        // MARK: - Cache Check First
        if let userId = viewModel.viewState.currentUser?.id,
           let baseURL = viewModel.viewState.baseURL {
            // Check cache first
            let hasCache = await MessageCacheManager.shared.hasCachedMessages(
                for: channelId,
                userId: userId,
                baseURL: baseURL
            )
            
            if hasCache {
                print("✅ CACHE: Found cached messages for channel \(channelId), loading instantly")
                
                // Load cached messages
                cacheLoadTask = Task { [weak self] in
                    guard let self = self else { return }
                    
                    // Double-check channel is still active
                    guard self.activeChannelId == currentChannelId else {
                        print("⚠️ CACHE_LOAD: Channel changed, discarding cache results")
                        return
                    }
                    
                    let cachedMessages = await MessageCacheManager.shared.loadCachedMessages(
                        for: channelId,
                        userId: userId,
                        baseURL: baseURL,
                        limit: cachePageSize,
                        offset: 0
                    )
                    
                    // Load cached users
                    let authorIds = Set(cachedMessages.map { $0.author })
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
                        // Double-check before UI update
                        guard self.activeChannelId == currentChannelId,
                              self.isViewLoaded else {
                            print("⚠️ CACHE_LOAD: Channel changed or view not loaded, discarding cache results")
                            return
                        }

                        if !self.viewModel.messages.isEmpty {
                            print("⚠️ CACHE_LOAD: Messages already loaded from API, skipping cache apply")
                            return
                        }
                        
                        // Add cached users to ViewState
                        for (userId, user) in cachedUsers {
                            self.viewModel.viewState.users[userId] = user
                        }
                        
                        // Add cached messages to ViewState
                        for message in cachedMessages {
                            self.viewModel.viewState.messages[message.id] = message
                        }
                        
                        // Update channel messages
                        let messageIds = cachedMessages.map { $0.id }
                        self.viewModel.viewState.channelMessages[channelId] = messageIds
                        self.viewModel.messages = messageIds
                        self.localMessages = messageIds
                        self.enforceMessageWindow(keepingMostRecent: true)
                        self.cachedMessageOffset = cachedMessages.count
                        
                        // Update data source
                        self.dataSource = LocalMessagesDataSource(
                            viewModel: self.viewModel,
                            viewController: self,
                            localMessages: self.localMessages
                        )
                        self.tableView.dataSource = self.dataSource
                        self.tableView.reloadData()
                        self.hideSkeletonView()
                        self.tableView.alpha = 1.0
                        
                        // CRITICAL: Clear any loading indicators since we have cached messages
                        self.tableView.tableFooterView = nil
                        self.messageLoadingState = .notLoading
                        
                        print("✅ CACHE: Displayed \(cachedMessages.count) cached messages instantly")
                    }
                }
            } else {
                print("🚀 VIEW_DID_APPEAR: No cached messages found, will load from API")
            }
        } else {
            print("⚠️ CACHE: No user context, skipping cache check - will load from API")
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
            
            // CRITICAL: Don't show loading spinner if we already have messages displayed (from cache)
            // The API call will update messages in the background without showing a spinner
            // Only show spinner if we have very few messages (might be incomplete cache)
            let messageCount = viewModel.viewState.channelMessages[channelId]?.count ?? 0
            if messageCount < 10 {
                // Very few messages, might be incomplete - show subtle loading indicator
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Only show if there's no existing footer view
                    if self.tableView.tableFooterView == nil {
                        let spinner = UIActivityIndicatorView(style: .medium)
                        spinner.startAnimating()
                        spinner.frame = CGRect(x: 0, y: 0, width: self.tableView.bounds.width, height: 44)
                        self.tableView.tableFooterView = spinner
                    }
                }
            }
            // If we have 10+ messages, assume cache is complete and don't show spinner
        } else {
            // print("🧹 No existing messages for channel: \(channelId), starting fresh")
            
            // Only clear if there are no existing messages
        viewModel.viewState.channelMessages[channelId] = []
        self.localMessages = []
        
            // Force DataSource refresh immediately to show loading state
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dataSource = LocalMessagesDataSource(viewModel: self.viewModel, 
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
        let effectiveLimit = viewModel.viewState.getEffectiveFetchLimit()
        print("🌐 API CALL: fetchHistory (nearby) - Channel: \(viewModel.channel.id), Target: \(targetId), Limit: \(effectiveLimit)")
        let result = try await viewModel.viewState.http.fetchHistory(
            channel: viewModel.channel.id,
            limit: effectiveLimit,  // Uses getEffectiveFetchLimit() for guardrail support
            nearby: targetId
        ).get()
        print("✅ API RESPONSE: fetchHistory (nearby) - Received \(result.messages.count) messages, \(result.users.count) users")
                
                // print("✅ Nearby API Response received with \(result.messages.count) messages")
                
                // Fetch reply message content for messages that have replies BEFORE MainActor.run
                print("🔗 CALLING fetchReplyMessagesContent (nearby API - first call) with \(result.messages.count) messages")
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
                                viewModel.viewState.members[member.id.server, default: [:]][member.id.user] = member
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
                        let newMessages = result.messages.filter { !existingMessageIds.contains($0.id) }
                        
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
                            self.dataSource = LocalMessagesDataSource(viewModel: self.viewModel, 
                                                                     viewController: self,
                                                                     localMessages: self.localMessages)
                            self.tableView.dataSource = self.dataSource
                            self.tableView.reloadData()
                            
                            // Update table view bouncing behavior
                            self.updateTableViewBouncing()
                            
                            // CRITICAL FIX: Keep loading state until target message is scrolled to
                            // This prevents any other loading from interfering
                            print("🎯 NEARBY_SUCCESS: Keeping messageLoadingState = .loading until scroll completes")
                            
                            // Instead, trigger scrollToTargetMessage properly
                            if let targetId = self.targetMessageId {
                                print("🎯 loadInitialMessages: Found target message \(targetId), triggering scroll")
                                
                                // Check if target message is actually loaded
                                let targetInLocalMessages = self.localMessages.contains(targetId)
                                let targetInViewState = self.viewModel.viewState.messages[targetId] != nil
                                
                                print("🎯 loadInitialMessages: Target message \(targetId) loaded check:")
                                print("   - In localMessages: \(targetInLocalMessages)")
                                print("   - In viewState: \(targetInViewState)")
                                
                                if targetInLocalMessages && targetInViewState {
                                    print("✅ Target message is loaded, scrolling to it")
                                    self.scrollToTargetMessage()
                                    
                                    // CRITICAL FIX: Only reset loading state AFTER successful scroll
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        self.messageLoadingState = .notLoading
                                        print("🎯 NEARBY_COMPLETE: Reset messageLoadingState after scroll completion")
                                    }
                                } else {
                                    print("❌ Target message NOT loaded, keeping targetMessageId for later")
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
                            print("🎯 NEARBY_EMPTY: Reset protection flags after empty nearby response")
                            
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
            // No target message ID, load regular messages
            await loadRegularMessages()
        }
    }
    private func loadRegularMessages() async {
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
        
        // Check if we already have messages in memory
        if let existingMessages = viewModel.viewState.channelMessages[channelId], !existingMessages.isEmpty {
            // print("📊 Found \(existingMessages.count) existing messages in memory - using cached data")
            
            // CRITICAL FIX: Create an explicit copy to avoid reference issues
            let messagesCopy = Array(existingMessages)
            
            // Update our local messages array directly
            self.localMessages = messagesCopy
            // print("🔄 Updated localMessages with \(messagesCopy.count) messages from viewState")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.enforceMessageWindow(keepingMostRecent: true)
                self.tableView.tableFooterView = nil
                
                // Create data source with local messages
                self.dataSource = LocalMessagesDataSource(viewModel: self.viewModel,
                                                        viewController: self,
                                                        localMessages: self.localMessages)
                self.tableView.dataSource = self.dataSource
                
                // Reload table data
                self.tableView.reloadData()
                // print("📊 TABLE_VIEW reloaded with \(self.localMessages.count) messages")
                
                // Check if user has manually scrolled up recently
                let hasManuallyScrolledUp = self.lastManualScrollUpTime != nil && 
                                           Date().timeIntervalSince(self.lastManualScrollUpTime!) < 10.0
                
                // FIXED: Always position at bottom when loading initial messages from memory
                // Only skip if user has manually scrolled up
                if !hasManuallyScrolledUp {
                    // CRITICAL FIX: Don't auto-position if target message was recently highlighted
                    if let highlightTime = self.lastTargetMessageHighlightTime,
                       Date().timeIntervalSince(highlightTime) < 10.0 {
                        // Just show table without positioning
                        self.tableView.alpha = 1.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.adjustTableInsetsForMessageCount()
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
                    }
                } else {
                    // print("👆 User has manually scrolled up, showing table without auto-positioning")
                    // Just show table and adjust insets
                    self.showTableViewWithFade()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.adjustTableInsetsForMessageCount()
                    }
                }
            }
        } else {
            // No messages in memory, fetch from server
            // print("🔄 No existing messages, fetching from server")
            
            // Show skeleton loading view
            DispatchQueue.main.async {
                self.showSkeletonView()
            }
            
            // TIMING: Start measuring API call duration
            let apiStartTime = Date()
            // print("⏱️ API_CALL_START: \(apiStartTime.timeIntervalSince1970)")
            
            do {
                // Call API with proper error handling
                print("🌐 API CALL: loadMoreMessages (initial) - Channel: \(viewModel.channel.id)")
                let result = await viewModel.loadMoreMessages(before: nil)
                print("✅ API RESPONSE: loadMoreMessages (initial) - Result: \(result != nil ? "Success with \(result!.messages.count) messages" : "Nil")")
                
                // DEBUG: Check if any messages have replies
                if let fetchResult = result {
                    let messagesWithReplies = fetchResult.messages.filter { $0.replies?.isEmpty == false }
                    print("🔗 API_DEBUG: Out of \(fetchResult.messages.count) messages, \(messagesWithReplies.count) have replies")
                    for message in messagesWithReplies {
                        print("🔗 API_DEBUG: Message \(message.id) has replies: \(message.replies ?? [])")
                    }
                }
                
                // TIMING: Calculate API call duration
                let apiEndTime = Date()
                let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
                // print("⏱️ API_CALL_END: \(apiEndTime.timeIntervalSince1970)")
                // print("⏱️ API_CALL_DURATION: \(String(format: "%.2f", apiDuration)) seconds")
                
                // Process the result
            if let fetchResult = result, !fetchResult.messages.isEmpty {
                    // print("✅ Successfully loaded \(fetchResult.messages.count) messages from API in \(String(format: "%.2f", apiDuration))s")
                    
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
                        viewModel.viewState.members[member.id.server, default: [:]][member.id.user] = member
                    }
                }
                
                // Process messages - save to both viewState
                for message in fetchResult.messages {
                    viewModel.viewState.messages[message.id] = message
                }
                        
                        // Fetch reply message content in the background to avoid blocking initial render.
                        await fetchReplyMessagesContentAndRefreshUI(for: fetchResult.messages)
                
                // Sort messages by creation timestamp to ensure chronological order
                let sortedMessages = fetchResult.messages.sorted { msg1, msg2 in
                    let date1 = createdAt(id: msg1.id)
                    let date2 = createdAt(id: msg2.id)
                    return date1 < date2
                }
                
                // Create the list of sorted message IDs
                let sortedIds = sortedMessages.map { $0.id }
                
                // CRITICAL: Update our local messages array directly
                await MainActor.run {
                    // Update our local copy
                    self.localMessages = sortedIds
                    // Also update the channel messages in viewState for consistency
                    self.viewModel.viewState.channelMessages[channelId] = sortedIds
                    // CRITICAL: Ensure viewModel.messages is also synced
                    self.viewModel.messages = sortedIds
                    self.enforceMessageWindow(keepingMostRecent: true)
                    }
                    
                    // TIMING: Calculate processing duration
                    let processingEndTime = Date()
                    let processingDuration = processingEndTime.timeIntervalSince(processingStartTime)
                    // print("⏱️ PROCESSING_END: \(processingEndTime.timeIntervalSince1970)")
                    // print("⏱️ PROCESSING_DURATION: \(String(format: "%.2f", processingDuration)) seconds")
                    
                    // TIMING: Start UI update time
                    let uiStartTime = Date()
                    // print("⏱️ UI_UPDATE_START: \(uiStartTime.timeIntervalSince1970)")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Hide skeleton and show messages
                self.hideSkeletonView()
                
                // CRITICAL: Clear any loading spinner at the bottom
                self.tableView.tableFooterView = nil
                
                    // print("📊 localMessages now has \(self.localMessages.count) messages")
                    
                    // CRITICAL: Mark data source as updating before changes
                    self.isDataSourceUpdating = true
                    print("📊 DATA_SOURCE: Marking as updating for loadInitialMessages")
                    
                    // Create data source with local messages
                    self.dataSource = LocalMessagesDataSource(viewModel: self.viewModel,
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
                    let hasManuallyScrolledUp = self.lastManualScrollUpTime != nil && 
                                           Date().timeIntervalSince(self.lastManualScrollUpTime!) < 10.0
                    
                    // FIXED: Always position at bottom when loading initial messages from API
                    // Only skip if user has manually scrolled up
                    if !hasManuallyScrolledUp {
                        // CRITICAL FIX: Don't auto-position if target message was recently highlighted
                        if let highlightTime = self.lastTargetMessageHighlightTime,
                           Date().timeIntervalSince(highlightTime) < 10.0 {
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
                        
                        // CRITICAL: Clear any loading spinner at the bottom
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
    static func withTimeout<T>(timeoutNanoseconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual operation task
            group.addTask {
                return try await operation()
            }
            
            // Add a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw TimeoutError()
            }
            
            // Return the first task that completes
            let result = try await group.next()!
            
            // Cancel all remaining tasks
            group.cancelAll()
            
            return result
        }
    }
    struct TimeoutError: Error {
        var localizedDescription: String {
            return "Operation timed out"
        }
    }
    internal func checkAndFetchMissingReplies() async {
        if isUserScrolling {
            pendingMissingReplyCheck = true
            return
        }

        // CRITICAL FIX: Throttle reply checks to avoid excessive API calls
        let now = Date()
        if let lastCheck = lastReplyCheckTime, now.timeIntervalSince(lastCheck) < replyCheckCooldown {
            print("🔗 CHECK_THROTTLED: Skipping reply check (last check was \(now.timeIntervalSince(lastCheck))s ago)")
            return
        }
        lastReplyCheckTime = now
        
        // Get current visible messages
        let currentMessages = localMessages.compactMap { messageId in
            viewModel.viewState.messages[messageId]
        }
        
        print("🔗 CHECK_MISSING: Checking \(currentMessages.count) messages for missing replies")
        
        // Find messages with replies that aren't loaded yet
        var messagesNeedingReplies: [Types.Message] = []
        var totalMessagesWithReplies = 0
        var totalReplyIds = 0
        var missingReplyIds = 0
        
        for message in currentMessages {
            guard let replies = message.replies, !replies.isEmpty else { continue }
            
            totalMessagesWithReplies += 1
            totalReplyIds += replies.count
            
            // Check if any reply content is missing
            let unloadedReplies = replies.filter { replyId in
                viewModel.viewState.messages[replyId] == nil
            }
            
            if !unloadedReplies.isEmpty {
                messagesNeedingReplies.append(message)
                missingReplyIds += unloadedReplies.count
                print("🔗 CHECK_MISSING: Message \(message.id) has \(unloadedReplies.count) missing replies: \(unloadedReplies)")
            }
        }
        
        print("🔗 CHECK_MISSING: Summary - Total messages with replies: \(totalMessagesWithReplies), Total reply IDs: \(totalReplyIds), Missing reply IDs: \(missingReplyIds)")
        
        if !messagesNeedingReplies.isEmpty {
            print("🔗 CHECK_MISSING: Found \(messagesNeedingReplies.count) messages with missing reply content, fetching now...")
            await fetchReplyMessagesContent(for: messagesNeedingReplies)
            
            // Refresh UI after fetching missing replies
            await MainActor.run {
                print("🔗 CHECK_MISSING: Refreshing UI after loading missing replies")
                self.refreshMessages()
            }
        } else {
            print("🔗 CHECK_MISSING: All reply content is already loaded!")
        }
    }
    func loadNewerMessages(after messageId: String) {
        let channelLastMessageId = viewModel.channel.last_message_id
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: [
            "filter": "LOAD_NEWER",
            "action": "loadNewerMessages_start",
            "afterMessageId": messageId,
            "localMessagesCount": localMessages.count,
            "localMessagesEmpty": localMessages.isEmpty,
            "isLoadingMore": isLoadingMore,
            "lastMessageId": localMessages.last ?? "nil",
            "channelLastMessageId": channelLastMessageId ?? "nil",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("MESSAGE_SCROLLING: \(jsonString)")
        }
        
        // Only if we have messages and not already loading
        guard !localMessages.isEmpty && !isLoadingMore else { 
            if let jsonDataGuard = try? JSONSerialization.data(withJSONObject: [
                "filter": "LOAD_NEWER",
                "action": "loadNewerMessages_guard_failed",
                "isEmpty": localMessages.isEmpty,
                "isLoadingMore": isLoadingMore,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]),
               let jsonStringGuard = String(data: jsonDataGuard, encoding: .utf8) {
                print("MESSAGE_SCROLLING: \(jsonStringGuard)")
            }
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
        
        // Create task to load messages with timeout protection
        Task {
            // CRITICAL FIX: Add timeout to prevent isLoadingMore from staying true forever
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout
                await MainActor.run {
                    if self.isLoadingMore {
                        if let jsonDataTimeout = try? JSONSerialization.data(withJSONObject: [
                            "filter": "LOAD_NEWER",
                            "action": "loadNewerMessages_timeout",
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                        ]),
                           let jsonStringTimeout = String(data: jsonDataTimeout, encoding: .utf8) {
                            print("MESSAGE_SCROLLING: \(jsonStringTimeout)")
                        }
                        self.isLoadingMore = false
                        self.messageLoadingState = .notLoading
                    }
                }
            }
            
            do {
                // Save count of messages before loading
                let initialCount = localMessages.count
                // print("📥📥 AFTER_CALL: Initial message count: \(initialCount)")
                
                // Call the API through the viewModel with after parameter
                let result = await viewModel.loadMoreMessages(
                    before: nil,
                    after: messageId
                )
                
                // Cancel timeout task since we got a result
                timeoutTask.cancel()
                
                // print("📥📥 AFTER_CALL: API call completed. Result is nil? \(result == nil)")
                
                // Process results on main thread
                await MainActor.run {
                    // Always reset loading flags first
                    isLoadingMore = false
                    messageLoadingState = .notLoading
                    
                    // Process the new messages
                    if let fetchResult = result, !fetchResult.messages.isEmpty {
                        // print("📥📥 AFTER_CALL: Processing \(fetchResult.messages.count) new messages")
                        
                        let channelLastMessageId = self.viewModel.channel.last_message_id
                        
                        if let jsonDataBefore = try? JSONSerialization.data(withJSONObject: [
                            "filter": "LOAD_NEWER",
                            "action": "loadNewerMessages_api_result",
                            "fetchResultCount": fetchResult.messages.count,
                            "localMessagesCountBefore": localMessages.count,
                            "lastMessageIdBefore": localMessages.last ?? "nil",
                            "firstNewMessageId": fetchResult.messages.first?.id ?? "nil",
                            "lastNewMessageId": fetchResult.messages.last?.id ?? "nil",
                            "channelLastMessageId": channelLastMessageId ?? "nil",
                            "newLastMatchesChannel": fetchResult.messages.last?.id == channelLastMessageId,
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                        ]),
                           let jsonStringBefore = String(data: jsonDataBefore, encoding: .utf8) {
                            print("MESSAGE_SCROLLING: \(jsonStringBefore)")
                        }
                        
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
                            
                            if let jsonData = try? JSONSerialization.data(withJSONObject: [
                                "filter": "LOAD_NEWER",
                                "action": "loadNewerMessages_adding",
                                "messagesToAddCount": messagesToAdd.count,
                                "beforeCount": localMessages.count,
                                "newMessageIds": Array(messagesToAdd.prefix(5)),
                                "lastMessageIdBefore": localMessages.last ?? "nil",
                                "channelLastMessageId": channelLastMessageId ?? "nil",
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]),
                               let jsonString = String(data: jsonData, encoding: .utf8) {
                                print("MESSAGE_SCROLLING: \(jsonString)")
                            }
                            
                            // Create new arrays to avoid reference issues
                            var updatedMessages = localMessages
                            updatedMessages.append(contentsOf: messagesToAdd)
                            
                            // Update all message arrays
                            viewModel.messages = updatedMessages
                            localMessages = updatedMessages
                            viewModel.viewState.channelMessages[viewModel.channel.id] = updatedMessages
                            
                            if let jsonData2 = try? JSONSerialization.data(withJSONObject: [
                                "filter": "LOAD_NEWER",
                                "action": "loadNewerMessages_before_enforce",
                                "afterCount": updatedMessages.count,
                                "lastMessageIdAfter": updatedMessages.last ?? "nil",
                                "channelLastMessageId": channelLastMessageId ?? "nil",
                                "keepingMostRecent": true,
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]),
                               let jsonString2 = String(data: jsonData2, encoding: .utf8) {
                                print("MESSAGE_SCROLLING: \(jsonString2)")
                            }
                            
                            self.enforceMessageWindow(keepingMostRecent: true)
                            
                            if let jsonData3 = try? JSONSerialization.data(withJSONObject: [
                                "filter": "LOAD_NEWER",
                                "action": "loadNewerMessages_after_enforce",
                                "localMessagesCountAfter": self.localMessages.count,
                                "lastMessageIdAfterEnforce": self.localMessages.last ?? "nil",
                                "viewModelMessagesCount": self.viewModel.messages.count,
                                "channelLastMessageId": channelLastMessageId ?? "nil",
                                "matchesChannelLatest": self.localMessages.last == channelLastMessageId,
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]),
                               let jsonString3 = String(data: jsonData3, encoding: .utf8) {
                                print("MESSAGE_SCROLLING: \(jsonString3)")
                            }
                            
                            // MEMORY MANAGEMENT: Aggressive cleanup after loading newer messages
                            if self.localMessages.count > Int(Double(MessageableChannelConstants.maxMessagesInMemory) * 1.2) {
                                self.enforceMessageWindow(keepingMostRecent: true)
                                // Also trigger ViewState cleanup if total messages are high
                                let totalMessages = self.viewModel.viewState.messages.count
                                if totalMessages > 1500 {
                                    Task.detached(priority: .background) {
                                        await MainActor.run {
                                            self.viewModel.viewState.enforceMemoryLimits()
                                        }
                                    }
                                }
                            }
                            
                            // Final verification
                            // print("📥📥 AFTER_CALL: Arrays updated: viewModel.messages=\(viewModel.messages.count), localMessages=\(localMessages.count)")
                            
                            if let jsonData4 = try? JSONSerialization.data(withJSONObject: [
                                "filter": "LOAD_NEWER",
                                "action": "loadNewerMessages_before_refresh",
                                "localMessagesCount": self.localMessages.count,
                                "viewModelMessagesCount": self.viewModel.messages.count,
                                "channelMessagesCount": self.viewModel.viewState.channelMessages[self.viewModel.channel.id]?.count ?? 0,
                                "lastMessageId": self.localMessages.last ?? "nil",
                                "channelLastMessageId": channelLastMessageId ?? "nil",
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]),
                               let jsonString4 = String(data: jsonData4, encoding: .utf8) {
                                print("MESSAGE_SCROLLING: \(jsonString4)")
                            }
                            
                            // CRITICAL FIX: Defer UI update to avoid jumps during scroll
                            // Only refresh if not currently scrolling to prevent UI jumps
                            if !self.tableView.isDragging && !self.tableView.isDecelerating {
                                self.refreshMessages()
                            } else {
                                // Defer refresh until scroll ends
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if !self.tableView.isDragging && !self.tableView.isDecelerating {
                                        self.refreshMessages()
                                    }
                                }
                            }
                            
                            if let jsonData5 = try? JSONSerialization.data(withJSONObject: [
                                "filter": "LOAD_NEWER",
                                "action": "loadNewerMessages_after_refresh",
                                "localMessagesCount": self.localMessages.count,
                                "tableViewRows": self.tableView.numberOfRows(inSection: 0),
                                "lastMessageId": self.localMessages.last ?? "nil",
                                "channelLastMessageId": channelLastMessageId ?? "nil",
                                "matchesChannelLatest": self.localMessages.last == channelLastMessageId,
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]),
                               let jsonString5 = String(data: jsonData5, encoding: .utf8) {
                                print("MESSAGE_SCROLLING: \(jsonString5)")
                            }
                            
                            // Show success notification
                            // print("✅ AFTER_CALL: Successfully loaded \(messagesToAdd.count) newer messages")
                        } else {
                            if let jsonDataEmpty = try? JSONSerialization.data(withJSONObject: [
                                "filter": "LOAD_NEWER",
                                "action": "loadNewerMessages_no_messages_to_add",
                                "messagesToAddEmpty": messagesToAdd.isEmpty,
                                "newMessageIdsCount": newMessageIds.count,
                                "existingIdsCount": existingIds.count,
                                "localMessagesCount": localMessages.count,
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]),
                               let jsonStringEmpty = String(data: jsonDataEmpty, encoding: .utf8) {
                                print("MESSAGE_SCROLLING: \(jsonStringEmpty)")
                            }
                            // print("📥📥 AFTER_CALL: No new unique messages to add (duplicates)")
                        }
                    } else {
                        if let jsonDataNoResult = try? JSONSerialization.data(withJSONObject: [
                            "filter": "LOAD_NEWER",
                            "action": "loadNewerMessages_empty_api_result",
                            "resultIsNil": result == nil,
                            "resultMessagesEmpty": result?.messages.isEmpty ?? true,
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                        ]),
                           let jsonStringNoResult = String(data: jsonDataNoResult, encoding: .utf8) {
                            print("MESSAGE_SCROLLING: \(jsonStringNoResult)")
                        }
                        // print("📥📥 AFTER_CALL: API returned empty result or no new messages")
                        
                        // CRITICAL FIX: Explicitly ensure loading flags are reset when result is empty
                        // This prevents isLoadingMore from staying true and blocking subsequent loads
                        isLoadingMore = false
                        messageLoadingState = .notLoading
                    }
                }
            } catch {
                // Cancel timeout task since we got an error
                timeoutTask.cancel()
                
                // print("❌ AFTER_CALL: Error loading newer messages: \(error)")
                
                // Reset loading state on main thread
                await MainActor.run {
                    isLoadingMore = false
                    messageLoadingState = .notLoading
                }
            }
        }
    }
    func refreshWithTargetMessage(_ messageId: String) async {
        print("🚀 ========== refreshWithTargetMessage CALLED ==========")
        print("🎯 refreshWithTargetMessage called with messageId: \(messageId)")
        print("🎯 Current channel: \(viewModel.channel.id)")
        print("🎯 Current targetMessageId: \(targetMessageId ?? "nil")")
        print("🎯 ViewState currentTargetMessageId: \(viewModel.viewState.currentTargetMessageId ?? "nil")")
        print("🔍 This is where API calls should happen for fetching the target message!")
        
        // CRITICAL FIX: Set loading state to prevent premature cleanup
        messageLoadingState = .loading
        print("🎯 Set messageLoadingState to .loading for target message")
        
        // CRITICAL FIX: Add timeout protection to prevent infinite loading
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds (reduced for better UX)
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
            print("🎯 Target message \(messageId) already processed, skipping to prevent duplicate highlights")
            return
        }
        
        // Validate that the message belongs to current channel (if already loaded)
        if let existingMessage = viewModel.viewState.messages[messageId] {
            if existingMessage.channel != viewModel.channel.id {
                print("❌ Target message \(messageId) belongs to channel \(existingMessage.channel), but current channel is \(viewModel.channel.id)")
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
                print("✅ Target message \(messageId) already exists and is visible, scrolling to it")
                
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
        print("🔄 REPLY_TARGET: Target message not found in loaded messages, loading nearby messages")
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
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
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
                    print("❌ DIRECT_TARGET: Fetched message \(messageId) belongs to channel \(message.channel), but current channel is \(viewModel.channel.id)")
                    await MainActor.run {
                        self.viewModel.viewState.currentTargetMessageId = nil
                        self.targetMessageId = nil
                        self.loadingHeaderView.isHidden = true
                        self.messageLoadingState = .notLoading
                        self.isLoadingMore = false
                    }
                    return
                }
                
                print("✅ DIRECT_TARGET: Successfully fetched target message directly: \(message.id)")
                
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
                        print("📍 DIRECT_TARGET: Inserted message at index \(insertIndex) of \(viewModel.messages.count)")
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
                    print("🔄 DIRECT_TARGET: Refreshing UI with \(self.localMessages.count) messages")
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
                print("❌ DIRECT_TARGET: Failed to fetch target message directly - likely deleted or inaccessible")
                
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
        let finalCheck = viewModel.messages.contains(messageId) || 
                        viewModel.viewState.messages[messageId] != nil ||
                        (viewModel.viewState.channelMessages[viewModel.channel.id]?.contains(messageId) ?? false)
                        
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
    private func loadInitialMessagesImmediate() async {
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
            
            // SMART LIMIT: Use 10 for specific channel in specific server, otherwise use effective fetch limit
            let baseLimit = (channelId == "01J7QTT66242A7Q26A2FH5TD48" && serverId == "01J544PT4T3WQBVBSDK3TBFZW7") ? 10 : viewModel.viewState.getEffectiveFetchLimit()
            let messageLimit = baseLimit
            
            // IMMEDIATE API CALL
            print("⚡ API CALL: fetchHistory IMMEDIATE - Channel: \(channelId), Limit: \(messageLimit)")
            let result = try await viewModel.viewState.http.fetchHistory(
                channel: channelId,
                limit: messageLimit,  // Uses getEffectiveFetchLimit() for guardrail support
                sort: "Latest",
                server: serverId,
                include_users: true
            ).get()
            
            let apiEndTime = Date()
            let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
            print("⚡ API_RESPONSE_IMMEDIATE: Received \(result.messages.count) messages in \(String(format: "%.2f", apiDuration))s")
            
            // IMMEDIATE PROCESSING
            let processingStartTime = Date()
            
            // Process users immediately
            for user in result.users {
                viewModel.viewState.users[user.id] = user
            }
            
            // Process members immediately
            if let members = result.members {
                for member in members {
                    viewModel.viewState.members[member.id.server, default: [:]][member.id.user] = member
                }
            }
            
            // Process messages immediately
            for message in result.messages {
                viewModel.viewState.messages[message.id] = message
            }
            
            // Fetch reply message content for messages that have replies
            print("🔗 CALLING fetchReplyMessagesContentAndRefreshUI (immediate load) with \(result.messages.count) messages")
            await fetchReplyMessagesContentAndRefreshUI(for: result.messages)
            
            // Sort messages immediately
            let sortedIds = result.messages.map { $0.id }.sorted { id1, id2 in
                let date1 = createdAt(id: id1)
                let date2 = createdAt(id: id2)
                return date1 < date2
            }
            
            let processingEndTime = Date()
            let processingDuration = processingEndTime.timeIntervalSince(processingStartTime)
            print("⚡ PROCESSING_IMMEDIATE: Processed \(sortedIds.count) messages in \(String(format: "%.2f", processingDuration))s")
            
            // IMMEDIATE UI UPDATE
            let uiStartTime = Date()
            
            await MainActor.run {
                // Hide skeleton first
                self.hideSkeletonView()
                
                // Update all data immediately
                self.localMessages = sortedIds
                self.viewModel.viewState.channelMessages[channelId] = sortedIds
                self.viewModel.messages = sortedIds
                self.enforceMessageWindow(keepingMostRecent: true)
                
                // Update data source immediately
                if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                    localDataSource.updateMessages(self.localMessages)
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
                print("⚡ BREAKDOWN: API=\(String(format: "%.2f", apiDuration))s, Processing=\(String(format: "%.2f", processingDuration))s, UI=\(String(format: "%.2f", uiDuration))s")
            }
            
        } catch {
            print("❌ IMMEDIATE_LOAD_ERROR: \(error)")
            
            DispatchQueue.main.async {
                self.hideSkeletonView()
                self.updateEmptyStateVisibility()
            }
        }
    }

}
