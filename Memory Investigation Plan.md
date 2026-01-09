# Memory Investigation & Optimization Plan

## Problem Statement
Memory grows to 1.8GB+ when:
- Opening multiple channels
- Scrolling through large channels (even without loading new data)
- App startup

**Hypothesis**: Images, videos, and media are being downloaded at full resolution during message load, rather than using thumbnails/previews with lazy loading.

---

## Investigation Findings

### 1. Image Loading Issues

#### Problem: Full-Resolution Images Loaded Immediately
**Location**: `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:1724-1753`

```swift
imageView.kf.setImage(
    with: url,
    placeholder: UIImage(systemName: "photo"),
    options: [
        .transition(.fade(0.3)),
        .cacheOriginalImage,  // ⚠️ PROBLEM: Caches full-resolution image
        .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))
    ]
)
```

**Issues**:
- No `downsamplingImage` option - loads full resolution images
- No `targetSize` specified - downloads original image size
- `.cacheOriginalImage` caches full-resolution images in memory
- Images load immediately when cell is configured, even if off-screen

**Impact**: A single 4K image (8-12MB) can consume significant memory. With 50-100 messages visible, this multiplies quickly.

---

#### Problem: LazyImage Component Loads Full Images
**Location**: `Revolt/Components/LazyImage.swift:68`

```swift
KFAnimatedImage(source: _source)
    .placeholder { Color.bgGray11 }
    .aspectRatio(contentMode: contentMode)
    .frame(width: width, height: height)
```

**Issues**:
- Uses `KFAnimatedImage` which loads full-resolution images
- No downsampling or thumbnail strategy
- Used in `MessageAttachment.swift` for all image attachments
- No size constraints passed to Kingfisher

**Impact**: All images in SwiftUI message views load at full resolution.

---

#### Problem: Avatar Images Load at Full Resolution
**Location**: Multiple files
- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:3841-3848`
- `Revolt/Pages/Channel/Messagable/Views/RepliesContainerView.swift:220-227`
- `Revolt/Components/Sheets/UserSheetViewController.swift:149-154`

```swift
avatarImageView.kf.setImage(
    with: avatarInfo.url,
    placeholder: UIImage(systemName: "person.circle.fill"),
    options: [
        .transition(.fade(0.2)),
        .cacheOriginalImage  // ⚠️ PROBLEM: Full-resolution avatars
    ]
)
```

**Issues**:
- Avatars are typically 128x128 or 256x256, but loaded at full resolution
- No targetSize specified (should be ~40x40 or 80x80 for display)
- Every message cell loads avatar immediately

**Impact**: With 100 visible messages, 100 full-resolution avatars are loaded.

---

#### Problem: Emoji Reactions Load Full Images
**Location**: `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:3074-3080, 3189-3195`

```swift
emojiImageView.kf.setImage(
    with: url,
    options: [
        .transition(.fade(0.2)),
        .cacheOriginalImage  // ⚠️ PROBLEM: Full-resolution emojis
    ]
)
```

**Issues**:
- Custom emojis loaded at full resolution
- No size constraints (emojis should be ~20x20 or 32x32)
- Multiple emojis per message multiply the problem

**Impact**: Each reaction emoji loads full-resolution image unnecessarily.

---

### 2. Video Loading Issues

#### Problem: Videos Create AVPlayer Instances Immediately
**Location**: `Revolt/Components/MessageRenderer/MessageAttachment.swift:61, 173`

```swift
VideoPlayer(player: AVPlayer(url: URL(string: viewState.formatUrl(with: attachment))!))
```

**Issues**:
- `AVPlayer` is created immediately when message is rendered
- AVPlayer may preload video metadata and even video data
- No thumbnail/preview strategy - full video URL is passed
- Used in both regular view and fullscreen view

**Impact**: Even if video isn't played, AVPlayer instances consume memory and may download video data.

---

#### Problem: Video Thumbnails Generated from Full Video
**Location**: `Revolt/Components/AudioPlayer/VideoPlayerView.swift:303-422`

```swift
private func generateThumbnail(from urlString: String) {
    // Creates AVAsset from full video URL
    // Generates thumbnail by loading video data
}
```

**Issues**:
- Thumbnail generation requires loading video file/stream
- No server-side thumbnail API used
- Full video data may be downloaded just for thumbnail
- Thumbnails cached but full video may remain in memory

**Impact**: Each video attachment triggers video download for thumbnail generation.

---

#### Problem: Video Download on Play
**Location**: `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:3524-3565`

```swift
let videoData = try await downloadVideo(from: urlString)
// Downloads entire video to temp file
```

**Issues**:
- Downloads entire video file before playing
- No streaming strategy
- Temp files may accumulate
- Large video files (100MB+) consume significant memory

**Impact**: Playing a single video can consume 100MB+ memory.

---

### 3. Network Request Issues

#### Problem: No Lazy Loading for Off-Screen Content
**Location**: `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

**Issues**:
- All message cells are configured when table view loads
- Images load immediately even if cell is off-screen
- No visibility-based loading strategy
- No prefetching limits

**Impact**: Scrolling through 1000 messages loads images for all visible + prefetched cells.

---

#### Problem: Multiple Image Loads Per Message
**Location**: `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:1655-1773`

**Issues**:
- Each message can have multiple image attachments
- All images load simultaneously
- No priority system (first image vs. others)
- No cancellation when scrolling away

**Impact**: A message with 5 images loads all 5 at full resolution immediately.

---

### 4. Kingfisher Cache Configuration

#### Current Configuration
**Location**: `Revolt/Delegates/AppDelegate.swift:69-92`

```swift
ImageCache.default.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024  // 50MB
ImageCache.default.diskStorage.config.sizeLimit = 200 * 1024 * 1024  // 200MB
ImageCache.default.memoryStorage.config.countLimit = 200
```

**Issues**:
- Cost limit is in bytes, but `.cacheOriginalImage` stores full-resolution images
- A single 4K image can be 8-12MB, quickly filling 50MB cache
- No per-image size limits
- No expiration strategy for large images

**Impact**: Cache fills quickly with full-resolution images, causing eviction but images may reload.

---

### 5. Message Cell Reuse Issues

#### Good: prepareForReuse Cleans Up
**Location**: `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:125-249`

**Positive**:
- Cancels Kingfisher tasks
- Clears image views
- Removes subviews

**Remaining Issues**:
- Images may have already loaded before cell is reused
- No size-based cleanup (large images remain in cache)
- Video players may retain references

---

## Root Causes Summary

1. **No Thumbnail Strategy**: All images load at full resolution
2. **No Downsampling**: Kingfisher loads original images without resizing
3. **Immediate Loading**: Images load when cells are configured, not when visible
4. **Video Preloading**: AVPlayer instances may preload video data
5. **No Size Limits**: No constraints on individual image sizes
6. **Cache Strategy**: Full-resolution images fill cache quickly
7. **Multiple Attachments**: All attachments load simultaneously
8. **No Priority System**: No distinction between critical vs. non-critical images

---

## Optimization Plan

### Phase 1: Image Thumbnail Strategy (High Impact)

#### 1.1 Implement Image Downsampling
**Files**: 
- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`
- `Revolt/Components/LazyImage.swift`

**Changes**:
- Add `DownsamplingImageProcessor` to all image loads
- Set appropriate `targetSize` based on display size:
  - Message images: 400x400 max (or based on container width)
  - Avatars: 80x80 (2x for retina = 160x160)
  - Emojis: 32x32 (2x for retina = 64x64)
  - Thumbnails: 200x200 max

**Example**:
```swift
let processor = DownsamplingImageProcessor(size: CGSize(width: 400, height: 400))
imageView.kf.setImage(
    with: url,
    options: [
        .processor(processor),
        .scaleFactor(UIScreen.main.scale),
        .cacheOriginalImage  // Keep for fullscreen view
    ]
)
```

**Expected Impact**: 80-90% reduction in image memory usage.

---

#### 1.2 Implement Lazy Image Loading
**Files**: 
- `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

**Changes**:
- Only load images for visible cells
- Cancel image loads when cells scroll off-screen
- Implement prefetching for nearby cells only (5-10 cells ahead/behind)

**Implementation**:
- Use `tableView(_:willDisplay:forRowAt:)` to start loading
- Use `tableView(_:didEndDisplaying:forRowAt:)` to cancel loading
- Track visible cells and cancel off-screen loads

**Expected Impact**: 50-70% reduction in simultaneous image loads.

---

#### 1.3 Add Thumbnail URLs (If API Supports)
**Files**: 
- `Revolt/Api/Http.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`

**Changes**:
- Check if API supports thumbnail URLs (e.g., `?thumbnail=true` or `?size=thumb`)
- Use thumbnail URLs for initial load
- Load full image only when user taps to view

**Expected Impact**: 90%+ reduction in initial image memory.

---

### Phase 2: Video Optimization (High Impact)

#### 2.1 Implement Video Thumbnail Strategy
**Files**: 
- `Revolt/Components/AudioPlayer/VideoPlayerView.swift`
- `Revolt/Components/MessageRenderer/MessageAttachment.swift`

**Changes**:
- Don't create AVPlayer until user taps play
- Use server-side thumbnails if available
- Generate thumbnails only when needed (lazy)
- Show static thumbnail image instead of VideoPlayer component

**Implementation**:
- Replace `VideoPlayer` with `LazyImage` showing thumbnail
- Create AVPlayer only in fullscreen view or when play button tapped
- Cancel thumbnail generation if cell scrolls off-screen

**Expected Impact**: 70-80% reduction in video-related memory.

---

#### 2.2 Implement Video Streaming
**Files**: 
- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:3524-3565`

**Changes**:
- Use AVPlayer with streaming instead of downloading entire file
- Remove `downloadVideo` function
- Play directly from URL with AVPlayer

**Expected Impact**: Eliminates 100MB+ spikes when playing videos.

---

### Phase 3: Cache Optimization

#### 3.1 Improve Kingfisher Cache Strategy
**Files**: 
- `Revolt/Delegates/AppDelegate.swift`

**Changes**:
- Reduce memory cache to 30MB (from 50MB)
- Implement size-based eviction for large images
- Add expiration time for cached images (1 hour)
- Separate cache for thumbnails vs. full images

**Expected Impact**: More predictable memory usage.

---

#### 3.2 Implement Image Size Limits
**Files**: 
- All image loading locations

**Changes**:
- Reject images larger than 5MB from memory cache
- Store large images only on disk
- Add size logging to identify problem images

**Expected Impact**: Prevents single large images from consuming all cache.

---

### Phase 4: Visibility-Based Loading (High Impact)

#### 4.1 Implement Cell Visibility Tracking
**Files**: 
- `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

**Changes**:
- Track which cells are currently visible
- Only load images for visible cells
- Cancel loads when cells scroll off-screen
- Prefetch for 5-10 cells ahead/behind only

**Implementation**:
```swift
func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    // Start loading images for this cell
}

func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    // Cancel image loads for this cell
}
```

**Expected Impact**: 60-80% reduction in simultaneous image loads.

---

## Implementation Priority

### Critical (Do First)
1. ✅ Image downsampling for message attachments
2. ✅ Image downsampling for avatars
3. ✅ Video thumbnail strategy (no AVPlayer until play)
4. ✅ Visibility-based image loading

### High Priority
5. ✅ Image downsampling for emojis
6. ✅ Video streaming instead of download
7. ✅ Cache size limits and eviction
8. ✅ **Image decoder cost calculation**
9. ✅ **Instrumentation and profiling**

---

## Expected Results

### Before Optimization
- Memory: 1.8GB+ with 10 channels, 1000 messages
- Image cache: 50MB+ with full-resolution images
- Video memory: 100MB+ per video played
- Startup memory: 500MB+

### After Optimization
- Memory: 300-500MB with 10 channels, 1000 messages
- Image cache: 20-30MB with downsampled images
- Video memory: 10-20MB (thumbnails only until play)
- Startup memory: 150-200MB

### Reduction
- **70-80% memory reduction** overall
- **90%+ reduction** in image memory
- **80%+ reduction** in video memory

---

## Questions & Considerations

### API Questions
1. Does the API support thumbnail URLs for images? (e.g., `?size=thumb` or `?thumbnail=true`) : Not sure
2. Does the API provide video thumbnail URLs? : Not sure
3. What are the typical image sizes in messages? (Need to measure)
4. What are the typical video sizes? (Need to measure)

### Implementation Questions
1. Should we maintain full-resolution images in disk cache for fullscreen view? No
2. What's the optimal thumbnail size for message images? (400x400? 600x600?)  400x400
3. Should we implement a separate thumbnail cache?, yes
4. How aggressive should we be with canceling off-screen loads? high for now

### Testing Questions
1. How do we measure memory impact of each optimization?
2. What's the acceptable trade-off between memory and image quality? I prefer memory optimised currently
3. Should we have different strategies for different image types? (photos vs. screenshots vs. memes) no

---

## Monitoring & Metrics

### Metrics to Track
1. Memory usage before/after optimizations
2. Image cache size and hit rate
3. Number of simultaneous image loads
4. Time to first image render
5. Memory spikes during scrolling
6. Video memory usage

### Logging to Add
1. Image sizes loaded (width, height, bytes)
2. Cache hit/miss rates
3. Number of images loaded per message
4. Memory usage per channel
5. Image load cancellations

---

## Next Steps

1. **Measure Current State**
   - Add memory instrumentation
   - Log image sizes being loaded
   - Track cache usage

2. **Implement Phase 1 (Image Downsampling)**
   - Start with message attachments
   - Then avatars
   - Then emojis

3. **Implement Phase 2 (Video Optimization)**
   - Remove immediate AVPlayer creation
   - Implement thumbnail strategy

4. **Test & Iterate**
   - Measure memory impact
   - Adjust thumbnail sizes
   - Fine-tune cache limits

5. **Implement Remaining Phases**
   - Visibility-based loading
   - Cache optimization

---

## Notes

- This plan focuses on media loading inefficiencies
- Text-only messages should not consume significant memory
- The 1.8GB memory suggests media is the primary culprit
- Downsampling is the highest-impact optimization
- Video optimization is critical for channels with many videos

---

## Gaps / Risks to Consider

1. **Text Rendering & Layout Caches**: Large attributed strings, markdown rendering, and layout caching (e.g., `UITextView`/`UILabel` sizing caches) can accumulate in long lists. Investigate message text rendering caches and reuse strategies.
2. **Message Data Retention**: View models or data stores might retain full message histories for all opened channels. Validate whether old channel messages are released on channel switch and whether in-memory caches are bounded.
3. **Diffable Data Sources / Snapshot Growth**: If using diffable data sources or large snapshots, repeated updates can retain prior state. Confirm snapshots are not accumulating and old ones are released.
4. **Prefetching Behavior**: Table/collection view prefetching may load media ahead of visibility, increasing memory. Ensure prefetch is limited and cancels aggressively.
5. **Async Task Retention**: Image/video load tasks or Combine pipelines might retain strong references to cells or view models. Audit for retain cycles and ensure tasks are canceled on reuse/deinit.
6. **Temporary File Accumulation**: Video downloads to temp files could accumulate on disk and keep file handles open. Verify cleanup and lifecycle of temp artifacts.
7. **Websocket / Event Buffering**: Realtime events or message history merging may keep redundant message copies. Confirm incremental updates are not duplicating message models.
8. **Image Decoder & Cache Settings**: Kingfisher memory cost may not match actual decoded image size (especially for animated images). Verify cost settings and consider `decodedImageScale`/`backgroundDecode`.
9. **Startup Preloading**: Startup memory spikes might come from eager loading (initial channel render, large caches, theme assets). Profile app launch to isolate initial allocations.
10. **Instrumentation Coverage**: Add Instruments-based checks (Allocations, Leaks, Time Profiler, VM Tracker) to confirm the real dominant allocators rather than assuming media-only causes.

---

## Gap Analysis & Recommendations

### 1. Text Rendering & Layout Caches

#### Current State
**Location**: `Revolt/Pages/Channel/Messagable/Utils/MarkdownProcessor.swift`

**Findings**:
- ✅ Markdown cache exists with 100-item limit and clears half when full
- ✅ Long messages (>1500 chars) use lightweight processing
- ⚠️ **Issue**: Cache stores full `NSAttributedString` objects (no size-based limit)
- ⚠️ **Issue**: `UITextView` in `MessageCell` may cache layout calculations
- ⚠️ **Issue**: No size-based cache limits (only count-based)

**Memory Impact**: 
- Each cached attributed string: ~1-5KB for short messages, 10-50KB for long messages
- With 100 cached messages: ~100KB-5MB (depends on message length)
- UITextView layout cache: ~50-200KB per visible cell

#### Recommendations
1. **Add size-based cache limits**:
   - Limit total cache size to 2MB
   - Evict largest entries first when size limit reached
   - Clear cache on memory warnings

2. **Optimize UITextView reuse**:
   - Clear `attributedText` in `prepareForReuse()` (already done)
   - Consider using `NSTextStorage` with better memory management
   - Clear text container cache when cell is reused

3. **Implement cache size tracking**:
   ```swift
   private var markdownCacheSize: Int = 0
   private let maxCacheSizeBytes = 2 * 1024 * 1024 // 2MB
   ```

**Implementation Priority**: Lower (cache is bounded, but can be optimized)

---

### 2. Message Data Retention

#### Current State
**Location**: `Revolt/ViewState.swift:1120-1260`, `1312-1350`

**Findings**:
- ✅ `clearChannelMessages()` trims channel IDs and removes old messages from `messages`
- ✅ `cleanupOrphanedMessages()` removes any `messages` entries not referenced by `channelMessages`
- ⚠️ **Issue**: `messages` retains all message objects referenced by `channelMessages` across channels (DMs are preserved), so growth depends on per-channel limits and cleanup call frequency

**Memory Impact**:
- With 10 channels at 50-100 messages each = 500-1000 messages
- Each message: ~1-5KB (text) + attachments metadata
- Total: ~0.5-5MB for messages alone (excluding media)

#### Recommendations
1. **Aggressive message cleanup**:
   - Confirm `clearChannelMessages()` is called on every channel switch
   - Only keep messages for active channel + 1-2 recently viewed channels
   - Clear messages older than 5 minutes from inactive channels

2. **Implement message reference counting**:
   - Track which channels reference each message
   - Only remove message when no channels reference it
   - Handle reply chains carefully (keep replied-to messages)

3. **Verify cleanup is working**:
   - Add logging to confirm messages are removed
   - Profile memory before/after channel switch
   - Check for retain cycles preventing cleanup

**Implementation Priority**: High (directly impacts memory growth)

---

### 3. Diffable Data Sources / Snapshot Growth

#### Current State
**Location**: `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

**Findings**:
- ✅ **Not using diffable data sources** - using custom `LocalMessagesDataSource`
- ✅ No snapshot accumulation issue
- ℹ️ Custom data source implementation is used instead

**Memory Impact**: None (not applicable)

#### Recommendations
- No action needed - not using diffable data sources
- Current custom data source appears memory-efficient

**Implementation Priority**: N/A

---

### 4. Prefetching Behavior

#### Current State
**Location**: `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift:7608-7654`

**Findings**:
- ✅ Prefetching is enabled: `tableView.isPrefetchingEnabled = true`
- ⚠️ **Issue**: Prefetches all attachment URLs via `ImagePrefetcher` (no limits)
- ⚠️ **Issue**: Prefetches full-size attachment URLs (no downsampling/thumbnail URLs)
- ⚠️ **Issue**: `cancelPrefetchingForRowsAt` is empty (no cancellation)
- ⚠️ **Issue**: Prefetches avatars and attachments in the same pass

**Memory Impact**:
- Prefetching 10-20 rows ahead = 10-20 messages
- Each message with 2-3 images = 20-60 images prefetched
- At full resolution: 20-60 images × 2-5MB each = 40-300MB prefetched

#### Recommendations
1. **Limit prefetching**:
   - Reduce prefetch distance to 5 rows (from default 10-20)
   - Only prefetch avatars (small, critical for UX)
   - Defer attachment prefetching until cell is visible

2. **Implement cancellation**:
   ```swift
   func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
       for indexPath in indexPaths {
           // Cancel any pending image loads for these rows
       }
   }
   ```

3. **Use downsampled prefetching**:
   - Prefetch thumbnails only (not full images)
   - Load full image when cell becomes visible

4. **Disable prefetching for large channels**:
   - Disable when message count > 500
   - Re-enable when scrolling slows down

**Implementation Priority**: High (prefetching loads many full-resolution images)

---

### 5. Async Task Retention

#### Current State
**Location**: `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:58-276, 3526-3565`, `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift:1854-1935, 8208-8232, 4464-4476`

**Findings**:
- ✅ `prepareForReuse()` cancels Kingfisher tasks
- ✅ Controller teardown cancels `loadingTask`, `pendingAPICall`, and `cacheLoadTask`/`replyFetchTask` during teardown
- ⚠️ **Issue**: `MessageCell` starts video download tasks without storing a cancelable handle
- ⚠️ **Issue**: `replyFetchDebounceTask` is canceled on reschedule but not explicitly canceled on teardown
- ⚠️ **Issue**: Several fire-and-forget `Task {}` blocks exist; verify all use `[weak self]` or are cancelable

**Memory Impact**:
- Uncanceled tasks retain cell/view references
- Can prevent cell deallocation
- Accumulates over time

#### Recommendations
1. **Track all async tasks**:
   - Store task references in cell/view controller
   - Cancel all tasks in `prepareForReuse()` and `deinit`
   - Use `Task` with weak references

2. **Audit task creation**:
   - Find all `Task { }` and `async` calls
   - Ensure they're canceled on cleanup
   - Use `Task.detached` with weak self where appropriate

3. **Video download task cleanup**:
   - Store video download task reference
   - Cancel in `prepareForReuse()` and `cleanupTempVideos()`

**Implementation Priority**: Lower (good cleanup exists, but needs verification)

---

### 6. Temporary File Accumulation

#### Current State
**Location**: `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:241-276, 3436, 3526-3565, 3956-4010`

**Findings**:
- ✅ `cleanupTempVideos()` exists and is called in `prepareForReuse()` and AVPlayer dismissal callbacks
- ✅ `tempVideoURLs` tracks created temp files
- ⚠️ **Issue**: No app-level cleanup for temp files on startup or crash recovery
- ⚠️ **Issue**: Temp files created by in-flight downloads could be orphaned if the cell/view controller is torn down mid-download

**Memory Impact**:
- Each video temp file: 10-500MB
- If cleanup fails: can accumulate gigabytes on disk
- Disk space issues can cause app crashes

#### Recommendations
1. **Add app-level temp file cleanup**:
   - Clean up temp files on app launch
   - Remove files older than 1 hour
   - Add cleanup in `applicationDidFinishLaunching`

2. **Improve cell cleanup**:
   - Ensure `cleanupTempVideos()` always runs
   - Use `defer` blocks for guaranteed cleanup
   - Add logging to track temp file creation/deletion

3. **Periodic cleanup**:
   - Run cleanup every 5 minutes
   - Clean up files from other sessions
   - Limit total temp directory size

**Implementation Priority**: Lower (cleanup exists, but needs hardening)

---

### 7. Websocket / Event Buffering

#### Current State
**Location**: `Revolt/ViewState.swift:3026-3123`, `3965-4004`

**Findings**:
- ✅ Events are processed incrementally (not buffered)
- ✅ `processEvent()` handles updates without duplication
- ⚠️ **Issue**: `messages.removeAll()` in Ready event may clear needed messages
- ⚠️ **Issue**: Event processing may create temporary message copies
- ⚠️ **Issue**: Large Ready events load all users/channels at once

**Memory Impact**:
- Ready event: loads all users, channels, servers at once
- Can be 1000+ users, 100+ channels
- Temporary spike during event processing

#### Recommendations
1. **Optimize Ready event processing**:
   - Process users/channels in batches
   - Use lazy loading for non-critical data
   - Don't clear all messages on Ready (merge instead)

2. **Verify no duplication**:
   - Add logging to track message updates
   - Ensure `messages[message.id] = message` doesn't create duplicates
   - Check for message ID collisions

3. **Batch event processing**:
   - Process multiple events in single batch
   - Reduce intermediate object creation
   - Use weak references in event handlers

**Implementation Priority**: Lower (events are processed efficiently, but Ready event is large)

---

### 8. Image Decoder & Cache Settings

#### Current State
**Location**: `Revolt/Delegates/AppDelegate.swift:69-92`

**Findings**:
- ✅ Cache limits are configured (50MB memory, 200MB disk, 200 count)
- ⚠️ **Issue**: Cost calculation may not match actual decoded size
- ⚠️ **Issue**: Animated images (GIFs) decode to multiple frames (not accounted for)
- ⚠️ **Issue**: No `decodedImageScale` or `backgroundDecode` options
- ⚠️ **Issue**: Cost is based on image data size, not decoded bitmap size

**Memory Impact**:
- Decoded image size = width × height × 4 bytes (RGBA)
- A 4K image (3840×2160) = 33MB decoded (but only 2-5MB compressed)
- Cost limit of 50MB may allow only 1-2 large images
- Animated GIFs: each frame is full size

#### Recommendations
1. **Improve cost calculation**:
   ```swift
   // Use actual decoded size for cost
   let cost = image.size.width * image.size.height * 4 // RGBA bytes
   ImageCache.default.store(image, forKey: key, cost: Int(cost))
   ```

2. **Add decoded image scale**:
   ```swift
   .downsamplingImage(scale: UIScreen.main.scale)
   ```

3. **Handle animated images**:
   - Limit animated image cache separately
   - Use lower frame count for cached GIFs
   - Consider not caching animated images in memory

4. **Background decoding**:
   - Decode images on background thread
   - Reduces main thread blocking
   - Better memory management

**Implementation Priority**: High (cost calculation affects cache efficiency)

---

### 9. Startup Preloading

#### Current State
**Location**: `Revolt/ViewState.swift:1568-1760`

**Findings**:
- ✅ `preloadImportantChannels()` runs on startup and after WebSocket reconnects
- ⚠️ **Issue**: Preloads up to 3 text channels + 5 DMs + 1 specific channel = up to 9 channels
- ⚠️ **Issue**: Each channel loads `getEffectiveFetchLimit()` (25/50/100), except the specific channel in its server uses 10
- ✅ Preloading waits 2 seconds before firing
- ⚠️ **Issue**: Channels are preloaded in parallel (`TaskGroup`), and `include_users: true` loads users with messages

**Memory Impact**:
- Up to 9 channels × 25-100 messages = 225-900 messages
- 225-900 messages × 1-5KB = ~0.2-4.5MB (text only)
- Plus images, avatars, etc. = 5-20MB startup spike

#### Recommendations
1. **Disable or defer preloading**:
   - Make preloading optional (user setting)
   - Defer until user interacts with app
   - Only preload current channel (not all channels)

2. **Reduce preload scope**:
   - Preload only 1 channel (current/active)
   - Reduce message limit to 10-20 (from 50)
   - Don't preload images (only metadata)

3. **Stagger preloading**:
   - Preload channels sequentially (not parallel)
   - Add delays between preloads
   - Cancel preloads if user navigates away

4. **Add preload flag**:
   ```swift
   var enableAutomaticPreloading: Bool {
       UserDefaults.standard.bool(forKey: "enablePreloading") ?? false
   }
   ```

**Implementation Priority**: Lower (startup spike is noticeable but temporary)

---

### 10. Instrumentation Coverage

#### Current State
**Findings**:
- ⚠️ **Issue**: Limited memory instrumentation
- ⚠️ **Issue**: No allocation tracking
- ⚠️ **Issue**: No leak detection
- ✅ Some logging exists but not comprehensive

#### Recommendations
1. **Add Instruments profiling**:
   - Use Allocations instrument to find dominant allocators
   - Use Leaks instrument to find retain cycles
   - Use Time Profiler to find memory-heavy operations
   - Use VM Tracker to see memory regions

2. **Add memory logging**:
   ```swift
   func logMemoryUsage(label: String) {
       let memory = mach_task_basic_info()
       var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
       let kerr: kern_return_t = withUnsafeMutablePointer(to: &memory) {
           $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
               task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
           }
       }
       if kerr == KERN_SUCCESS {
           print("\(label): \(memory.resident_size / 1024 / 1024)MB")
       }
   }
   ```

3. **Add memory breakpoints**:
   - Set breakpoints on high memory usage
   - Track memory growth over time
   - Identify memory spikes

4. **Profile specific operations**:
   - Memory before/after channel load
   - Memory before/after scrolling
   - Memory before/after image load
   - Memory on app startup

**Implementation Priority**: High (needed to verify optimizations work)

---

## Updated Implementation Priority

### Critical (Do First)
1. ✅ Image downsampling for message attachments
2. ✅ Image downsampling for avatars  
3. ✅ Video thumbnail strategy (no AVPlayer until play)
4. ✅ Visibility-based image loading
5. ✅ **Prefetching optimization** (limit and cancel)
6. ✅ **Message data retention** (aggressive cleanup)

### High Priority
7. ✅ Image downsampling for emojis
8. ✅ Video streaming instead of download
9. ✅ Cache size limits and eviction
10. ✅ **Image decoder cost calculation**
11. ✅ **Instrumentation and profiling**


---

## TODO
1. Add lightweight logging to confirm `clearChannelMessages()` runs on every channel switch.
2. Implement `cancelPrefetchingForRowsAt` and cap prefetch distance.
3. Validate Ready-event memory spikes with Instruments (Allocations + VM Tracker).

---

## Additional Memory Investigation: Other Causes

### 11. Video Cache & AVAsset Retention

#### Current State
**Location**: `Revolt/Components/AudioPlayer/VideoPlayerView.swift:31-32, 409-410`

**Findings**:
- ✅ Static caches have LRU limits (50 thumbnails, 100 durations)
- ✅ `deinit` cancels `assetLoadingTask` and sets `videoAsset = nil`
- ⚠️ **Issue**: `videoAsset` is stored as instance property but may be retained by `AVAssetImageGenerator`
- ⚠️ **Issue**: `AVAsset` created from URL may download video data even for thumbnail generation
- ⚠️ **Issue**: Thumbnail generation downloads first 2MB of video (`downloadVideoForThumbnail`) but full video may be cached by AVFoundation

**Memory Impact**:
- Each `AVAsset` instance: ~1-5MB (depends on video metadata)
- `AVAssetImageGenerator` may retain decoded frames: ~5-20MB per generator
- With 50 cached thumbnails: potential 50-250MB if AVAssets are retained
- Video thumbnail generation downloads 2MB per video, but AVFoundation may cache more

#### Recommendations
1. **Release AVAsset immediately after thumbnail generation**:
   ```swift
   private func generateThumbnailFromLocalFile(url: URL, cacheKey: String) async {
       let asset = AVAsset(url: url)
       let imageGenerator = AVAssetImageGenerator(asset: asset)
       // ... generate thumbnail ...
       // CRITICAL: Release asset and generator immediately
       imageGenerator = nil
       asset = nil
   }
   ```

2. **Use weak references for AVAsset in VideoPlayerView**:
   - Store `videoAsset` only when actively needed
   - Set to `nil` immediately after thumbnail generation
   - Don't retain `AVAsset` in instance property

3. **Limit concurrent thumbnail generations**:
   - Use a semaphore to limit to 2-3 concurrent thumbnail generations
   - Cancel thumbnail generation if cell scrolls off-screen

4. **Add AVAsset cleanup tracking**:
   - Log when AVAssets are created and released
   - Verify deallocation in Instruments

**Implementation Priority**: High (AVAssets can retain significant memory)

---

### 12. Audio Cache & AVPlayer Retention

#### Current State
**Location**: `Revolt/Components/AudioPlayer/AudioPlayerManager.swift:16-17, 482, 551-552`

**Findings**:
- ✅ Duration cache has LRU limit (200 entries)
- ✅ `stop()` sets `player = nil` and `playerItem = nil`
- ⚠️ **Issue**: `AVPlayer` and `AVPlayerItem` may retain buffered audio data
- ⚠️ **Issue**: `playerItem` observers (Combine publishers) may retain references
- ⚠️ **Issue**: Audio session remains active even when not playing (though code shows deactivation)
- ⚠️ **Issue**: OGG conversion creates temp files that may accumulate

**Memory Impact**:
- `AVPlayer` with buffered audio: ~10-50MB per player
- `AVPlayerItem` with loaded audio: ~5-20MB per item
- OGG temp files: ~5-50MB per file (until cleaned up)
- With multiple audio messages: can accumulate 100MB+

#### Recommendations
1. **Aggressive AVPlayer cleanup**:
   ```swift
   func stop() {
       player?.pause()
       removeTimeObserver()
       removePlayerObservers()
       
       // CRITICAL: Replace current item with nil to release buffered data
       player?.replaceCurrentItem(with: nil)
       player = nil
       playerItem = nil
       
       // ... rest of cleanup ...
   }
   ```

2. **Clean up OGG temp files immediately**:
   - Remove temp files after playback ends (already done, but verify)
   - Add periodic cleanup for orphaned temp files
   - Limit concurrent OGG conversions to 1

3. **Verify Combine subscription cleanup**:
   - Ensure all `cancellables` are cleared in `removePlayerObservers()`
   - Use `[weak self]` in all Combine publishers (already done)

4. **Add audio memory tracking**:
   - Log AVPlayer creation and deallocation
   - Track temp file creation/deletion

**Implementation Priority**: Medium (audio is less common than images, but can spike)

---

### 13. Message Data Structure Size

#### Current State
**Location**: `Types/Message.swift:218-294`, `Types/File.swift:100-137`

**Findings**:
- Message struct contains:
  - `id: String` (~20-40 bytes)
  - `content: String?` (~0-10KB for long messages)
  - `author: String` (~20-40 bytes)
  - `channel: String` (~20-40 bytes)
  - `attachments: [File]?` (~100-500 bytes per attachment)
  - `embeds: [Embed]?` (~200-1000 bytes per embed)
  - `reactions: [String: [String]]?` (~50-200 bytes per reaction)
  - `user: User?` (~500-2000 bytes, includes avatar URL, username, etc.)
  - `member: Member?` (~300-1000 bytes)
  - Other optional fields: ~100-500 bytes

**Memory Impact**:
- Small text message: ~500 bytes - 1KB
- Message with 1 image attachment: ~1-2KB (metadata only, not image data)
- Message with 5 attachments: ~2-5KB
- Message with long content (1000+ chars): ~5-10KB
- Message with embeds: ~3-8KB
- With 2000 messages in memory: ~1-10MB (text/metadata only)
- **Note**: This is metadata only - actual image/video data is separate

#### Recommendations
1. **Message size is reasonable** - not a major concern
2. **Consider lazy loading for large content**:
   - Store full content only for visible messages
   - Store truncated content for off-screen messages
   - Load full content when message becomes visible

3. **Optimize attachment metadata**:
   - Don't store full `File` objects if only URL is needed
   - Store minimal metadata (id, url, size) instead of full `File` struct

4. **Consider message compression**:
   - Use compression for long message content
   - Store compressed content and decompress on display

**Implementation Priority**: Low (message metadata is small compared to media)

---

### 14. UIKit View Hierarchy Overhead

#### Current State
**Location**: `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift:12-300`, `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift:1819-1860`

**Findings**:
- ✅ `prepareForReuse()` aggressively cleans up views
- ✅ Cells are properly registered and reused
- ✅ `didEndDisplaying` cancels image loads
- ⚠️ **Issue**: `MessageCell` has many subviews (avatar, username, content, attachments, reactions, replies, etc.)
- ⚠️ **Issue**: Each cell creates multiple `UIImageView` instances for attachments
- ⚠️ **Issue**: `UITextView` (contentLabel) may cache layout calculations
- ⚠️ **Issue**: Auto Layout constraints accumulate if not properly removed
- ⚠️ **Issue**: Table view may retain off-screen cells in reuse pool

**Memory Impact**:
- Each `MessageCell` instance: ~50-200KB (depends on content)
- `UITextView` layout cache: ~20-100KB per visible cell
- Auto Layout constraint objects: ~1-5KB per cell
- Reuse pool (10-20 cells): ~1-4MB
- With 50 visible cells: ~2.5-10MB for cells alone

#### Recommendations
1. **Optimize cell reuse**:
   - Reduce reuse pool size if possible
   - Clear `UITextView` layout cache in `prepareForReuse()`:
     ```swift
     contentLabel.textContainer.layoutManager?.textContainer(forGlyphAt: 0, actualCharacterRange: nil)
     ```

2. **Limit subview creation**:
   - Reuse `UIImageView` instances instead of creating new ones
   - Use view tags to find and reuse existing views
   - Pool image views for attachments

3. **Clear Auto Layout constraints properly**:
   - Remove all constraints in `prepareForReuse()` (already done via `clearDynamicConstraints()`)
   - Verify constraints are actually removed

4. **Optimize UITextView**:
   - Use `NSTextStorage` with better memory management
   - Clear `attributedText` in `prepareForReuse()` (already done)
   - Consider using `UILabel` for simple text (but UITextView needed for links)

5. **Profile view hierarchy**:
   - Use Instruments to measure actual cell memory usage
   - Check for view hierarchy leaks

**Implementation Priority**: Medium (view hierarchy is necessary but can be optimized)

---

### 15. Potential Memory Leaks & Retain Cycles

#### Current State
**Location**: Multiple files (audited 316 Task blocks, 20 Combine subscriptions, 50 NotificationCenter observers)

**Findings**:

**✅ Good Practices**:
- Extensive use of `[weak self]` in closures and async tasks (97+ instances found)
- Weak references for delegates (`weak var delegate`) - properly used
- `deinit` methods clean up timers, observers, and tasks
- Most Combine subscriptions use `[weak self]` and are stored in `cancellables`
- Most NotificationCenter observers are removed in `deinit`

**⚠️ Issues Found**:

1. **Task blocks without `[weak self]`** (High Priority):
   - `MessageableChannelViewController.swift:373`: `Task { await loadInitialMessages() }` - captures `self` strongly
   - `MessageableChannelViewController.swift:794`: `Task { await loadInitialMessages() }` - captures `self` strongly
   - `ViewState.swift:3126`: `Task { await MainActor.run { self.cleanupStaleUnreads() } }` - captures `self` strongly
   - `VideoPlayerView.swift:350`: `Task { ... }` in `generateThumbnail` - captures `self` strongly
   - `MessageableChannelViewController.swift:7057`: `Task { [self] in ... }` - **explicitly captures self strongly** (intentional but risky)
   - Multiple `Task { @MainActor in }` blocks without `[weak self]` (29 instances found)

2. **Combine Subscriptions** (Medium Priority):
   - ✅ `AudioPlayerManager`: Properly uses `cancellables` and clears in `removePlayerObservers()`
   - ✅ `AudioPlayerView`: Properly uses `cancellables` and clears in cleanup
   - ⚠️ `ViewState`: Has `cancellables` but only 1 subscription found - verify all are cleared
   - ⚠️ `MessageableChannelViewController`: Has `cancellables` but no subscriptions found - may be unused
   - ⚠️ `MessageableChannel.swift`: Has `cancellables` but no subscriptions found - may be unused

3. **NotificationCenter Observers** (Low Priority):
   - ✅ Most observers use selector-based API (safer, automatically removed on dealloc)
   - ✅ Block-based observers use `[weak self]` (Websocket.swift:560, 572)
   - ✅ Observers are removed in `deinit` (MessageableChannelViewController, AudioPlayerManager, etc.)
   - ⚠️ Some observers may not be removed if `deinit` doesn't run (retain cycle prevents deinit)

4. **AVPlayer Observers** (Medium Priority):
   - ✅ `AudioPlayerManager`: Uses Combine publishers with `[weak self]` and stores in `cancellables`
   - ✅ NotificationCenter observers for AVPlayer are removed in `removePlayerObservers()`
   - ⚠️ Time observer may not be removed if `removeTimeObserver()` isn't called

**Memory Impact**:
- Retain cycles prevent deallocation
- Can cause unbounded memory growth
- Hard to detect without Instruments
- **Estimated impact**: 10-100MB+ per retained object if cycles exist

#### Specific Issues to Fix

**Critical (Fix Immediately)**:

1. **MessageableChannelViewController.swift:373**:
   ```swift
   // BEFORE (captures self strongly):
   Task {
       await loadInitialMessages()
   }
   
   // AFTER (use weak self):
   Task { [weak self] in
       await self?.loadInitialMessages()
   }
   ```

2. **MessageableChannelViewController.swift:794**:
   ```swift
   // BEFORE:
   Task {
       await loadInitialMessages()
   }
   
   // AFTER:
   Task { [weak self] in
       await self?.loadInitialMessages()
   }
   ```

3. **ViewState.swift:3126**:
   ```swift
   // BEFORE:
   Task {
       await MainActor.run {
           self.cleanupStaleUnreads()
       }
   }
   
   // AFTER:
   Task { [weak self] in
       await MainActor.run {
           self?.cleanupStaleUnreads()
       }
   }
   ```

4. **VideoPlayerView.swift:350**:
   ```swift
   // BEFORE:
   Task {
       do {
           // ... thumbnail generation ...
       }
   }
   
   // AFTER:
   Task { [weak self] in
       guard let self = self else { return }
       do {
           // ... thumbnail generation ...
       }
   }
   ```

5. **MessageableChannelViewController.swift:7057**:
   ```swift
   // BEFORE (explicitly captures self strongly):
   let task = Task { [self] in
       // ... API call ...
   }
   
   // AFTER (use weak self and store task reference):
   let task = Task { [weak self] in
       guard let self = self else { return }
       // ... API call ...
   }
   // Store task reference and cancel in deinit/viewDidDisappear
   ```

**High Priority (Fix Soon)**:

6. **Task blocks with @MainActor** (29 instances):
   - Most are in ViewState and MessageableChannelViewController
   - Add `[weak self]` to all `Task { @MainActor in }` blocks
   - Verify tasks are cancelled when view controller is deallocated

7. **Combine subscriptions cleanup**:
   - Verify `ViewState.cancellables` is cleared in appropriate cleanup method
   - Verify `MessageableChannelViewController.cancellables` is used or removed
   - Add `cancellables.removeAll()` in `deinit` if not already present

**Medium Priority**:

8. **AVPlayer time observer**:
   - Verify `removeTimeObserver()` is always called
   - Add to `deinit` as backup

#### Recommendations

1. **Fix all Task blocks without `[weak self]`**:
   - Add `[weak self]` to all Task blocks that capture self
   - Use `guard let self = self else { return }` pattern for early exit
   - Store task references for long-running tasks and cancel in cleanup

2. **Verify Combine subscription cleanup**:
   - Add `cancellables.removeAll()` in all `deinit` methods that have `cancellables`
   - Verify all Combine publishers use `[weak self]`
   - Use `store(in: &cancellables)` for all subscriptions

3. **Verify NotificationCenter cleanup**:
   - All observers should be removed in `deinit`
   - Use selector-based API when possible (automatically cleaned up)
   - Use `[weak self]` in block-based observers

4. **Add leak detection**:
   - Use Instruments Leaks tool to find actual retain cycles
   - Add logging in `deinit` to verify objects are deallocated:
     ```swift
     deinit {
         print("🗑️ DEINIT: \(type(of: self)) is being deallocated")
         // ... cleanup ...
     }
     ```
   - Track object creation/deallocation counts

5. **Specific areas to check**:
   - `MessageCell` - verify all callbacks use weak references ✅ (already good)
   - `MessageableChannelViewController` - fix Task blocks without weak self ⚠️
   - `VideoPlayerView` - fix Task block without weak self ⚠️
   - `AudioPlayerManager` - verify AVPlayer cleanup ✅ (already good)
   - `ViewState` - fix Task blocks without weak self ⚠️

**Implementation Priority**: **Critical** (retain cycles can cause unbounded growth and prevent deallocation)

---

### 16. Temporary File Accumulation

#### Current State
**Location**: `Revolt/Components/AudioPlayer/VideoPlayerView.swift:353-361`, `Revolt/Components/AudioPlayer/AudioPlayerManager.swift:607-612`

**Findings**:
- ✅ Video temp files cleaned up in `defer` block
- ✅ OGG temp files cleaned up after playback
- ⚠️ **Issue**: Temp files may be orphaned if app crashes
- ⚠️ **Issue**: No app-level cleanup on startup
- ⚠️ **Issue**: Temp files accumulate if cleanup fails

**Memory Impact**:
- Each video temp file: ~10-500MB
- Each OGG temp file: ~5-50MB
- If cleanup fails: can accumulate gigabytes on disk
- Disk space issues can cause app crashes

#### Recommendations
1. **Add app-level temp file cleanup**:
   ```swift
   // In AppDelegate.application(_:didFinishLaunchingWithOptions:)
   func cleanupTempFiles() {
       let tempDir = FileManager.default.temporaryDirectory
       let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
       
       // Clean up files older than 1 hour
       let oneHourAgo = Date().addingTimeInterval(-3600)
       // ... remove old files ...
   }
   ```

2. **Improve cell cleanup**:
   - Ensure `cleanupTempVideos()` always runs
   - Use `defer` blocks for guaranteed cleanup
   - Add logging to track temp file creation/deletion

3. **Periodic cleanup**:
   - Run cleanup every 5 minutes
   - Clean up files from other sessions
   - Limit total temp directory size

**Implementation Priority**: Lower (cleanup exists, but needs hardening)

---

## Updated Implementation Priority

### Critical (Do First)
1. ✅ Image downsampling for message attachments
2. ✅ Image downsampling for avatars  
3. ✅ Video thumbnail strategy (no AVPlayer until play)
4. ✅ Visibility-based image loading
5. ✅ **Prefetching optimization** (limit and cancel)
6. ✅ **Message data retention** (aggressive cleanup)
7. ✅ **AVAsset cleanup** (release immediately after thumbnail generation)
8. ✅ **Retain cycle audit** (verify all Task blocks use weak references)

### High Priority
9. ✅ Image downsampling for emojis
10. ✅ Video streaming instead of download
11. ✅ Cache size limits and eviction
12. ✅ **Image decoder cost calculation**
13. ✅ **Instrumentation and profiling**
14. ✅ **AVPlayer cleanup** (replace current item with nil)
15. ✅ **UIKit view hierarchy optimization** (UITextView layout cache)

### Medium Priority
16. ✅ **Audio temp file cleanup** (app-level cleanup)
17. ✅ **Message content lazy loading** (for very long messages)
18. ✅ **Limit concurrent thumbnail generations**

---

## Next Steps

1. **Profile with Instruments**:
   - Use Allocations instrument to find dominant allocators
   - Use Leaks instrument to find retain cycles
   - Use VM Tracker to see memory regions
   - Profile specific operations (channel load, scrolling, image load)

2. **Implement AVAsset cleanup**:
   - Release AVAsset immediately after thumbnail generation
   - Don't retain AVAsset in instance property
   - Add logging to verify cleanup

3. **Audit retain cycles**:
   - Find all Task blocks without `[weak self]`
   - Verify all Combine subscriptions are cancelled
   - Add deinit logging to verify deallocation

4. **Add app-level temp file cleanup**:
   - Clean up temp files on app launch
   - Add periodic cleanup
   - Limit temp directory size

5. **Optimize UIKit view hierarchy**:
   - Clear UITextView layout cache
   - Reuse image views
   - Profile actual cell memory usage
