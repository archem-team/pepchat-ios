Implement Message Caching with Order Preservation
Problem Analysis
From the logs, every channel entry triggers an API call:

"🚀 VIEW_DID_APPEAR: No messages found, loading from API IMMEDIATELY"
This happens even when returning to a recently viewed channel
MessageCacheManager exists but is not integrated into the loading flow
Messages are cleared from memory when leaving, but not saved to cache
Current Flow Issues
No cache check: loadInitialMessages() always calls API
No cache saving: Messages from API are not saved to MessageCacheManager
Memory-only storage: Messages only exist in ViewState.messages dictionary
Order preservation: ULID-based sorting exists but cache doesn't leverage it
Implementation Plan
1. Integrate Cache Check in Message Loading
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift

Modify loadInitialMessages() to check cache first
Load cached messages instantly and display them
Then fetch from API in background to update
Show loading indicator only if no cache exists
2. Save Messages to Cache After API Response
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewModel.swift

After successful API response in loadMoreMessages(), save messages to cache
Use MessageCacheManager.shared.cacheMessages() 
Also cache users with MessageCacheManager.shared.cacheUsers()
Save in background to avoid blocking UI
3. Cache Messages Immediately After API Response (NOT During Cleanup)
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewModel.swift

CRITICAL: Save to cache immediately after receiving messages from API
Do NOT cache during cleanup (would slow down channel closing)
Use background task: Task.detached { await MessageCacheManager.shared.cacheMessages(...) }
Cache both message objects and users in same transaction
This ensures cache is always up-to-date without blocking UI
4. Enhance MessageCacheManager for Order Preservation
File: Revolt/1Storage/MessageCacheManager.swift

Ensure loadCachedMessages() returns messages in correct chronological order
Use ULID timestamp extraction for sorting (already implemented)
Add method to get last cached message ID for incremental updates
Add method to merge new messages with cached ones (handle gaps)
5. Handle Cache Updates for Edits and Deletes
File: Revolt/1Storage/MessageCacheManager.swift and Revolt/ViewState.swiftFor Message Edits:

When WebSocket .message_update event received (ViewState line 2505):
Update message in cache: updateCachedMessage(messageId, newContent, editedAt)
When local edit succeeds (MessageInputHandler line 365):
Update cache after updating ViewState
Cache update is non-blocking background operation
For Message Deletes:

When WebSocket .message_delete event received (ViewState line 2540):
Remove from cache: deleteCachedMessage(messageId)
When local delete succeeds (RepliesManager line 370):
Remove from cache after removing from ViewState
Cache deletion is non-blocking background operation
Cache Invalidation Methods:

updateCachedMessage(id:content:editedAt:) - Update edited message
deleteCachedMessage(id:) - Remove deleted message
clearChannelCache(channelId:) - Clear all cache for a channel (when needed)
Add timestamp-based cache freshness check
Consider cache expiration (e.g., 24 hours for active channels)
6. Optimize Cache Loading Performance
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift

Load cache asynchronously but display immediately
Use pagination for large channels (load 50 messages at a time)
Show skeleton loader only if cache is empty
Display cached messages instantly, then update with API response
Implementation Details
Cache-First Loading Flow
1. User opens channel
2. Check MessageCacheManager.hasCachedMessages()
3. If cached:
      - Load cached messages instantly (async but fast)
      - Display messages immediately
      - Fetch from API in background
      - Merge/update messages when API responds
4. If not cached:
      - Show skeleton loader
      - Fetch from API
      - Save to cache after receiving
      - Display messages
Message Order Preservation
ULIDs are lexicographically sortable and contain timestamps
Use createdAt(id:) function to extract timestamp
Sort messages by created_at in SQLite (already implemented)
When merging API response with cache, maintain chronological order
Cache Update Strategy
Immediate caching: Save to cache right after API response (background, non-blocking)
User isolation: All cache operations include userId and baseURL in keys
Incremental updates: Track lastCachedMessageId per channel, fetch only newer messages
Deterministic freshness (computed, not server-provided): 
Compute serverLastMessageId from API response: max(messages.map { $0.id }) (ULIDs are sortable)
Cache stale if: (now - lastUpdated) > 1 hour OR computedServerLastMessageId > lastCachedMessageId
Always fetch if cache is older than 1 hour
Always fetch if computed server last message ID is newer than cached last message ID
Message count mismatch is secondary indicator (cache has 50, API returns 100 = likely stale)
Strict merge logic: 
De-duplicate by message ID using Set<String>
Respect tombstone set (deleted message IDs)
Sort by ULID timestamp (never by array index)
Atomic UI update (single reloadData() after merge)
Gap handling: If API returns messages older than lastCachedMessageId, fill gaps but maintain order
Size management: Enforce 500 messages per channel limit, evict oldest when exceeded
Edit/Delete Handling Strategy
WebSocket events: 
.message_update: Check editedAt timestamp, only update if WebSocket edit is newer than cache
.message_delete: Add to tombstone set AND remove from cache
Process WebSocket events before applying API merge results
Local actions: 
After successful edit API call → update cache with new content and editedAt
After successful delete API call → add to tombstone set and remove from cache
Race condition prevention:
Maintain `deletedMessageIds: [String: Set<String>]` per channel in ViewState
Check tombstone set before inserting any cached message
Use sequential processing (actor or serial queue) for merge operations
Background operations: All cache updates are non-blocking background tasks
Order preservation: Edits maintain message position (same ULID), deletes remove from ordered list
Risks and Mitigations
1. Stale or Inconsistent UI (Duplicate/Reordered Rows)
Risk: Showing cached messages then merging API results can cause duplicates or reordered rows.Mitigation:

Strict de-duplication: Use Set<String> for message IDs during merge, only add if not present
Stable ULID sort: Always sort by created_at extracted from ULID, never by array index
Last cached message ID boundary: Track lastCachedMessageId per channel, only merge messages newer than this
Merge algorithm: 
Create Set of cached message IDs
Filter API messages: only include if ID not in Set AND (newer than lastCachedMessageId OR filling gap)
Combine arrays, sort by ULID timestamp
Update UI atomically with single array replacement
2. Race Conditions with WebSocket Events
Risk: WebSocket updates arrive during merge, re-inserting deleted/edited content.Mitigation:

Tombstone tracking: Maintain `deletedMessageIds: [String: Set<String>]` in ViewState per channel
Tombstone retention policy: 
Expire tombstones after 7 days (same as message cache retention)
Clear tombstones when channel cache is cleared
Limit tombstone set size to 1000 per channel (evict oldest when exceeded)
Clear all tombstones on app launch if cache schema version changes
Store tombstones in SQLite tombstones table with deleted_at timestamp
Edit timestamps: Compare editedAt timestamps - only apply cache update if WebSocket edit is newer
Sequential processing: Use actor or serial queue for merge operations
Event ordering: Process WebSocket events before applying API merge results
Guard checks: Before inserting cached message, check if it's been deleted/edited via WebSocket
3. User/Session Isolation
Risk: Cache keys don't include user/session, showing wrong user's messages after sign-out/sign-in.Mitigation:

Cache key format: "\(userId)_\(baseURL)_\(channelId)" or "\(sessionId)_\(channelId)"
Clear cache on sign-out: MessageCacheManager.clearAllCaches() when signOut() is called
Validate on load: Check currentUser.id matches cache key before loading
Database schema update: Add user_id and base_url columns to messages table
Migration: Clear old cache on first launch after update
4. Cache Bloat for Large Channels
Risk: Caching all messages without eviction can blow disk/memory.Mitigation:

Per-channel limits: Max 500 messages per channel in cache (configurable)
LRU eviction: Remove oldest messages when limit exceeded
Size-based limits: Max 100MB total cache size, evict oldest channels first
Automatic cleanup: Background task runs daily to remove messages older than 7 days
Selective caching: Only cache channels viewed in last 24 hours
Pagination: Load 50 messages at a time, don't cache entire channel history
5. Attachment/Media Payloads
Risk: Full message payloads with attachment metadata can be large.Mitigation:

Exclude large blobs: Don't cache attachment binary data, only metadata (URLs, IDs, sizes)
Separate storage: Use separate table for attachment metadata if needed
Size limits: Skip caching messages with attachments > 5MB
Lazy loading: Cache message text/content, fetch attachment metadata on-demand
Compression: Consider compressing message_data BLOB in SQLite
6. UI Thread Contention
Risk: Background merge operations can cause UI jitter if not properly scheduled.Mitigation:

MainActor isolation: All UI updates must be @MainActor
Background processing: Cache loading/merging happens off main thread
Atomic updates: Single tableView.reloadData() after merge complete, not incremental
Debouncing: Debounce rapid cache updates (max 1 update per 100ms)
Task cancellation: Cancel cache load tasks when view controller deallocates
Weak references: Use [weak self] in all async cache operations
7. Cache Invalidation Policy
Risk: Vague expiration times can miss messages or show stale data.Mitigation:

Deterministic invalidation (computed, not server-provided):
Compute server last message ID: Use max(messages.map { $0.id }) from API response (ULIDs are lexicographically sortable)
Cache is stale if: (now - lastUpdated) > 1 hour OR computedServerLastMessageId > lastCachedMessageId
Always fetch if cache is older than 1 hour
Always fetch if computed server last message ID is newer than cached last message ID
Message count mismatch is secondary indicator (cache has 50, API returns 100 = likely stale)
Fallback freshness check: If API returns empty messages but cache has messages, check if cache is >5 minutes old
Force refresh: User pull-to-refresh always bypasses cache
WebSocket invalidation: If WebSocket reports new message with ID older than lastCachedMessageId, invalidate cache (gap detected)
Version tracking: Add cache_schema_version to UserDefaults, enforce migration on mismatch
8. Cleanup on Channel Leave
Risk: Cache load tasks can apply results to deallocated views.Mitigation:

Task cancellation: Store cacheLoadTask: Task<Void, Never>? and cancel in viewDidDisappear
Channel state tracking: Add activeChannelId: String? property (not just boolean isActive)
Set to viewModel.channel.id in viewDidAppear
Clear to nil in viewDidDisappear
Check activeChannelId == currentChannelId before applying cache results
Weak view controller: Use [weak self] in all cache loading closures
Guard checks: Before applying cache results, check viewController != nil and isViewLoaded and activeChannelId == currentChannelId
Early return: If view controller is deallocated or channel changed, discard cache results silently
9. Server Last Message ID Computation
Risk: Plan references serverLastMessageId but API doesn't provide it directly. The FetchHistory response only contains messages, users, and members arrays - no explicit last_message_id field.Mitigation:

Compute from API response: Since ULIDs are lexicographically sortable, compute serverLastMessageId = max(messages.map { $0.id }) from FetchHistory.messages array
Implementation: After receiving API response in loadMoreMessages(), compute: let serverLastMessageId = result.messages.map { $0.id }.max()
Store computed value: Save computed serverLastMessageId to channel_info.last_message_id column in SQLite
Use for freshness: Compare computedServerLastMessageId > lastCachedMessageId to detect new messages on server
Handle empty responses: If API returns empty array, keep existing lastCachedMessageId (no new messages on server)
Incremental updates: When fetching with after parameter, compute new max from all messages in response and update stored value
Edge case: If API returns messages but max ID is older than cached, this indicates gap-filling - still update cache but don't mark as stale
10. Tombstone Growth
Risk: deletedMessageIds can grow without bound if not evicted, consuming memory and disk space.Mitigation:

Retention policy: Expire tombstones after 7 days (same as message cache retention)
Store deleted_at timestamp in tombstones table
Background task runs daily: DELETE FROM tombstones WHERE deleted_at < (NOW() - 7 days)
Size limits: Limit tombstone set to 1000 per channel, evict oldest when exceeded
When limit reached: DELETE FROM tombstones WHERE channel_id = ? ORDER BY deleted_at ASC LIMIT (count - 1000)
Automatic cleanup: Background task runs daily to remove expired tombstones
Call MessageCacheManager.expireTombstones(olderThan: 7) from ViewState cleanup timer
Clear on cache clear: Remove all tombstones when channel cache is cleared
DELETE FROM tombstones WHERE channel_id = ? AND user_id = ? AND base_url = ?
Persist to database: Store tombstones in SQLite tombstones table with message_id, channel_id, user_id, base_url, deleted_at columns
Schema migration: Clear all tombstones when cache schema version changes (part of checkAndMigrateSchema())
Memory optimization: Keep in-memory deletedMessageIds Set for fast lookups, but persist to DB for durability
11. Cache Schema Versioning
Risk: No versioning mechanism specified for cache migrations. Schema changes (e.g., adding user_id column) would break existing cache.Mitigation:

Version storage: Store cache_schema_version in UserDefaults (not in database) with key "messageCacheSchemaVersion"
Current version: Define private let currentSchemaVersion = 1 in MessageCacheManager
Migration check: Call checkAndMigrateSchema() in MessageCacheManager.init() before any database operations
Migration logic: 
If storedVersion < currentSchemaVersion: Clear all caches (DROP all tables, recreate), update version to current
If storedVersion == 0: First launch, set version to current (no migration needed)
If storedVersion == currentSchemaVersion: No migration needed, proceed normally
If storedVersion > currentSchemaVersion: Future version detected, clear cache and reset to current (downgrade protection)
Version increments: Increment currentSchemaVersion when:
Schema changes (new columns, table structure, index changes)
Cache key format changes (e.g., adding user_id to keys)
Tombstone structure changes
Breaking changes to message serialization format
Migration in ViewState: Call MessageCacheManager.shared.checkAndMigrateSchema() in ViewState.init() as backup check
Implementation: 
func checkAndMigrateSchema() {
    let storedVersion = UserDefaults.standard.integer(forKey: "messageCacheSchemaVersion")
    if storedVersion < currentSchemaVersion || storedVersion > currentSchemaVersion {
        // Clear all caches
        clearAllCaches()
        UserDefaults.standard.set(currentSchemaVersion, forKey: "messageCacheSchemaVersion")
    } else if storedVersion == 0 {
        // First launch
        UserDefaults.standard.set(currentSchemaVersion, forKey: "messageCacheSchemaVersion")
    }
    // Recreate tables if needed
    createTables()
}
12. Cache Load Pagination vs UI
Risk: Unclear UI behavior for showing cached messages vs API pagination. "Load 50 messages at a time" + "display instantly" creates confusion about partial vs complete views.Mitigation:

Cache display strategy: Load ALL cached messages initially (up to 500 limit) for instant complete display
No pagination for cache - it's a complete snapshot
User sees full cached history immediately (up to 500 messages)
No pagination UI for cache: Cache is shown as complete set, no "load more" indicator needed
If cache has 500 messages, show all 500 instantly
If cache has 10 messages, show all 10 instantly
API pagination separate: API "load more" (scroll to top) works independently, merges with cached set
User scrolls to top → triggers API call for older messages
API results prepend to top of list
No conflict with cache display
UI behavior:
If cache exists: 
Show all cached messages immediately (complete view, no loading indicator)
Fetch API in background (non-blocking)
Merge API results incrementally when received (add new messages, update edited ones)
User can scroll to top to load older messages via API (pagination works as before)
If cache doesn't exist:
Show skeleton loader
Fetch API
Save to cache after receiving
Display messages
Implementation: 
loadCachedMessagesForDisplay(channelId:userId:baseURL:) returns all cached messages (limit: 500, not paginated)
UI displays complete cached set immediately via tableView.reloadData()
API results merge in background without pagination UI
No "showing 50 of 500" indicator - cache is treated as complete snapshot
13. Channel Selection State Guard
Risk: Cache results might apply to wrong channel if user navigates fast. Boolean isActive flag is insufficient - need channel-specific guard.Mitigation:

Channel-keyed state: Use activeChannelId: String? (not boolean isActive)
Store the actual channel ID that's currently active
nil means no channel is active
Set on appear: activeChannelId = viewModel.channel.id in viewDidAppear(_:)
Set immediately when view appears, before any cache loading
Clear on disappear: activeChannelId = nil in viewDidDisappear(_:)
Clear immediately when view disappears
Guard before apply: Check activeChannelId == currentChannelId before applying cache results
At task start: Capture currentChannelId = viewModel.channel.id
Before UI update: Verify self.activeChannelId == currentChannelId
If mismatch: Discard cache results silently (channel changed)
Task cancellation: Cancel cacheLoadTask when activeChannelId changes
In viewDidDisappear: cacheLoadTask?.cancel() and set to nil
In viewDidAppear: Cancel any existing task before starting new one
Double-check pattern: Verify channel ID matches at both task start and UI update time
Capture currentChannelId at task creation
Check activeChannelId == currentChannelId before applying results
Check isViewLoaded to ensure view is still valid
Implementation:
private var activeChannelId: String? = nil
private var cacheLoadTask: Task<Void, Never>? = nil

override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    let currentChannelId = viewModel.channel.id
    activeChannelId = currentChannelId
    cacheLoadTask?.cancel() // Cancel any existing task
    loadCachedMessages()
}

func loadCachedMessages() {
    let currentChannelId = viewModel.channel.id
    guard activeChannelId == currentChannelId else { return }
    
    cacheLoadTask = Task { [weak self] in
        guard let self = self else { return }
        let cached = await MessageCacheManager.shared.loadCachedMessages(...)
        
        await MainActor.run {
            // Double-check before UI update
            guard self.activeChannelId == currentChannelId,
                  self.isViewLoaded else {
                return
            }
            // Apply cached messages to UI
        }
    }
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    activeChannelId = nil
    cacheLoadTask?.cancel()
    cacheLoadTask = nil
}
Implementation Details (Updated)
Cache Key Format
func cacheKey(for channelId: String, userId: String, baseURL: String) -> String {
    return "\(userId)_\(baseURL)_\(channelId)"
}
Cache Schema Versioning
// In MessageCacheManager init:
private let currentSchemaVersion = 1
private let schemaVersionKey = "messageCacheSchemaVersion"

func checkAndMigrateSchema() {
    let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
    if storedVersion < currentSchemaVersion {
        // Clear all caches and migrate
        clearAllCaches()
        UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
    } else if storedVersion == 0 {
        // First launch - set version
        UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
    }
}
Merge Algorithm with De-duplication
func mergeMessages(cached: [Message], api: [Message], lastCachedId: String?, deletedIds: Set<String>) -> (merged: [Message], serverLastMessageId: String?) {
    let cachedIds = Set(cached.map { $0.id })
    
    // Compute server last message ID from API response (ULIDs are lexicographically sortable)
    let serverLastMessageId = api.map { $0.id }.max()
    
    // Filter API messages: not in cache, not deleted, and (newer than lastCached OR filling gap)
    let newMessages = api.filter { message in
        !cachedIds.contains(message.id) &&
        !deletedIds.contains(message.id) &&
        (lastCachedId == nil || message.id > lastCachedId || isFillingGap(message, cached))
    }
    
    // Combine and sort by ULID timestamp (stable sort)
    let merged = (cached + newMessages)
        .sorted { createdAt(id: $0.id) < createdAt(id: $1.id) }
    
    return (merged, serverLastMessageId)
}
Cache Eviction Strategy
// Per-channel limit
private let maxMessagesPerChannel = 500

// Total cache size limit
private let maxCacheSizeMB = 100

// Automatic cleanup
func evictOldMessages() {
    // Remove messages older than 7 days
    // Remove channels not viewed in 24 hours
    // Keep only most recent 500 messages per channel
    // Expire tombstones older than 7 days
}
Cache Load Pagination Strategy
// UI Behavior: Load full cached set initially, then page API results
func loadCachedMessagesForDisplay(channelId: String, userId: String, baseURL: String) async -> [Message] {
    // Load ALL cached messages (up to per-channel limit of 500)
    // UI displays all cached messages immediately (complete view)
    // API fetch happens in background and merges incrementally
    // No pagination UI needed for cache - it's instant complete display
    // Pagination only applies to API "load more" (scroll to top)
    return await MessageCacheManager.shared.loadCachedMessages(
        for: channelId, 
        userId: userId, 
        baseURL: baseURL,
        limit: 500  // Load all cached messages
    )
}
Channel Selection State Guard
// In MessageableChannelViewController:
private var activeChannelId: String? = nil
private var cacheLoadTask: Task<Void, Never>? = nil

func loadCachedMessages() {
    let currentChannelId = viewModel.channel.id
    activeChannelId = currentChannelId
    
    cacheLoadTask = Task { [weak self] in
        guard let self = self else { return }
        
        // Check channel is still active before applying results
        guard self.activeChannelId == currentChannelId else {
            print("⚠️ CACHE_LOAD: Channel changed, discarding cache results")
            return
        }
        
        let cached = await MessageCacheManager.shared.loadCachedMessages(...)
        
        // Double-check before UI update
        await MainActor.run {
            guard self.activeChannelId == currentChannelId,
                  self.isViewLoaded else {
                return
            }
            // Apply cached messages to UI
        }
    }
}

override func viewDidDisappear() {
    activeChannelId = nil
    cacheLoadTask?.cancel()
    cacheLoadTask = nil
}
Files to Modify
Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift
Task management: Add cacheLoadTask: Task<Void, Never>? property
Channel state tracking: Add activeChannelId: String? property, set in viewDidAppear, clear in viewDidDisappear
Cache loading: Modify loadInitialMessages() to check cache first with user isolation
Cache pagination strategy: 
Load ALL cached messages initially (up to 500 limit) for instant display
No pagination UI for cache - it's a complete instant display
API results merge incrementally in background
Safe merge: Use @MainActor for UI updates, background task for merge
Task cancellation: Cancel cacheLoadTask in viewDidDisappear and deinit
Weak references: Use [weak self] in all cache loading closures
Guard checks: 
Verify activeChannelId == currentChannelId before applying cache results
Verify isViewLoaded and viewController != nil before UI updates
Revolt/Pages/Channel/Messagable/MessageableChannelViewModel.swift
Background caching: Save messages to cache after API response in loadMoreMessages() using Task.detached
User context: Pass viewState.currentUser.id and viewState.baseURL to cache operations
Compute server last message ID: Calculate max(messages.map { $0.id }) from API response and store
Cache users: Cache users when processing API response (same transaction)
Size limits: Enforce per-channel message limits before caching (max 500)
Attachment handling: Skip caching messages with large attachments (>5MB) or exclude attachment blobs
Revolt/ViewState.swift
DO NOT cache during cleanup (keep cleanup fast)
Tombstone tracking: Add `deletedMessageIds: [String: Set<String>]` to track deleted messages per channel
Tombstone retention: 
Expire tombstones after 7 days (call MessageCacheManager.expireTombstones())
Limit tombstone set size to 1000 per channel
Clear tombstones when channel cache is cleared
Cache update handlers for WebSocket events:
Update cache on .message_update event (check edit timestamp)
Delete from cache on .message_delete event (add to tombstone set AND persist to DB)
Sign-out cleanup: Call MessageCacheManager.clearAllCaches() in signOut() (clears messages and tombstones)
User context: Pass currentUser.id and baseURL to all cache operations
Schema migration: Call MessageCacheManager.checkAndMigrateSchema() in init()
Revolt/1Storage/MessageCacheManager.swift
Schema versioning: 
Add checkAndMigrateSchema() called in init()
Store cache_schema_version in UserDefaults
Clear all caches on version mismatch
User isolation: Update schema to include user_id and base_url columns
Cache key format: Use "\(userId)_\(baseURL)_\(channelId)" for all operations
Server last message ID: 
Compute from API response: max(messages.map { $0.id })
Store in channel_info.last_message_id column
Use for freshness checks: serverLastMessageId > cachedLastMessageId
Eviction methods: 
evictOldMessages(olderThan:) - Remove messages older than N days
evictChannelCache(channelId:) - Remove all messages for channel
enforcePerChannelLimit(channelId:maxMessages:) - Keep only N most recent
Tombstone management:
Add tombstones table with message_id, channel_id, user_id, base_url, deleted_at
expireTombstones(olderThan:) - Remove tombstones older than 7 days
enforceTombstoneLimit(channelId:maxCount:) - Limit to 1000 per channel
Merge methods:
getLastCachedMessageId(for:userId:baseURL:) - Get boundary for incremental updates
mergeMessages(cached:api:lastCachedId:deletedIds:) -> (merged, serverLastMessageId) - Strict de-dup with ULID sort, returns computed server last ID
Cache update methods:
updateCachedMessage(id:content:editedAt:userId:baseURL:) - Update edited message
deleteCachedMessage(id:userId:baseURL:) - Remove deleted message and add tombstone
Cache management:
clearAllCaches() - Called on sign-out, clears messages and tombstones
getCacheStats(userId:baseURL:) - Get size/count for monitoring
Deterministic freshness: 
isCacheStale(channelId:userId:baseURL:maxAge:serverLastMessageId:) - Check if cache needs refresh
Uses computed serverLastMessageId from API response, not server-provided value
Track last_updated and last_message_id in channel_info table
Benefits
Instant loading: Cached channels load immediately
Reduced API calls: Only fetch when cache is stale or missing
Better UX: No loading spinners for recently viewed channels
Offline support: Can view cached messages without network
Bandwidth savings: Fewer unnecessary API requests
Data safety: User isolation prevents cross-user data leaks