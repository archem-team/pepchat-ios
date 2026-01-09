Memory Optimization Plan
Problem Analysis
Memory grows to 1.25GB+ when opening multiple channels and scrolling messages. Root causes:

Message accumulation: ViewState.messages dictionary holds up to 7000 messages across all channels, but with 10+ channels open, this quickly fills memory
Image cache bloat: Kingfisher's ImageCache.default has no explicit memory limits, caching full-resolution images for avatars, attachments, emojis, and reactions
Per-channel limits not enforced: MessageableChannelConstants.maxMessagesInMemory = 100 but ViewState.maxChannelMessages = 800, creating inconsistency
No proactive cleanup: Memory cleanup functions are disabled (enforceMessageLimits() returns early)
Image references: Cells hold image references even after reuse, and images accumulate in memory cache
Multiple channel state: Opening channels quickly accumulates messages/users/images before cleanup runs
Size variance: Count-based limits don't account for large attachments (a few large images can spike RAM)
Server fetch mismatch: Client prunes to 50 messages but server fetches 100, causing immediate re-accumulation
User cache growth: ViewState.users dictionary grows unbounded per channel - message pruning doesn't cap user objects retained
Video/AVAsset caching: VideoPlayerView and AudioPlayerManager have static caches (thumbnails, durations) with no limits, and AVAsset objects may be retained by AVPlayer
Solution Overview
Implement multi-layered memory management:

Aggressive per-channel limits: Reduce to 50-100 messages per channel when not active
User cache limits: Cap user objects per channel and globally
Image cache limits: Configure Kingfisher with memory and disk limits + eviction policies + dynamic count limits
Video/AVAsset cache limits: Add limits to VideoPlayerView and AudioPlayerManager caches
Limited cache clearing: Only clear memory cache on memory warnings (not on channel exit) to prevent flicker
Proactive cleanup: Re-enable and improve memory cleanup with better thresholds (off-main-thread)
UX preservation: Preserve pinned messages, unread markers, reply context, and target messages
Size-based eviction: Track message sizes, not just counts
Memory pressure handling: Respond to system memory warnings with temporary limits that restore
Server-client sync: Match server fetch limits to client pruning limits
UI consistency: Handle message removal with proper diffing and loading placeholders
Feature flags: Enable staged rollout with ability to rollback
Background/foreground handling: Aggressive trimming on background, restore on foreground
Multitasking awareness: Detect split view/background fetch to prevent premature eviction
Memory instrumentation: Track per-channel memory costs for attribution
Test plan: Explicit validation steps for regression testing
Implementation Plan
1. Configure Kingfisher Image Cache Limits with Dynamic Eviction Policies
File: Revolt/Delegates/AppDelegate.swift (in application(_:didFinishLaunchingWithOptions:))Memory Cache Configuration:

Set ImageCache.default.memoryStorage.config.totalCostLimit = 50MB (memory cache)
Set ImageCache.default.memoryStorage.config.countLimit = 200 (increased from 100 for emoji/reaction-heavy views)
Set ImageCache.default.memoryStorage.config.cleanInterval = 300 (clean every 5 minutes)
Set ImageCache.default.memoryStorage.config.expiration = .seconds(3600) (expire after 1 hour)
Disk Cache Configuration:

Set ImageCache.default.diskStorage.config.sizeLimit = 200MB (disk cache)
Set ImageCache.default.diskStorage.config.expiration = .days(7) (expire after 7 days)
Age-based eviction: Kingfisher automatically evicts expired entries on access
Size-based eviction: Kingfisher automatically evicts oldest entries when size limit exceeded
Rationale: Prevents image cache from consuming unlimited memory. Increased count limit (200) handles emoji/reaction-heavy views without cache thrash. Age-based eviction prevents stale cache buildup. Size-based eviction prevents disk bloat. Configure once at app launch.

2. Limited Image Cache Clearing Strategy
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swiftProblem: Kingfisher doesn't support scoped cache clearing by channel without custom cache keys. Custom cache keys would require modifying all image loading code.Solution: DO NOT clear image cache on channel exit. Instead:

Only clear memory cache on memory warnings (see section 7)
Rely on Kingfisher's automatic eviction (age + size limits configured above)
Cancel in-flight downloads when leaving channel:
In viewDidDisappear: Cancel all Kingfisher download tasks for this channel's images
Use imageView.kf.cancelDownloadTask() for each image view in visible cells
Clear cell image references in prepareForReuse() (already implemented)
File: Revolt/ViewState.swift

DO NOT call ImageCache.default.clearMemoryCache() in clearChannelMessages()
DO NOT implement scoped cache clearing (not feasible without major refactoring)
Rationale: Prevents avatar/attachment flicker. Kingfisher's automatic eviction handles cache management. Canceling downloads prevents wasted bandwidth.

3. Reduce Per-Channel Message Limits with UX Preservation
Files:

Revolt/Pages/Channel/Messagable/Models/MessageableChannelConstants.swift
Revolt/ViewState.swift
Change MessageableChannelConstants.maxMessagesInMemory from 100 to 50 (active channel)
Change ViewState.maxChannelMessages from 800 to 100 (inactive channels)
Change ViewState.maxMessagesInMemory from 7000 to 2000 (total across all channels)
UX Preservation Requirements:File: Revolt/ViewState.swift - Modify clearChannelMessages():

Preserve target message: If currentTargetMessageId exists and belongs to this channel, keep it + 20 messages around it
Preserve unread markers: Keep messages referenced in `unreads[channelId]?.last_id` and `unreads[channelId]?.mentions`
Preserve reply context: For messages with replies array, keep parent messages (messages referenced in replies)
Preserve recent messages: Always keep last 50 messages (or more if target/unread/replies require it)
Rehydration strategy: When user navigates to preserved message (target/unread/reply), fetch surrounding context via API if needed
Window Size Behavior During Long Scroll Sessions:

Active channel window: Keep 50 messages in memory during active scrolling
When leaving channel: Keep 50 messages (same as active window) - no additional reduction
During scrolling: enforceMessageWindow() maintains 50-message window by removing oldest messages outside window
No janky reloads: Messages are removed from dictionary but IDs remain in channelMessages array - UI shows loading placeholders if user scrolls to removed area
Rationale: With 10 channels open at 100 messages each = 1000 messages minimum. Reducing to 50 active + 100 inactive per channel = ~500-1000 messages total, but preserving UX-critical messages. Window size (50) matches "keep when leaving" (50) to prevent conflicts.

4. Implement User Cache Limits Per Channel
File: Revolt/ViewState.swift

Add `channelUserIds: [String: Set<String>]` dictionary to track which users belong to which channels
Update when messages are added: Add message author to `channelUserIds[channelId]`
Add maxUsersPerChannel = 100 constant (max users to keep per channel)
Modify clearChannelMessages() to also clean up users:
Get users referenced by remaining messages in channel
Remove users from users dictionary that are no longer referenced by any channel
Keep users referenced by UX-critical messages (target/unread/reply context)
Add cleanupOrphanedUsers() helper:
Find users not referenced by any channel's messages
Remove from users dictionary (except current user and friends)
Reduce maxUsersInMemory from 2000 to 1000 (total across all channels)
Rationale: Prevents user cache from growing unbounded. With 10 channels at 100 users each = 1000 users max, matching new limit. Per-channel tracking ensures users are removed when channels are cleared.

5. Sync Server Fetch Limits with Client Pruning
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift

Modify loadInitialMessages() and loadMoreMessages():
Change default limit parameter from 100 to 50 to match client pruning
When loading older messages (scroll to top), use limit: 50 instead of 100
When loading newer messages (scroll to bottom), use limit: 50
File: Revolt/Pages/Channel/Messagable/MessageableChannel.swift

Modify loadMoreMessages():
Change limit: 100 to limit: 50 to match client pruning
File: Revolt/ViewState.swift

Modify preloadChannel():
Change messageLimit from 50 to match active channel limit (50)
Ensure preloading doesn't exceed client-side limits
Rationale: Prevents immediate re-accumulation after pruning. Server fetches 50, client keeps 50 = no waste.

6. Implement Size-Based Message Eviction
File: Revolt/ViewState.swift

Add `messageSizes: [String: Int]` dictionary to track approximate memory size per message
Improved size calculation (more accurate than rough estimates):
Content size: (message.content?.utf8.count ?? 0) (bytes, not character count)
Attachment size: Sum of attachment.size values from metadata (if available)
Fallback for attachments without size: attachment.size ?? 100KB per attachment
User object size: Estimate ~500 bytes per user referenced by message
Total: contentBytes + attachmentBytes + (userCount * 500)
Add totalMessageMemorySize: Int property to track cumulative size
Note: This is still an estimate - actual decoded image/video memory may be higher, but this provides a reasonable proxy
Modify cleanup to consider both count AND size:
If totalMessageMemorySize > 100MB OR messages.count > 1500, trigger cleanup
Evict largest messages first (from least-recently-accessed channels)
Still preserve UX-critical messages (target/unread/replies)
Rationale: A few large attachments can spike RAM even with low message counts. Improved size calculation uses actual bytes (UTF-8) and attachment metadata sizes. Still an estimate but more accurate than character count.

7. Re-enable Memory Cleanup with Consolidated Timer (Off-Main-Thread)
File: Revolt/ViewState.swift

Add single shared cleanup timer: private var memoryCleanupTimer: Timer?
Timer lifecycle management:
Timer runs every 60 seconds (not 30s to reduce CPU/battery impact)
Timer is cancelled when app goes to background (applicationDidEnterBackground)
Timer is restarted when app becomes active (applicationWillEnterForeground)
Teardown on logout/reset: In signOut() method, cancel and nil the timer: memoryCleanupTimer?.invalidate(); memoryCleanupTimer = nil
Guard against multiple timers: Check memoryCleanupTimer == nil before creating new timer, or always invalidate existing timer first
Deinit cleanup: In deinit, invalidate timer to prevent leaks
Main-thread protection: All cleanup work must be off-main-thread:
Use Task.detached(priority: .background) for cleanup operations
Only UI updates (if any) happen on MainActor
Message/user dictionary removals happen off-main-thread
Use actor isolation or serial queue for thread-safe dictionary access
In cleanup:
Check messages.count > 1500 (75% of 2000 limit) OR totalMessageMemorySize > 75MB
Remove oldest messages from least-recently-accessed channels first
Preserve UX-critical messages
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift

Re-enable enforceMessageLimits() but make it lightweight (no timer)
Call enforceMessageWindow() during scrolling (every 30 messages loaded, not every 5-10 seconds)
Main-thread protection: enforceMessageWindow() must be off-main-thread:
Use Task.detached for message removal work
Only tableView.reloadData() happens on main thread
Batch UI updates to prevent hitches
Trigger cleanup when localMessages.count > 75 (before hitting 100 limit)
DO NOT add separate 5-10 second timer (use ViewState's shared timer)
Rationale: Single shared timer prevents timer leaks and reduces CPU/battery impact. Off-main-thread cleanup prevents UI hitches during scrolling. Cleanup triggered by thresholds, not fixed intervals.

8. Add Memory Pressure Handling with Restore Path
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift

In handleMemoryWarning(): 
Clear memory cache: ImageCache.default.clearMemoryCache() (only on memory warnings)
Reduce current channel messages to 30 (from 50), preserving UX-critical messages
Clear all inactive channel messages (keep only 20 per channel), preserving UX-critical messages
Use autoreleasepool to release temporary objects (not "garbage collection" - Swift uses ARC)
Restore path: After 30 seconds of no memory warnings, restore normal limits (50 active, 100 inactive)
File: Revolt/ViewState.swift

Add didReceiveMemoryWarning() handler:
Set temporaryMemoryLimit = true flag
Reduce effective maxMessagesInMemory to 1000 temporarily
Clear memory cache: ImageCache.default.clearMemoryCache() (only on memory warnings)
Remove messages from channels not accessed in last 5 minutes
Restore path: After 30 seconds, set temporaryMemoryLimit = false and restore normal limits
Add memoryWarningRestoreTimer: Timer? to track restore timing
Rationale: Responds to system memory pressure before crash, but restores normal UX after pressure passes. Only clears image cache on memory warnings, not on channel exit.

9. Optimize Message Window Enforcement with UI Consistency
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift

Modify enforceMessageWindow():
Reduce window size from 100 to 50 for active channel
Call during scrolling (every 30 messages loaded)
UI Consistency: When removing messages:
Don't remove message objects immediately - keep IDs in channelMessages array
Remove message objects from ViewState.messages dictionary only (not IDs)
Update data source with new message list before removing objects
Use tableView.reloadData() or batch updates to ensure UI consistency
Show loading placeholders if messages are removed but user scrolls to that area
Preserve UX-critical messages: Don't remove target/unread/reply messages even if outside window
Rationale: Keeps active channel memory footprint small while preserving UX. Removing objects (not IDs) prevents UI diffing issues. Loading placeholders handle re-fetch.

10. Add Channel Access Tracking with Persistence and Multitasking Awareness
File: Revolt/ViewState.swift

Add `channelLastAccessTime: [String: Date]` dictionary
Persistence: Save to UserDefaults with key "channelLastAccessTimes":
Serialize as [String: TimeInterval] (store timestamps, not Date objects)
Load on init(): `channelLastAccessTime = UserDefaults.standard.dictionary(forKey: "channelLastAccessTimes") as? [String: TimeInterval] ?? [:]`
Save on access update: UserDefaults.standard.set(channelLastAccessTime.mapValues { $0.timeIntervalSince1970 }, forKey: "channelLastAccessTimes")
Update access time when channel is viewed (in selectChannel and selectDm)
Multitasking awareness:
Add isAppInSplitView: Bool flag (check UIApplication.shared.windows.count > 1 or use UIScene API)
Add isAppInBackgroundFetch: Bool flag (check UIApplication.shared.applicationState == .background)
Active channel definition: Channel is "active" if:
It's the current channel (currentChannel == .channel(channelId))
OR app is in split view and channel is visible in any window
OR app is performing background fetch for this channel
In cleanup: Only evict channels that are truly inactive (not current, not in split view, not being fetched)
In cleanup: Remove messages from channels not accessed in last 2 minutes (only if truly inactive)
Keep only 20 messages for channels not accessed in 5+ minutes (preserving UX-critical messages)
App relaunch handling: On first launch after update, treat all channels as "accessed now" to prevent aggressive cleanup
Rationale: Prioritizes memory for actively-used channels. Persistence prevents treating all channels as stale on app relaunch. Multitasking awareness prevents premature eviction during split view or background fetch.

11. Add Background/Foreground Handling
File: Revolt/Delegates/AppDelegate.swift

In applicationDidEnterBackground():
Aggressive trimming: Reduce inactive channel messages to 10 (from 20)
Conditional cache clearing: Only clear memory cache if RAM usage > 500MB threshold:
Check ViewState.shared.checkMemoryUsage().usedMB > 500
If above threshold: ImageCache.default.clearMemoryCache() to free RAM
If below threshold: Keep cache to prevent re-decoding/re-downloads on foreground
Cancel cleanup timer: Stop periodic cleanup timer
Save state: Persist channel access times and current limits
In applicationWillEnterForeground():
Restore limits: Restore normal message limits (50 active, 100 inactive)
Restart cleanup timer: Resume periodic cleanup
Load state: Restore channel access times from UserDefaults
File: Revolt/ViewState.swift

Add isAppInBackground: Bool flag
Modify cleanup to be more aggressive when isAppInBackground == true
Update flag in applicationDidEnterBackground / applicationWillEnterForeground handlers
Rationale: Conditional cache clearing prevents unnecessary re-decoding when memory is not critical. Aggressive trimming on background frees RAM for other apps. Restore on foreground ensures good UX when user returns.

12. Add Feature Flags for Staged Rollout
File: Revolt/ViewState.swift

Explicit default registration: Register feature flag defaults in init() or application(_:didFinishLaunchingWithOptions:):
      // Register defaults if not already set
      if UserDefaults.standard.object(forKey: "enableAggressiveMemoryManagement") == nil {
          UserDefaults.standard.set(true, forKey: "enableAggressiveMemoryManagement") // Default: true after rollout
      }
      if UserDefaults.standard.object(forKey: "aggressiveMessageLimit") == nil {
          UserDefaults.standard.set(50, forKey: "aggressiveMessageLimit") // Default: 50
      }
      if UserDefaults.standard.object(forKey: "aggressiveUserLimit") == nil {
          UserDefaults.standard.set(1000, forKey: "aggressiveUserLimit") // Default: 1000
      }
Add feature flag constants with fallback:
      private var enableAggressiveMemoryManagement: Bool {
          UserDefaults.standard.object(forKey: "enableAggressiveMemoryManagement") as? Bool ?? true // Fallback to true
      }
      private var aggressiveMessageLimit: Int {
          UserDefaults.standard.object(forKey: "aggressiveMessageLimit") as? Int ?? 50 // Fallback to 50
      }
      private var aggressiveUserLimit: Int {
          UserDefaults.standard.object(forKey: "aggressiveUserLimit") as? Int ?? 1000 // Fallback to 1000
      }
Wrap all aggressive limits in feature flag checks:
If !enableAggressiveMemoryManagement, use old limits (100 messages, 2000 users, 7000 total messages)
If enabled, use new limits (50 messages, 1000 users, 2000 total messages)
Add remote config support (optional): Fetch flags from server on app launch
Rollback strategy: Set enableAggressiveMemoryManagement = false in UserDefaults to instantly rollback
File: Revolt/Pages/Channel/Messagable/Models/MessageableChannelConstants.swift

Make maxMessagesInMemory configurable via feature flag with fallback:
      static var maxMessagesInMemory: Int {
          UserDefaults.standard.object(forKey: "enableAggressiveMemoryManagement") as? Bool ?? true ? 50 : 100
      }
Rationale: Enables staged rollout and instant rollback if UX regressions occur. Can A/B test different limit values.

13. Add Per-Channel Memory Cost Instrumentation
File: Revolt/ViewState.swift

Add `channelMemoryCosts: [String: ChannelMemoryCost]` dictionary:
          struct ChannelMemoryCost {
              var messageCount: Int
              var messageSizeBytes: Int
              var userCount: Int
              var imageCacheSizeBytes: Int // Estimated - see note below
              var videoCacheSizeBytes: Int // Estimated (thumbnails, durations, AVAssets)
              var totalBytes: Int { messageSizeBytes + videoCacheSizeBytes } // Exclude imageCacheSizeBytes - see note
          }
Image cache attribution limitation: 
Kingfisher uses a global cache shared across all channels
Per-channel image cache attribution is not feasible without custom cache keys
Solution: Track imageCacheSizeBytes as 0 per channel, but log total image cache size separately
In logChannelMemoryCosts(): Log total ImageCache.default.memoryStorage.config.totalCostLimit usage separately
This provides accurate total memory picture without misleading per-channel attribution
Update costs when messages/users are added/removed per channel
Add logging method: logChannelMemoryCosts():
Log per-channel breakdown: messages, users, video cache (image cache logged separately as total)
Log total memory: messages + users + image cache (total) + video cache
Call during cleanup to track effectiveness
Add method: `getChannelMemoryAttribution() -> [String: ChannelMemoryCost]`:
Returns current memory costs per channel (without image cache per-channel)
Used for monitoring and debugging
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift

Log channel memory cost when leaving channel (viewDidDisappear)
Log before/after cleanup to measure effectiveness
Rationale: Enables attribution of memory usage per channel. Image cache is tracked as total (not per-channel) since it's global. Helps identify which channels consume most memory and whether limits are effective.

14. Handle Video and AVAsset Caches
File: Revolt/Components/AudioPlayer/VideoPlayerView.swift

Add limits to static caches:
thumbnailCache: Max 50 entries (already has comment "keep only last 50")
durationCache: Max 100 entries
Implement LRU eviction: Remove oldest entries when limit exceeded
Clear caches on memory warnings: VideoPlayerView.thumbnailCache.removeAll() and VideoPlayerView.durationCache.removeAll()
AVAsset cleanup: 
Release videoAsset when view is removed: Set videoAsset = nil in deinit or prepareForReuse
Cancel any pending AVAsset loading operations
Use weak references for AVAsset completion handlers
File: Revolt/Components/AudioPlayer/AudioPlayerManager.swift

Add limits to durationCache:
Max 200 entries (larger than VideoPlayerView since audio is more common)
Implement LRU eviction: Remove oldest entries when limit exceeded
Clear cache on memory warnings: durationCache.removeAll()
AVPlayer cleanup:
Release player and playerItem when not playing: Set to nil after playback ends
Cancel time observers when not needed
Use player.replaceCurrentItem(with: nil) to release current item
File: Revolt/Pages/Channel/Messagable/Views/MessageCell.swift

In prepareForReuse(): Release any AVAsset/AVPlayer references
Cancel video thumbnail generation if in progress
Clear video player view references
Rationale: Video thumbnails, durations, and AVAsset objects can consume significant memory. Limits prevent unbounded growth. AVAsset cleanup prevents retention by AVPlayer.

15. Add Monitoring with Thresholds and Guardrails
File: Revolt/ViewState.swift

Add memory monitoring helper: checkMemoryUsage() -> (usedMB: Double, warning: Bool, critical: Bool)
Memory measurement implementation:
Use task_info(mach_task_self(), MACH_TASK_BASIC_INFO, ...) with mach_task_basic_info struct (already implemented in codebase)
Calculate: Double(info.resident_size) / 1024.0 / 1024.0 (convert to MB)
Run off-main-thread: Execute checkMemoryUsage() in Task.detached(priority: .background) to avoid main-thread cost
Cache result for 5 seconds to avoid frequent system calls
Thresholds:
Warning: Memory > 600MB OR message count > 1800 OR message size > 90MB OR user count > 900
Critical: Memory > 800MB OR message count > 1900 OR message size > 95MB OR user count > 950
Guardrails (when critical threshold hit):
Disable image previews: Set flag disableImagePreviews = true
Reduce fetch limits: Set reducedFetchLimit = true flag, temporarily reduce server fetch limit from 50 to 25
Fetch limit enforcement: 
Add getEffectiveFetchLimit() -> Int helper that checks reducedFetchLimit flag
Update all fetch paths to use getEffectiveFetchLimit() instead of hardcoded 50:
loadInitialMessages(), loadMoreMessages(), preloadChannel()
Restore fetch limit: After 60 seconds of normal memory, set reducedFetchLimit = false and restore to 50
Persistence: Store reducedFetchLimit in UserDefaults to survive app restart (restore on next session)
Aggressive cleanup: Reduce inactive channel messages to 10 (from 20)
Log alert: Log critical memory state for debugging
Include per-channel attribution: Log getChannelMemoryAttribution() to identify problem channels
Restore guardrails: After 60 seconds of normal memory, restore disableImagePreviews = false and normal limits
File: Revolt/Pages/Channel/Messagable/Views/MessageCell.swift

Check viewState.disableImagePreviews flag before loading images
If disabled, show placeholder only (no image loading)
Rationale: Prevents memory from growing beyond recoverable levels. Guardrails provide "stop-the-bleed" protection. Per-channel attribution helps identify root causes.

16. Add Test Plan for Regression Validation
File: Create RevoltTests/MemoryOptimizationTests.swift (new test file)Test Cases:

Scrollback Stability Test:
Load channel with 200+ messages
Scroll to top (load older messages)
Verify messages don't disappear unexpectedly
Verify loading placeholders appear for pruned messages
Verify messages re-fetch correctly when scrolled to
Reply Context Preservation Test:
Load channel with reply threads
Navigate to channel with aggressive limits enabled
Verify parent messages of replies are preserved
Verify reply context is maintained after cleanup
Verify reply navigation still works
Jump-to-Unread Test:
Mark channel as unread
Navigate away and back
Verify unread marker message is preserved
Verify jump-to-unread still works
Verify unread count is accurate
Image Flicker Test:
Load channel with images/avatars
Switch between multiple channels rapidly
Verify no image flicker or re-downloads
Verify images remain cached across channel switches
Verify only memory cache is cleared on memory warnings
Memory Limit Enforcement Test:
Open 10+ channels simultaneously
Verify total messages stay under 2000 limit
Verify per-channel messages respect limits (50 active, 100 inactive)
Verify user count stays under 1000 limit
Verify memory usage stays under 600MB
Background/Foreground Test:
Load channels with messages
Background app
Verify aggressive trimming occurs
Foreground app
Verify limits are restored
Verify messages reload correctly
Multitasking Test:
Open channel in split view
Verify channel is treated as "active" even when not current
Verify messages are not evicted prematurely
Verify background fetch doesn't trigger eviction
Video Cache Test:
Load channels with video attachments
Verify video thumbnail cache respects limits (50 entries)
Verify duration cache respects limits (100/200 entries)
Verify AVAsset cleanup occurs
Verify memory doesn't grow unbounded with videos
Manual Testing Checklist:

[ ] Open 10+ channels, scroll messages, verify no crashes
[ ] Jump to unread marker, verify it's preserved
[ ] Navigate to reply, verify parent context is preserved
[ ] Switch channels rapidly, verify no image flicker
[ ] Background app, verify memory is freed
[ ] Foreground app, verify UX is restored
[ ] Use split view, verify channels aren't evicted prematurely
[ ] Load videos, verify cache limits are respected
Rationale: Explicit test plan ensures regressions are caught before release. Covers all critical UX flows that could be affected by aggressive memory management.

Implementation Todos
Phase 1: Foundation (Immediate Impact)
configure-kingfisher-cache: Configure Kingfisher image cache limits (50MB memory, 200MB disk, 200 count limit, expiration policies) in AppDelegate
add-feature-flags: Add feature flags with explicit default registration and fallback values to prevent false defaults
reduce-message-limits: Reduce message limits: 50 active channel, 100 inactive, 2000 total across all channels (depends on: add-feature-flags)
sync-server-fetch-limits: Change all server fetch limits from 100 to 50 to match client pruning (depends on: reduce-message-limits)
add-video-cache-limits: Add limits to VideoPlayerView (50 thumbnails, 100 durations) and AudioPlayerManager (200 durations) caches
Phase 2: Cleanup & Eviction (Prevent Accumulation)
implement-size-based-eviction: Implement improved size-based eviction using UTF-8 bytes and attachment metadata sizes (depends on: reduce-message-limits)
re-enable-cleanup-timer: Re-enable memory cleanup timer (60s interval, off-main-thread) with proper lifecycle management (cancel on background/logout/deinit) (depends on: implement-size-based-eviction)
implement-user-cache-limits: Add per-channel user tracking and cleanup, reduce maxUsersInMemory to 1000 (depends on: reduce-message-limits)
add-channel-access-tracking: Add channel access tracking with persistence and multitasking awareness (split view, background fetch)
add-background-foreground-handling: Add conditional cache clearing (>500MB threshold) and aggressive trimming on background, restore on foreground (depends on: configure-kingfisher-cache)
Phase 3: Monitoring & Testing (Optimization)
add-memory-monitoring: Implement checkMemoryUsage() using task_info (off-main-thread) with thresholds, guardrails, and getEffectiveFetchLimit() helper (depends on: re-enable-cleanup-timer)
add-memory-instrumentation: Add per-channel memory cost tracking (messages, users, video cache) with total image cache logged separately (depends on: implement-size-based-eviction)
update-message-window-enforcement: Update enforceMessageWindow() to use off-main-thread cleanup with UI consistency (remove objects, keep IDs) (depends on: re-enable-cleanup-timer)
add-memory-pressure-handling: Add memory warning handlers with cache clearing and temporary limits that restore after 30s (depends on: add-memory-monitoring)
create-test-plan: Create comprehensive test plan with test cases for scrollback stability, reply context, jump-to-unread, image flicker, etc.
Implementation Order
Phase 1 (Immediate impact): Configure image cache limits + eviction policies + reduce message limits + sync server fetch limits + feature flags + video cache limits
Phase 2 (Prevent accumulation): Re-enable cleanup with consolidated timer (off-main-thread) + size-based eviction + UX preservation + access tracking persistence + user cache limits + multitasking awareness
Phase 3 (Optimization): Memory pressure handling with restore + UI consistency + background/foreground handling + monitoring with guardrails + instrumentation + test plan
Expected Results
Memory usage should stay under 400-600MB with 10+ channels open
Image cache limited to 50MB memory + 200MB disk with automatic eviction (200 image count limit)
Video caches limited: 50 thumbnails, 100/200 durations, AVAsset cleanup
Active channel: 50 messages max (preserving UX-critical messages)
Inactive channels: 20-100 messages max (preserving UX-critical messages)
Total messages: 2000 max across all channels (or 100MB total size)
Total users: 1000 max across all channels
Server fetch limits match client pruning (50 messages)
System memory warnings trigger immediate cleanup with restore after 30s
No avatar/attachment flicker when switching channels (no cache clearing on exit)
Guardrails prevent memory from exceeding 800MB
Feature flags enable staged rollout and rollback
Background trimming frees RAM, foreground restore ensures good UX
No UI hitches during scrolling (cleanup off-main-thread)
Multitasking-aware eviction prevents premature cleanup
Monitoring
Add logging to track:

Memory usage before/after cleanup
Message counts per channel
Message memory size (total and per-channel)
User counts per channel (new)
Image cache size (memory and disk)
Video cache sizes (thumbnails, durations, AVAssets) (new)
Cleanup frequency and effectiveness
UX-critical message preservation (target/unread/reply counts)
Per-channel memory attribution (messages vs users vs images vs videos) (new)
Threshold alerts: Log when warning/critical thresholds are hit
Guardrail activations: Log when guardrails are activated/deactivated
Feature flag state: Log current feature flag values
Main-thread blocking: Log if cleanup takes >16ms (one frame)
Multitasking state: Log split view and background fetch states
Open Questions Resolved
Which user flows must preserve deep scrollback?: Jump-to-message (currentTargetMessageId), unread markers (unreads), reply context (replies array), search results (preserve search context messages)
Re-fetch behavior after pruning?: When user navigates to preserved message, fetch surrounding context via API if needed. Show loading placeholders during fetch.
Is Kingfisher the only cache?: No, VideoPlayerView and AudioPlayerManager have caches that need limits.
Disk cache eviction?: Age-based (7 days) + size-based (200MB limit) via Kingfisher's built-in eviction
Scoped cache clearing?: Not feasible without custom cache keys. Use automatic eviction + only clear on memory warnings.
UI consistency?: Remove message objects (not IDs), update data source first, use proper table view updates
Access tracking persistence?: Store in UserDefaults as [String: TimeInterval] to survive app relaunch
User cache growth?: Added per-channel user tracking and cleanup. Cap at 1000 users total.
Feature flag strategy?: Added feature flags for staged rollout and instant rollback.
Kingfisher count limit?: Increased to 200 to handle emoji/reaction-heavy views.
Window size conflict?: Clarified - window size (50) matches "keep when leaving" (50). No conflict.
Per-channel memory attribution?: Added instrumentation to track messages vs users vs images vs videos per channel.
Background/foreground handling?: Added aggressive trimming on background, restore on foreground.