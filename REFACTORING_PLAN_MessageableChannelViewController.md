# Refactoring Plan: MessageableChannelViewController.swift

## Overview
**Current State:** 8,964 lines in a single file  
**Target:** Break into multiple files, each ≤300 lines  
**Strategy:** Extract by functional responsibility into extensions and separate classes

**⚠️ ARCHITECTURE REVIEW COMPLETED**: This plan has been reviewed and enhanced with critical risk mitigations. See `ARCHITECTURE_REVIEW_RefactoringPlan.md` for detailed analysis.

---

## File Structure Analysis

### Current File Breakdown:
1. **Main Class** (lines 30-8023): ~7,993 lines
   - Properties and initialization
   - View lifecycle methods
   - Setup methods
   - Message loading logic
   - Scroll handling
   - Memory management
   - Target message handling
   - Reply handling
   - NSFW handling
   - Image handling
   - Empty state handling

2. **Extensions** (lines 8029-8964): ~935 lines
   - MessageCell extensions
   - UITableViewDataSourcePrefetching
   - Empty state handling
   - NSFWOverlayView class
   - MessageInputView extensions
   - MessageSkeletonView class
   - Memory management
   - Scroll position preservation
   - Helper functions

---

## Refactoring Plan

### Phase 1: Extract Standalone Classes (Already Partially Done)

#### ✅ Already Extracted (from comments):
- `ReplyMessage` → `Models/ReplyMessage.swift`
- `MessageableChannelConstants` → `Models/MessageableChannelConstants.swift`
- `MessageableChannelErrors` → `Models/MessageableChannelErrors.swift`
- `PermissionsManager` → `Managers/PermissionsManager.swift`
- `RepliesManager` → `Managers/RepliesManager.swift`
- `TypingIndicatorManager` → `Managers/TypingIndicatorManager.swift`
- `ScrollPositionManager` → `Managers/ScrollPositionManager.swift`
- `MessageInputHandler` → `Utils/MessageInputHandler.swift`
- `ToastView` → `Views/ToastView.swift`
- `NSFWOverlayView` → `Views/NSFWOverlayView.swift`

#### 🔄 Need to Extract:

1. **NSFWOverlayView.swift** (lines 8267-8414, ~147 lines)
   - Extract to: `Views/NSFWOverlayView.swift`
   - Includes: `NSFWOverlayViewDelegate` protocol and `NSFWOverlayView` class

2. **MessageSkeletonView.swift** (lines 8560-8656, ~96 lines)
   - Extract to: `Views/MessageSkeletonView.swift`
   - Standalone UIView subclass

3. **NotificationBanner.swift** (lines 8426-8483, ~57 lines)
   - Extract to: `Views/NotificationBanner.swift`
   - Currently private class, should be standalone

**Risk Level**: 🟢 Low - Standalone classes with minimal dependencies

---

### Phase 2: Extract Low-Risk Extensions First

**Strategy**: Start with extensions that have minimal dependencies and state requirements.

#### 2.1 Standalone Helper Functions

**File 1: MessageableChannelViewController+Helpers.swift** (~100 lines)
- `generateMessageLink(serverId:channelId:messageId:viewState:)` async
- Other standalone helper functions
- Pure functions with no state dependencies

**File 2: MessageableChannelViewController+Utilities.swift** (~200 lines)
- `showErrorAlert(message:)`
- `getViewState() -> ViewState`
- `markLastMessageAsSeen()`
- `disableAutoAcknowledgment()`
- `resetLoadingStateIfNeeded()`
- `extractRetryAfterValue(from:)`
- Helper methods for message processing

**Risk Level**: 🟢 Low - Minimal dependencies

#### 2.2 Protocol Conformance Extensions

**File 3: MessageableChannelViewController+Prefetching.swift** (~100 lines)
- `UITableViewDataSourcePrefetching` conformance
- `tableView(_:prefetchRowsAt:)`
- `tableView(_:cancelPrefetchingForRowsAt:)`

**File 4: MessageableChannelViewController+Delegates.swift** (~150 lines)
- Consolidate all delegate protocol methods
- `UITextFieldDelegate` methods
- `NSFWOverlayViewDelegate` methods
- `UIGestureRecognizerDelegate` methods
- Note: `UIScrollViewDelegate` already in `MessageableChannelViewController+ScrollView.swift`

**Risk Level**: 🟢 Low - Isolated protocol conformance

#### 2.3 UI Component Extensions (Low Dependencies)

**File 5: MessageableChannelViewController+EmptyState.swift** (~200 lines)
- `showEmptyStateView()`
- `hideEmptyStateView()`
- `updateEmptyStateVisibility()`
- Empty state UI setup

**File 6: MessageableChannelViewController+SkeletonLoading.swift** (~200 lines)
- `showSkeletonView()`
- `hideSkeletonView()`
- `updateSkeletonView()`
- Skeleton loading state management

**File 7: MessageableChannelViewController+NewMessageButton.swift** (~150 lines)
- `setupNewMessageButton()`
- `newMessageButtonTapped()`
- `showNewMessageButton()`
- Related button state management

**File 8: MessageableChannelViewController+ImageHandling.swift** (~200 lines)
- `showFullScreenImage(_:)`
- `nsfwOverlayViewDidConfirm(_:)`
- Image tap handling
- Full-screen image presentation

**Risk Level**: 🟡 Medium - UI state dependencies

---

### Phase 3: Extract Medium-Risk Extensions

**Strategy**: Extract extensions with moderate state dependencies and async operations.

#### 3.1 Reply Handling Extensions

**File 9: MessageableChannelViewController+Replies.swift** (~250 lines)
- `addReply(_:)`
- `removeReply(at:)`
- `clearReplies()`
- `fetchMessageForReply(messageId:channelId:)` async
- `fetchUserForMessage(userId:)` async
- `handleReplyClick(messageId:channelId:)`
- `showReplies(_:)`
- Reply-related UI updates

**Risk Level**: 🟡 Medium - Async operations, state dependencies

#### 3.2 Table View Update Extensions

**File 10: MessageableChannelViewController+TableViewUpdates.swift** (~250 lines)
- `refreshMessages(forceUpdate:)` implementation details
- `updateTableViewBouncing()`
- `adjustTableInsetsForMessageCount()`
- `enforceMessageWindow(keepingMostRecent:)`
- Table view data source updates
- Table view reload logic

**File 11: MessageableChannelViewController+ScrollPosition.swift** (~150 lines)
- `reloadTableViewMaintainingScrollPosition(messagesForDataSource:)`
- Scroll position preservation logic
- Anchor message finding and restoration

**Risk Level**: 🟡 Medium - Complex state synchronization

---

### Phase 4: Extract High-Risk Extensions (Requires Careful Testing)

**Strategy**: Extract extensions with complex state, async operations, and notification handling. Test thoroughly after each extraction.

#### 4.1 Message Loading Extensions

**File 12: MessageableChannelViewController+MessageLoading.swift** (~300 lines)
- `loadInitialMessages()` async
- `loadRegularMessages()` async
- `loadMoreMessages(before:server:messages:)`
- `loadNewerMessages(after:)`
- `refreshMessages(forceUpdate:)`
- `refreshWithTargetMessage(_:)` async
- `fetchReplyMessagesContent(for:)` async
- Message window enforcement methods

**⚠️ Critical Considerations**:
- State synchronization with `localMessages`, `viewModel.messages`, `viewState.channelMessages`
- Thread safety (`@MainActor` requirements)
- Task cancellation on view disappearance
- Rate limiting and debouncing logic

**Risk Level**: 🔴 High - Complex async operations, state synchronization

#### 4.2 Message Handling Extensions

**File 13: MessageableChannelViewController+MessageHandling.swift** (~300 lines)
- `messagesDidChange(_:)` notification handler
- `handleNewMessages(_:)` notification handler
- `handleNewSocketMessage(_:)` notification handler
- `handleNetworkError(_:)` notification handler
- `handleChannelSearchClosed(_:)` notification handler
- `handleVideoPlayerDismiss(_:)` notification handler
- `handleSystemLog(_:)` notification handler
- `handleChannelSearchClosing(_:)` notification handler
- `handleMemoryWarning()` notification handler
- `checkForScrollNeeded()` timer method

**⚠️ Critical Considerations**:
- Notification debouncing (`messageChangeDebounceInterval`)
- Thread safety for notification handlers
- State updates must be on main thread
- Consider creating `MessageableChannelNotificationCoordinator` if complexity grows

**Risk Level**: 🔴 High - Notification handling, state updates

#### 4.3 Scroll Handling Extensions

**File 14: MessageableChannelViewController+ScrollHandling.swift** (~300 lines)
- `scrollToBottom(animated:)` and related methods
- `scrollToTargetMessage()` and related target message scrolling
- `isUserNearBottom(threshold:)` and legacy version
- `loadMoreMessagesIfNeeded(for:)`
- `handleScrollEndForReplyPrefetch()`
- `positionTableAtBottomBeforeShowing()`
- `reloadTableViewMaintainingScrollPosition(messagesForDataSource:)`
- Scroll protection methods
- Note: `UIScrollViewDelegate` methods already in `MessageableChannelViewController+ScrollView.swift`

**⚠️ Critical Considerations**:
- Scroll position synchronization
- Protection against scrolling during data source updates (`isDataSourceUpdating`)
- Target message protection logic
- Thread safety

**Risk Level**: 🔴 High - Complex scroll state management

#### 4.4 Target Message Extensions

**File 15: MessageableChannelViewController+TargetMessage.swift** (~250 lines)
- Target message properties and state management
- `activateTargetMessageProtection(reason:)`
- `clearTargetMessageProtection(reason:)`
- `debugTargetMessageProtection()`
- `safeScrollToRow(at:at:animated:reason:)`
- `logScrollToBottomAttempt(animated:reason:)`
- Target message loading and scrolling logic

**⚠️ Critical Considerations**:
- State synchronization with `targetMessageId`, `targetMessageProcessed`, `isInTargetMessagePosition`
- Timer management (`clearTargetMessageTimer`)
- Protection against premature clearing
- Thread safety

**Risk Level**: 🔴 High - Complex state synchronization

#### 4.5 Memory Management Extensions

**File 16: MessageableChannelViewController+MemoryManagement.swift** (~300 lines)
- `performInstantMemoryCleanup()`
- `performLightMemoryCleanup()`
- `performAggressiveMemoryCleanup()`
- `cleanupDMSpecificData(channelId:)`
- `enforceMessageLimits()`
- `checkMemoryUsageAndCleanup()`
- `startMemoryCleanupTimer()`
- `stopMemoryCleanupTimer()`
- `forceImmediateMemoryCleanup()`
- `performFinalInstantCleanup()`
- `logMemoryUsage(prefix:)`
- `setupMemoryLogging()`

**⚠️ Critical Considerations**:
- Must be called in correct lifecycle order
- Task cancellation required
- Image cache cleanup
- ViewState cleanup coordination
- Memory leak prevention

**Risk Level**: 🔴 High - Critical cleanup logic, memory safety

---

### Phase 5: Extract Setup and Lifecycle (Last - Most Dependencies)

**Strategy**: Extract these last as they have the most dependencies on other extracted code.

#### 5.1 Setup Methods

**File 17: MessageableChannelViewController+Setup.swift** (~250 lines)
- `setupCustomHeader()` implementation
- `setupTableView()` implementation
- `setupMessageInput()` implementation
- `setupNewMessageButton()` implementation
- `setupSwipeGesture()` implementation
- `setupBindings()` implementation
- `setupKeyboardObservers()` implementation
- `setupAdditionalMessageObservers()` implementation

**Risk Level**: 🟡 Medium - Depends on properties and managers

#### 5.2 Lifecycle Methods

**File 18: MessageableChannelViewController+Lifecycle.swift** (~250 lines)
- `viewDidLoad()` and related setup
- `viewWillAppear(_:)`
- `viewDidAppear(_:)`
- `viewWillDisappear(_:)`
- `viewDidDisappear(_:)`
- `deinit`

**⚠️ Critical Considerations**:
- Must call setup methods in correct order
- Task cancellation in `viewDidDisappear`
- Memory cleanup coordination
- Manager initialization

**Risk Level**: 🟡 Medium - Depends on setup methods and cleanup logic

#### 5.3 Properties (Extract Only If Needed)

**File 19: MessageableChannelViewController+Properties.swift** (~200 lines)
- **⚠️ EXTRACT LAST**: Properties have complex interdependencies
- Property declarations (only if extraction is beneficial)
- Initialization methods
- Property accessors
- Target message protection properties and methods

**⚠️ Critical Considerations**:
- `targetMessageId` has `didSet` affecting multiple properties
- `localMessages` must stay synchronized with `viewModel.messages`
- Manager lazy properties depend on view controller initialization
- **Recommendation**: Keep most properties in main file unless extraction provides clear benefit

**Risk Level**: 🔴 High - Complex interdependencies

---

### Phase 6: Extract External Extensions

#### 6.1 MessageCell Extensions

**File 20: MessageCell+Extensions.swift** (~100 lines)
- `MessageCell` extensions (lines 8029-8034, 8488-8523)
- Image tap handling
- Reaction button extensions

#### 6.2 MessageInputView Extensions

**File 21: MessageInputView+Extensions.swift** (~100 lines)
- `MessageInputView` extensions (lines 8526-8555)
- Upload button extensions
- Reaction button extensions

**Risk Level**: 🟢 Low - External class extensions

---

### Phase 7: Main File Cleanup

**File 22: MessageableChannelViewController.swift** (~200-250 lines)
- Core class declaration
- Essential properties that must remain in main file
- Manager lazy properties
- Basic initialization
- Protocol conformances (delegate declarations)
- Import statements
- Documentation comments

---
- `viewDidLoad()` and related setup
- `viewWillAppear(_:)`
- `viewDidAppear(_:)`
- `viewWillDisappear(_:)`
- `viewDidDisappear(_:)`
- `deinit`
- Setup methods: `setupCustomHeader()`, `setupTableView()`, `setupMessageInput()`, `setupNewMessageButton()`, `setupSwipeGesture()`, `setupBindings()`, `setupKeyboardObservers()`, `setupAdditionalMessageObservers()`

**File 2: MessageableChannelViewController+Properties.swift** (~200 lines)
- All property declarations
- Initialization methods
- Property accessors
- Target message protection properties and methods

**File 3: MessageableChannelViewController+Setup.swift** (~250 lines)
- `setupCustomHeader()` implementation
- `setupTableView()` implementation
- `setupMessageInput()` implementation
- `setupNewMessageButton()` implementation
- `setupSwipeGesture()` implementation
- `setupBindings()` implementation
- `setupKeyboardObservers()` implementation
- `setupAdditionalMessageObservers()` implementation

#### 2.2 Message Loading Extensions

**File 4: MessageableChannelViewController+MessageLoading.swift** (~300 lines)
- `loadInitialMessages()` async
- `loadRegularMessages()` async
- `loadMoreMessages(before:server:messages:)`
- `loadNewerMessages(after:)`
- `refreshMessages(forceUpdate:)`
- `refreshWithTargetMessage(_:)` async
- `fetchReplyMessagesContent(for:)` async
- Message window enforcement methods

**File 5: MessageableChannelViewController+MessageHandling.swift** (~300 lines)
- `messagesDidChange(_:)` notification handler
- `handleNewMessages(_:)` notification handler
- `handleNewSocketMessage(_:)` notification handler
- `handleNetworkError(_:)` notification handler
- `handleChannelSearchClosed(_:)` notification handler
- `handleVideoPlayerDismiss(_:)` notification handler
- `handleSystemLog(_:)` notification handler
- `handleChannelSearchClosing(_:)` notification handler
- `handleMemoryWarning()` notification handler
- `checkForScrollNeeded()` timer method

#### 2.3 Scroll and Navigation Extensions

**File 6: MessageableChannelViewController+ScrollHandling.swift** (~300 lines)
- `scrollToBottom(animated:)` and related methods
- `scrollToTargetMessage()` and related target message scrolling
- `isUserNearBottom(threshold:)` and legacy version
- `loadMoreMessagesIfNeeded(for:)`
- `handleScrollEndForReplyPrefetch()`
- `positionTableAtBottomBeforeShowing()`
- `reloadTableViewMaintainingScrollPosition(messagesForDataSource:)`
- Scroll protection methods
- Note: `UIScrollViewDelegate` methods already in `MessageableChannelViewController+ScrollView.swift`

**File 7: MessageableChannelViewController+TargetMessage.swift** (~250 lines)
- Target message properties and state management
- `activateTargetMessageProtection(reason:)`
- `clearTargetMessageProtection(reason:)`
- `debugTargetMessageProtection()`
- `safeScrollToRow(at:at:animated:reason:)`
- `logScrollToBottomAttempt(animated:reason:)`
- Target message loading and scrolling logic

#### 2.4 UI Components Extensions

**File 8: MessageableChannelViewController+NewMessageButton.swift** (~150 lines)
- `setupNewMessageButton()` (if not in Setup)
- `newMessageButtonTapped()`
- `showNewMessageButton()`
- Related button state management

**File 9: MessageableChannelViewController+EmptyState.swift** (~200 lines)
- `showEmptyStateView()`
- `hideEmptyStateView()`
- `updateEmptyStateVisibility()`
- Empty state UI setup

**File 10: MessageableChannelViewController+SkeletonLoading.swift** (~200 lines)
- `showSkeletonView()`
- `hideSkeletonView()`
- `updateSkeletonView()`
- Skeleton loading state management

#### 2.5 Memory Management Extensions

**File 11: MessageableChannelViewController+MemoryManagement.swift** (~300 lines)
- `performInstantMemoryCleanup()`
- `performLightMemoryCleanup()`
- `performAggressiveMemoryCleanup()`
- `cleanupDMSpecificData(channelId:)`
- `enforceMessageLimits()`
- `checkMemoryUsageAndCleanup()`
- `startMemoryCleanupTimer()`
- `stopMemoryCleanupTimer()`
- `forceImmediateMemoryCleanup()`
- `performFinalInstantCleanup()`
- `logMemoryUsage(prefix:)`
- `setupMemoryLogging()`

#### 2.6 Reply Handling Extensions

**File 12: MessageableChannelViewController+Replies.swift** (~250 lines)
- `addReply(_:)`
- `removeReply(at:)`
- `clearReplies()`
- `fetchMessageForReply(messageId:channelId:)` async
- `fetchUserForMessage(userId:)` async
- `handleReplyClick(messageId:channelId:)`
- `showReplies(_:)`
- Reply-related UI updates

#### 2.7 Image and Media Extensions

**File 13: MessageableChannelViewController+ImageHandling.swift** (~200 lines)
- `showFullScreenImage(_:)`
- `nsfwOverlayViewDidConfirm(_:)`
- Image tap handling
- Full-screen image presentation

#### 2.8 Table View Extensions

**File 14: MessageableChannelViewController+TableViewUpdates.swift** (~250 lines)
- `refreshMessages(forceUpdate:)` implementation details
- `updateTableViewBouncing()`
- `adjustTableInsetsForMessageCount()`
- `enforceMessageWindow(keepingMostRecent:)`
- Table view data source updates
- Table view reload logic

#### 2.9 Utility Extensions

**File 15: MessageableChannelViewController+Utilities.swift** (~200 lines)
- `showErrorAlert(message:)`
- `getViewState() -> ViewState`
- `markLastMessageAsSeen()`
- `disableAutoAcknowledgment()`
- `resetLoadingStateIfNeeded()`
- `extractRetryAfterValue(from:)`
- Helper methods for message processing

**File 16: MessageableChannelViewController+Prefetching.swift** (~100 lines)
- `UITableViewDataSourcePrefetching` conformance
- `tableView(_:prefetchRowsAt:)`
- `tableView(_:cancelPrefetchingForRowsAt:)`

**File 17: MessageableChannelViewController+ScrollPosition.swift** (~150 lines)
- `reloadTableViewMaintainingScrollPosition(messagesForDataSource:)`
- Scroll position preservation logic
- Anchor message finding and restoration

#### 2.10 Helper Functions and Extensions

**File 18: MessageableChannelViewController+Helpers.swift** (~100 lines)
- `generateMessageLink(serverId:channelId:messageId:viewState:)` async
- Other standalone helper functions

**File 19: MessageCell+Extensions.swift** (~100 lines)
- `MessageCell` extensions (lines 8029-8034, 8488-8523)
- Image tap handling
- Reaction button extensions

**File 20: MessageInputView+Extensions.swift** (~100 lines)
- `MessageInputView` extensions (lines 8526-8555)
- Upload button extensions
- Reaction button extensions

---

### Phase 3: Main File Cleanup

**File 21: MessageableChannelViewController.swift** (~200-250 lines)
- Core class declaration
- Essential properties that must remain in main file
- Manager lazy properties
- Basic initialization
- Protocol conformances (delegate declarations)
- Import statements
- Documentation comments

---

## Implementation Order (Revised by Risk Level)

### Step 0: Pre-Refactoring Preparation ⚠️ REQUIRED
1. Complete Phase 0 tasks (state audit, memory audit, dependency mapping)
2. Set up testing infrastructure
3. Create dependency graphs
4. Document all risks and mitigation strategies

### Step 1: Extract Standalone Classes (Low Risk)
1. Extract `NSFWOverlayView` to `Views/NSFWOverlayView.swift`
2. Extract `MessageSkeletonView` to `Views/MessageSkeletonView.swift`
3. Extract `NotificationBanner` to `Views/NotificationBanner.swift`
4. **Test**: Build verification, basic functionality

### Step 2: Extract Low-Risk Extensions
1. Extract helpers and utilities (Files 1-2)
2. Extract protocol conformances (Files 3-4)
3. Extract UI components (Files 5-8)
4. **Test**: After each extraction - build, basic functionality

### Step 3: Extract Medium-Risk Extensions
1. Extract reply handling (File 9)
2. Extract table view updates (Files 10-11)
3. **Test**: After each extraction - integration tests, state synchronization

### Step 4: Extract High-Risk Extensions (One at a Time)
1. Extract message loading (File 12) - **Test thoroughly**
2. Extract message handling (File 13) - **Test thoroughly**
3. Extract scroll handling (File 14) - **Test thoroughly**
4. Extract target message (File 15) - **Test thoroughly**
5. Extract memory management (File 16) - **Test thoroughly**
6. **Test**: After each extraction - full integration tests, memory leak tests, performance tests

### Step 5: Extract Setup and Lifecycle (Last)
1. Extract setup methods (File 17)
2. Extract lifecycle methods (File 18)
3. Extract properties only if beneficial (File 19) - **Consider keeping in main file**
4. **Test**: Full integration tests, lifecycle tests

### Step 6: Extract External Extensions
1. Extract MessageCell extensions (File 20)
2. Extract MessageInputView extensions (File 21)
3. **Test**: Build verification

### Step 7: Clean Up Main File
1. Remove extracted code
2. Keep only essential class structure
3. Add import statements for new files
4. Verify all references work
5. Update documentation

### Step 8: Comprehensive Testing
1. Build and verify no compilation errors
2. Run full test suite (unit + integration)
3. Memory leak detection tests
4. Performance profiling (before/after comparison)
5. Manual testing of critical flows:
   - Message loading and pagination
   - Scroll behavior and position preservation
   - Target message navigation
   - Memory management and cleanup
   - Notification handling
   - Reply handling
   - Image handling
   - Empty state and skeleton loading

---

## File Size Estimates

| File | Estimated Lines | Status |
|------|----------------|--------|
| MessageableChannelViewController.swift (main) | ~200-250 | ✅ Target |
| +Lifecycle.swift | ~250 | ✅ Target |
| +Properties.swift | ~200 | ✅ Target |
| +Setup.swift | ~250 | ✅ Target |
| +MessageLoading.swift | ~300 | ✅ Target |
| +MessageHandling.swift | ~300 | ✅ Target |
| +ScrollHandling.swift | ~300 | ✅ Target |
| +TargetMessage.swift | ~250 | ✅ Target |
| +NewMessageButton.swift | ~150 | ✅ Target |
| +EmptyState.swift | ~200 | ✅ Target |
| +SkeletonLoading.swift | ~200 | ✅ Target |
| +MemoryManagement.swift | ~300 | ✅ Target |
| +Replies.swift | ~250 | ✅ Target |
| +ImageHandling.swift | ~200 | ✅ Target |
| +TableViewUpdates.swift | ~250 | ✅ Target |
| +Utilities.swift | ~200 | ✅ Target |
| +Prefetching.swift | ~100 | ✅ Target |
| +ScrollPosition.swift | ~150 | ✅ Target |
| +Helpers.swift | ~100 | ✅ Target |
| MessageCell+Extensions.swift | ~100 | ✅ Target |
| MessageInputView+Extensions.swift | ~100 | ✅ Target |
| NSFWOverlayView.swift | ~150 | ✅ Target |
| MessageSkeletonView.swift | ~100 | ✅ Target |
| **TOTAL** | **~4,200** | ✅ All under 300 |

---

## Critical Architectural Considerations

### State Synchronization Strategy

**Problem**: Complex state dependencies between:
- `localMessages` (view controller)
- `viewModel.messages` (Binding)
- `viewState.channelMessages[channelId]` (global state)
- `dataSource` (table view data source)

**Solution**:
1. Document all state mutation points in Phase 0
2. Ensure all state mutations are on `@MainActor`
3. Use `isDataSourceUpdating` flag to prevent concurrent updates
4. Consider creating `MessageStateCoordinator` if complexity grows
5. Add state synchronization tests before extracting message loading

**Implementation**:
- All state mutations must be on main thread
- Use `await MainActor.run { }` for async state updates
- Test state synchronization after each extraction

### Memory Management Strategy

**Problem**: 63+ `[weak self]` captures indicate complex memory management requirements.

**Solution**:
1. Audit all closures in Phase 0
2. Ensure all extracted methods maintain proper `[weak self]` captures
3. Document ownership semantics for each manager
4. Test for memory leaks after each extraction
5. Ensure task cancellation in lifecycle methods

**Implementation**:
- Use `[weak self]` in all closures that capture `self`
- Cancel all tasks in `viewDidDisappear`
- Test memory leaks using XCTest memory assertions
- Profile memory usage before/after refactoring

### Protocol Conformance Strategy

**Problem**: Multiple protocol conformances scattered throughout file.

**Solution**:
1. Consolidate protocol methods in dedicated extension files
2. Keep protocol conformance declarations in main file
3. Extract protocol method implementations to extensions
4. Test protocol conformance after extraction

**Implementation**:
- Create `MessageableChannelViewController+Delegates.swift` for delegate protocols
- Keep protocol declarations in main class
- Extract implementations to extensions

### Notification Handling Strategy

**Problem**: Heavy use of `NotificationCenter` with debouncing logic.

**Solution**:
1. Document all notification handlers in Phase 0
2. Consider creating `MessageableChannelNotificationCoordinator` if complexity grows
3. Maintain debouncing logic (`messageChangeDebounceInterval`)
4. Test notification handling after extraction

**Implementation**:
- Keep notification handlers in `MessageableChannelViewController+MessageHandling.swift`
- Document notification contracts
- Test notification debouncing behavior

### Task Management Strategy

**Problem**: Multiple concurrent async tasks requiring cancellation.

**Solution**:
1. Document all tasks in Phase 0
2. Ensure all tasks are cancelled in `viewDidDisappear`
3. Use structured concurrency where possible
4. Test task cancellation after extraction

**Implementation**:
- Cancel all tasks in lifecycle methods
- Use `Task.detached` only when necessary
- Test task lifecycle and cancellation

### Dependencies
- Some methods depend on properties in the main class
- Extensions can access all properties and methods from the main class
- Ensure proper access control (internal vs private)
- Document property dependencies in Phase 0

### Testing Strategy
- **Phase 0**: Set up test infrastructure
- Extract one extension at a time
- Test after each extraction:
  - Build verification
  - Unit tests (if applicable)
  - Integration tests for state synchronization
  - Memory leak tests for high-risk extractions
- Use git commits to track progress
- Roll back if issues arise
- Full test suite after all extractions

### Code Organization
- Keep related functionality together
- Maintain logical grouping
- Follow existing extension patterns (see `Extensions/` folder)
- Use clear, descriptive file names
- Create `REFACTORING_INDEX.md` mapping old line numbers to new files

### Potential Challenges
1. **Circular Dependencies**: Ensure extensions don't create circular references
2. **Property Access**: Some properties may need to be `internal` instead of `private`
3. **Manager Access**: Ensure managers are accessible from extensions
4. **State Management**: Maintain consistent state across extracted methods
5. **Thread Safety**: All state mutations must be on main thread
6. **Memory Leaks**: Test for retain cycles after each extraction
7. **Task Cancellation**: Ensure all tasks are properly cancelled
8. **Notification Handling**: Maintain debouncing and thread safety

### Benefits
- ✅ Improved code organization
- ✅ Easier to navigate and understand
- ✅ Better separation of concerns
- ✅ Easier to test individual components
- ✅ Reduced merge conflicts
- ✅ Better code review process

---

## Execution Checklist

### Phase 0: Pre-Refactoring Preparation ⚠️ REQUIRED
  - [ ] Create `REFACTORING_INDEX.md`, all updates should be added here so keep track of progress

### Phase 1: Extract Standalone Classes
- [ ] Extract NSFWOverlayView
- [ ] Extract MessageSkeletonView
- [ ] Extract NotificationBanner
- [ ] Test: Build verification, basic functionality

### Phase 2: Extract Low-Risk Extensions
- [ ] Extract helpers (File 1)
- [ ] Extract utilities (File 2)
- [ ] Extract prefetching (File 3)
- [ ] Extract delegates (File 4)
- [ ] Extract empty state (File 5)
- [ ] Extract skeleton loading (File 6)
- [ ] Extract new message button (File 7)
- [ ] Extract image handling (File 8)
- [ ] Test: After each extraction

### Phase 3: Extract Medium-Risk Extensions
- [ ] Extract replies (File 9)
- [ ] Extract table view updates (File 10)
- [ ] Extract scroll position (File 11)
- [ ] Test: Integration tests, state synchronization

### Phase 4: Extract High-Risk Extensions
- [x] Extract message loading (File 12) - **Test thoroughly**
- [ ] Extract message handling (File 13) - **Test thoroughly**
- [ ] Extract scroll handling (File 14) - **Test thoroughly**
- [ ] Extract target message (File 15) - **Test thoroughly**
- [ ] Extract memory management (File 16) - **Test thoroughly**
- [ ] Test: Full integration tests, memory leak tests, performance tests

### Phase 5: Extract Setup and Lifecycle
- [ ] Extract setup methods (File 17)
- [ ] Extract lifecycle methods (File 18)
- [ ] Extract properties (File 19) - **Only if beneficial**
- [ ] Test: Full integration tests, lifecycle tests

### Phase 6: Extract External Extensions
- [ ] Extract MessageCell extensions (File 20)
- [ ] Extract MessageInputView extensions (File 21)
- [ ] Test: Build verification

### Phase 7: Clean Up Main File
- [ ] Remove extracted code
- [ ] Keep only essential class structure
- [ ] Add import statements
- [ ] Verify all references work
- [ ] Update documentation
