//
//  MessageableChannelViewController.swift
//  Revolt
//

import Combine
import Kingfisher
import ObjectiveC
import SwiftUI
import Types
import UIKit
import ULID

// REFACTORING NOTE:
// The following components have been extracted to separate files:
// - ReplyMessage -> Models/ReplyMessage.swift
// - MessageableChannelConstants -> Models/MessageableChannelConstants.swift
// - MessageableChannelErrors -> Models/MessageableChannelErrors.swift
// - PermissionsManager -> Managers/PermissionsManager.swift
// - RepliesManager -> Managers/RepliesManager.swift
// - TypingIndicatorManager -> Managers/TypingIndicatorManager.swift
// - ScrollPositionManager -> Managers/ScrollPositionManager.swift
// - ToastView -> Views/ToastView.swift
// - NSFWOverlayView -> Views/NSFWOverlayView.swift
// - MessageInputHandler -> Utils/MessageInputHandler.swift
// - Extensions moved to separate files in Extensions/ folder

// MARK: - MessageableChannelViewController
class MessageableChannelViewController: UIViewController, UITextFieldDelegate,
    NSFWOverlayViewDelegate, UIGestureRecognizerDelegate
{
    var tableView: UITableView!
    var viewModel: MessageableChannelViewModel
    // Change the type of dataSource to accept both MessageTableViewDataSource and its subclasses
    var dataSource: UITableViewDataSource!
    private var cancellables = Set<AnyCancellable>()

    // IMPORTANT NEW PROPERTY: Local copy of messages that we control completely
    var localMessages: [String] = []

    // Properties needed for NSFW handling
    internal var over18HasSeen: Bool = false
    var isLoadingMore: Bool = false

    // Skeleton loading view
    internal var skeletonView: MessageSkeletonView?

    // Add a variable to track the exact loading state
    enum LoadingState: Equatable {
        case loading
        case notLoading
    }

    // Store loading task separately
    internal var loadingTask: Task<Void, Never>? = nil
    var messageLoadingState: LoadingState = .notLoading

    // Variable to track the time of last successful request
    var lastSuccessfulLoadTime: Date = .distantPast

    // CRITICAL FIX: Add property to track when API returns empty messages
    var lastEmptyResponseTime: Date?

    // CRITICAL: Add flag to protect against scrolling during data source updates
    var isDataSourceUpdating: Bool = false

    // Properties moved from managers for compatibility
    var scrollToBottomWorkItem: DispatchWorkItem?
    var lastManualScrollTime: Date?
    var lastManualScrollUpTime: Date?
    var scrollProtectionTimer: Timer?
    var scrollCheckTimer: Timer?
    var contentSizeObserverRegistered = false
    var lastScrollToBottomTime: Date?
    let scrollDebounceInterval: TimeInterval = 2.0
    var networkErrorCooldown: TimeInterval = 5.0
    var maxLogMessages = 20
    var minimumAPICallInterval: TimeInterval = 3.0

    // Replies view properties
    internal var repliesView: RepliesContainerView?

    // Custom navigation header
    var headerView: UIView!
    internal var backButton: UIButton!
    internal var channelNameLabel: UILabel!
    internal var channelIconView: UIImageView!
    internal var searchButton: UIButton!

    // Track keyboard state
    var keyboardHeight: CGFloat = 0
    var isKeyboardVisible = false

    // Message input
    var messageInputView: MessageInputView!
    var messageInputBottomConstraint: NSLayoutConstraint!

    // New Message Indicator
    var newMessageButton: UIButton!
    var hasUnreadMessages: Bool = false

    // Replies container view - now managed by RepliesManager
    var replies: [ReplyMessage] = []  // Made public for Manager access

    // Toggle sidebar callback
    var toggleSidebar: (() -> Void)?

    // Track whether we're returning from search to prevent unnecessary cleanup
    var isReturningFromSearch: Bool = false
    
    var isViewDisappearing: Bool = false

    // Target message ID to scroll to
    var targetMessageId: String? {
        didSet {
            print(
                "🎯 MessageableChannelViewController: targetMessageId changed from \(oldValue ?? "nil") to \(targetMessageId ?? "nil")"
            )

            // Reset the processed flag when targetMessageId changes
            if targetMessageId != oldValue {
                targetMessageProcessed = false
                print("🎯 Reset targetMessageProcessed to false")

                // CRITICAL FIX: Clear any existing timer to prevent multiple clearing
                clearTargetMessageTimer?.invalidate()
                clearTargetMessageTimer = nil
            }
        }
    }

    // Flag to track if we've already processed the current target message
    internal var targetMessageProcessed: Bool = false

    // Timer to clear target message ID
    internal var clearTargetMessageTimer: Timer?

    // Track when target message was last highlighted to prevent auto-scroll
    internal var lastTargetMessageHighlightTime: Date?

    // Track if user reached this position via target message (to prevent auto-reload)
    internal var isInTargetMessagePosition: Bool = false

    // SIMPLIFIED TARGET MESSAGE PROTECTION
    // User can scroll freely anywhere without clearing protection
    internal var targetMessageProtectionActive: Bool {
        return targetMessageId != nil || isInTargetMessagePosition || targetMessageProcessed
    }

    // Add class-level variable to prevent duplicate API calls
    internal static var loadingChannels = Set<String>()
    internal static var loadingMutex = NSLock()

    // Add a new property that tracks if we have already scrolled to the target message

    // Public accessor for ViewState to be used by ReplyItemView
    func getViewState() -> ViewState {
        return viewModel.viewState
    }

    // MARK: - Managers
    lazy var permissionsManager = PermissionsManager(viewModel: viewModel, viewController: self)
    private lazy var repliesManager = RepliesManager(viewModel: viewModel, viewController: self)
    private lazy var typingIndicatorManager = TypingIndicatorManager(
        viewModel: viewModel, viewController: self)
    internal lazy var scrollPositionManager = ScrollPositionManager(viewController: self)
    internal lazy var messageInputHandler = MessageInputHandler(
        viewModel: viewModel, viewController: self, repliesManager: repliesManager)

    // MARK: - Public Properties for Manager Access
    // lastManualScrollUpTime is defined as stored property above

    // Add a private property to monitor recent log messages after class declaration
    private var recentLogMessages = [String]()
    private var lastNetworkErrorTime: Date?

    // CRITICAL: Add debounce mechanism to prevent infinite notification loops
    private var lastMessageChangeNotificationTime: Date = .distantPast
    private let messageChangeDebounceInterval: TimeInterval = 0.5  // 500ms minimum between processing notifications

    // Add these properties after other properties
    // Rate limiting properties
    private var lastAPICallTime: Date = .distantPast
    internal var pendingAPICall: DispatchWorkItem?
    private var isThrottled = false

    // Track if returning from search to prevent unwanted scrolling
    internal var wasInSearch = false

    // CRITICAL MEMORY MANAGEMENT: Add message count limits to prevent memory issues
    private let maxLocalMessagesInMemory = 400
    private let maxViewStateMessagesPerChannel = 400
    private let memoryCleanupThreshold = 400

    // Add this property to track the last before message id
    internal var lastBeforeMessageId: String? = nil

    // JUMPING FIX: Track inset adjustments to prevent excessive calls
    private var lastInsetAdjustmentTime: Date = .distantPast
    private var lastMessageCountForInsets: Int = 0
    private let insetAdjustmentCooldown: TimeInterval = 1.0  // 1 second cooldown

    // MEMORY MANAGEMENT: Automatic cleanup timer
    private var memoryCleanupTimer: Timer?
    private let memoryCleanupInterval: TimeInterval = 30.0  // Clean up every 30 seconds

    // Add this property to track if we're currently loading older messages
    internal var isLoadingOlderMessages = false

    // Track scroll position for infinite scroll down detection
    internal var lastScrollOffset: CGFloat = 0

    // Flag to prevent concurrent cleanup operations
    private var isCleaningUp = false

    init(viewModel: MessageableChannelViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    init(
        viewModel: MessageableChannelViewModel, toggleSidebar: (() -> Void)? = nil,
        targetMessageId: String? = nil
    ) {
        self.viewModel = viewModel
        self.toggleSidebar = toggleSidebar
        self.targetMessageId = targetMessageId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Match bgDefaultPurple13 color
        view.backgroundColor = .bgDefaultPurple13

        // Make sure we extend to all edges of the screen including notch area
        edgesForExtendedLayout = .all

        // Hide navigation bar if presented in a navigation controller
        navigationController?.setNavigationBarHidden(true, animated: false)

        // Hide status bar
        setNeedsStatusBarAppearanceUpdate()

        // Set this view to ignore safe area insets
        additionalSafeAreaInsets = .zero

        // Configure view to extend under system UI elements
        if #available(iOS 11.0, *) {
            // Ensure content extends to edges
            view.insetsLayoutMarginsFromSafeArea = false
        }

        setupCustomHeader()
        setupTableView()
        setupMessageInput()
        setupNewMessageButton()  // Add new message button
        setupSwipeGesture()  // Add swipe gesture for back navigation
        setupBindings()
        setupKeyboardObservers()
        setupAdditionalMessageObservers()  // Add additional message observer

        // Initialize managers (typing indicator setup is handled automatically)
        _ = typingIndicatorManager

        // Configure UI based on permissions
        permissionsManager.configureUIBasedOnPermissions()

        // Initialize message count tracking
        lastKnownMessageCount = localMessages.count
        // print("🚀 INIT: Set initial lastKnownMessageCount to \(lastKnownMessageCount)")

        // CRITICAL FIX: Reset empty response time for new channel
        lastEmptyResponseTime = nil
        print("🔄 INIT: Reset lastEmptyResponseTime for new channel")

        // CRITICAL FIX: Check if we have a target message from ViewState before loading
        // Don't load regular messages if we have a target message to avoid duplicate API calls
        if let targetFromViewState = viewModel.viewState.currentTargetMessageId {
            print(
                "🎯 VIEW_DID_LOAD: Target message found in ViewState: \(targetFromViewState), skipping regular load"
            )
            targetMessageId = targetFromViewState
            targetMessageProcessed = false
        } else {
            // Force an initial load of messages only if no target message
            print("📜 VIEW_DID_LOAD: No target message, loading regular messages")
            Task {
                await loadInitialMessages()
            }
        }

        // Check if the channel is NSFW
        if viewModel.channel.nsfw && !self.over18HasSeen {
            self.over18HasSeen = true
            showNSFWOverlay()
        }

        // Add observer for system log messages that might indicate network issues
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemLog),
            name: NSNotification.Name("SystemLogMessage"),
            object: nil
        )

        // Add observer for when user is closing search to return to channel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChannelSearchClosing),
            name: NSNotification.Name("ChannelSearchClosing"),
            object: nil
        )
    }

    @objc internal func newMessageButtonTapped() {
        // Function to scroll to new message and hide the button
        scrollToBottom(animated: true)

        // Hide the button with animation
        UIView.animate(withDuration: 0.3) {
            self.newMessageButton.alpha = 0
        } completion: { _ in
            self.newMessageButton.isHidden = true
            self.hasUnreadMessages = false
        }
    }

    internal func showNewMessageButton() {
        // If the button is already displayed, do nothing
        if !newMessageButton.isHidden && newMessageButton.alpha > 0 {
            return
        }

        // Show button with animation
        newMessageButton.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.newMessageButton.alpha = 1
        }

        hasUnreadMessages = true

        // If no click on the button for a few seconds, automatically hide it
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            // Only hide if still showing
            if !self.newMessageButton.isHidden && self.newMessageButton.alpha > 0 {
                UIView.animate(withDuration: 0.3) {
                    self.newMessageButton.alpha = 0
                } completion: { _ in
                    self.newMessageButton.isHidden = true
                }
            }
        }
    }

    // Always hide status bar to maximize screen space
    override var prefersStatusBarHidden: Bool {
        return true
    }


    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Hide navigation bar if presented in a navigation controller
        navigationController?.setNavigationBarHidden(true, animated: animated)

        // If inside a tab bar controller, hide the tab bar
        tabBarController?.tabBar.isHidden = true

        // Make sure we extend to all edges, including safe areas at top and bottom
        if #available(iOS 11.0, *) {
            // Set the content to extend under the safe areas
            tableView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }

        // Update bouncing behavior in viewWillAppear
        updateTableViewBouncing()
    }

    /// Performs INSTANT memory cleanup - no delays, no async operations

    internal func performInstantMemoryCleanup() {
        let channelId = viewModel.channel.id
        print("⚡ INSTANT_CLEANUP: Starting IMMEDIATE memory cleanup for channel \(channelId)")

        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. IMMEDIATE: Clear all local data synchronously
        self.localMessages.removeAll(keepingCapacity: false)
        viewModel.messages.removeAll(keepingCapacity: false)

        // 2. IMMEDIATE: Clear ViewState data synchronously (no Task, no async)
        viewModel.viewState.channelMessages.removeValue(forKey: channelId)
        viewModel.viewState.preloadedChannels.remove(channelId)
        viewModel.viewState.atTopOfChannel.remove(channelId)
        viewModel.viewState.currentlyTyping.removeValue(forKey: channelId)

        // 3. IMMEDIATE: Remove all message objects for this channel
        let messagesToRemove = viewModel.viewState.messages.keys.filter { messageId in
            if let message = viewModel.viewState.messages[messageId] {
                return message.channel == channelId
            }
            return false
        }

        for messageId in messagesToRemove {
            viewModel.viewState.messages.removeValue(forKey: messageId)
        }

        print("⚡ INSTANT_CLEANUP: Removed \(messagesToRemove.count) message objects immediately")

        // 4. IMMEDIATE: Clear table view and data source
        self.dataSource = nil

        // 5. IMMEDIATE: Reset all state variables
        isInTargetMessagePosition = false
        targetMessageProcessed = false
        isLoadingMore = false
        messageLoadingState = .notLoading

        // 6. IMMEDIATE: Force memory cleanup without autoreleasepool delays
        ImageCache.default.clearMemoryCache()

        // 7. IMMEDIATE: Call ViewState instant cleanup (no async operations)
        viewModel.viewState.cleanupChannelFromMemory(
            channelId: channelId, preserveForNavigation: false)

        // 8. IMMEDIATE: Force garbage collection
        _ = viewModel.viewState.messages.count + viewModel.viewState.users.count

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000  // Convert to milliseconds

        print(
            "⚡ INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms - IMMEDIATE cleanup done!"
        )
    }

    /// Performs light memory cleanup for cross-channel navigation
    private func performLightMemoryCleanup() {
        print("🧹 LIGHT_CLEANUP: Starting light memory cleanup")

        let channelId = viewModel.channel.id

        // Clear only local view controller data
        self.localMessages.removeAll()
        viewModel.messages.removeAll()

        // Clear preloaded status to allow reloading
        viewModel.viewState.preloadedChannels.remove(channelId)

        // For light cleanup, preserve ViewState messages but clear channel message list
        // This allows the messages to be reloaded when returning to the channel
        viewModel.viewState.channelMessages.removeValue(forKey: channelId)

        // Clear table view data source
        if let dataSource = self.dataSource as? LocalMessagesDataSource {
            dataSource.updateMessages([])
        }

        // Reset view controller state
        isInTargetMessagePosition = false
        targetMessageProcessed = false

        print("🧹 LIGHT_CLEANUP: Completed - preserved ViewState messages for navigation")
    }

    /// Performs aggressive memory cleanup when fully leaving channel
    private func performAggressiveMemoryCleanup() {
        print("🧹 AGGRESSIVE_CLEANUP: Starting aggressive memory cleanup")

        let channelId = viewModel.channel.id
        let isDM = viewModel.channel.isDM
        let isGroupDM = viewModel.channel.isGroupDmChannel

        // 1. Clear all local data immediately
        self.localMessages.removeAll()
        viewModel.messages.removeAll()

        // 2. Use ViewState's comprehensive cleanup method
        Task { @MainActor in
            self.viewModel.viewState.cleanupChannelFromMemory(
                channelId: channelId, preserveForNavigation: false)
        }

        // 3. Special cleanup for DMs (additional local cleanup)
        if isDM || isGroupDM {
            cleanupDMSpecificData(channelId: channelId)
        }

        // 4. Clear table view data
        if let dataSource = self.dataSource as? LocalMessagesDataSource {
            dataSource.updateMessages([])
        }

        // 5. Force memory cleanup
        autoreleasepool {
            // Clear image cache for this channel
            ImageCache.default.clearMemoryCache()

            // Force garbage collection
            _ = viewModel.viewState.messages.count
        }

        print("🧹 AGGRESSIVE_CLEANUP: Completed - removed all channel data from memory")
    }

    /// Cleanup DM-specific data and unused user objects
    private func cleanupDMSpecificData(channelId: String) {
        guard let channel = viewModel.viewState.channels[channelId] else { return }

        print("🧹 DM_CLEANUP: Cleaning up DM-specific data for channel \(channelId)")

        // Get recipient IDs for this DM
        let recipientIds = channel.recipients

        // Determine which users can be safely removed
        var usersToKeep = Set<String>()

        // Always keep current user
        if let currentUserId = viewModel.viewState.currentUser?.id {
            usersToKeep.insert(currentUserId)
        }

        // Keep users needed for other active channels
        for (otherChannelId, messageIds) in viewModel.viewState.channelMessages {
            if otherChannelId == channelId { continue }

            // Keep users from other DMs
            if let otherChannel = viewModel.viewState.channels[otherChannelId] {
                usersToKeep.formUnion(otherChannel.recipients)
            }

            // Keep message authors from other channels
            for messageId in messageIds {
                if let message = viewModel.viewState.messages[messageId] {
                    usersToKeep.insert(message.author)
                    if let mentions = message.mentions {
                        usersToKeep.formUnion(mentions)
                    }
                }
            }
        }

        // Keep users needed for servers
        for server in viewModel.viewState.servers.values {
            usersToKeep.insert(server.owner)
            // Keep members of servers
            if let serverMembers = viewModel.viewState.members[server.id] {
                usersToKeep.formUnion(serverMembers.keys)
            }
        }

        // Remove users that are no longer needed
        let usersToRemove = recipientIds.filter { userId in
            !usersToKeep.contains(userId) && userId != viewModel.viewState.currentUser?.id
        }

        if !usersToRemove.isEmpty {
            print("🧹 DM_CLEANUP: Removing \(usersToRemove.count) unused users from memory")
            for userId in usersToRemove {
                viewModel.viewState.users.removeValue(forKey: userId)

                // Also remove from members if they exist
                for serverId in viewModel.viewState.members.keys {
                    viewModel.viewState.members[serverId]?.removeValue(forKey: userId)
                }
            }
        } else {
            print("🧹 DM_CLEANUP: All users are still needed, keeping them")
        }

        // Clear any DM-specific caches
        // Note: Keep the channel object itself for future conversations
        print("🧹 DM_CLEANUP: Completed DM cleanup")
    }

    // CRITICAL: Add automatic memory management to prevent crashes
    private func enforceMessageLimits() {
        // DISABLED: Memory cleanup was causing UI freezes
        // Don't perform any message limit enforcement while in the channel
        return
    }

    // Check if we need memory cleanup
    private func checkMemoryUsageAndCleanup() {
        // DISABLED: Memory cleanup was causing UI freezes
        // Don't perform any memory cleanup checks while in the channel
        return
    }

    // Start automatic memory cleanup timer
    internal func startMemoryCleanupTimer() {
        // DISABLED: Memory cleanup was causing UI freezes
        // Don't start any automatic cleanup timers while in the channel
        return
    }

    // Stop memory cleanup timer
    internal func stopMemoryCleanupTimer() {
        memoryCleanupTimer?.invalidate()
        memoryCleanupTimer = nil
        // Keep the timer invalidation but remove the print
    }

    // Helper method to log memory usage
    func logMemoryUsage(prefix: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            // print("📊 MEMORY USAGE [\(prefix)]: \(String(format: "%.2f", usedMB)) MB")
            // print("   - Messages in viewState: \(viewModel.viewState.messages.count)")
            // print("   - Users in viewState: \(viewModel.viewState.users.count)")
            // print("   - Channel messages count: \(viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0)")
            // print("   - Local messages count: \(localMessages.count)")
            // print("   - Servers: \(viewModel.viewState.servers.count)")
            // print("   - Members dictionaries: \(viewModel.viewState.members.count)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure our view covers the entire screen
        view.frame = UIScreen.main.bounds

        // Update table view bouncing behavior when layout changes
        if tableView.window != nil {
            updateTableViewBouncing()
        }
    }

    @objc internal func backButtonTapped() {
        print(
            "🔙 BACK_BUTTON: Tapped - Channel: \(viewModel.channel.id), Server: \(viewModel.channel.server ?? "nil")"
        )
        print("🔙 BACK_BUTTON: Channel type: \(type(of: viewModel.channel))")
        print("🔙 BACK_BUTTON: Current path count: \(viewModel.viewState.path.count)")
        print("🔙 BACK_BUTTON: Current path: \(viewModel.viewState.path)")
        print(
            "🔙 BACK_BUTTON: lastInviteServerContext: \(viewModel.viewState.lastInviteServerContext ?? "nil")"
        )
        print("🔙 BACK_BUTTON: currentSelection: \(viewModel.viewState.currentSelection)")
        print("🔙 BACK_BUTTON: currentChannel: \(viewModel.viewState.currentChannel)")

        // CRITICAL FIX: For channels with navigation path containing only maybeChannelView(s) (likely from invite),
        // clear path to show appropriate sidebar/main view instead of previous screen
        let isOnlyChannelViews = viewModel.viewState.path.allSatisfy { destination in
            if case .maybeChannelView = destination {
                return true
            }
            return false
        }

        print("🔙 BACK_BUTTON: isOnlyChannelViews: \(isOnlyChannelViews)")
        print("🔙 BACK_BUTTON: path.isEmpty: \(viewModel.viewState.path.isEmpty)")

        if isOnlyChannelViews && !viewModel.viewState.path.isEmpty {
            if let serverId = viewModel.channel.server {
                // Server channel case
                print(
                    "🔙 BACK_BUTTON: Detected invite-style navigation (server channel with only maybeChannelViews)"
                )
                print("🔙 BACK_BUTTON: ServerId: \(serverId)")
                print("🔙 BACK_BUTTON: Clearing path and selecting server \(serverId)")

                // Clear the navigation path completely
                viewModel.viewState.path.removeAll()

                // Clear invite context if it exists
                viewModel.viewState.lastInviteServerContext = nil

                // Make sure the correct server is selected
                viewModel.viewState.selectServer(withId: serverId)

                // NEW FIX: Force channel list refresh after selecting server to prevent empty lists
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.viewModel.viewState.objectWillChange.send()
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ForceChannelListRefresh"),
                        object: ["serverId": serverId])
                }

                print(
                    "🔙 BACK_BUTTON: After selectServer - currentSelection: \(viewModel.viewState.currentSelection)"
                )
                print(
                    "🔙 BACK_BUTTON: After selectServer - currentChannel: \(viewModel.viewState.currentChannel)"
                )
                print("🔙 BACK_BUTTON: Completed invite-style back navigation for server channel")
            } else {
                // DM or other non-server channel case
                print(
                    "🔙 BACK_BUTTON: Detected invite-style navigation (non-server channel with only maybeChannelViews)"
                )
                print("🔙 BACK_BUTTON: Clearing path to return to DMs/main view")

                // Clear the navigation path completely
                viewModel.viewState.path.removeAll()

                // Clear invite context if it exists
                viewModel.viewState.lastInviteServerContext = nil

                // Navigate to DMs view
                viewModel.viewState.selectDms()

                // NEW FIX: Force DM list refresh after selecting DMs to prevent empty lists
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.viewModel.viewState.objectWillChange.send()
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ForceDMListRefresh"), object: nil)
                }

                print("🔙 BACK_BUTTON: Set currentSelection to DMs")
                print(
                    "🔙 BACK_BUTTON: Completed invite-style back navigation for non-server channel")
            }
            return
        }

        print("🔙 BACK_BUTTON: Using normal navigation path.removeLast()")

        // For normal navigation with multiple path items, use path.removeLast()
        if !viewModel.viewState.path.isEmpty {
            viewModel.viewState.path.removeLast()
            print(
                "🔙 BACK_BUTTON: Removed last path item, new count: \(viewModel.viewState.path.count)"
            )
        } else {
            // Fallback: If no navigation path, try UIKit navigation or toggle sidebar
            print("🔙 BACK_BUTTON: No navigation path, using fallback")
            if let navigationController = navigationController {
                navigationController.popViewController(animated: true)
            } else {
                dismiss(animated: true)
            }

            // Call toggle sidebar if available
            toggleSidebar?()
        }
    }

    @objc internal func searchButtonTapped() {
        // Set flag to track that we're going to search
        wasInSearch = true
        isReturningFromSearch = false

        // Navigate to the channel search page
        viewModel.viewState.path.append(NavigationDestination.channel_search(viewModel.channel.id))
    }

    @objc internal func channelHeaderTapped() {
        // Only show server info if this channel belongs to a server
        guard let serverId = viewModel.channel.server,
            let server = viewModel.viewState.servers[serverId]
        else {
            // print("Channel does not belong to a server or server not found")
            return
        }

        presentServerInfoSheet(for: server)
    }

    // Make sure to remove observers in deinit
    deinit {
        // print("🗑️ DEINIT: MessageableChannelViewController is being deallocated")

        // CRITICAL: Clear target message ID and highlight time to prevent re-targeting
        lastTargetMessageHighlightTime = nil
        isInTargetMessagePosition = false
        print("🎯 DEINIT: Clearing currentTargetMessageId to prevent re-targeting")

        NotificationCenter.default.removeObserver(self)

        // Cancel scroll protection timer
        scrollProtectionTimer?.invalidate()
        scrollProtectionTimer = nil

        // Stop memory cleanup timer
        memoryCleanupTimer?.invalidate()
        memoryCleanupTimer = nil

        // CRITICAL FIX: Invalidate scroll check timer to prevent memory leak
        scrollCheckTimer?.invalidate()
        scrollCheckTimer = nil

        // Cancel any pending scroll operations
        scrollToBottomWorkItem?.cancel()
        scrollToBottomWorkItem = nil

        // Cancel any pending API calls
        loadingTask?.cancel()
        loadingTask = nil

        pendingAPICall?.cancel()
        pendingAPICall = nil

        // Add contentSize observer removal if it exists
        if contentSizeObserverRegistered {
            tableView.removeObserver(self, forKeyPath: "contentSize")
            contentSizeObserverRegistered = false
        }

        // CRITICAL MEMORY FIX: Clear all message arrays to prevent memory leaks
        let messageCount = localMessages.count

        // Clear local arrays immediately
        localMessages.removeAll()
        recentLogMessages.removeAll()

        // Use Task for actor-isolated properties
        Task { @MainActor [weak viewModel] in
            guard let viewModel = viewModel else { return }

            // Store channel ID inside Task to avoid actor isolation issues
            let channelId = viewModel.channel.id

            // CRITICAL: Clear target message ID in ViewState
            viewModel.viewState.currentTargetMessageId = nil
            print("🎯 DEINIT TASK: Cleared currentTargetMessageId from ViewState")

            // Get message IDs before clearing
            let messageIds = viewModel.messages

            viewModel.messages.removeAll()

            // Clear channel messages from viewState
            viewModel.viewState.channelMessages[channelId]?.removeAll()

            // Also remove the actual message objects from viewState.messages dictionary
            for messageId in messageIds {
                viewModel.viewState.messages.removeValue(forKey: messageId)
            }

            // Clear image cache
            ImageCache.default.clearMemoryCache()

            // print("🗑️ DEINIT CLEANUP: Removed \(messageIds.count) message objects from viewState")
        }

        // Clear table view references
        tableView?.dataSource = nil
        dataSource = nil

        // Clear skeleton view if it exists
        skeletonView?.removeFromSuperview()
        skeletonView = nil

        // CRITICAL FIX: Cleanup MessageInputView to clear strong references
        messageInputView?.cleanup()
        messageInputView = nil

        // Clear managers that might hold references
        // (Note: These are lazy vars, so they'll be cleared automatically if not accessed)

        // print("🗑️ DEINIT: Cleanup completed - freed \(messageCount) messages from memory")
    }
    
    private func presentServerInfoSheet(for server: Server) {
        // Create the ServerInfoSheet with required parameters
        let serverInfoSheet = ServerInfoSheet(
            isPresentedServerSheet: .constant(true),
            server: server,
            onNavigation: { [weak self] route, serverId in
                guard let self = self else { return }

                // First dismiss the current modal
                self.dismiss(animated: true) {
                    // Handle navigation after dismissal
                    DispatchQueue.main.async {
                        switch route {
                        case .overview:
                            self.viewModel.viewState.path.append(
                                NavigationDestination.server_overview_settings(serverId))
                        case .channels:
                            self.viewModel.viewState.path.append(
                                NavigationDestination.server_channels(serverId))
                        case .roles:
                            self.viewModel.viewState.path.append(
                                NavigationDestination.server_role_setting(serverId))
                        case .emojis:
                            self.viewModel.viewState.path.append(
                                NavigationDestination.server_emoji_settings(serverId))
                        case .members:
                            self.viewModel.viewState.path.append(
                                NavigationDestination.server_members_view(serverId))
                        case .invite:
                            self.viewModel.viewState.path.append(
                                NavigationDestination.server_invites(serverId))
                        case .banned:
                            self.viewModel.viewState.path.append(
                                NavigationDestination.server_banned_users(serverId))
                        }
                    }
                }
            }
        )

        // Wrap the SwiftUI view in a UIHostingController
        let hostingController = UIHostingController(
            rootView: serverInfoSheet.environmentObject(viewModel.viewState))

        // Configure the presentation style
        hostingController.modalPresentationStyle = .pageSheet

        // Present the sheet
        present(hostingController, animated: true, completion: nil)
    }

    

    @objc internal func handleSwipeGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .changed:
            // Only allow left-to-right swipe (positive x translation)
            if translation.x > 0 {
                // Optional: Add visual feedback here if desired
                // For example, you could slightly move the view or add a shadow
            }
        case .ended:
            // Check if the swipe was significant enough (distance and velocity)
            let swipeThreshold: CGFloat = 100  // Minimum distance
            let velocityThreshold: CGFloat = 500  // Minimum velocity

            if translation.x > swipeThreshold && velocity.x > velocityThreshold {
                // Trigger back navigation
                backButtonTapped()
            }
        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow the swipe gesture to work simultaneously with table view scrolling
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
            let translation = panGesture.translation(in: view)
            let velocity = panGesture.velocity(in: view)

            // Only recognize horizontal swipes that are more horizontal than vertical
            // and are moving from left to right
            return abs(velocity.x) > abs(velocity.y) && velocity.x > 0 && translation.x > 0
        }
        return true
    }

    // SUPER FAST: Simplified message change handler
    @objc internal func messagesDidChange(_ notification: Notification) {
        // Debounce rapid notifications
        let now = Date()
        guard now.timeIntervalSince(lastMessageChangeNotificationTime) >= 0.1 else { return }
        lastMessageChangeNotificationTime = now

        // Check if this is a reaction update
        var isReactionUpdate = false
        var reactionChannelId: String? = nil
        var reactionMessageId: String? = nil

        if let notificationData = notification.object as? [String: Any] {
            reactionChannelId = notificationData["channelId"] as? String
            reactionMessageId = notificationData["messageId"] as? String
            let updateType = notificationData["type"] as? String
            isReactionUpdate = updateType == "reaction_added" || updateType == "reaction_removed"
        }

        // For reaction updates, handle them immediately without blocking conditions
        if isReactionUpdate {
            print(
                "🔥 CONTROLLER: Processing reaction update for channel \(reactionChannelId ?? "unknown"), message \(reactionMessageId ?? "unknown")"
            )
            // Process reaction updates immediately since they don't interfere with loading states
            // and should always update the UI when received from the backend
        } else {
            // CRITICAL FIX: Don't process regular message changes during nearby loading
            if messageLoadingState == .loading {
                print("🔄 BLOCKED: messagesDidChange blocked - nearby loading in progress")
                return
            }

            // CRITICAL FIX: Don't process regular message changes if target message protection is active
            if targetMessageProtectionActive {
                print("🔄 BLOCKED: messagesDidChange blocked - target message protection active")
                return
            }
        }

        // For reaction updates, check if it's for this channel
        if isReactionUpdate {
            guard let channelId = reactionChannelId, channelId == viewModel.channel.id else {
                return
            }
            if let messageId = reactionMessageId,
                let messageIndex = localMessages.firstIndex(of: messageId),
                messageIndex < tableView.numberOfRows(inSection: 0)
            {

                let indexPath = IndexPath(row: messageIndex, section: 0)
                let isLastMessage = messageIndex == localMessages.count - 1
                let wasNearBottom = isUserNearBottom(threshold: 80)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    print(
                        "🔥 RELOADING ROW: Reloading row \(indexPath.row) for message \(messageId)")

                    // Force check if message has been updated in ViewState
                    if let updatedMessage = self.viewModel.viewState.messages[messageId] {
                        print(
                            "🔥 FORCE CHECK: Message \(messageId) reactions in ViewState: \(updatedMessage.reactions?.keys.joined(separator: ", ") ?? "none")"
                        )
                    } else {
                        print("🔥 FORCE CHECK: Message \(messageId) not found in ViewState!")
                    }

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                    self.tableView.layoutIfNeeded()

                    // CRITICAL FIX: Don't auto-scroll if target message was recently highlighted
                    if let highlightTime = self.lastTargetMessageHighlightTime,
                        Date().timeIntervalSince(highlightTime) < 10.0
                    {
                        return
                    }

                    // Only if last message and user is at bottom, check if it went under keyboard
                    if isLastMessage && wasNearBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard let cellRect = self.tableView.cellForRow(at: indexPath)?.frame
                            else { return }
                            let visibleHeight =
                                self.tableView.frame.height
                                - (self.isKeyboardVisible ? self.keyboardHeight : 0)
                            let cellBottom = cellRect.maxY - self.tableView.contentOffset.y
                            if cellBottom > visibleHeight {
                                // If cell bottom is below visible area, scroll to show it completely
                                let targetOffset = max(cellRect.maxY - visibleHeight + 20, 0)
                                self.tableView.setContentOffset(
                                    CGPoint(x: 0, y: targetOffset), animated: true)
                            }
                        }
                    }
                }
            } else {
                refreshMessages(forceUpdate: true)  // Force update for reactions
            }
            return
        }

        // Skip if wrong channel (for regular message updates)
        if let sender = notification.object as? MessageableChannelViewModel,
            sender.channel.id != viewModel.channel.id
        {
            return
        }

        // Skip if no actual change (for regular message updates)
        let newCount = viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0
        guard newCount != lastKnownMessageCount else { return }
        lastKnownMessageCount = newCount

        // Skip if user is scrolling (for regular message updates)
        guard !tableView.isDragging, !tableView.isDecelerating else { return }

        // Use lightweight refresh
        refreshMessages()
    }

    // Legacy method for compatibility (can be removed after testing)
    private func scrollToBottomLegacy(animated: Bool) {
        guard !isViewDisappearing else { return }
        // First check if we have messages
        // print("🔽 SCROLL_TO_BOTTOM: Starting forced scroll to bottom (animated: \(animated))")

        // CRITICAL: Don't auto-scroll if user is manually scrolling or recently scrolled up
        if tableView.isDragging || tableView.isDecelerating {
            // print("🔽 SCROLL_TO_BOTTOM: User is manually scrolling, cancelling auto-scroll")
            return
        }

        // Don't scroll if user manually scrolled up in the last 5 seconds
        if let lastScrollUpTime = lastManualScrollUpTime,
            Date().timeIntervalSince(lastScrollUpTime) < 5.0
        {
            // print("🔽 SCROLL_TO_BOTTOM: User scrolled up recently (\(Date().timeIntervalSince(lastScrollUpTime))s ago), cancelling auto-scroll")
            return
        }

        // Don't scroll if we're currently loading more messages
        if isLoadingMore {
            // print("🔽 SCROLL_TO_BOTTOM: Currently loading more messages, cancelling auto-scroll")
            return
        }

        // If table is hidden, use positionTableAtBottomBeforeShowing instead
        if tableView.alpha == 0.0 {
            // CRITICAL FIX: Don't auto-position if target message was recently highlighted
            if let highlightTime = lastTargetMessageHighlightTime,
                Date().timeIntervalSince(highlightTime) < 10.0
            {
                print("🎯 SCROLL_TO_BOTTOM: Target message highlighted recently, skipping position")
                return
            }

            // print("🔽 SCROLL_TO_BOTTOM: Table is hidden, using positionTableAtBottomBeforeShowing")
            positionTableAtBottomBeforeShowing()
            return
        }

        // If there are few messages, don't scroll
        let messageCount = tableView.numberOfRows(inSection: 0)
        if messageCount < 12 {
            // print("📊 SCROLL_TO_BOTTOM: Few messages (\(messageCount)), automatic scrolling not performed")
            return
        }

        // Implement debounce to prevent rapid consecutive scrolls
        let now = Date()
        if let lastTime = lastScrollToBottomTime,
            now.timeIntervalSince(lastTime) < scrollDebounceInterval
        {
            // print("⏱️ SCROLL_TO_BOTTOM: Skipping due to debounce, last scroll was \(now.timeIntervalSince(lastTime)) seconds ago")
            return
        }

        // Update last scroll time
        lastScrollToBottomTime = now

        // Cancel any pending scroll operations
        scrollToBottomWorkItem?.cancel()

        // Force layout to update immediately
        tableView.layoutIfNeeded()

        // Check if we have more than 3 messages - if so, reset contentInset to ensure proper scrolling
        let numberOfRows = self.tableView.numberOfRows(inSection: 0)
        if numberOfRows > 3 && tableView.contentInset.top > 0 {
            // Reset content inset immediately for proper scrolling
            UIView.animate(withDuration: 0.1) {
                self.tableView.contentInset = UIEdgeInsets.zero
            }
            // print("🔽 SCROLL_TO_BOTTOM: Reset contentInset to zero before scrolling (message count > 3)")
        }

        // Create a new work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Check if we have any messages or rows
            if numberOfRows > 0 {
                let lastRowIndex = numberOfRows - 1
                let indexPath = IndexPath(row: lastRowIndex, section: 0)

                let currentRows = self.tableView.numberOfRows(inSection: 0)
                guard !self.isViewDisappearing, self.tableView.dataSource != nil, currentRows > 0 else { return }
                IndexPath(row: currentRows - 1, section: 0)
                // Use multiple scroll approaches to guarantee scrolling
                // First try scrollToRow
                self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)

                // Remove excess contentInset that might cause empty space
                if self.tableView.contentInset.top > 0 {
                    self.tableView.contentInset = .zero
                    // print("📏 Removed excess contentInset.top in scrollToBottom")
                }

                // Then also try setting contentOffset directly
                let y = self.tableView.contentSize.height - self.tableView.frame.height
                if y > 0 {
                    self.tableView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
                }

                // print("🔽 SCROLL_TO_BOTTOM: Scrolled to last row at index \(lastRowIndex) using multiple approaches")

                // Force another scroll check after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.3 : 0.1)) {
                    [weak self] in
                    guard let self = self else { return }

                    // Verify and adjust if needed
                    let finalRows = self.tableView.numberOfRows(inSection: 0)
                    if finalRows > 0 {
                        let finalIndexPath = IndexPath(row: finalRows - 1, section: 0)
                        self.tableView.scrollToRow(at: finalIndexPath, at: .bottom, animated: false)

                        // For extra assurance, also try direct offset
                        let finalY = self.tableView.contentSize.height - self.tableView.frame.height
                        if finalY > 0 {
                            self.tableView.setContentOffset(
                                CGPoint(x: 0, y: finalY), animated: false)
                        }

                        // Add a third attempt with a longer delay to handle any layout changes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self = self else { return }

                            // Final verification
                            let lastRows = self.tableView.numberOfRows(inSection: 0)
                            if lastRows > 0 {
                                let lastIndexPath = IndexPath(row: lastRows - 1, section: 0)
                                self.tableView.scrollToRow(
                                    at: lastIndexPath, at: .bottom, animated: false)

                                // One last direct offset attempt
                                let lastY =
                                    self.tableView.contentSize.height - self.tableView.frame.height
                                if lastY > 0 {
                                    self.tableView.setContentOffset(
                                        CGPoint(x: 0, y: lastY), animated: false)
                                }

                                // print("🔽 SCROLL_TO_BOTTOM: Final scroll verification complete")
                            }
                        }
                    }
                }
            } else {
                // print("⚠️ SCROLL_TO_BOTTOM: No rows in table, can't scroll")
            }
        }

        // Save the work item reference
        scrollToBottomWorkItem = workItem

        // Execute immediately without delay for better responsiveness
        DispatchQueue.main.async(execute: workItem)
    }

    // Improved isUserNearBottom with more relaxed threshold
    func isUserNearBottom(threshold: CGFloat? = nil) -> Bool {
        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            print(
                "🎯 NEAR_BOTTOM_CHECK: Target message protection active, not considering user near bottom"
            )
            return false
        }

        return scrollPositionManager.isUserNearBottom(threshold: threshold)
    }

    // Legacy method for compatibility
    private func isUserNearBottomLegacy(threshold: CGFloat? = nil) -> Bool {
        guard let tableView = tableView, tableView.numberOfRows(inSection: 0) > 0 else {
            //  // print("📊 IS_USER_NEAR_BOTTOM: No rows in table, returning true")
            return true  // If there are no messages, consider user at the bottom
        }

        // If user is actively scrolling, don't consider them at bottom
        if tableView.isDragging || tableView.isDecelerating {
            return false
        }

        // If user has manually scrolled up recently, don't consider them at bottom
        // This prevents auto-scrolling to bottom when user is reading previous messages
        if let lastScrollUpTime = lastManualScrollUpTime,
            Date().timeIntervalSince(lastScrollUpTime) < 15.0
        {
            return false
        }

        // CRITICAL FIX: If we have a target message, don't consider user at bottom
        // This prevents auto-scrolling when we're positioned on a target message
        if targetMessageId != nil {
            return false
        }

        // Get contentOffset and contentSize
        let contentHeight = tableView.contentSize.height
        let offsetY = tableView.contentOffset.y
        let frameHeight = tableView.frame.size.height

        // User is considered "near bottom" if they are scrolled to the last 20% of content
        // Using a more generous threshold to ensure better auto-scrolling
        let distanceFromBottom = contentHeight - (offsetY + frameHeight)

        // Use provided threshold or default value
        let calculatedThreshold = threshold ?? (frameHeight * 1.5)

        // Add debug print
        //  // print("📊 IS_USER_NEAR_BOTTOM: Distance from bottom: \(distanceFromBottom), Threshold: \(calculatedThreshold), Is near bottom: \(distanceFromBottom < calculatedThreshold)")

        return distanceFromBottom < calculatedThreshold
    }

    private func startScrollProtection() {
        // Cancel existing timer
        scrollProtectionTimer?.invalidate()

        // Start a timer that monitors for unwanted auto-scroll for 3 seconds
        scrollProtectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            // If user is still dragging or decelerating, keep protecting
            if self.tableView.isDragging || self.tableView.isDecelerating {
                // Cancel any auto-scroll operations
                self.scrollToBottomWorkItem?.cancel()
                self.scrollToBottomWorkItem = nil
            } else {
                // User finished scrolling, stop protection after a short delay
                timer.invalidate()
                self.scrollProtectionTimer = nil
            }
        }
    }
    
    // Add properties to manage rate limiting
    internal var lastMessageSeenTime = Date(timeIntervalSince1970: 0)
    internal var messageSeenThrottleInterval: TimeInterval = 5.0  // At least 5 seconds between seen acknowledgments
    internal var isAcknowledgingMessage = false
    internal var retryQueue = [RetryTask]()

    // MARK: - Mark Unread Protection
    // Temporarily disable automatic acknowledgment after marking as unread
    internal var isAutoAckDisabled = false
    internal var autoAckDisableTime: Date?
    internal let autoAckDisableDuration: TimeInterval = 30.0  // Disable for 30 seconds after mark unread
    

    // Helper method to safely update isLoadingMore
    private func setIsLoadingMore(_ value: Bool) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        isLoadingMore = value
        // print("📱 isLoadingMore set to \(value)")
    }

    // Public method to reset the nearby loading flag when navigating to a new channel (moved to extension)

    // Typing indicator setup is now handled by TypingIndicatorManager

    internal func showNSFWOverlay() {
        let channelName = viewModel.channel.getName(viewModel.viewState)
        NSFWOverlayView.show(in: view, channelName: channelName, delegate: self)
    }

    // MARK: - NSFWOverlayViewDelegate
    func nsfwOverlayViewDidConfirm(_ view: NSFWOverlayView) {
        view.dismiss(animated: true)
        over18HasSeen = true
    }

    // MARK: - Image Handling
    func showFullScreenImage(_ image: UIImage) {
        let imageViewController = FullScreenImageViewController(image: image)
        imageViewController.modalPresentationStyle = .overFullScreen
        present(imageViewController, animated: true, completion: nil)
    }

    private func setupMessageGrouping() {
        // Logic for message grouping will be implemented in the table view data source methods
    }

    private func addNewMessageIndicator() {
        // This will be implemented when handling unreads
    }

    // FAST: Lightweight refresh method with minimal overhead
    func refreshMessages(forceUpdate: Bool = false) {
        print("🔄 targetMessageProtectionActive: \(targetMessageProtectionActive)")

        // CRITICAL FIX: Don't refresh if we're in the middle of nearby loading (unless forced for reactions)
        if messageLoadingState == .loading && !forceUpdate {
            print("🔄 BLOCKED: refreshMessages blocked - nearby loading in progress")
            return
        }

        // CRITICAL FIX: Only block if protection is active AND we don't have a new target message to process (unless forced for reactions)
        if targetMessageProtectionActive && (targetMessageId == nil || targetMessageProcessed)
            && !forceUpdate
        {
            print(
                "🔄 BLOCKED: refreshMessages blocked - target message protection active and no new target"
            )
            return
        }

        // Skip if user is interacting with table
        guard !tableView.isDragging, !tableView.isDecelerating else {
            // print("🔄 Skipping refreshMessages - user is interacting with table")
            return
        }

        // Skip if user recently scrolled up, BUT NOT if we have a target message
        if let lastScrollUpTime = lastManualScrollUpTime,
            Date().timeIntervalSince(lastScrollUpTime) < 10.0,
            targetMessageId == nil
        {
            // print("🔄 Skipping refreshMessages - user recently scrolled up (no target message)")
            return
        } else if targetMessageId != nil {
            // print("🔄 Continuing refreshMessages despite recent scroll - have target message")
        }

        // Get new messages directly - no async overhead
        guard let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id],
            !channelMessages.isEmpty,
            localMessages != channelMessages
        else { return }

        // CRITICAL: Check if actual message objects exist before refreshing
        let hasActualMessages =
            channelMessages.first(where: { viewModel.viewState.messages[$0] != nil }) != nil
        if !hasActualMessages {
            // print("⚠️ refreshMessages: Only message IDs found, no actual messages - need to load messages")

            // CRITICAL FIX: Don't force reload if target message protection is active (unless forced for reactions)
            if targetMessageProtectionActive && !forceUpdate {
                print("🔄 BLOCKED: Force reload blocked - target message protection active")
                return
            }

            // Hide table and show loading spinner
            tableView.alpha = 0.0
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.startAnimating()
            spinner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
            tableView.tableFooterView = spinner

            // Force load messages if we only have IDs
            Task {
                await loadInitialMessages()
            }
            return
        }

        let wasNearBottom = isUserNearBottom()
        localMessages = channelMessages

        // CRITICAL: Mark data source as updating to protect scroll events
        isDataSourceUpdating = true
        print("📊 DATA_SOURCE: Marking as updating before table reload")

        // FAST: Update existing data source if possible
        if let existingDataSource = dataSource as? LocalMessagesDataSource {
            existingDataSource.updateMessages(localMessages)
        } else {
            // Only create new data source if needed
            dataSource = LocalMessagesDataSource(
                viewModel: viewModel, viewController: self, localMessages: localMessages)
            tableView.dataSource = dataSource
        }

        // FAST: Single reload operation
        tableView.reloadData()

        // CRITICAL: Reset flag after reload with slight delay to prevent immediate scroll conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isDataSourceUpdating = false
            print("📊 DATA_SOURCE: Marking as stable after table reload")
        }

        // Update table view bouncing behavior after refresh
        updateTableViewBouncing()

        // CRITICAL FIX: Check if we need to fetch reply content for newly loaded messages
        // Only check if we have messages and table view is visible, and not loading
        if !localMessages.isEmpty && tableView.alpha > 0 && messageLoadingState == .notLoading {
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                await self.checkAndFetchMissingReplies()
            }
        }

        // CRITICAL FIX: Check for target message after reload - ONLY call scrollToTargetMessage ONCE
        if let targetId = targetMessageId, !targetMessageProcessed {
            print("🎯 Found unprocessed targetMessageId in refreshMessages: \(targetId)")
            print("🎯 localMessages count: \(localMessages.count)")

            // Check if target message is actually loaded
            let targetInLocalMessages = localMessages.contains(targetId)
            let targetInViewState = viewModel.viewState.messages[targetId] != nil

            if targetInLocalMessages && targetInViewState {
                print(
                    "✅ Target message is loaded in refreshMessages, calling scrollToTargetMessage ONCE"
                )
                // Mark as processed BEFORE calling scrollToTargetMessage to prevent multiple calls
                targetMessageProcessed = true
                scrollToTargetMessage()
            } else {
                print("❌ Target message NOT loaded in refreshMessages, skipping scroll")
            }
        } else if let targetId = targetMessageId, targetMessageProcessed {
            print(
                "🎯 Found targetMessageId but already processed: \(targetId) - preserving target position"
            )
            // CRITICAL FIX: Do NOT auto-scroll when we have a target message
            // The target message should remain visible regardless of bottom position
        } else if wasNearBottom {
            // CRITICAL FIX: Don't auto-scroll if user was positioned on a target message recently
            if targetMessageProtectionActive || isInTargetMessagePosition {
                print(
                    "🎯 REFRESH_MESSAGES: Target message protection or position active, skipping auto-scroll"
                )
                return
            }

            // CRITICAL FIX: Don't auto-scroll if target message was highlighted recently (within 30 seconds)
            if let highlightTime = lastTargetMessageHighlightTime,
                Date().timeIntervalSince(highlightTime) < 30.0
            {
                print(
                    "🎯 REFRESH_MESSAGES: Target message highlighted recently (\(Date().timeIntervalSince(highlightTime))s ago), skipping auto-scroll"
                )
                return
            }

            // Auto-scroll if user was at bottom and no target message protection
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                print(
                    "🎯 REFRESH_MESSAGES: Auto-scrolling because user was near bottom and no target protection"
                )

                // Use proper scrolling method that considers keyboard state
                if self.isKeyboardVisible && !self.localMessages.isEmpty {
                    let lastIndex = self.localMessages.count - 1
                    if lastIndex >= 0 && lastIndex < self.tableView.numberOfRows(inSection: 0) {
                        let indexPath = IndexPath(row: lastIndex, section: 0)
                        self.safeScrollToRow(
                            at: indexPath, at: .bottom, animated: false,
                            reason: "refresh messages with keyboard")
                    }
                } else {
                    self.scrollToBottom(animated: false)
                }
            }
        }

        updateEmptyStateVisibility()
    }

    // Add LocalMessagesDataSource class inside view controller
    class LocalMessagesDataSource: NSObject, UITableViewDataSource {
        private var localMessages: [String] = []
        private var viewModelRef: MessageableChannelViewModel
        private weak var viewControllerRef: MessageableChannelViewController?

        // CRITICAL FIX: Add thread-safe persistent cache for messages
        private var cachedMessages: [String] = []
        private let cacheQueue = DispatchQueue(
            label: "messages.cache.queue", attributes: .concurrent)

        // Track row count to prevent race conditions
        private var lastReturnedRowCount: Int = 0

        // OPTIMIZATION: Cache frequently accessed message data
        private var messageCache: [String: Message] = [:]
        private var userCache: [String: User] = [:]

        init(
            viewModel: MessageableChannelViewModel,
            viewController: MessageableChannelViewController, localMessages: [String]
        ) {
            self.viewModelRef = viewModel
            self.viewControllerRef = viewController

            // CRITICAL: Always prefer messages from viewState over passed localMessages
            if let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id],
                !channelMessages.isEmpty
            {
                // Take explicit copy of viewState messages
                self.localMessages = Array(channelMessages)
                // Also cache it for future use
                self.cachedMessages = Array(channelMessages)
                self.lastReturnedRowCount = channelMessages.count
                // print("🔒 LocalMessagesDataSource init: Using \(channelMessages.count) messages from viewState")
            } else if !localMessages.isEmpty {
                // Only if viewState has no messages, use passed localMessages
                self.localMessages = localMessages
                // Also cache it for future use
                self.cachedMessages = Array(localMessages)
                self.lastReturnedRowCount = localMessages.count
                // print("🔒 LocalMessagesDataSource init: Using \(localMessages.count) passed messages")
            } else if !viewModel.messages.isEmpty {
                // As last resort, use viewModel.messages
                self.localMessages = viewModel.messages
                // Also cache it for future use
                self.cachedMessages = Array(viewModel.messages)
                self.lastReturnedRowCount = viewModel.messages.count
                // print("🔒 LocalMessagesDataSource init: Using \(viewModel.messages.count) messages from viewModel")
            } else {
                // print("⚠️ LocalMessagesDataSource init: No messages available!")
            }

            super.init()
        }

        // Method to force update messages and clear any cached inconsistencies
        func forceUpdateMessages(_ messages: [String]) {
            cacheQueue.sync(flags: .barrier) {
                self.localMessages = Array(messages)
                self.cachedMessages = Array(messages)
                self.lastReturnedRowCount = messages.count
                print("🔄 FORCE_UPDATE: Data source updated with \(messages.count) messages")
            }
        }

        /// Removes the cached message for the given ID so the next cell configuration reads the latest from viewState (e.g. after message edit).
        func invalidateMessageCache(forMessageId messageId: String) {
            cacheQueue.sync(flags: .barrier) {
                messageCache.removeValue(forKey: messageId)
            }
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return cacheQueue.sync {
                let count = localMessages.count
                lastReturnedRowCount = count
                print(
                    "📊 LOCAL DATA SOURCE: Returning \(count) rows (localMessages: \(localMessages.count))"
                )
                return count
            }
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
            -> UITableViewCell
        {
            // CRITICAL: Thread-safe bounds check with fallback cell
            return cacheQueue.sync {
                // Double check bounds against both local messages and last returned count
                guard indexPath.row < localMessages.count && indexPath.row < lastReturnedRowCount
                else {
                    print(
                        "⚠️ BOUNDS_ERROR: indexPath.row=\(indexPath.row), localMessages.count=\(localMessages.count), lastReturnedRowCount=\(lastReturnedRowCount)"
                    )
                    return createFallbackCell(
                        tableView: tableView, indexPath: indexPath, reason: "Index out of bounds")
                }

                let messageId = localMessages[indexPath.row]

                // OPTIMIZED: Try cache first, then viewState
                let message: Message
                if let cachedMessage = messageCache[messageId] {
                    message = cachedMessage
                } else if let viewStateMessage = viewModelRef.viewState.messages[messageId] {
                    message = viewStateMessage
                    messageCache[messageId] = viewStateMessage  // Cache for future use
                } else {
                    print("⚠️ MESSAGE_NOT_FOUND: messageId=\(messageId) at index=\(indexPath.row)")
                    return createFallbackCell(
                        tableView: tableView, indexPath: indexPath,
                        reason: "Message not found: \(messageId)")
                }

                // Handle system messages
                if message.system != nil {
                    guard
                        let systemCell = tableView.dequeueReusableCell(
                            withIdentifier: "SystemMessageCell", for: indexPath)
                            as? SystemMessageCell
                    else {
                        print("⚠️ SYSTEM_CELL_ERROR: Failed to dequeue SystemMessageCell")
                        return createFallbackCell(
                            tableView: tableView, indexPath: indexPath,
                            reason: "System cell dequeue failed")
                    }
                    systemCell.configure(with: message, viewState: viewModelRef.viewState)
                    return systemCell
                }

                // Handle regular messages with better safety
                guard
                    let messageCell = tableView.dequeueReusableCell(
                        withIdentifier: "MessageCell", for: indexPath) as? MessageCell
                else {
                    print("⚠️ MESSAGE_CELL_ERROR: Failed to dequeue MessageCell")
                    return createFallbackCell(
                        tableView: tableView, indexPath: indexPath,
                        reason: "Message cell dequeue failed")
                }

                // OPTIMIZED: Author lookup with cache and fallback
                let author: User
                if let cachedAuthor = userCache[message.author] {
                    author = cachedAuthor
                } else if let foundAuthor = viewModelRef.viewState.users[message.author] {
                    author = foundAuthor
                    userCache[message.author] = foundAuthor  // Cache for future use
                } else {
                    print("⚠️ AUTHOR_NOT_FOUND: Creating fallback author for messageId=\(messageId)")
                    let fallbackAuthor = User(
                        id: message.author,
                        username: "Loading...",
                        discriminator: "0000",
                        avatar: nil,
                        relationship: .None
                    )
                    author = fallbackAuthor
                    userCache[message.author] = fallbackAuthor  // Cache fallback too
                }

                // Safe continuation check
                let isContinuation =
                    viewControllerRef?.shouldGroupWithPreviousMessage(at: indexPath) ?? false
                let member = viewModelRef.getMember(message: message).wrappedValue

                // PERFORMANCE: Configure cell with optimized method
                messageCell.configure(
                    with: message, author: author, member: member,
                    viewState: viewModelRef.viewState, isContinuation: isContinuation)

                // PERFORMANCE: Set delegates efficiently
                messageCell.textViewContent.delegate = viewControllerRef

                // PERFORMANCE: Use weak references for callbacks
                messageCell.onMessageAction = {
                    [weak viewController = viewControllerRef] action, message in
                    viewController?.handleMessageAction(action, message: message)
                }

                messageCell.onImageTapped = { [weak viewController = viewControllerRef] image in
                    viewController?.showFullScreenImage(image)
                }

                messageCell.onAvatarTap = { [weak viewModel = viewModelRef] in
                    viewModel?.viewState.openUserSheet(user: author, member: member)
                }

                messageCell.onUsernameTap = { [weak viewModel = viewModelRef] in
                    viewModel?.viewState.openUserSheet(user: author, member: member)
                }

                return messageCell
            }
        }

        // CRITICAL: Create a proper fallback cell instead of returning empty UITableViewCell
        private func createFallbackCell(
            tableView: UITableView, indexPath: IndexPath, reason: String
        ) -> UITableViewCell {
            let fallbackCell = UITableViewCell(style: .default, reuseIdentifier: nil)
            fallbackCell.backgroundColor = UIColor(named: "bgDefaultPurple13") ?? .systemBackground
            fallbackCell.textLabel?.text = "Loading message..."
            fallbackCell.textLabel?.textColor = UIColor(named: "textGray04") ?? .systemGray
            fallbackCell.textLabel?.font = UIFont.systemFont(ofSize: 14)
            fallbackCell.selectionStyle = .none

            // Add a subtle loading indicator
            let activityIndicator: UIActivityIndicatorView
            if #available(iOS 13.0, *) {
                activityIndicator = UIActivityIndicatorView(style: .medium)
            } else {
                activityIndicator = UIActivityIndicatorView(style: .gray)
            }
            activityIndicator.startAnimating()
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            fallbackCell.contentView.addSubview(activityIndicator)
            NSLayoutConstraint.activate([
                activityIndicator.centerYAnchor.constraint(
                    equalTo: fallbackCell.contentView.centerYAnchor),
                activityIndicator.trailingAnchor.constraint(
                    equalTo: fallbackCell.contentView.trailingAnchor, constant: -16),
            ])

            print("🔄 FALLBACK_CELL: Created for index=\(indexPath.row), reason=\(reason)")
            return fallbackCell
        }

        func updateMessages(_ messages: [String]) {
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.localMessages = messages
                self.cachedMessages = Array(messages)  // Update cache too
                self.lastReturnedRowCount = messages.count

                // OPTIMIZATION: Clean up cache for messages no longer visible
                self.cleanupCache(currentMessages: messages)
                // print("🔄 LocalMessagesDataSource: Updated with \(messages.count) messages")
            }
        }

        // OPTIMIZATION: Clean up cache to prevent memory leaks
        private func cleanupCache(currentMessages: [String]) {
            let currentMessageSet = Set(currentMessages)

            // Remove cached messages that are no longer in the current message list
            messageCache = messageCache.filter { currentMessageSet.contains($0.key) }

            // Keep user cache small but don't be too aggressive
            if userCache.count > 100 {
                // Remove half of the least recently used users
                let keysToRemove = Array(userCache.keys.shuffled().prefix(userCache.count / 2))
                for key in keysToRemove {
                    userCache.removeValue(forKey: key)
                }
            }

            print(
                "🧹 CACHE_CLEANUP: messageCache=\(messageCache.count), userCache=\(userCache.count)")
        }
    }

    // New method to refresh messages without auto-scrolling to bottom (moved to extension)

    // Helper to add timeout to tasks
    static func withTimeout<T>(
        timeoutNanoseconds: UInt64, operation: @escaping () async throws -> T
    ) async throws -> T {
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
            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    // Timeout error
    struct TimeoutError: Error {
        var localizedDescription: String {
            return "Operation timed out"
        }
    }

    // MARK: - Replies Handling

    func addReply(_ reply: ReplyMessage) {
        repliesManager.addReply(reply)
    }

    func removeReply(at id: String) {
        repliesManager.removeReply(at: id)
    }

    func clearReplies() {
        repliesManager.clearReplies()
    }

    /// Track when we last checked for missing replies to avoid excessive API calls
    internal var lastReplyCheckTime: Date?
    internal let replyCheckCooldown: TimeInterval = 2.0  // 2 seconds between checks

    /// Fetch reply message content for messages that have replies and immediately refresh UI
    internal func fetchReplyMessagesContentAndRefreshUI(for messages: [Types.Message]) async {
        print("🔗 FETCH_AND_REFRESH: Starting fetch and refresh for \(messages.count) messages")

        // Track which reply IDs we're about to fetch
        var replyIdsBeingFetched: Set<String> = []
        for message in messages {
            guard let replies = message.replies, !replies.isEmpty else { continue }
            for replyId in replies {
                let isInCache = viewModel.viewState.messages[replyId] != nil
                let isBeingFetched = ongoingReplyFetches.contains(replyId)
                if !isInCache && !isBeingFetched {
                    replyIdsBeingFetched.insert(replyId)
                }
            }
        }

        print("🔗 FETCH_AND_REFRESH: Will fetch \(replyIdsBeingFetched.count) reply messages")

        await fetchReplyMessagesContent(for: messages)

        // CRITICAL: Always refresh UI after fetching replies for initial load
        await MainActor.run {
            print("🔗 FETCH_AND_REFRESH: Refreshing UI after initial reply loading")

            // Force a complete refresh if we fetched any replies
            if !replyIdsBeingFetched.isEmpty {
                // Use reloadData instead of refreshMessages for more complete refresh
                if let tableView = self.tableView {
                    print(
                        "🔗 FETCH_AND_REFRESH: Forcing complete table reload after fetching \(replyIdsBeingFetched.count) replies"
                    )
                    tableView.reloadData()
                } else {
                    self.refreshMessages()
                }
            } else {
                self.refreshMessages()
            }
        }
    }

    /// Track ongoing reply fetches to prevent duplicates
    private var ongoingReplyFetches = Set<String>()

    /// Fetch reply message content for messages that have replies
    internal func fetchReplyMessagesContent(for messages: [Types.Message]) async {
        print("🔗 FETCH_REPLIES: Processing \(messages.count) messages for reply content")

        // DEBUG: Check what messages we have and their replies
        var messagesWithReplies = 0
        var totalReplyIds = 0

        for message in messages {
            if let replies = message.replies, !replies.isEmpty {
                messagesWithReplies += 1
                totalReplyIds += replies.count
                print("🔗 DEBUG: Message \(message.id) has \(replies.count) replies: \(replies)")
            }
        }

        print(
            "🔗 DEBUG: Found \(messagesWithReplies) messages with replies, total \(totalReplyIds) reply IDs"
        )

        // Collect all unique reply message IDs that need to be fetched
        var replyIdsToFetch = Set<String>()
        var replyChannelMap = [String: String]()  // messageId -> channelId

        for message in messages {
            guard let replies = message.replies, !replies.isEmpty else { continue }

            for replyId in replies {
                // Check if already in cache or being fetched
                let isInCache = viewModel.viewState.messages[replyId] != nil
                let isBeingFetched = ongoingReplyFetches.contains(replyId)
                print(
                    "🔗 DEBUG: Reply \(replyId) - In cache: \(isInCache), Being fetched: \(isBeingFetched)"
                )

                // Only fetch if not already in cache and not being fetched
                if !isInCache && !isBeingFetched {
                    replyIdsToFetch.insert(replyId)
                    replyChannelMap[replyId] = message.channel
                    ongoingReplyFetches.insert(replyId)  // Mark as being fetched
                    print("🔗 DEBUG: Added \(replyId) to fetch list for channel \(message.channel)")
                }
            }
        }

        print("🔗 DEBUG: Total unique reply IDs to fetch: \(replyIdsToFetch.count)")
        if !replyIdsToFetch.isEmpty {
            print("🔗 DEBUG: Reply IDs to fetch: \(Array(replyIdsToFetch))")
        }

        guard !replyIdsToFetch.isEmpty else {
            print("✅ FETCH_REPLIES: All reply messages already cached or no replies found")
            return
        }

        print("🔗 FETCH_REPLIES: Need to fetch \(replyIdsToFetch.count) reply messages")
        print("🌐 FETCH_REPLIES: About to start API calls for replies!")

        // Fetch reply messages concurrently for better performance
        print(
            "🌐 FETCH_REPLIES: Starting concurrent fetch of \(replyIdsToFetch.count) reply messages")
        await withTaskGroup(of: Void.self) { group in
            for replyId in replyIdsToFetch {
                group.addTask { [weak self] in
                    guard let self = self,
                        let channelId = replyChannelMap[replyId]
                    else {
                        print("❌ FETCH_REPLIES: Missing self or channelId for reply \(replyId)")
                        return
                    }

                    print(
                        "🔍 FETCH_REPLIES: Starting fetch for reply \(replyId) in channel \(channelId)"
                    )
                    if let replyMessage = await self.fetchMessageForReply(
                        messageId: replyId, channelId: channelId)
                    {
                        print("✅ FETCH_REPLIES: Successfully fetched reply \(replyId)")

                        // Also fetch the author if needed
                        await MainActor.run {
                            if self.viewModel.viewState.users[replyMessage.author] == nil {
                                print(
                                    "👥 FETCH_REPLIES: Fetching author \(replyMessage.author) for reply \(replyId)"
                                )
                                Task {
                                    await self.fetchUserForMessage(userId: replyMessage.author)
                                }
                            } else {
                                print(
                                    "👥 FETCH_REPLIES: Author \(replyMessage.author) already cached for reply \(replyId)"
                                )
                            }
                        }
                    } else {
                        print("❌ FETCH_REPLIES: Failed to fetch reply \(replyId)")
                    }
                }
            }
        }

        print("🔗 FETCH_REPLIES: Completed fetching reply messages")

        // CRITICAL FIX: Force UI refresh after fetching replies
        await MainActor.run {
            // Clear ongoing fetches
            for replyId in replyIdsToFetch {
                ongoingReplyFetches.remove(replyId)
            }

            // FORCE refresh UI to show newly loaded reply content
            if !replyIdsToFetch.isEmpty {
                print(
                    "🔗 FORCE_REFRESH: Forcing UI refresh after loading \(replyIdsToFetch.count) reply messages"
                )

                // Force table view to reload data for messages with replies
                if let tableView = self.tableView {
                    // Find visible cells that might have replies
                    let visibleIndexPaths = tableView.indexPathsForVisibleRows ?? []
                    var indexPathsToReload: [IndexPath] = []

                    for indexPath in visibleIndexPaths {
                        if indexPath.row < localMessages.count {
                            let messageId = localMessages[indexPath.row]
                            if let message = viewModel.viewState.messages[messageId],
                                let replies = message.replies, !replies.isEmpty
                            {
                                // Check if any of the replies we just fetched belong to this message
                                let hasNewlyFetchedReplies = replies.contains { replyId in
                                    replyIdsToFetch.contains(replyId)
                                }
                                if hasNewlyFetchedReplies {
                                    indexPathsToReload.append(indexPath)
                                }
                            }
                        }
                    }

                    if !indexPathsToReload.isEmpty {
                        print(
                            "🔗 FORCE_REFRESH: Reloading \(indexPathsToReload.count) cells with newly fetched replies"
                        )
                        tableView.reloadRows(at: indexPathsToReload, with: .none)
                    }
                }
            }
        }

    }

    // Legacy methods for compatibility (can be removed after testing)
    private func addReplyLegacy(_ reply: ReplyMessage) {
        // First clear any existing replies - only allow one reply at a time
        clearReplies()

        // Add the new reply
        replies.append(reply)
        updateRepliesView()
    }

    private func removeReplyLegacy(at id: String) {
        let wasEmpty = replies.isEmpty

        // Remove the reply
        replies.removeAll(where: { $0.messageId == id })

        // Update the UI
        updateRepliesView()

        // If this was the last reply, make sure we adjust the layout properly
        if !wasEmpty && replies.isEmpty {
            // Force layout update
            view.layoutIfNeeded()

            // If we're at the bottom, scroll to show the latest messages correctly
            if isUserNearBottom() {
                DispatchQueue.main.async {
                    self.scrollToBottom(animated: false)
                }
            }
        }
    }

    private func clearRepliesLegacy() {
        let wasEmpty = replies.isEmpty

        // Clear all replies
        replies.removeAll()

        // Update the UI
        updateRepliesView()

        // If we had replies before, make sure we adjust the layout properly
        if !wasEmpty {
            // Force layout update immediately
            view.layoutIfNeeded()

            // If we're at the bottom, scroll to show the latest messages correctly
            if isUserNearBottom() {
                DispatchQueue.main.async {
                    self.scrollToBottom(animated: false)
                }
            }
        }
    }

    // Replies view management is now handled by RepliesManager
    private func updateRepliesView() {
        // Delegate to RepliesManager
        // This method is kept for compatibility with existing code
    }

    private func startReply(to message: Types.Message) {
        repliesManager.startReply(to: message)
    }

    // Add a method to handle message actions
    internal func handleMessageAction(_ action: MessageCell.MessageAction, message: Types.Message) {
        repliesManager.handleMessageAction(action, message: message)
    }

    /// Invalidates the table data source's message cache for the given ID so the next reload shows the latest content (e.g. after edit).
    internal func invalidateMessageCache(forMessageId messageId: String) {
        if let localDataSource = dataSource as? LocalMessagesDataSource {
            localDataSource.invalidateMessageCache(forMessageId: messageId)
        }
    }

    // Legacy method for compatibility (can be removed after testing)
    private func handleMessageActionLegacy(
        _ action: MessageCell.MessageAction, message: Types.Message
    ) {
        switch action {
        case .edit:
            // Implement editing message functionality
            print("Edit message: \(message.id)")

            // Set the message being edited
            Task {
                // Fetch replies for the message if any
                var replies: [ReplyMessage] = []

                for replyId in message.replies ?? [] {
                    var replyMessage: Types.Message? = viewModel.viewState.messages[replyId]

                    if replyMessage == nil {
                        // Use our new fetch method instead of direct HTTP call
                        replyMessage = await fetchMessageForReply(
                            messageId: replyId, channelId: viewModel.channel.id)
                    }

                    if let replyMessage = replyMessage {
                        // Make sure we have the author too
                        if viewModel.viewState.users[replyMessage.author] == nil {
                            await fetchUserForMessage(userId: replyMessage.author)
                        }

                        if let replyAuthor = viewModel.viewState.users[replyMessage.author] {
                            // Create reply object
                            let isMention = message.mentions?.contains(replyMessage.author) ?? false
                            replies.append(
                                ReplyMessage(
                                    message: replyMessage,
                                    mention: isMention
                                ))
                        }
                    }
                }

                // Update UI on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    // Set message content in input field
                    self.messageInputView.setText(message.content)

                    // Set editing state and show replies if any
                    self.messageInputView.setEditingMessage(message)

                    if !replies.isEmpty {
                        self.showReplies(replies)
                    }

                    // Focus the text field
                    self.messageInputView.focusTextField()
                }
            }
        case .delete:
            // Handle deleting message
            print("Delete message: \(message.id)")
        case .report:
            // Handle reporting message
            print("Report message: \(message.id)")
        case .copy:
            // Copy message content to clipboard
            UIPasteboard.general.string = message.content
            print("Copied message content")
        case .reply:
            // Handle replying to message with proper async handling
            print("Reply to message: \(message.id)")

            // First check if we have the message and its author in cache
            if viewModel.viewState.messages[message.id] != nil,
                viewModel.viewState.users[message.author] != nil
            {
                // Message and author are cached, proceed immediately
                startReply(to: message)
            } else {
                // Message or author not in cache, fetch first
                Task {
                    var fetchedMessage = message

                    // Try to fetch the message if not in cache
                    if viewModel.viewState.messages[message.id] == nil {
                        if let fetched = await fetchMessageForReply(
                            messageId: message.id, channelId: message.channel)
                        {
                            fetchedMessage = fetched
                        } else {
                            // Failed to fetch message
                            DispatchQueue.main.async {
                                print("❌ REPLY_START: Failed to load message for reply")
                            }
                            return
                        }
                    }

                    // Try to fetch the author if not in cache
                    if viewModel.viewState.users[fetchedMessage.author] == nil {
                        await fetchUserForMessage(userId: fetchedMessage.author)
                    }

                    // Now proceed with reply on main thread
                    DispatchQueue.main.async {
                        self.startReply(to: fetchedMessage)
                    }
                }
            }
        case .mention:
            // Insert mention into text field
            if let author = viewModel.viewState.users[message.author] {
                let mention = "@\(author.username)"
                messageInputView.insertText(mention + " ")
                messageInputView.focusTextField()
            }
        // print("Mention user from message: \(message.id)")
        case .markUnread:
            // Handle marking message as unread
            print("Mark message as unread: \(message.id)")
        case .copyLink:
            // Copy message link to clipboard
            let channelId = message.channel

            // Generate proper URL based on channel type and current domain
            Task {
                let link = await generateMessageLink(
                    serverId: viewModel.server?.id,
                    channelId: channelId,
                    messageId: message.id,
                    viewState: viewModel.viewState
                )

                await MainActor.run {
                    UIPasteboard.general.string = link
                    viewModel.viewState.showAlert(
                        message: "Message Link Copied!", icon: .peptideLink)
                }
            }
        case .copyId:
            // Copy message ID to clipboard
            UIPasteboard.general.string = message.id
            Task { @MainActor in
                viewModel.viewState.showAlert(message: "Message ID Copied!", icon: .peptideId)
            }
        case .react(let emoji):
            // Handle emoji reaction
            if emoji == "-1" {
                // Open emoji picker
                // print("Open custom emoji picker for message: \(message.id)")
            } else {
                // Add reaction with the given emoji
                // print("React with emoji \(emoji) to message: \(message.id)")
                // Here you would call your API to add the reaction
                // For example: api.addReaction(messageId: message.id, emoji: emoji)
            }
        }
    }

    // Add an explicit function to handle sending new messages
    func handleNewMessageSent() {
        // print("📤 HANDLE_NEW_MESSAGE_SENT: New message sent by user")

        // COMPREHENSIVE CLEAR: When user sends a message, clear all target message protection
        clearTargetMessageProtection(reason: "user sent new message")

        // Reset lastManualScrollUpTime since user is sending a message and expects to see it
        lastManualScrollUpTime = nil

        // Force layout update first to ensure table view size is correct
        self.view.layoutIfNeeded()
        self.tableView.layoutIfNeeded()

        // Wait a moment for the message to be added to the view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Force another layout update
            self.view.layoutIfNeeded()
            self.tableView.layoutIfNeeded()

            // If keyboard is visible, ensure proper scrolling with content inset consideration
            if self.isKeyboardVisible && !self.localMessages.isEmpty {
                let lastIndex = self.localMessages.count - 1
                if lastIndex >= 0 && lastIndex < self.tableView.numberOfRows(inSection: 0) {
                    let indexPath = IndexPath(row: lastIndex, section: 0)

                    // First scroll to bottom
                    self.safeScrollToRow(
                        at: indexPath, at: .bottom, animated: false,
                        reason: "new message sent - first scroll")

                    // Then do an animated scroll to ensure visibility
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.safeScrollToRow(
                            at: indexPath, at: .bottom, animated: true,
                            reason: "new message sent - second scroll")
                        // print("📜 HANDLE_NEW_MESSAGE_SENT: Double scrolled to ensure visibility")
                    }
                }
            } else {
                // Normal scroll when keyboard is not visible
                self.scrollToBottom(animated: true)
                // print("📜 HANDLE_NEW_MESSAGE_SENT: Scrolled to bottom normally")
            }
        }
    }

    // Handle internal peptide.chat links (moved to extension)

    // Sync localMessages with viewState to ensure consistency
    internal func syncLocalMessagesWithViewState() {
        // CRITICAL FIX: Only sync if arrays are actually different to prevent notification loops
        let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id] ?? []

        // Update localMessages to match current viewModel.messages or channelMessages
        if !channelMessages.isEmpty && localMessages != channelMessages {
            localMessages = Array(channelMessages)
            // print("🔄 Synced localMessages with channelMessages: \(localMessages.count) messages")
        } else if !viewModel.messages.isEmpty && localMessages != viewModel.messages {
            localMessages = viewModel.messages
            // print("🔄 Synced localMessages with viewModel.messages: \(localMessages.count) messages")
        }

        // Also ensure viewModel.messages is in sync - but ONLY if they're actually different
        let needsViewModelSync = !localMessages.isEmpty && viewModel.messages != localMessages
        let needsChannelMessagesSync =
            !localMessages.isEmpty
            && (viewModel.viewState.channelMessages[viewModel.channel.id] ?? []) != localMessages

        if needsViewModelSync || needsChannelMessagesSync {
            viewModel.messages = localMessages
            viewModel.viewState.channelMessages[viewModel.channel.id] = localMessages
            // print("🔄 Synced viewModel.messages and channelMessages with localMessages (only because they differed)")
        }
    }

    // Clear any existing highlights
    private func clearAllHighlights() {
        for case let cell as MessageCell in tableView.visibleCells {
            if cell.tag == 9999 {
                cell.clearHighlight()
            }
        }

        // CRITICAL FIX: Don't clear lastTargetMessageHighlightTime here
        // It should only be cleared by the timer after extended protection period
        // This prevents premature clearing that would allow auto-scroll
    }

    // Highlight the target message with animation (with retry mechanism)
    internal func highlightTargetMessage(at indexPath: IndexPath, retryCount: Int = 0) {
        print(
            "🎯 highlightTargetMessage CALLED - indexPath: \(indexPath.row), retryCount: \(retryCount)"
        )
        print("🎯 Table view visible cells count: \(tableView.visibleCells.count)")
        print("🎯 Table view total rows: \(tableView.numberOfRows(inSection: 0))")

        guard let cell = tableView.cellForRow(at: indexPath) as? MessageCell else {
            // print("⚠️ Could not find MessageCell at index path \(indexPath.row), retry: \(retryCount)")
            // print("⚠️ Available cell types at this index: \(type(of: tableView.cellForRow(at: indexPath)))")

            // Retry up to 3 times with increasing delays
            if retryCount < 3 {
                let delay = 0.2 + (Double(retryCount) * 0.2)  // 0.2s, 0.4s, 0.6s
                // print("🔄 Will retry highlightTargetMessage in \(delay) seconds")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.highlightTargetMessage(at: indexPath, retryCount: retryCount + 1)
                }
            } else {
                // print("❌ Failed to highlight message after 3 retries - cell not available")
            }
            return
        }

        // print("✅ Found MessageCell at index \(indexPath.row)!")

        // First clear any existing highlights
        // print("🧹 Clearing all existing highlights")
        clearAllHighlights()

        // print the message ID to debug
        if indexPath.row < localMessages.count {
            let messageId = localMessages[indexPath.row]
            // print("🎯 Highlighting message with ID: \(messageId), target ID is: \(targetMessageId ?? "nil")")
        }

        // print("🎨 Starting highlight animation")
        // Apply highlight to the cell with faster animation
        UIView.animate(withDuration: 0.1) {
            cell.setAsTargetMessage()
            // print("🎨 setAsTargetMessage() called on cell")
        }

        // print("📳 Triggering haptic feedback")
        // Provide stronger haptic feedback to indicate the message was found
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        // Start pulse effect immediately
        // print("✨ Starting pulse effect immediately")
        self.pulseHighlight(cell: cell)

        // Keep the highlight for 10 seconds, but also allow manual clearing
        // print("⏰ Scheduling highlight clear in 10 seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak cell] in
            guard let cell = cell, cell.tag == 9999 else {
                // print("⏰ 10-second clear: cell is nil or tag changed")
                return
            }
            // print("🧹 Clearing highlight after 10 seconds")
            cell.clearHighlight()
        }

        // print("✅ Successfully highlighted target message at index \(indexPath.row)")

        // CRITICAL FIX: Mark as processed immediately to prevent duplicate highlights
        targetMessageProcessed = true
        // print("🎯 Marked target message as processed to prevent duplicates")

        // CRITICAL FIX: Set flag to prevent auto-scroll after target message highlighting
        lastTargetMessageHighlightTime = Date()

        // CRITICAL FIX: Mark that user is now in target message position
        isInTargetMessagePosition = true
        print("🎯 Set isInTargetMessagePosition = true to prevent auto-reload")

        // CRITICAL FIX: Reset loading state after successful highlight to allow future loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.messageLoadingState == .loading {
                self.messageLoadingState = .notLoading
                print("🎯 HIGHLIGHT_COMPLETE: Reset messageLoadingState after successful highlight")
            }
        }

        // Clear the target message ID in ViewState after successful highlighting
        // Wait longer to ensure highlighting is visible to user
        // print("⏰ Scheduling targetMessageId clear in 3 seconds")

        // CRITICAL FIX: Don't clear target message immediately - keep it for user experience
        clearTargetMessageTimer?.invalidate()
        clearTargetMessageTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) {
            [weak self] _ in
            guard let self = self else {
                print("❌ Could not clear targetMessageId - self is nil")
                return
            }
            print("🎯 Timer fired - clearing targetMessageId after 5 seconds")
            self.viewModel.viewState.currentTargetMessageId = nil
            self.targetMessageId = nil
            self.clearTargetMessageTimer = nil

            // CRITICAL FIX: Also clear position flag to prevent protection
            self.isInTargetMessagePosition = false
            self.lastTargetMessageHighlightTime = nil
            print("🎯 Cleared targetMessageId and position flags after successful highlighting")
        }
    }

    // Helper method to create a pulsing highlight effect
    private func pulseHighlight(cell: MessageCell, pulseCount: Int = 1, currentPulse: Int = 0) {
        // print("✨ pulseHighlight called - pulse \(currentPulse + 1) of \(pulseCount)")

        // If we've reached the desired number of pulses, restore original state but keep highlighted
        if currentPulse >= pulseCount {
            // print("✨ Pulse effect completed after \(currentPulse) pulses")
            return
        }

        // print("✨ Starting pulse animation - fade out")
        // Create pulse effect by changing opacity with faster animation
        UIView.animate(
            withDuration: 0.2,
            animations: {
                // Fade out
                cell.contentView.alpha = 0.7
            }
        ) { _ in
            // print("✨ Fade out completed - starting fade in")
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    // Fade in
                    cell.contentView.alpha = 1.0
                }
            ) { _ in
                // print("✨ Fade in completed - scheduling next pulse")
                // Continue with next pulse
                self.pulseHighlight(
                    cell: cell, pulseCount: pulseCount, currentPulse: currentPulse + 1)
            }
        }
    }


    // Helper method to extract retry_after value from JSON error response
    private func extractRetryAfterValue(from errorData: String?) -> Int? {
        guard let data = errorData else { return nil }

        do {
            // Try to parse the error data as JSON
            if let dataObj = try JSONSerialization.jsonObject(with: Data(data.utf8), options: [])
                as? [String: Any],
                let retryAfter = dataObj["retry_after"] as? Int
            {
                // print("📊 Extracted retry_after: \(retryAfter)")
                return retryAfter
            }
        } catch {
            // print("❌ Error parsing JSON from error data: \(error)")
        }

        return nil
    }

    // Make shouldGroupWithPreviousMessage public for the data source to use
    internal func shouldGroupWithPreviousMessage(at indexPath: IndexPath) -> Bool {
        // Safety check to prevent index out of range
        if indexPath.row == 0 || indexPath.row >= localMessages.count {
            return false
        }

        // CRITICAL FIX: Ensure we have enough messages in the array
        guard localMessages.count > 1 && indexPath.row > 0 else {
            return false
        }

        // Additional safety check for array bounds
        guard indexPath.row - 1 < localMessages.count else {
            return false
        }

        // Use localMessages instead of viewModel.messages
        let currentMessageId = localMessages[indexPath.row]
        let previousMessageId = localMessages[indexPath.row - 1]

        guard let currentMessage = viewModel.viewState.messages[currentMessageId],
            let previousMessage = viewModel.viewState.messages[previousMessageId]
        else {
            return false
        }

        // CRITICAL FIX: Messages with attachments should NEVER be grouped to ensure username is always visible
        if let attachments = currentMessage.attachments, !attachments.isEmpty {
            // print("🖼️ Message with attachments at row \(indexPath.row) - NEVER group to ensure username visibility")
            return false
        }

        let sameAuthor = currentMessage.author == previousMessage.author

        let currentDate = createdAt(id: currentMessage.id)
        let previousDate = createdAt(id: previousMessage.id)
        let timeInterval = currentDate.timeIntervalSince(previousDate)
        let closeEnough = timeInterval < 5 * 60

        let shouldGroup = sameAuthor && closeEnough

        return shouldGroup
    }

    // Add property to track when we last received messages
    internal var lastMessageUpdateTime = Date()
    internal let minimumUpdateInterval: TimeInterval = 5.0  // Minimum seconds between updates
    private var lastKnownMessageCount: Int = 0  // Track last known message count

    // Helper method to check if we should update messages
    private func shouldUpdateMessages() -> Bool {
        // Don't update if user is actively scrolling
        if tableView.isDragging || tableView.isDecelerating {
            return false
        }

        // Don't update if it's been less than minimumUpdateInterval since last update
        let timeSinceLastUpdate = Date().timeIntervalSince(lastMessageUpdateTime)
        if timeSinceLastUpdate < minimumUpdateInterval {
            return false
        }

        return true
    }

    // Add new property for the loading view
    var loadingHeaderView: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 80))

        // Add background with shadow
        view.backgroundColor = UIColor.bgDefaultPurple13.withAlphaComponent(0.9)
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 3)
        view.layer.shadowOpacity = 0.3
        view.layer.shadowRadius = 4

        // Add activity indicator at the center
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        view.addSubview(spinner)

        let label = UILabel()
        label.text = "Loading ..."
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        // Center the spinner and position the label
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -10),

            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
        ])

        // Hide by default
        view.isHidden = true

        return view
    }()

    //    // MARK: - Show Full Screen Image
    //    internal func showFullScreenImage(_ image: UIImage) {
    //        let imageViewController = FullScreenImageViewController(image: image)
    //        imageViewController.modalPresentationStyle = .fullScreen
    //        present(imageViewController, animated: true, completion: nil)
    //    }


    // Add a method to update layout when replies visibility changes
    internal func updateLayoutForReplies(isVisible: Bool) {
        // Get the height of the replies view
        let repliesHeight: CGFloat = isVisible ? min(CGFloat(replies.count) * 60, 180) : 0

        // Update tableView bottom inset to make space for replies
        var insets = tableView.contentInset
        insets.bottom =
            messageInputView.frame.height + repliesHeight + (isKeyboardVisible ? keyboardHeight : 0)
        tableView.contentInset = insets

        // Also update the scroll indicator insets
        tableView.scrollIndicatorInsets = insets

        // Animate the change
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }


    // Add a method to check for network errors in logs
    internal func checkForNetworkErrors(in logMessage: String) {
        // Add the log message to our recent logs
        recentLogMessages.append(logMessage)

        // Keep only the last maxLogMessages
        if recentLogMessages.count > maxLogMessages {
            recentLogMessages.removeFirst()
        }

        // Check if we've detected a network error recently (avoid multiple detections)
        if let lastError = lastNetworkErrorTime,
            Date().timeIntervalSince(lastError) < networkErrorCooldown
        {
            return
        }

        // Check for network error patterns in recent logs
        let errorPatterns = ["Connection reset by peer", "tcp_input", "nw_read_request_report"]
        for pattern in errorPatterns {
            if logMessage.contains(pattern) {
                // print("⚠️ Detected network error: \(pattern)")
                lastNetworkErrorTime = Date()

                // Post notification about network error
                NotificationCenter.default.post(
                    name: NSNotification.Name("NetworkErrorOccurred"),
                    object: nil
                )
                break
            }
        }
    }

    // Method to adjust table insets based on message count
    func adjustTableInsetsForMessageCount() {
        // Safety check - make sure table view is loaded
        guard tableView != nil, tableView.window != nil else {
            // print("⚠️ Table view not ready for inset adjustment")
            return
        }

        // CRITICAL FIX: Don't adjust insets during target message operations
        if targetMessageProtectionActive {
            print("📏 BLOCKED: Inset adjustment blocked - target message protection active")
            return
        }

        // Get the current number of messages
        let messageCount = tableView.numberOfRows(inSection: 0)

        // If no messages, don't adjust insets
        guard messageCount > 0 else {
            // print("📏 No messages to adjust insets for")
            // Disable bouncing for empty state
            tableView.alwaysBounceVertical = false
            tableView.bounces = false
            // Remove header to prevent scrolling
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }
            return
        }

        // JUMPING FIX: Implement cooldown to prevent excessive calls
        let now = Date()
        let timeSinceLastAdjustment = now.timeIntervalSince(lastInsetAdjustmentTime)

        // Skip if called too recently AND message count hasn't changed significantly
        if timeSinceLastAdjustment < insetAdjustmentCooldown
            && abs(messageCount - lastMessageCountForInsets) <= 1
        {
            // print("📏 COOLDOWN: Skipping inset adjustment (called \(timeSinceLastAdjustment)s ago, count change: \(abs(messageCount - lastMessageCountForInsets)))")
            return
        }

        // Update tracking variables
        lastInsetAdjustmentTime = now
        lastMessageCountForInsets = messageCount

        // CRITICAL FIX: For very few messages (under 10), just update bouncing
        // Don't use contentInset for positioning - it causes scrolling issues
        if messageCount <= 10 {
            // Just update bouncing behavior
            updateTableViewBouncing()
            // print("📏 Updated bouncing for \(messageCount) messages")
            return
        }

        // Improvement: Increased message threshold for better user experience - apply spacing for up to 15 messages
        if messageCount > 15 {
            // If we have more than 15 messages, remove the spacing
            if tableView.contentInset.top > 0 {
                UIView.animate(withDuration: 0.2) {
                    self.tableView.contentInset = UIEdgeInsets.zero
                }
                // print("📏 Reset insets to zero (message count > 15)")
            }
            // Enable bouncing for many messages
            tableView.alwaysBounceVertical = true
            tableView.bounces = true
            return
        }

        // For messages between 11-15, calculate spacing more carefully

        // Calculate the visible height of the table
        let visibleHeight = tableView.bounds.height

        // Calculate the total height of all cells with error handling
        var totalCellHeight: CGFloat = 0

        for i in 0..<messageCount {
            let indexPath = IndexPath(row: i, section: 0)
            // Add safety check for rect calculation
            guard indexPath.row < tableView.numberOfRows(inSection: 0) else {
                // print("⚠️ Index path out of bounds: \(indexPath)")
                break
            }
            let rowHeight = tableView.rectForRow(at: indexPath).height
            totalCellHeight += rowHeight
        }

        // print("📏 ADJUST_TABLE_INSETS: visibleHeight=\(visibleHeight), totalCellHeight=\(totalCellHeight), messageCount=\(messageCount)")

        // Just update bouncing behavior for medium message counts
        updateTableViewBouncing()

        // print("📊 Medium message count (\(messageCount)), inset adjustment complete")
    }



    // Add this method to reset loading state
    func resetLoadingStateIfNeeded() {
        // Get time since last load attempt
        let now = Date()
        let timeSinceLastLoad = now.timeIntervalSince(lastSuccessfulLoadTime)

        // If loading state is stuck for more than 10 seconds, reset it
        if isLoadingMore && timeSinceLastLoad > 10.0 {
            // print("⚠️ Loading state appears to be stuck for \(Int(timeSinceLastLoad)) seconds - resetting")
            isLoadingMore = false
            messageLoadingState = .notLoading
            lastSuccessfulLoadTime = now
        }

        // Also check for inconsistency between isLoadingMore and messageLoadingState
        if isLoadingMore && messageLoadingState == .notLoading {
            // print("⚠️ Loading state inconsistency detected - isLoadingMore is true but messageLoadingState is notLoading")
            isLoadingMore = false
        }
    }

    // Throttled API call method to prevent rate limiting
    private func throttledAPICall(for lastMessageId: String) {
        // Cancel any pending API call
        pendingAPICall?.cancel()

        // Calculate time since last API call
        let timeSinceLastCall = Date().timeIntervalSince(lastAPICallTime)

        // If we've made a call too recently, debounce and wait
        if timeSinceLastCall < minimumAPICallInterval {
            // // print("🔄 THROTTLE: Last API call was \(String(format: "%.1f", timeSinceLastCall))s ago, debouncing...")

            // Show throttle indicator
            if !isThrottled {
                isThrottled = true
                DispatchQueue.main.async {
                    //                    let banner = NotificationBanner(message: "Waiting to load more messages...")
                    //                    banner.show(duration: 1.5)
                }
            }

            // Create a new delayed task
            let delayTime = minimumAPICallInterval - timeSinceLastCall
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }

                // Reset throttle state
                self.isThrottled = false

                // Check if we're still at bottom and should make the call
                if self.isUserNearBottom() && !self.isLoadingMore {
                    //   // print("🔄 THROTTLE: Executing delayed API call after \(String(format: "%.1f", delayTime))s")
                    self.makeDirectAPICall(for: lastMessageId)
                } else {
                    // // print("🔄 THROTTLE: Conditions changed, cancelling delayed API call")
                }
            }

            // Save the work item and schedule it
            pendingAPICall = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delayTime, execute: workItem)

        } else {
            // Enough time has passed, make the call immediately
            // print("🔄 THROTTLE: Making immediate API call, \(String(format: "%.1f", timeSinceLastCall))s since last call")
            makeDirectAPICall(for: lastMessageId)
        }
    }

    // The actual API call implementation (extracted from the scrollViewDidScroll method)
    private func makeDirectAPICall(for lastMessageId: String) {
        // Update last API call time immediately
        lastAPICallTime = Date()

        // Don't proceed if already loading
        if isLoadingMore {
            // print("⚠️ Already loading, skipping API call")
            return
        }

        // Set loading flag with timestamp for tracking
        isLoadingMore = true
        let loadStartTime = Date()
        lastSuccessfulLoadTime = loadStartTime

        // Show visual feedback
        DispatchQueue.main.async {
            //            let banner = NotificationBanner(message: "Loading newer messages...")
            //            banner.show(duration: 1.0)
        }

        // Make the API call directly using a new approach with completion handler
        // print("⬇️⬇️⬇️ Starting API call with lastMessageId: \(lastMessageId)")

        // Create a new task with strong self reference to ensure it completes
        let task = Task { [self] in
            do {
                // Force synchronization first
                if viewModel.messages.isEmpty {
                    // print("⬇️⬇️⬇️ Syncing viewModel.messages with localMessages")
                    viewModel.messages = localMessages
                    viewModel.viewState.channelMessages[viewModel.channel.id] = localMessages
                }

                // Get initial count for comparison
                let initialCount = localMessages.count

                // Call API directly with strong error handling
                // print("⬇️⬇️⬇️ Making direct API call to fetch messages after \(lastMessageId)")
                let result = try await viewModel.viewState.http.fetchHistory(
                    channel: viewModel.channel.id,
                    limit: 100,
                    before: nil,
                    after: lastMessageId,
                    sort: "Oldest",  // Add sort=Oldest parameter for after requests
                    server: viewModel.channel.server
                ).get()

                // print("⬇️⬇️⬇️ API call completed successfully, got \(result.messages.count) messages")

                // Fetch reply messages BEFORE MainActor.run
                print(
                    "🔗 CALLING fetchReplyMessagesContent (makeDirectAPICall) with \(result.messages.count) messages"
                )
                await self.fetchReplyMessagesContent(for: result.messages)

                // Process results on main thread
                await MainActor.run {
                    // Always reset loading flags first
                    isLoadingMore = false
                    messageLoadingState = .notLoading

                    // Process the new messages
                    if !result.messages.isEmpty {
                        // print("⬇️⬇️⬇️ Processing \(result.messages.count) new messages")

                        // Process all messages
                        for message in result.messages {
                            // Add to viewState messages dictionary
                            viewModel.viewState.messages[message.id] = message
                        }

                        // Get IDs of new messages
                        let newMessageIds = result.messages.map { $0.id }
                        let existingIds = Set(localMessages)
                        let messagesToAdd = newMessageIds.filter { !existingIds.contains($0) }

                        // Add new messages if there are any to add
                        if !messagesToAdd.isEmpty {
                            // print("⬇️⬇️⬇️ Adding \(messagesToAdd.count) new messages to local arrays")

                            // Create new arrays to avoid reference issues
                            var updatedMessages = localMessages
                            updatedMessages.append(contentsOf: messagesToAdd)

                            // Update all message arrays
                            viewModel.messages = updatedMessages
                            localMessages = updatedMessages
                            viewModel.viewState.channelMessages[viewModel.channel.id] =
                                updatedMessages

                            // Final verification
                            // print("⬇️⬇️⬇️ Arrays updated: viewModel.messages=\(viewModel.messages.count), localMessages=\(localMessages.count)")

                            // Update UI
                            refreshMessages()

                            // Show success notification
                            //                            let banner = NotificationBanner(message: "Loaded \(messagesToAdd.count) new messages")
                            //                            banner.show(duration: 2.0)

                            // Show "New Messages" button instead of auto-scrolling
                            // This allows the user to choose when to scroll to bottom
                            // Removed call to showNewMessageButton - only triggered by socket messages now
                        } else {
                            //                            // print("⬇️⬇️⬇️ No new unique messages to add (all are duplicates)")
                            //                            let banner = NotificationBanner(message: "No new messages available")
                            //                            banner.show(duration: 2.0)
                        }
                    } else {
                        // print("⬇️⬇️⬇️ API returned empty result")
                        print("ℹ️ LOAD_NEWER: You've reached the end of this conversation")
                    }
                }
            } catch let error as RevoltError {
                // print("⬇️⬇️⬇️ ERROR: API call failed with error: \(error)")

                // Reset loading state on main thread
                await MainActor.run {
                    isLoadingMore = false
                    messageLoadingState = .notLoading

                    // Handle rate limit errors specifically
                    if case .HTTPError(let data, let code) = error, code == 429 {
                        // print("⏱️ Rate limited: \(data ?? "No additional info")")

                        // Extract retry_after from the error response
                        if let retryAfter = extractRetryAfterValue(from: data) {
                            let seconds = Double(retryAfter) / 1000.0
                            let formattedTime = String(format: "%.1f", seconds)

                            // Increase the minimum API call interval based on server response
                            minimumAPICallInterval = max(
                                minimumAPICallInterval, min(Double(retryAfter) / 1000.0, 30.0))

                            // Show user-friendly message with the retry time
                            print(
                                "⏳ RATE_LIMIT: Please wait \(formattedTime) seconds before loading more messages."
                            )

                            // Update the last API call time to enforce the retry_after delay
                            lastAPICallTime = Date().addingTimeInterval(
                                -minimumAPICallInterval + Double(retryAfter) / 1000.0)
                        } else {
                            // Fallback message if we couldn't extract the retry time
                            print(
                                "⏳ RATE_LIMIT: Please wait a few seconds before loading more messages."
                            )

                            // Set a default delay
                            minimumAPICallInterval = max(minimumAPICallInterval, 5.0)
                            lastAPICallTime = Date()
                        }
                    } else {
                        // Generic error handling for other errors
                        let banner = NotificationBanner(
                            message: "Failed to load messages: \(error.localizedDescription)")
                        banner.show(duration: 2.0)
                    }
                }
            } catch {
                // print("⬇️⬇️⬇️ ERROR: Unknown error in API call: \(error)")

                // Reset loading state on main thread
                await MainActor.run {
                    isLoadingMore = false
                    messageLoadingState = .notLoading

                    // Show generic error message
                    let banner = NotificationBanner(
                        message: "Failed to load messages: \(error.localizedDescription)")
                    banner.show(duration: 2.0)
                }
            }
        }

        // Set a timeout to reset loading state if task gets stuck
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            guard let self = self else { return }

            // If we're still loading after 15 seconds
            if self.isLoadingMore && Date().timeIntervalSince(loadStartTime) >= 15.0 {
                // print("⬇️⬇️⬇️ TIMEOUT: API call didn't complete in 15 seconds, resetting loading state")
                self.isLoadingMore = false
                self.messageLoadingState = .notLoading
                task.cancel()  // Try to cancel the task
            }
        }
    }
}

// RepliesContainerViewDelegate conformance moved to RepliesManager

// Add image tap handler to MessageCell
extension MessageCell {
    @objc func handleImageTap(_ gesture: UITapGestureRecognizer) {
        if let imageView = gesture.view as? UIImageView, let image = imageView.image {
            onImageTapped?(image)
        }
    }
}

// Legacy scroll view delegate methods (moved to extensions)

// MARK: - TypingIndicatorView

// MARK: - MessageInputViewDelegate Implementation (Moved to MessageInputHandler)
// The MessageInputViewDelegate methods have been moved to MessageInputHandler
// for better separation of concerns.

// MARK: - MessageableChannelViewController showErrorAlert Extension  (Moved to MessageableChannelViewController+Extensions.swift)

// MARK: - UIImagePickerControllerDelegate Implementation
// Note: UIImagePickerControllerDelegate is now handled by MessageInputHandler

// MARK: - UITableViewDataSourcePrefetching tableView (Moved to MessageableChannelViewController+Extensions.swift)

// MARK: - Empty State Handling showEmptyStateView()  (Moved to MessagableChannelViewController+Extensions.swift)


// MARK: - NSFWOverlayView and Delegate (Moved to NSFWOverlayView.swift)

// Add simple notification banner to show messages to the user 
private class NotificationBanner {
    private let containerView = UIView()
    private let messageLabel = UILabel()

    init(message: String) {
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        containerView.layer.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.text = message
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
        ])
    }

    func show(duration: TimeInterval = 2.0) {
        guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return
        }

        keyWindow.addSubview(containerView)

        // Position at top center
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(
                equalTo: keyWindow.safeAreaLayoutGuide.topAnchor, constant: 20),
            containerView.centerXAnchor.constraint(equalTo: keyWindow.centerXAnchor),
            containerView.widthAnchor.constraint(
                lessThanOrEqualTo: keyWindow.widthAnchor, constant: -40),
        ])

        // Start with alpha 0
        containerView.alpha = 0.0

        // Animate in
        UIView.animate(withDuration: 0.3) {
            self.containerView.alpha = 1.0
        }

        // Auto dismiss after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(
                withDuration: 0.3,
                animations: {
                    self.containerView.alpha = 0.0
                }
            ) { _ in
                self.containerView.removeFromSuperview()
            }
        }
    }
}



// Add these extensions at the end of the file, just before the last curly brace

// MARK: - Extension MessageCell (Moved to MessageableChannelViewController+MessageCell)

// MARK: - UITextViewDelegate (moved to extension)

// MARK: - Helper Functions
/// Generates a dynamic message link based on the current domain
private func generateMessageLink(
    serverId: String?, channelId: String, messageId: String, viewState: ViewState
) async -> String {
    // Get the current base URL and determine the web domain
    let baseURL = await viewState.baseURL ?? viewState.defaultBaseURL
    let webDomain: String

    if baseURL.contains("peptide.chat") {
        webDomain = "https://peptide.chat"
    } else if baseURL.contains("app.revolt.chat") {
        webDomain = "https://app.revolt.chat"
    } else {
        // Fallback for other instances - extract domain from API URL
        if let url = URL(string: baseURL),
            let host = url.host
        {
            webDomain = "https://\(host)"
        } else {
            webDomain = "https://app.revolt.chat"  // Ultimate fallback
        }
    }

    // Generate proper URL based on channel type
    if let serverId = serverId, !serverId.isEmpty {
        // Server channel
        return "\(webDomain)/server/\(serverId)/channel/\(channelId)/\(messageId)"
    } else {
        // DM channel
        return "\(webDomain)/channel/\(channelId)/\(messageId)"
    }
}
