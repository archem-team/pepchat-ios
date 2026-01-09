Memory Optimization Implementation Todos
Phase 1: Foundation (Immediate Impact)
Configure Kingfisher Image Cache Limits
Set memory cache: 50MB, count: 200, expiration: 1 hour
Set disk cache: 200MB, expiration: 7 days
File: Revolt/Delegates/AppDelegate.swift
Add Feature Flags with Explicit Defaults
Register defaults in init() or application(_:didFinishLaunchingWithOptions:)
Add fallback values in feature flag properties
File: Revolt/ViewState.swift
Reduce Message Limits
Change MessageableChannelConstants.maxMessagesInMemory to 50
Change ViewState.maxChannelMessages to 100
Change ViewState.maxMessagesInMemory to 2000
Files: Revolt/Pages/Channel/Messagable/Models/MessageableChannelConstants.swift, Revolt/ViewState.swift
Sync Server Fetch Limits
Change all limit parameters from 100 to 50
Files: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift, Revolt/Pages/Channel/Messagable/MessageableChannel.swift, Revolt/ViewState.swift
Add Video Cache Limits
VideoPlayerView: thumbnailCache (50), durationCache (100)
AudioPlayerManager: durationCache (200)
Files: Revolt/Components/AudioPlayer/VideoPlayerView.swift, Revolt/Components/AudioPlayer/AudioPlayerManager.swift
Phase 2: Cleanup & Eviction (Prevent Accumulation)
Implement Improved Size-Based Eviction
Use UTF-8 byte count for content (not character count)
Use attachment.size from metadata
Track totalMessageMemorySize
File: Revolt/ViewState.swift
Re-enable Memory Cleanup Timer
Add timer with 60s interval
Off-main-thread cleanup
Timer lifecycle: cancel on background/logout/deinit
Guard against multiple timers
File: Revolt/ViewState.swift
Implement User Cache Limits
Add channelUserIds tracking
Add cleanupOrphanedUsers()
Reduce maxUsersInMemory to 1000
File: Revolt/ViewState.swift
Add Channel Access Tracking
Persist to UserDefaults
Multitasking awareness (split view, background fetch)
File: Revolt/ViewState.swift
Add Background/Foreground Handling
Conditional cache clearing (>500MB threshold)
Aggressive trimming on background
Restore on foreground
File: Revolt/Delegates/AppDelegate.swift, Revolt/ViewState.swift
Phase 3: Monitoring & Testing (Optimization)
Add Memory Monitoring
Implement checkMemoryUsage() using task_info (off-main-thread)
Add thresholds and guardrails
Implement getEffectiveFetchLimit() for guardrail enforcement
File: Revolt/ViewState.swift
Add Per-Channel Memory Instrumentation
Track message/user/video cache per channel
Log total image cache separately (not per-channel)
File: Revolt/ViewState.swift
Update Message Window Enforcement
Off-main-thread cleanup
UI consistency (remove objects, keep IDs)
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift
Add Memory Pressure Handling
Clear cache only on memory warnings
Temporary limits with restore path
File: Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift, Revolt/ViewState.swift
Create Test Plan
Add test cases for regression validation