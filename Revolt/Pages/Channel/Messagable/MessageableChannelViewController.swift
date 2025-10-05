//
//  MessageableChannelViewController.swift
//  Revolt
//

import UIKit
import Combine
import Types
import Kingfisher
import ObjectiveC
import SwiftUI

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
class MessageableChannelViewController: UIViewController, UITextFieldDelegate, NSFWOverlayViewDelegate, UIGestureRecognizerDelegate {
    var tableView: UITableView!
    var viewModel: MessageableChannelViewModel
    // Change the type of dataSource to accept both MessageTableViewDataSource and its subclasses
    var dataSource: UITableViewDataSource!
    private var cancellables = Set<AnyCancellable>()
    
    // IMPORTANT NEW PROPERTY: Local copy of messages that we control completely
    var localMessages: [String] = []
    
    // Properties needed for NSFW handling
    private var over18HasSeen: Bool = false
    var isLoadingMore: Bool = false
    
    // Skeleton loading view
    private var skeletonView: MessageSkeletonView?
    
    // Add a variable to track the exact loading state
    enum LoadingState: Equatable {
        case loading
        case notLoading
    }
    
    // Store loading task separately
    private var loadingTask: Task<Void, Never>? = nil
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
    var lastScrollToBottomTime: Date?
    let scrollDebounceInterval: TimeInterval = 2.0
    var networkErrorCooldown: TimeInterval = 5.0
    var maxLogMessages = 20
    var minimumAPICallInterval: TimeInterval = 3.0
    
    // Replies view properties
    private var repliesView: RepliesContainerView?
    
    // Custom navigation header
    var headerView: UIView!
    private var backButton: UIButton!
    private var channelNameLabel: UILabel!
    private var channelIconView: UIImageView!
    private var searchButton: UIButton!
    
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
    var replies: [ReplyMessage] = [] // Made public for Manager access
    
    // Toggle sidebar callback
    var toggleSidebar: (() -> Void)?
    
    // Track whether we're returning from search to prevent unnecessary cleanup
	var isReturningFromSearch: Bool = false
    
    // Target message ID to scroll to
    var targetMessageId: String? {
        didSet {
            print("🎯 MessageableChannelViewController: targetMessageId changed from \(oldValue ?? "nil") to \(targetMessageId ?? "nil")")
            
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
    private var clearTargetMessageTimer: Timer?
    
    // Track when target message was last highlighted to prevent auto-scroll
    internal var lastTargetMessageHighlightTime: Date?
    
    // Track if user reached this position via target message (to prevent auto-reload)
    internal var isInTargetMessagePosition: Bool = false
    
    // SIMPLIFIED TARGET MESSAGE PROTECTION
    // User can scroll freely anywhere without clearing protection
    internal var targetMessageProtectionActive: Bool {
        return targetMessageId != nil ||
               isInTargetMessagePosition ||
               targetMessageProcessed
    }
    
    // Method to safely activate target message protection to prevent jumping
    internal func activateTargetMessageProtection(reason: String) {
        print("🛡️ ACTIVATE_PROTECTION: Activating target message protection - reason: \(reason)")
        isInTargetMessagePosition = true
        lastTargetMessageHighlightTime = Date()
        targetMessageProcessed = false
        
        // Clear any existing timer to prevent premature clearing
        clearTargetMessageTimer?.invalidate()
        clearTargetMessageTimer = nil
        
        // IMPROVED: Set a very long fallback timer (5 minutes) to eventually clear protection
        // This gives user plenty of time to explore chat context freely
        clearTargetMessageTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: false) { [weak self] _ in
            self?.clearTargetMessageProtection(reason: "5-minute fallback timer")
        }
    }
    
    // Method to safely clear target message protection when user explicitly interacts
    internal func clearTargetMessageProtection(reason: String) {
        print("🎯 CLEAR_PROTECTION: Clearing target message protection - reason: \(reason)")
        print("🎯 CLEAR_PROTECTION: Previous state - targetMessageId: \(targetMessageId ?? "nil"), isInPosition: \(isInTargetMessagePosition), processed: \(targetMessageProcessed)")
        targetMessageId = nil
        isInTargetMessagePosition = false
        lastTargetMessageHighlightTime = nil
        targetMessageProcessed = false
        clearTargetMessageTimer?.invalidate()
        clearTargetMessageTimer = nil
        viewModel.viewState.currentTargetMessageId = nil
        print("🎯 CLEAR_PROTECTION: Protection successfully cleared")
    }
    
    // Debug function to check protection status
    internal func debugTargetMessageProtection() {
        print("🔍 TARGET_MESSAGE_DEBUG:")
        print("   - targetMessageId: \(targetMessageId ?? "nil")")
        print("   - isInTargetMessagePosition: \(isInTargetMessagePosition)")
        print("   - targetMessageProcessed: \(targetMessageProcessed)")
        print("   - protectionActive: \(targetMessageProtectionActive)")
        print("   - timer active: \(clearTargetMessageTimer != nil)")
        if let timer = clearTargetMessageTimer {
            print("   - timer remaining: \(timer.fireDate.timeIntervalSinceNow)s")
        }
    }
    
    // ULTIMATE PROTECTION: Override scrollToRow to block ALL unwanted auto-scrolls
    internal func safeScrollToRow(at indexPath: IndexPath, at position: UITableView.ScrollPosition, animated: Bool, reason: String) {
        print("🔍 SCROLL_ATTEMPT: \(reason) - target row: \(indexPath.row), position: \(position), animated: \(animated)")
        debugTargetMessageProtection()
        
        // Allow target message navigation and user-initiated scrolls
        let allowedReasons = ["target message", "scroll to specific message", "user interaction"]
        let isAllowedReason = allowedReasons.contains { reason.lowercased().contains($0.lowercased()) }
        
        if targetMessageProtectionActive && !isAllowedReason {
            print("🛡️ BLOCKED_SCROLL: scrollToRow blocked by protection - reason: \(reason)")
            print("🛡️ BLOCKED_SCROLL: attempted scroll to row \(indexPath.row), position: \(position), animated: \(animated)")
            return
        }
        
        if isAllowedReason {
            print("✅ ALLOWED_SCROLL: scrollToRow allowed (whitelisted reason) - \(reason)")
        } else {
            print("✅ ALLOWED_SCROLL: scrollToRow allowed (no protection) - \(reason)")
        }
        tableView.scrollToRow(at: indexPath, at: position, animated: animated)
    }
    
    // Enhanced scrollToBottom with protection debugging  
    func logScrollToBottomAttempt(animated: Bool, reason: String) {
        print("🔍 SCROLL_TO_BOTTOM_ATTEMPT: \(reason) - animated: \(animated)")
        debugTargetMessageProtection()
    }
    
    // Add class-level variable to prevent duplicate API calls
    private static var loadingChannels = Set<String>()
    private static var loadingMutex = NSLock()
    
    // Add a new property that tracks if we have already scrolled to the target message

    
    // Public accessor for ViewState to be used by ReplyItemView
    func getViewState() -> ViewState {
        return viewModel.viewState
    }
    
    // MARK: - Managers
    lazy var permissionsManager = PermissionsManager(viewModel: viewModel, viewController: self)
    private lazy var repliesManager = RepliesManager(viewModel: viewModel, viewController: self)
    private lazy var typingIndicatorManager = TypingIndicatorManager(viewModel: viewModel, viewController: self)
    private lazy var scrollPositionManager = ScrollPositionManager(viewController: self)
    private lazy var messageInputHandler = MessageInputHandler(viewModel: viewModel, viewController: self, repliesManager: repliesManager)
    
        // MARK: - Public Properties for Manager Access
    // lastManualScrollUpTime is defined as stored property above
    
    // Add a private property to monitor recent log messages after class declaration
    private var recentLogMessages = [String]()
    private var lastNetworkErrorTime: Date?
    
    // CRITICAL: Add debounce mechanism to prevent infinite notification loops
    private var lastMessageChangeNotificationTime: Date = .distantPast
    private let messageChangeDebounceInterval: TimeInterval = 0.5 // 500ms minimum between processing notifications
    
    // Add these properties after other properties
    // Rate limiting properties
    private var lastAPICallTime: Date = .distantPast
    private var pendingAPICall: DispatchWorkItem?
    private var isThrottled = false
    
    // Track if returning from search to prevent unwanted scrolling
    private var wasInSearch = false
    
    // CRITICAL MEMORY MANAGEMENT: Add message count limits to prevent memory issues
    private let maxLocalMessagesInMemory = 400
    private let maxViewStateMessagesPerChannel = 400
    private let memoryCleanupThreshold = 400
    
    // Add this property to track the last before message id
    private var lastBeforeMessageId: String? = nil
    
    // JUMPING FIX: Track inset adjustments to prevent excessive calls
    private var lastInsetAdjustmentTime: Date = .distantPast
    private var lastMessageCountForInsets: Int = 0
    private let insetAdjustmentCooldown: TimeInterval = 1.0 // 1 second cooldown
    
    // MEMORY MANAGEMENT: Automatic cleanup timer
    var memoryCleanupTimer: Timer? // Changed to internal for extension access
    private let memoryCleanupInterval: TimeInterval = 30.0 // Clean up every 30 seconds
    
    // Add this property to track if we're currently loading older messages
    private var isLoadingOlderMessages = false
    
    // Track scroll position for infinite scroll down detection
    internal var lastScrollOffset: CGFloat = 0
    
    // Flag to prevent concurrent cleanup operations
    private var isCleaningUp = false
    
    init(viewModel: MessageableChannelViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    init(viewModel: MessageableChannelViewModel, toggleSidebar: (() -> Void)? = nil, targetMessageId: String? = nil) {
        self.viewModel = viewModel
        self.toggleSidebar = toggleSidebar
        self.targetMessageId = targetMessageId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Performance Optimization Flags
    private var hasLoadedInitialData = false
    private var hasSetupHeavyComponents = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 🚀 PERFORMANCE: Basic UI setup only (essential components)
        setupBasicUI()
        
        // 🚀 PERFORMANCE: Defer heavy operations to background
        DispatchQueue.main.async {
            self.setupHeavyComponentsInBackground()
        }
        
        // 🚀 PERFORMANCE: Load data immediately in viewDidLoad
        loadInitialDataIfNeeded()
        
        print("⚡ PERFORMANCE: viewDidLoad completed - basic UI + data loading")
    }
    
    // MARK: - Performance Optimized Setup Methods
    
    /// Sets up only essential UI components for immediate display
    private func setupBasicUI() {
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
        
        // Essential UI components only
        setupCustomHeader()
        setupTableView()
        setupMessageInput()
        
        // Basic observers only
        setupBasicObservers()
        
        // Initialize message count tracking
        lastKnownMessageCount = localMessages.count
        
        // CRITICAL FIX: Reset empty response time for new channel
        lastEmptyResponseTime = nil
        print("🔄 INIT: Reset lastEmptyResponseTime for new channel")
        
        // Check if the channel is NSFW
        if viewModel.channel.nsfw && !self.over18HasSeen {
            self.over18HasSeen = true
            showNSFWOverlay()
        }
    }
    
    /// Sets up heavy components in background to avoid blocking UI
    private func setupHeavyComponentsInBackground() {
        guard !hasSetupHeavyComponents else { return }
        hasSetupHeavyComponents = true
        
        print("⚡ PERFORMANCE: Starting background setup")
        
        // Heavy UI components
        setupNewMessageButton()
        setupSwipeGesture()
        setupKeyboardObservers()
        setupAdditionalMessageObservers()
        
        // Initialize managers
        _ = typingIndicatorManager
        
        // Configure UI based on permissions
        permissionsManager.configureUIBasedOnPermissions()
        
        // Additional observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemLog),
            name: NSNotification.Name("SystemLogMessage"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChannelSearchClosing),
            name: NSNotification.Name("ChannelSearchClosing"),
            object: nil
        )
        
        print("⚡ PERFORMANCE: Background setup completed")
    }
    
    /// Sets up only basic observers needed for immediate functionality
    private func setupBasicObservers() {
        // Essential message observer only
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(messagesDidChange),
            name: NSNotification.Name("MessagesDidChange"),
            object: nil
        )
    }
    
    // Additional helper to force scroll after a message is added
    private func setupAdditionalMessageObservers() {
        // Listen for new messages through a simple notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewMessages),
            name: NSNotification.Name("NewMessagesReceived"),
            object: nil
        )
        
        // Add a network error observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkError),
            name: NSNotification.Name("NetworkErrorOccurred"),
            object: nil
        )
        
        // Add observer for new socket messages ONLY for new message indicator
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewSocketMessage),
            name: NSNotification.Name("NewSocketMessageReceived"),
            object: nil
        )
        
        // Add a timer to periodically check for scroll needed, but with a longer interval
        // This reduces unnecessary checks that could cause unwanted scrolling
        Timer.scheduledTimer(timeInterval: 10.0, target: self, selector: #selector(checkForScrollNeeded), userInfo: nil, repeats: true)
        
        // Start automatic memory cleanup timer to prevent memory crashes
        startMemoryCleanupTimer()
        
        // Add observer for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Add observer for channel search closed to detect returning from search
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChannelSearchClosed),
            name: NSNotification.Name("ChannelSearchClosed"),
            object: nil
        )
        
        // Add observer for video player dismiss
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVideoPlayerDismiss),
            name: NSNotification.Name("VideoPlayerDidDismiss"),
            object: nil
        )
    }
    
    // New: Only show new message button if a new message is received from socket and user is not at bottom
    @objc private func handleNewSocketMessage(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
              let channelId = userInfo["channelId"] as? String,
              channelId == viewModel.channel.id else { return }
        
        // print debug info for socket message
        // print("🔔 SOCKET: Received socket message for channel \(channelId)")
        
        let hasManuallyScrolledUp = lastManualScrollUpTime != nil &&
                                    Date().timeIntervalSince(lastManualScrollUpTime!) < 10.0
        
        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if !isUserNearBottom() || hasManuallyScrolledUp || targetMessageProtectionActive {
            // This is the ONLY place where showNewMessageButton should be called
            showNewMessageButton()
            // print("🔔 SOCKET: Showing new message button because user is not at bottom or target highlighted")
        } else {
            // print("🔔 SOCKET: User is at bottom, auto-scrolling instead of showing button")
            // Use proper scrolling method that considers keyboard state
            if isKeyboardVisible && !localMessages.isEmpty {
                let lastIndex = localMessages.count - 1
                if lastIndex >= 0 && lastIndex < tableView.numberOfRows(inSection: 0) {
                    let indexPath = IndexPath(row: lastIndex, section: 0)
                    safeScrollToRow(at: indexPath, at: .bottom, animated: true, reason: "socket message with keyboard")
                }
            } else {
                scrollToBottom(animated: true)
            }
        }
    }
    
    // Add new method to handle network errors
    @objc private func handleNetworkError(_ notification: Notification) {
        // print("⚠️ Network error detected, preventing automatic scrolls for 5 seconds")
        
        // Temporarily increase the debounce time after network error
        let errorDebounceTime = Date().addingTimeInterval(5.0)
        lastScrollToBottomTime = errorDebounceTime
        
        // Block new message notifications from causing scrolls for a while
        UserDefaults.standard.set(viewModel.messages.count, forKey: "LastMessageCount_\(viewModel.channel.id)")
    }
    
    // Handle channel search closed to detect returning from search
    @objc private func handleChannelSearchClosed(_ notification: Notification) {
        // Check if the notification is for this channel
        guard let channelId = notification.object as? String,
              channelId == viewModel.channel.id else {
            return
        }
        
                 // Set flag to prevent unwanted scrolling when returning from search
         isReturningFromSearch = true
         wasInSearch = false
         // print("🔍 SEARCH_CLOSED: Channel search closed for channel \(channelId), setting flag to prevent scroll")
         
         // Reset the flag after a short delay to ensure it doesn't interfere with future navigation
         DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
             self.isReturningFromSearch = false
         }
    }
    
    // Handle video player dismiss to ensure navigation bar is hidden
    @objc private func handleVideoPlayerDismiss(_ notification: Notification) {
        // print("🎬 MessageableChannelViewController: Video player dismissed, ensuring navigation bar is hidden")
        
        // Force hide navigation bar
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        // Force layout update
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        // Double-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.navigationController?.setNavigationBarHidden(true, animated: false)
        }
    }
    
    // Update handleNewMessages to only scroll if user is near bottom
    @objc private func handleNewMessages(_ notification: Notification) {
        // CRITICAL FIX: Don't handle new messages during nearby loading
        if messageLoadingState == .loading {
            print("📬 BLOCKED: handleNewMessages blocked - nearby loading in progress")
            return
        }
        
        // CRITICAL FIX: Don't handle if target message protection is active
        if targetMessageProtectionActive {
            print("📬 BLOCKED: handleNewMessages blocked - target message protection active")
            return
        }
        
        let currentMessageCount = viewModel.messages.count
        let storedMessageCount = UserDefaults.standard.integer(forKey: "LastMessageCount_\(viewModel.channel.id)")
        
        // Only scroll if there are actual new messages
        if currentMessageCount > storedMessageCount {
            // print("📬 Direct notification of new messages - found \(currentMessageCount - storedMessageCount) new messages")
            // Update stored count
            UserDefaults.standard.set(currentMessageCount, forKey: "LastMessageCount_\(viewModel.channel.id)")
            
            // Check if user has manually scrolled up recently
            let hasManuallyScrolledUp = lastManualScrollUpTime != nil && 
                                       Date().timeIntervalSince(lastManualScrollUpTime!) < 10.0
            
            // COMPREHENSIVE TARGET MESSAGE PROTECTION
            // Only scroll if user is near bottom AND hasn't manually scrolled up recently AND no target message protection
            if isUserNearBottom() && !hasManuallyScrolledUp && !targetMessageProtectionActive {
                // First scroll immediately
                scrollToBottom(animated: true)
                // Then schedule multiple scrolls with delays to ensure we catch the UI update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.scrollToBottom(animated: true)
                    // One more scroll after a bit longer delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.scrollToBottom(animated: false)
                    }
                }
            } else {
                // print("👆 User is not near bottom or has manually scrolled up, not auto-scrolling")
                // Do NOT show new message button here anymore
                // showNewMessageButton() // <-- REMOVE THIS LINE
            }
        } else {
            // print("📬 Message notification received but no new messages found. Ignoring scroll request.")
        }
    }
    
    @objc private func checkForScrollNeeded() {
        // Skip checks if tableView is nil or user is actively scrolling or we're loading more messages
        guard let tableView = tableView else { return }
        if tableView.isDragging || tableView.isDecelerating || isLoadingMore {
            return
        }
        
        // Add a variable to track user's last manual scroll time
        if let lastManualScrollTime = lastManualScrollTime, Date().timeIntervalSince(lastManualScrollTime) < 10.0 {
                          // If less than 10 seconds have passed since the last manual scroll, do nothing
            return
        }
        
        // Only check if we have messages and the app is active
        guard !viewModel.messages.isEmpty, 
              UIApplication.shared.applicationState == .active else {
            return
        }
        
        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            return
        }
        
        // Only scroll if we're near bottom already AND not showing last message
        // If we're in the middle or top of chat, don't auto-scroll
        if isUserNearBottom(threshold: 100) {
            // Check if the last visible row is already the last message or close to it
            if let lastVisibleRow = tableView.indexPathsForVisibleRows?.last?.row,
               lastVisibleRow >= viewModel.messages.count - 2 {
                // Already showing the last message or very close, don't scroll
                return
            }
            
            // Check if enough time has passed since the last message update
            let timeSinceLastUpdate = Date().timeIntervalSince(lastMessageUpdateTime)
            if timeSinceLastUpdate < minimumUpdateInterval {
                // Too soon after a message update, skip scrolling
                return
            }
            
            // Only scroll if we're already near bottom but not showing last message
           // // print("⏱️ Timer check - auto-scrolling since user is near bottom but not showing last message")
            scrollToBottom(animated: true)
        } else {
           // // print("👆 [Timer] User is not near bottom, skipping auto-scroll")
        }
    }
    
    // Setup new message button for scrolling to bottom
    private func setupNewMessageButton() {
        // New message button
        newMessageButton = UIButton(type: .system)
        newMessageButton.translatesAutoresizingMaskIntoConstraints = false
        newMessageButton.backgroundColor = .systemBlue
        newMessageButton.layer.cornerRadius = 16
        newMessageButton.layer.masksToBounds = true
        newMessageButton.setTitle("New Messages", for: .normal)
        newMessageButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        newMessageButton.setTitleColor(.white, for: .normal)
        newMessageButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        newMessageButton.addTarget(self, action: #selector(newMessageButtonTapped), for: .touchUpInside)
        newMessageButton.layer.shadowColor = UIColor.black.cgColor
        newMessageButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        newMessageButton.layer.shadowOpacity = 0.3
        newMessageButton.layer.shadowRadius = 3
        
        // Add an icon to the button
        let arrowImage = UIImage(systemName: "arrow.down")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: arrowImage)
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        newMessageButton.addSubview(imageView)
        
        // Position the image on the left side of the button
        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: newMessageButton.centerYAnchor),
            imageView.leadingAnchor.constraint(equalTo: newMessageButton.leadingAnchor, constant: 10),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        // Adjust button title insets to make room for the image
        newMessageButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        
        // Hide the button initially
        newMessageButton.alpha = 0
        newMessageButton.isHidden = true
        
        // Add to view hierarchy
        view.addSubview(newMessageButton)
        
        // Position at the bottom center of the screen, above the message input
        NSLayoutConstraint.activate([
            newMessageButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            newMessageButton.bottomAnchor.constraint(equalTo: messageInputView.topAnchor, constant: -16),
            newMessageButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    @objc private func newMessageButtonTapped() {
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
    
    private func showNewMessageButton() {
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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // 🚀 PERFORMANCE: Data already loaded in viewDidLoad, just handle viewDidAppear logic
        handleViewDidAppearLogic()
        
        print("⚡ PERFORMANCE: viewDidAppear completed - data already loaded")
    }
    
    // MARK: - Performance Optimized Data Loading
    
    /// Loads initial data immediately in viewDidLoad
    private func loadInitialDataIfNeeded() {
        guard !hasLoadedInitialData else { return }
        hasLoadedInitialData = true
        
        print("⚡ PERFORMANCE: Starting immediate data loading in viewDidLoad")
        
        // CRITICAL FIX: Check if we have a target message from ViewState before loading
        if let targetFromViewState = viewModel.viewState.currentTargetMessageId {
            print("🎯 PERFORMANCE: Target message found in ViewState: \(targetFromViewState), skipping regular load")
            targetMessageId = targetFromViewState
            targetMessageProcessed = false
        } else {
            // Load messages immediately
            Task {
                await loadInitialMessages()
            }
        }
    }
    
    /// Handles existing viewDidAppear logic (search return, target messages, etc.)
    private func handleViewDidAppearLogic() {
        // CRITICAL FIX: Check if we have a target message from ViewState that we need to restore
        if targetMessageId == nil, let targetFromViewState = viewModel.viewState.currentTargetMessageId {
            print("🎯 VIEW_DID_APPEAR: Restoring target message from ViewState: \(targetFromViewState)")
            targetMessageId = targetFromViewState
            targetMessageProcessed = false
        }
        
        // Check if we're returning from search - if so, reload messages and skip scroll-related operations
        if isReturningFromSearch {
            print("🔍 VIEW_DID_APPEAR: Returning from search, reloading messages")
            
            // Re-register observer
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MessagesDidChange"), object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(messagesDidChange),
                name: NSNotification.Name("MessagesDidChange"),
                object: nil
            )
            
            // Check if we have messages in ViewState
            let channelId = viewModel.channel.id
            let hasMessages = !(viewModel.viewState.channelMessages[channelId]?.isEmpty ?? true)
            
            if hasMessages {
                // Reload messages to show them again
                refreshMessages()
                
                // Show table view if hidden
                if tableView.alpha == 0.0 {
                    tableView.alpha = 1.0
                }
                
                // Scroll to bottom if messages exist
                if !localMessages.isEmpty {
                    scrollToBottom(animated: false)
                }
            } else {
                // No messages in ViewState, need to reload from API
                print("🔍 VIEW_DID_APPEAR: No messages in ViewState, reloading from API")
                
                // Show loading indicator
                tableView.alpha = 0.0
                let spinner = UIActivityIndicatorView(style: .large)
                spinner.startAnimating()
                spinner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
                tableView.tableFooterView = spinner
                
                // Reload messages from API
                Task {
                    await loadInitialMessages()
                }
            }
            
            // Reset the flag after processing
            isReturningFromSearch = false
            print("🔍 VIEW_DID_APPEAR: Cleared isReturningFromSearch flag")
            
            return
        }
        
        // CRITICAL FIX: Don't apply global fix during cross-channel target message navigation
        if targetMessageId == nil && !targetMessageProtectionActive {
            // Apply Global Fix to ensure message display and fix black screen issues
            applyGlobalFix()
            
            // Update table view bouncing behavior when view appears
            updateTableViewBouncing()
        } else {
            print("🎯 VIEW_DID_APPEAR: Skipping global fix - target message navigation in progress")
        }
        
       // // print("🔄 VIEW_DID_APPEAR: View appeared, checking notification observers")
        
        // Ensure notification observer is registered for all MessagesDidChange notifications
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MessagesDidChange"), object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(messagesDidChange),
            name: NSNotification.Name("MessagesDidChange"),
            object: nil // Set to nil to receive all notifications with this name
        )
       // // print("🔄 VIEW_DID_APPEAR: Re-registered MessagesDidChange observer")
        
        // Check if we're already loading this channel
        let channelId = viewModel.channel.id
        
        // If we don't have a specific target message and table is hidden, show it properly positioned
        if targetMessageId == nil && !viewModel.messages.isEmpty && tableView.alpha == 0.0 {
            print("📱 VIEW_DID_APPEAR: Positioning table at bottom and showing")
            positionTableAtBottomBeforeShowing()
            
            // Adjust table insets after positioning
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.adjustTableInsetsForMessageCount()
            }
        }
        
        // Note: Automatic preloading is controlled by ViewState.enableAutomaticPreloading
        // When disabled, messages are loaded only when user explicitly enters the channel
        print("📵 PRELOAD_CONTROLLED: Automatic preloading controlled by ViewState setting for channel \(channelId)")
        
        // CRITICAL FIX: Check if user is in target message position to prevent reload
        if isInTargetMessagePosition {
            print("🎯 VIEW_DID_APPEAR: User is in target message position, preserving current view")
            return
        }
        
        // CRITICAL FIX: Always prioritize target message handling over existing messages
        if targetMessageId != nil {
            print("🎯 VIEW_DID_APPEAR: Target message found, using nearby API (prioritized over existing messages)")
            
            // CRITICAL FIX: Don't trigger loading if already in progress
            if messageLoadingState == .loading {
                print("🎯 VIEW_DID_APPEAR: Loading already in progress, skipping duplicate trigger")
                return
            }
            
            // CRITICAL FIX: Set loading state and hide empty state before starting
            messageLoadingState = .loading
            DispatchQueue.main.async {
                self.hideEmptyStateView()
                print("🚫 VIEW_DID_APPEAR: Hidden empty state before target message loading")
            }
            
            // Show loading spinner and trigger target message loading
            tableView.alpha = 0.0
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.startAnimating()
            spinner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
            tableView.tableFooterView = spinner
            
            // Trigger target message loading which will use nearby API
            Task {
                print("🎯 VIEW_DID_APPEAR: Triggering target message loading")
                await loadInitialMessages()
                
                // Adjust table insets after loading messages
                DispatchQueue.main.async {
                    self.adjustTableInsetsForMessageCount()
                    
                    // CRITICAL FIX: Check for missing reply content after initial load with delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        Task {
                            print("🔗 VIEW_APPEARED: Checking for missing replies after delay (first case)")
                            await self.checkAndFetchMissingReplies()
                        }
                    }
                }
            }
        } else {
            // SMART LOADING: Check if we have actual message objects, not just IDs (only when no target message)
            let hasActualMessages = !(viewModel.viewState.channelMessages[channelId]?.isEmpty ?? true) &&
                                   viewModel.viewState.channelMessages[channelId]?.first(where: { viewModel.viewState.messages[$0] != nil }) != nil
            
            if hasActualMessages {
                print("✅ VIEW_DID_APPEAR: Messages already loaded, showing immediately")
                // Messages exist, show them immediately without loading
                tableView.alpha = 1.0
                tableView.tableFooterView = nil
                refreshMessages()
                
                // Adjust table insets and check for missing replies
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    await MainActor.run {
                    self.adjustTableInsetsForMessageCount()
                    }
                    await self.checkAndFetchMissingReplies()
                }
            } else {
                print("🚀 VIEW_DID_APPEAR: No messages found, loading from API IMMEDIATELY")
                
                // Show skeleton loading view instead of spinner
                showSkeletonView()
                
                // Start loading immediately without any delays
                Task {
                    print("🚀 IMMEDIATE_LOAD: Starting API call NOW for channel \(channelId)")
                    //await loadInitialMessagesImmediate()
                    
                    // Hide skeleton and show messages
                    DispatchQueue.main.async {
                        self.hideSkeletonView()
                        self.adjustTableInsetsForMessageCount()
                    
                    // CRITICAL FIX: Check for missing reply content after initial load with delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        Task {
                            print("🔗 VIEW_APPEARED: Checking for missing replies after delay (second case)")
                            await self.checkAndFetchMissingReplies()
                        }
                    }
                    }
                }
            }
        }
        
        // Check if the channel is NSFW
        if viewModel.channel.nsfw && !self.over18HasSeen {
            self.over18HasSeen = true
            showNSFWOverlay()
        }
        
        // Apply global fix after view appears to ensure messages are visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            // Only apply fix if table is empty but we have messages
            if self.tableView.numberOfRows(inSection: 0) == 0 && !(self.viewModel.viewState.channelMessages.isEmpty) {
                self.applyGlobalFix()
            }
        }
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
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Show navigation bar when leaving this view
        navigationController?.setNavigationBarHidden(false, animated: animated)
        
        // Restore tab bar if needed
        tabBarController?.tabBar.isHidden = false
        
        // Dismiss keyboard if visible
        view.endEditing(true)
        
        print("🚀 IMMEDIATE_CLEANUP: Starting INSTANT memory cleanup for channel \(viewModel.channel.id)")
        let cleanupStartTime = CFAbsoluteTimeGetCurrent()
        
        // IMMEDIATE: Cancel all pending operations first
        scrollToBottomWorkItem?.cancel()
        scrollToBottomWorkItem = nil
        scrollProtectionTimer?.invalidate()
        scrollProtectionTimer = nil
        loadingTask?.cancel()
        loadingTask = nil
        pendingAPICall?.cancel()
        pendingAPICall = nil
        
        // CRITICAL FIX: Don't clear target message ID if it's for a different channel (navigation to new channel)
        if let targetId = viewModel.viewState.currentTargetMessageId {
            // Check if target message is for the current (old) channel or a different (new) channel
            if let targetMessage = viewModel.viewState.messages[targetId] {
                if targetMessage.channel == viewModel.channel.id {
                    // Target message is for THIS (old) channel - we can clear it safely
                    print("🎯 IMMEDIATE_CLEANUP: Target message is for current channel \(viewModel.channel.id), clearing it")
                    viewModel.viewState.currentTargetMessageId = nil
                    targetMessageId = nil
                    targetMessageProcessed = false
                } else {
                    // Target message is for DIFFERENT (new) channel - preserve it!
                    print("🎯 IMMEDIATE_CLEANUP: Target message is for different channel \(targetMessage.channel), preserving it")
                }
            } else {
                // Target message not loaded yet - this means we're navigating to find it, so preserve it
                print("🎯 IMMEDIATE_CLEANUP: Target message not loaded yet, preserving for navigation")
            }
        }
        
        // Stop automatic memory cleanup timer
        stopMemoryCleanupTimer()
        
        // CRITICAL FIX: Don't cleanup if we're returning from search
        if isReturningFromSearch {
            print("🔍 IMMEDIATE_CLEANUP: Returning from search, skipping ALL cleanup")
            return
        }
        
        // IMMEDIATE CLEANUP: Always perform instant cleanup regardless of navigation
        performInstantMemoryCleanup()
        
        let cleanupEndTime = CFAbsoluteTimeGetCurrent()
        let cleanupDuration = (cleanupEndTime - cleanupStartTime) * 1000
        print("🚀 IMMEDIATE_CLEANUP: Total viewWillDisappear cleanup completed in \(String(format: "%.2f", cleanupDuration))ms")
    }
    
    // MARK: - Memory Management
    // Memory management methods moved to MessageableChannelViewController+MemoryManagement.swift
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        
        // Ensure our view covers the entire screen
        view.frame = UIScreen.main.bounds
        
        // Update table view bouncing behavior when layout changes
        if tableView.window != nil {
            updateTableViewBouncing()
        }
    }
    
    private func setupCustomHeader() {
        // Create the header container
        headerView = UIView()
        headerView.backgroundColor = .bgDefaultPurple13 // Changed from .bgGray12 to match chat background
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        
        // Back button (left)
        backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        backButton.tintColor = .textDefaultGray01
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        headerView.addSubview(backButton)
        
        // Channel icon (next to back button)
        channelIconView = UIImageView()
        channelIconView.translatesAutoresizingMaskIntoConstraints = false
        channelIconView.contentMode = .scaleAspectFit
        channelIconView.clipsToBounds = true
        channelIconView.layer.cornerRadius = 18 // Adjusted for the larger size (36/2)
        channelIconView.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        channelIconView.isUserInteractionEnabled = true
        headerView.addSubview(channelIconView)
        
        // Add tap gesture to channel icon
        let iconTapGesture = UITapGestureRecognizer(target: self, action: #selector(channelHeaderTapped))
        channelIconView.addGestureRecognizer(iconTapGesture)
        
        // Channel name (next to icon)
        channelNameLabel = UILabel()
        channelNameLabel.text = viewModel.channel.getName(viewModel.viewState)
        channelNameLabel.textColor = .textDefaultGray01
        channelNameLabel.font = UIFont.boldSystemFont(ofSize: 16)
        channelNameLabel.translatesAutoresizingMaskIntoConstraints = false
        channelNameLabel.textAlignment = .left
        channelNameLabel.isUserInteractionEnabled = true
        headerView.addSubview(channelNameLabel)
        
        // Add tap gesture to channel name
        let nameTapGesture = UITapGestureRecognizer(target: self, action: #selector(channelHeaderTapped))
        channelNameLabel.addGestureRecognizer(nameTapGesture)
        
        // Search button (right)
        searchButton = UIButton(type: .system)
        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.tintColor = .textDefaultGray01
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.addTarget(self, action: #selector(searchButtonTapped), for: .touchUpInside)
        headerView.addSubview(searchButton)
        
        // Load channel icon based on channel type
        switch viewModel.channel {
        case .text_channel(let c):
            if let icon = c.icon {
                // Try to get the full URL for the channel icon
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(
                        with: iconUrl,
                        placeholder: UIImage(systemName: "number"),
                        options: [
                            .transition(.fade(0.2)),
                            .cacheOriginalImage
                        ]
                    )
                }
            } else {
                // Use hashtag icon for text channels
                channelIconView.image = UIImage(systemName: "number")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor.clear
            }
            
        case .voice_channel(let c):
            if let icon = c.icon {
                // Try to get the full URL for the channel icon
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(
                        with: iconUrl,
                        placeholder: UIImage(systemName: "speaker.wave.2.fill"),
                        options: [
                            .transition(.fade(0.2)),
                            .cacheOriginalImage
                        ]
                    )
                }
            } else {
                // Use speaker icon for voice channels
                channelIconView.image = UIImage(systemName: "speaker.wave.2.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor.clear
            }
            
        case .group_dm_channel(let c):
            if let icon = c.icon {
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(
                        with: iconUrl,
                        placeholder: UIImage(systemName: "person.2.circle.fill"),
                        options: [
                            .transition(.fade(0.2)),
                            .cacheOriginalImage
                        ]
                    )
                }
            } else {
                // Use group icon for group DM channels
                channelIconView.image = UIImage(systemName: "person.2.circle.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor(named: "bgGreen07")
            }
            
        case .dm_channel(let c):
            // For DM channels, show the other user's avatar
            if let recipient = viewModel.viewState.getDMPartnerName(channel: c) {
                let avatarInfo = viewModel.viewState.resolveAvatarUrl(user: recipient, member: nil, masquerade: nil)
                
                // Always load avatar (either actual or default) from URL
                channelIconView.kf.setImage(
                    with: avatarInfo.url,
                    placeholder: UIImage(systemName: "person.circle.fill"),
                    options: [
                        .transition(.fade(0.2)),
                        .cacheOriginalImage
                    ]
                )
                
                // Set background color based on whether user has avatar or not
                if !avatarInfo.isAvatarSet {
                    channelIconView.backgroundColor = UIColor(
                        hue: CGFloat(recipient.username.hashValue % 100) / 100.0,
                        saturation: 0.8,
                        brightness: 0.8,
                        alpha: 1.0
                    )
                } else {
                    channelIconView.backgroundColor = UIColor.clear
                }
            } else {
                // Fallback icon when recipient is nil
                channelIconView.image = UIImage(systemName: "person.circle.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor(named: "bgGray11")
            }
            
        case .saved_messages(_):
            // Use bookmark icon for saved messages
            channelIconView.image = UIImage(systemName: "bookmark.circle.fill")
            channelIconView.tintColor = .iconDefaultGray01
            channelIconView.backgroundColor = UIColor(named: "bgGreen07")
        }
        
        // Add bottom separator
        let separator = UIView()
        separator.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        separator.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(separator)
        
        // Setup constraints to position everything
        NSLayoutConstraint.activate([
            // Header view - Anchor to top edge of screen, not safe area
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 95), // Reduced from 100
            
            // Back button - Position at the bottom left
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            backButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -15), // Adjusted for smaller header
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 28),
            
            // Channel icon - Positioned next to back button
            channelIconView.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 10),
            channelIconView.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            channelIconView.widthAnchor.constraint(equalToConstant: 36), // Increased from 30
            channelIconView.heightAnchor.constraint(equalToConstant: 36), // Increased from 30
            
            // Channel name - Positioned next to channel icon
            channelNameLabel.leadingAnchor.constraint(equalTo: channelIconView.trailingAnchor, constant: 10),
            channelNameLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            channelNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: searchButton.leadingAnchor, constant: -10),
            
            // Search button - Position at the bottom right
            searchButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            searchButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 28),
            searchButton.heightAnchor.constraint(equalToConstant: 28),
            
            // Separator at the bottom
            separator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 0),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    @objc private func backButtonTapped() {
        print("🔙 BACK_BUTTON: Tapped - Channel: \(viewModel.channel.id), Server: \(viewModel.channel.server ?? "nil")")
        print("🔙 BACK_BUTTON: Channel type: \(type(of: viewModel.channel))")
        print("🔙 BACK_BUTTON: Current path count: \(viewModel.viewState.path.count)")
        print("🔙 BACK_BUTTON: Current path: \(viewModel.viewState.path)")
        print("🔙 BACK_BUTTON: lastInviteServerContext: \(viewModel.viewState.lastInviteServerContext ?? "nil")")
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
                print("🔙 BACK_BUTTON: Detected invite-style navigation (server channel with only maybeChannelViews)")
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
                    NotificationCenter.default.post(name: NSNotification.Name("ForceChannelListRefresh"), object: ["serverId": serverId])
                }
                
                print("🔙 BACK_BUTTON: After selectServer - currentSelection: \(viewModel.viewState.currentSelection)")
                print("🔙 BACK_BUTTON: After selectServer - currentChannel: \(viewModel.viewState.currentChannel)")
                print("🔙 BACK_BUTTON: Completed invite-style back navigation for server channel")
            } else {
                // DM or other non-server channel case
                print("🔙 BACK_BUTTON: Detected invite-style navigation (non-server channel with only maybeChannelViews)")
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
                    NotificationCenter.default.post(name: NSNotification.Name("ForceDMListRefresh"), object: nil)
                }
                
                print("🔙 BACK_BUTTON: Set currentSelection to DMs")
                print("🔙 BACK_BUTTON: Completed invite-style back navigation for non-server channel")
            }
            return
        }
        
        print("🔙 BACK_BUTTON: Using normal navigation path.removeLast()")
        
        // For normal navigation with multiple path items, use path.removeLast()
        if !viewModel.viewState.path.isEmpty {
            viewModel.viewState.path.removeLast()
            print("🔙 BACK_BUTTON: Removed last path item, new count: \(viewModel.viewState.path.count)")
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
    
    @objc private func searchButtonTapped() {
        // Set flag to track that we're going to search
        wasInSearch = true
        isReturningFromSearch = false
        
        // Navigate to the channel search page
        viewModel.viewState.path.append(NavigationDestination.channel_search(viewModel.channel.id))
    }
    
    @objc private func channelHeaderTapped() {
        // Only show server info if this channel belongs to a server
        guard let serverId = viewModel.channel.server,
              let server = viewModel.viewState.servers[serverId] else {
            // print("Channel does not belong to a server or server not found")
            return
        }
        
        presentServerInfoSheet(for: server)
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
                            self.viewModel.viewState.path.append(NavigationDestination.server_overview_settings(serverId))
                        case .channels:
                            self.viewModel.viewState.path.append(NavigationDestination.server_channels(serverId))
                        case .roles:
                            self.viewModel.viewState.path.append(NavigationDestination.server_role_setting(serverId))
                        case .emojis:
                            self.viewModel.viewState.path.append(NavigationDestination.server_emoji_settings(serverId))
                        case .members:
                            self.viewModel.viewState.path.append(NavigationDestination.server_members_view(serverId))
                        case .invite:
                            self.viewModel.viewState.path.append(NavigationDestination.server_invites(serverId))
                        case .banned:
                            self.viewModel.viewState.path.append(NavigationDestination.server_banned_users(serverId))
                        }
                    }
                }
            }
        )
        
        // Wrap the SwiftUI view in a UIHostingController
        let hostingController = UIHostingController(rootView: serverInfoSheet.environmentObject(viewModel.viewState))
        
        // Configure the presentation style
        hostingController.modalPresentationStyle = .pageSheet
        
        // Present the sheet
        present(hostingController, animated: true, completion: nil)
    }
    
    private func setupSwipeGesture() {
        // Create a pan gesture recognizer for left-to-right swipe
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }
    
    @objc private func handleSwipeGesture(_ gesture: UIPanGestureRecognizer) {
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
            let swipeThreshold: CGFloat = 100 // Minimum distance
            let velocityThreshold: CGFloat = 500 // Minimum velocity
            
                         if translation.x > swipeThreshold && velocity.x > velocityThreshold {
                 // Trigger back navigation
                 backButtonTapped()
             }
         default:
             break
         }
     }
     
     // MARK: - UIGestureRecognizerDelegate
     func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
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
     
     private func setupTableView() {
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        // Initialize the data source first (use LocalMessagesDataSource)
        dataSource = LocalMessagesDataSource(viewModel: viewModel, viewController: self, localMessages: localMessages)
        
        // Set up the table view
        tableView.delegate = self
        tableView.dataSource = dataSource
        tableView.prefetchDataSource = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: "MessageCell")
        tableView.register(SystemMessageCell.self, forCellReuseIdentifier: "SystemMessageCell")
        tableView.separatorStyle = .none
        tableView.backgroundColor = .bgDefaultPurple13
        
        tableView.keyboardDismissMode = .interactive
        tableView.estimatedRowHeight = 80 // Reduced for better performance
        tableView.rowHeight = UITableView.automaticDimension
        
        // PERFORMANCE: Enable cell prefetching and optimize scrolling
        tableView.isPrefetchingEnabled = true
        tableView.dragInteractionEnabled = false // Disable drag to improve performance
        
        // PERFORMANCE: Optimize table view for better scrolling
        tableView.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0.996)  // Custom slower deceleration for longer scroll distance
        tableView.showsVerticalScrollIndicator = true
        tableView.showsHorizontalScrollIndicator = false
        
        // PERFORMANCE: Optimize content inset adjustment
        if #available(iOS 11.0, *) {
            tableView.contentInsetAdjustmentBehavior = .never
        }
        
        tableView.contentInsetAdjustmentBehavior = .never
        
        // Disable bouncing by default - will be enabled when content exceeds visible area
        tableView.alwaysBounceVertical = false
        tableView.bounces = false
        
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        
        tableView.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0.996)  // Custom slower deceleration for longer scroll distance
        
        // Don't add loading header view initially - will be added when needed
        // tableView.tableHeaderView = loadingHeaderView
        
        // CRITICAL: Hide table view initially to prevent visual jump
        tableView.alpha = 0.0
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        // print some setup information for debugging
        // print("📋 Table view setup complete:")
        // print("   • ViewModel has \(viewModel.messages.count) messages")
        // print("   • ViewState has \(viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0) channel messages")
    }
    
    private func setupBindings() {
        // Observe messages array changes in viewModel via NotificationCenter
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(messagesDidChange),
            name: NSNotification.Name("MessagesDidChange"),
            object: nil // Changed from object: nil to capture all notifications with this name
        )
        
        // Add a direct observer to watch the tableView contentSize
        // This helps detect when new content is added
        tableView.addObserver(self, forKeyPath: "contentSize", options: [.new, .old], context: nil)
        
        // Initial reload
        refreshMessages()
    }
    
    // Override observeValue to detect content size changes
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "contentSize" && object as? UITableView === tableView {
            // Update bouncing behavior whenever content size changes
            updateTableViewBouncing()
            
            // ContentSize changed - check if it's larger than before
            if let oldSize = change?[.oldKey] as? CGSize,
               let newSize = change?[.newKey] as? CGSize,
               newSize.height > oldSize.height + 20 { // Significant increase in height
                
                // If user is near bottom and scrolling is enabled, scroll to show new content
                if isUserNearBottom() && !isLoadingMore && tableView.isScrollEnabled {
                    // print("📏 TableView content size increased significantly while user near bottom - scrolling")
                    scrollToBottom(animated: true)
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
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
        
        // Cancel any pending scroll operations
        scrollToBottomWorkItem?.cancel()
        scrollToBottomWorkItem = nil
        
        // Cancel any pending API calls
        loadingTask?.cancel()
        loadingTask = nil
        
        pendingAPICall?.cancel()
        pendingAPICall = nil
        
        // Add contentSize observer removal if it exists
        if let tableView = tableView {
            tableView.removeObserver(self, forKeyPath: "contentSize")
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
        
        // Clear managers that might hold references
        // (Note: These are lazy vars, so they'll be cleared automatically if not accessed)
        
        // print("🗑️ DEINIT: Cleanup completed - freed \(messageCount) messages from memory")
    }
    
    // SUPER FAST: Simplified message change handler
    @objc private func messagesDidChange(_ notification: Notification) {
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
            print("🔥 CONTROLLER: Processing reaction update for channel \(reactionChannelId ?? "unknown"), message \(reactionMessageId ?? "unknown")")
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
            guard let channelId = reactionChannelId, channelId == viewModel.channel.id else { return }
            if let messageId = reactionMessageId,
               let messageIndex = localMessages.firstIndex(of: messageId),
               messageIndex < tableView.numberOfRows(inSection: 0) {

                let indexPath = IndexPath(row: messageIndex, section: 0)
                let isLastMessage = messageIndex == localMessages.count - 1
                let wasNearBottom = isUserNearBottom(threshold: 80)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    print("🔥 RELOADING ROW: Reloading row \(indexPath.row) for message \(messageId)")
                    
                    // Force check if message has been updated in ViewState
                    if let updatedMessage = self.viewModel.viewState.messages[messageId] {
                        print("🔥 FORCE CHECK: Message \(messageId) reactions in ViewState: \(updatedMessage.reactions?.keys.joined(separator: ", ") ?? "none")")
                    } else {
                        print("🔥 FORCE CHECK: Message \(messageId) not found in ViewState!")
                    }
                    
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                    self.tableView.layoutIfNeeded()

                    // CRITICAL FIX: Don't auto-scroll if target message was recently highlighted
                    if let highlightTime = self.lastTargetMessageHighlightTime,
                       Date().timeIntervalSince(highlightTime) < 10.0 {
                        return
                    }

                    // Only if last message and user is at bottom, check if it went under keyboard
                    if isLastMessage && wasNearBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard let cellRect = self.tableView.cellForRow(at: indexPath)?.frame else { return }
                            let visibleHeight = self.tableView.frame.height - (self.isKeyboardVisible ? self.keyboardHeight : 0)
                            let cellBottom = cellRect.maxY - self.tableView.contentOffset.y
                            if cellBottom > visibleHeight {
                                // If cell bottom is below visible area, scroll to show it completely
                                let targetOffset = max(cellRect.maxY - visibleHeight + 20, 0)
                                self.tableView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: true)
                            }
                        }
                    }
                }
            } else {
                refreshMessages(forceUpdate: true) // Force update for reactions
            }
            return
        }
        
        // Skip if wrong channel (for regular message updates)
        if let sender = notification.object as? MessageableChannelViewModel,
           sender.channel.id != viewModel.channel.id { return }
        
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
        // First check if we have messages
        // print("🔽 SCROLL_TO_BOTTOM: Starting forced scroll to bottom (animated: \(animated))")
        
        // CRITICAL: Don't auto-scroll if user is manually scrolling or recently scrolled up
        if tableView.isDragging || tableView.isDecelerating {
            // print("🔽 SCROLL_TO_BOTTOM: User is manually scrolling, cancelling auto-scroll")
            return
        }
        
        // Don't scroll if user manually scrolled up in the last 5 seconds
        if let lastScrollUpTime = lastManualScrollUpTime,
           Date().timeIntervalSince(lastScrollUpTime) < 5.0 {
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
               Date().timeIntervalSince(highlightTime) < 10.0 {
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
           now.timeIntervalSince(lastTime) < scrollDebounceInterval {
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
                DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.3 : 0.1)) { [weak self] in
                    guard let self = self else { return }
                    
                    // Verify and adjust if needed
                    let finalRows = self.tableView.numberOfRows(inSection: 0)
                    if finalRows > 0 {
                        let finalIndexPath = IndexPath(row: finalRows - 1, section: 0)
                        self.tableView.scrollToRow(at: finalIndexPath, at: .bottom, animated: false)
                        
                        // For extra assurance, also try direct offset
                        let finalY = self.tableView.contentSize.height - self.tableView.frame.height
                        if finalY > 0 {
                            self.tableView.setContentOffset(CGPoint(x: 0, y: finalY), animated: false)
                        }
                        
                        // Add a third attempt with a longer delay to handle any layout changes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self = self else { return }
                            
                            // Final verification
                            let lastRows = self.tableView.numberOfRows(inSection: 0)
                            if lastRows > 0 {
                                let lastIndexPath = IndexPath(row: lastRows - 1, section: 0)
                                self.tableView.scrollToRow(at: lastIndexPath, at: .bottom, animated: false)
                                
                                // One last direct offset attempt
                                let lastY = self.tableView.contentSize.height - self.tableView.frame.height
                                if lastY > 0 {
                                    self.tableView.setContentOffset(CGPoint(x: 0, y: lastY), animated: false)
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
            print("🎯 NEAR_BOTTOM_CHECK: Target message protection active, not considering user near bottom")
            return false
        }
        
        return scrollPositionManager.isUserNearBottom(threshold: threshold)
    }
    
    // Legacy method for compatibility
    private func isUserNearBottomLegacy(threshold: CGFloat? = nil) -> Bool {
        guard let tableView = tableView, tableView.numberOfRows(inSection: 0) > 0 else {
          //  // print("📊 IS_USER_NEAR_BOTTOM: No rows in table, returning true")
            return true // If there are no messages, consider user at the bottom
        }
        
        // If user is actively scrolling, don't consider them at bottom
        if tableView.isDragging || tableView.isDecelerating {
            return false
        }
        
        // If user has manually scrolled up recently, don't consider them at bottom
        // This prevents auto-scrolling to bottom when user is reading previous messages
        if let lastScrollUpTime = lastManualScrollUpTime, 
           Date().timeIntervalSince(lastScrollUpTime) < 15.0 {
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
         scrollProtectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
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
           Date().timeIntervalSince(lastEmpty) < 60.0 { // Don't retry for 1 minute
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
                    self.tableView.scrollRectToVisible(CGRect(x: 0, y: self.tableView.contentOffset.y - 60, width: 1, height: 1), animated: true)
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
    
    // Add properties to manage rate limiting
    private var lastMessageSeenTime = Date(timeIntervalSince1970: 0)
    private var messageSeenThrottleInterval: TimeInterval = 5.0 // At least 5 seconds between seen acknowledgments
    private var isAcknowledgingMessage = false
    private var retryQueue = [RetryTask]()
    
    // MARK: - Mark Unread Protection
    // Temporarily disable automatic acknowledgment after marking as unread
    private var isAutoAckDisabled = false
    private var autoAckDisableTime: Date?
    private let autoAckDisableDuration: TimeInterval = 30.0 // Disable for 30 seconds after mark unread
    
    // Define a struct to handle retry tasks
    private struct RetryTask {
        let messageId: String
        let channelId: String
        let retryCount: Int
        let nextRetryTime: Date
    }
    
    // MARK: - Public Methods for Mark Unread
    
    /// Temporarily disable automatic acknowledgment after marking as unread
    func disableAutoAcknowledgment() {
        print("🚫 Disabling auto-acknowledgment for \(autoAckDisableDuration) seconds")
        isAutoAckDisabled = true
        autoAckDisableTime = Date()
    }
    
    // Mark the last message as seen by the user - with rate limiting
    func markLastMessageAsSeen() {
        // Check if auto-acknowledgment is temporarily disabled
        if let disableTime = autoAckDisableTime {
            let now = Date()
            if now.timeIntervalSince(disableTime) < autoAckDisableDuration {
                print("🚫 Auto-acknowledgment disabled - skipping markLastMessageAsSeen")
                return
            } else {
                // Disable period has expired, re-enable auto-ack
                print("✅ Auto-acknowledgment re-enabled after disable period")
                isAutoAckDisabled = false
                autoAckDisableTime = nil
            }
        }
        
        // Only mark as seen if there are messages and we're not already doing it
        guard let lastMessageId = viewModel.messages.last, !isAcknowledgingMessage else {
            return
        }
        
        // Check if enough time has passed since last acknowledgment
        let now = Date()
        if now.timeIntervalSince(lastMessageSeenTime) < messageSeenThrottleInterval {
            // Not enough time has passed, add to retry queue instead
            let retryTime = lastMessageSeenTime.addingTimeInterval(messageSeenThrottleInterval)
            addToRetryQueue(messageId: lastMessageId, channelId: viewModel.channel.id, retryTime: retryTime)
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
                    viewModel.viewState.unreads[viewModel.channel.id] = Unread(id: unreadId, last_id: lastMessageId)
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
                if case .failure(429, let data) = error, let retryAfter = extractRetryAfter(from: data) {
                    // print("Rate limited for \(retryAfter) seconds")
                    
                    // Adjust our throttle interval based on server response
                    self.messageSeenThrottleInterval = max(self.messageSeenThrottleInterval, min(Double(retryAfter), 60.0))
                    
                    // Add to retry queue with the server's suggested delay
                    let retryTime = Date().addingTimeInterval(Double(retryAfter))
                    addToRetryQueue(messageId: lastMessageId, channelId: viewModel.channel.id, retryTime: retryTime)
                } else {
                    // For other errors, retry with exponential backoff
                    addToRetryQueue(messageId: lastMessageId, channelId: viewModel.channel.id, retryCount: 1)
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
        
        if let dataObj = try? JSONSerialization.jsonObject(with: Data(data.utf8), options: []) as? [String: Any],
           let retryAfter = dataObj["retry_after"] as? Int {
            return retryAfter
        }
        return nil
    }
    
    // Add a task to the retry queue
    private func addToRetryQueue(messageId: String, channelId: String, retryCount: Int = 0, retryTime: Date? = nil) {
        // Calculate next retry time using exponential backoff if not provided
        let nextRetryTime: Date
        if let time = retryTime {
            nextRetryTime = time
        } else {
            // Exponential backoff: 2^retryCount seconds with a max of 30 seconds
            let delay = min(pow(2.0, Double(retryCount)), 30.0)
            nextRetryTime = Date().addingTimeInterval(delay)
        }
        
        // Add to retry queue
        let task = RetryTask(messageId: messageId, channelId: channelId, retryCount: retryCount, nextRetryTime: nextRetryTime)
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
            retryQueue.removeAll(where: { $0.messageId == nextTask.messageId && $0.channelId == nextTask.channelId })
            
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
                            self.processRetryQueue() // Process the next task if any
                        }
                    } catch let error as HTTPError {
                        // print("Retry failed to mark message as seen: \(error)")
                        
                        // Check for rate limiting
                        if case .failure(429, let data) = error, let retryAfter = extractRetryAfter(from: data) {
                            // print("Rate limited for \(retryAfter) seconds during retry")
                            
                            // Adjust our throttle interval based on server response
                            self.messageSeenThrottleInterval = max(self.messageSeenThrottleInterval, min(Double(retryAfter), 60.0))
                            
                            // Add back to retry queue with server's delay
                            let retryTime = Date().addingTimeInterval(Double(retryAfter))
                            addToRetryQueue(messageId: nextTask.messageId, channelId: nextTask.channelId, retryCount: nextTask.retryCount + 1, retryTime: retryTime)
                        } else {
                            // For other errors, retry with increased backoff
                            addToRetryQueue(messageId: nextTask.messageId, channelId: nextTask.channelId, retryCount: nextTask.retryCount + 1)
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
                addToRetryQueue(messageId: nextTask.messageId, channelId: nextTask.channelId, retryCount: nextTask.retryCount, retryTime: retryTime)
            }
        }
    }
    
    // New method for loading older messages
    func loadMoreMessages(before messageId: String?, server: String? = nil, messages: [String] = []) {
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
            
            print("🌐 API CALL: loadMoreMessages (before) - Channel: \(viewModel.channel.id), Before: \(messageId ?? "nil")")
            
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
                    self.tableView.scrollRectToVisible(CGRect(x: 0, y: self.tableView.contentOffset.y - 60, width: 1, height: 1), animated: true)
                }
            }
            
            // Save count of messages before loading
            let initialMessagesCount = viewModel.messages.count
            
            // Create a new Task for loading messages
            let loadTask = Task<Void, Never>(priority: .userInitiated) {
                do {
                    // Display request information - ADD DETAILED LOGGING
                    print("⏳ BEFORE_CALL: Waiting for API response for messageId=\(messageId ?? "nil"), channelId=\(self.viewModel.channel.id)")
                    
                    // CRITICAL: Ensure we're using the right method for Before calls
                    print("⏳ BEFORE_CALL: Calling viewModel.loadMoreMessages with before=\(messageId ?? "nil")")
                    let loadResult = await self.viewModel.loadMoreMessages(
                        before: messageId
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
                    self.lastSuccessfulLoadTime = Date() // Update to prevent immediate retries
                    
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
    
    // Helper method to safely update isLoadingMore
    private func setIsLoadingMore(_ value: Bool) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        isLoadingMore = value
        // print("📱 isLoadingMore set to \(value)")
    }
    
    // Public method to reset the nearby loading flag when navigating to a new channel (moved to extension)
    
    // Typing indicator setup is now handled by TypingIndicatorManager
    
    private func showNSFWOverlay() {
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
    
    private func setupMessageInput() {
        // Create a container for message input
        messageInputView = MessageInputView(frame: .zero)
        messageInputView.translatesAutoresizingMaskIntoConstraints = false
        messageInputView.delegate = messageInputHandler
        view.addSubview(messageInputView)
        
        // Add constraints for message input
        messageInputBottomConstraint = messageInputView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            messageInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageInputBottomConstraint!
        ])
        
        // Update table view constraints to position it above the message input
        NSLayoutConstraint.activate([
            tableView.bottomAnchor.constraint(equalTo: messageInputView.topAnchor)
        ])
        
        // Reply container view is now managed by RepliesManager
        
        // Check permission and update UI accordingly
        if !permissionsManager.sendMessagePermission {
            messageInputView.isHidden = true
            permissionsManager.createAndShowNoPermissionView()
        }
        
        // Configure upload button based on uploadFiles permission
        messageInputView.uploadButtonEnabled = permissionsManager.userHasPermission(Types.Permissions.uploadFiles)
        
        // CRITICAL: Configure textView delegate BEFORE setting up mention functionality
        let textView = messageInputView.textView
        textView.delegate = self
        // print("DEBUG: Set textView.delegate to self (MessageableChannelViewController)")
        
        // Setup mention functionality AFTER setting delegate
        messageInputView.setupMentionFunctionality(viewState: viewModel.viewState, channel: viewModel.channel, server: viewModel.server)
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
        if targetMessageProtectionActive && (targetMessageId == nil || targetMessageProcessed) && !forceUpdate {
            print("🔄 BLOCKED: refreshMessages blocked - target message protection active and no new target")
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
           targetMessageId == nil { 
            // print("🔄 Skipping refreshMessages - user recently scrolled up (no target message)")
            return 
        } else if targetMessageId != nil {
            // print("🔄 Continuing refreshMessages despite recent scroll - have target message")
        }
        
        // Get new messages directly - no async overhead
        guard let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id],
              !channelMessages.isEmpty,
              localMessages != channelMessages else { return }
        
        // CRITICAL: Check if actual message objects exist before refreshing
        let hasActualMessages = channelMessages.first(where: { viewModel.viewState.messages[$0] != nil }) != nil
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
            dataSource = LocalMessagesDataSource(viewModel: viewModel, viewController: self, localMessages: localMessages)
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
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
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
                print("✅ Target message is loaded in refreshMessages, calling scrollToTargetMessage ONCE")
                // Mark as processed BEFORE calling scrollToTargetMessage to prevent multiple calls
                targetMessageProcessed = true
                scrollToTargetMessage()
            } else {
                print("❌ Target message NOT loaded in refreshMessages, skipping scroll")
            }
        } else if let targetId = targetMessageId, targetMessageProcessed {
            print("🎯 Found targetMessageId but already processed: \(targetId) - preserving target position")
            // CRITICAL FIX: Do NOT auto-scroll when we have a target message
            // The target message should remain visible regardless of bottom position
        } else if wasNearBottom {
            // CRITICAL FIX: Don't auto-scroll if user was positioned on a target message recently
            if targetMessageProtectionActive || isInTargetMessagePosition {
                print("🎯 REFRESH_MESSAGES: Target message protection or position active, skipping auto-scroll")
                return
            }
            
            // CRITICAL FIX: Don't auto-scroll if target message was highlighted recently (within 30 seconds)
            if let highlightTime = lastTargetMessageHighlightTime,
               Date().timeIntervalSince(highlightTime) < 30.0 {
                print("🎯 REFRESH_MESSAGES: Target message highlighted recently (\(Date().timeIntervalSince(highlightTime))s ago), skipping auto-scroll")
                return
            }
            
            // Auto-scroll if user was at bottom and no target message protection
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                print("🎯 REFRESH_MESSAGES: Auto-scrolling because user was near bottom and no target protection")
                
                // Use proper scrolling method that considers keyboard state
                if self.isKeyboardVisible && !self.localMessages.isEmpty {
                    let lastIndex = self.localMessages.count - 1
                    if lastIndex >= 0 && lastIndex < self.tableView.numberOfRows(inSection: 0) {
                        let indexPath = IndexPath(row: lastIndex, section: 0)
                        self.safeScrollToRow(at: indexPath, at: .bottom, animated: false, reason: "refresh messages with keyboard")
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
        private var viewControllerRef: MessageableChannelViewController
        
        // CRITICAL FIX: Add thread-safe persistent cache for messages
        private var cachedMessages: [String] = []
        private let cacheQueue = DispatchQueue(label: "messages.cache.queue", attributes: .concurrent)
        
        // Track row count to prevent race conditions
        private var lastReturnedRowCount: Int = 0
        
        // OPTIMIZATION: Cache frequently accessed message data
        private var messageCache: [String: Message] = [:]
        private var userCache: [String: User] = [:]
        
        init(viewModel: MessageableChannelViewModel, viewController: MessageableChannelViewController, localMessages: [String]) {
            self.viewModelRef = viewModel
            self.viewControllerRef = viewController
            
            // CRITICAL: Always prefer messages from viewState over passed localMessages
            if let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id], 
               !channelMessages.isEmpty {
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
        
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return cacheQueue.sync {
                let count = localMessages.count
                lastReturnedRowCount = count
                print("📊 LOCAL DATA SOURCE: Returning \(count) rows (localMessages: \(localMessages.count))")
                return count
            }
        }
        
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            // CRITICAL: Thread-safe bounds check with fallback cell
            return cacheQueue.sync {
                // Double check bounds against both local messages and last returned count
                guard indexPath.row < localMessages.count && indexPath.row < lastReturnedRowCount else {
                    print("⚠️ BOUNDS_ERROR: indexPath.row=\(indexPath.row), localMessages.count=\(localMessages.count), lastReturnedRowCount=\(lastReturnedRowCount)")
                    return createFallbackCell(tableView: tableView, indexPath: indexPath, reason: "Index out of bounds")
                }
                
                let messageId = localMessages[indexPath.row]
                
                // OPTIMIZED: Try cache first, then viewState
                let message: Message
                if let cachedMessage = messageCache[messageId] {
                    message = cachedMessage
                } else if let viewStateMessage = viewModelRef.viewState.messages[messageId] {
                    message = viewStateMessage
                    messageCache[messageId] = viewStateMessage // Cache for future use
                } else {
                    print("⚠️ MESSAGE_NOT_FOUND: messageId=\(messageId) at index=\(indexPath.row)")
                    return createFallbackCell(tableView: tableView, indexPath: indexPath, reason: "Message not found: \(messageId)")
                }
                
                // Handle system messages
                if message.system != nil {
                    guard let systemCell = tableView.dequeueReusableCell(withIdentifier: "SystemMessageCell", for: indexPath) as? SystemMessageCell else {
                        print("⚠️ SYSTEM_CELL_ERROR: Failed to dequeue SystemMessageCell")
                        return createFallbackCell(tableView: tableView, indexPath: indexPath, reason: "System cell dequeue failed")
                    }
                    systemCell.configure(with: message, viewState: viewModelRef.viewState)
                    return systemCell
                }
                
                // Handle regular messages with better safety
                guard let messageCell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as? MessageCell else {
                    print("⚠️ MESSAGE_CELL_ERROR: Failed to dequeue MessageCell")
                    return createFallbackCell(tableView: tableView, indexPath: indexPath, reason: "Message cell dequeue failed")
                }
                
                // OPTIMIZED: Author lookup with cache and fallback
                let author: User
                if let cachedAuthor = userCache[message.author] {
                    author = cachedAuthor
                } else if let foundAuthor = viewModelRef.viewState.users[message.author] {
                    author = foundAuthor
                    userCache[message.author] = foundAuthor // Cache for future use
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
                    userCache[message.author] = fallbackAuthor // Cache fallback too
                }
                
                // Safe continuation check
                let isContinuation = viewControllerRef.shouldGroupWithPreviousMessage(at: indexPath)
                let member = viewModelRef.getMember(message: message).wrappedValue
                
                // PERFORMANCE: Configure cell with optimized method
                messageCell.configure(with: message, author: author, member: member, viewState: viewModelRef.viewState, isContinuation: isContinuation)
                
                // PERFORMANCE: Set delegates efficiently
                messageCell.textViewContent.delegate = viewControllerRef
                
                // PERFORMANCE: Use weak references for callbacks
                messageCell.onMessageAction = { [weak viewController = viewControllerRef] action, message in
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
        private func createFallbackCell(tableView: UITableView, indexPath: IndexPath, reason: String) -> UITableViewCell {
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
                activityIndicator.centerYAnchor.constraint(equalTo: fallbackCell.contentView.centerYAnchor),
                activityIndicator.trailingAnchor.constraint(equalTo: fallbackCell.contentView.trailingAnchor, constant: -16)
            ])
            
            print("🔄 FALLBACK_CELL: Created for index=\(indexPath.row), reason=\(reason)")
            return fallbackCell
        }
        
        func updateMessages(_ messages: [String]) {
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.localMessages = messages
                self.cachedMessages = Array(messages) // Update cache too
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
            
            print("🧹 CACHE_CLEANUP: messageCache=\(messageCache.count), userCache=\(userCache.count)")
        }
    }
    
    // New method to refresh messages without auto-scrolling to bottom (moved to extension)
    
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
    
    private func loadInitialMessages() async {
        let channelId = viewModel.channel.id
        
        // CRITICAL FIX: Reset empty response time when loading initial messages
        lastEmptyResponseTime = nil
        print("🔄 LOAD_INITIAL: Reset lastEmptyResponseTime for initial load")
        
        // CRITICAL FIX: Don't reload if user is in target message position
        if isInTargetMessagePosition && targetMessageId == nil {
            print("🎯 LOAD_INITIAL: User is in target message position, skipping reload to preserve position")
            return
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
        
        // 🎯 REACTIVE ARCHITECTURE: Use ViewModel for data loading
        // ViewModel handles Database read + Network sync in background
        print("💾 REACTIVE: Delegating to ViewModel for data loading")
        
        await viewModel.loadChannelMessages()
        
        print("✅ REACTIVE: ViewModel loaded data - UI will update via DatabaseObserver")
        
        if let targetId = self.targetMessageId {
            // 🎯 REACTIVE: Use ViewModel to load target message
            print("🎯 REACTIVE: Delegating target message \(targetId) to ViewModel")
            
            // Set protection flags
    messageLoadingState = .loading
    isInTargetMessagePosition = true
    lastTargetMessageHighlightTime = Date()
            print("🎯 REACTIVE: Protection flags set")
            
            // Let ViewModel handle loading
            let foundInDB = await viewModel.loadTargetMessage(targetId)
            
            if foundInDB {
                print("💾 REACTIVE: Target message loaded from Database")
                await MainActor.run {
                    self.refreshMessages()
                                    self.scrollToTargetMessage()
                                    }
                                } else {
                print("🔄 REACTIVE: ViewModel triggered network sync for target message")
            }
        }
    }
    
    // Helper method to load regular messages without a target
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
                        
                        // Fetch reply message content for messages that have replies
                        print("🔗 CALLING fetchReplyMessagesContentAndRefreshUI with \(fetchResult.messages.count) messages")
                        await fetchReplyMessagesContentAndRefreshUI(for: fetchResult.messages)
                        
                        // CRITICAL FIX: Also check for any preloaded messages that might have replies
                        let allCurrentMessages = localMessages.compactMap { messageId in
                            viewModel.viewState.messages[messageId]
                        }
                        print("🔗 PRELOAD_CHECK: Checking \(allCurrentMessages.count) total messages for missing replies after regular load")
                        await fetchReplyMessagesContentAndRefreshUI(for: allCurrentMessages)
                
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
    
    // Helper to add timeout to tasks
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
    
    // MARK: - Fetch Message for Reply
    
    /// Fetch a specific message from the server if it's not in cache
    /// This is used when replying to old messages that aren't currently loaded
    func fetchMessageForReply(messageId: String, channelId: String) async -> Types.Message? {
        print("🔍 FETCH_REPLY: Delegating to ViewModel for message \(messageId)")
        
        // Delegate to ViewModel
        let message = await viewModel.loadSingleMessage(messageId)
        
        if let message = message {
            print("✅ FETCH_REPLY: ViewModel returned message")
            return message
        } else {
            print("🔄 FETCH_REPLY: Message not found in Database/ViewState - network sync triggered")
            
            // Wait a bit for network sync to complete and check again
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Check if message was loaded by network sync
            if let syncedMessage = viewModel.viewState.messages[messageId] {
                print("✅ FETCH_REPLY: Message loaded after network sync")
                return syncedMessage
            } else {
                print("❌ FETCH_REPLY: Message still not available after sync - possibly deleted or 404")
                
                // Message couldn't be loaded - might be deleted (404) or access denied
                // Return nil and let the UI handle it gracefully
            return nil
            }
        }
    }
    
    /// Fetch user data if not in cache
    func fetchUserForMessage(userId: String) async {
        print("👤 FETCH_USER: Delegating to ViewModel for user \(userId)")
        
        // Delegate to ViewModel
        let user = await viewModel.loadUser(userId)
        
        if let user = user {
            print("✅ FETCH_USER: ViewModel returned user \(user.username)")
        } else {
            print("🔄 FETCH_USER: ViewModel triggered network sync")
        }
        
        // Old HTTP fetch code removed - network sync happens in background
        if false {
            print("❌ FETCH_USER: Failed to fetch user (code removed)")
        }
    }
    
    /// Track when we last checked for missing replies to avoid excessive API calls
    private var lastReplyCheckTime: Date?
    private let replyCheckCooldown: TimeInterval = 2.0 // 2 seconds between checks
    
    /// Check if any messages have missing reply content and fetch them
    private func checkAndFetchMissingReplies() async {
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
    
    /// Fetch reply message content for messages that have replies and immediately refresh UI
    private func fetchReplyMessagesContentAndRefreshUI(for messages: [Types.Message]) async {
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
                    print("🔗 FETCH_AND_REFRESH: Forcing complete table reload after fetching \(replyIdsBeingFetched.count) replies")
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
    private func fetchReplyMessagesContent(for messages: [Types.Message]) async {
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
        
        print("🔗 DEBUG: Found \(messagesWithReplies) messages with replies, total \(totalReplyIds) reply IDs")
        
        // Collect all unique reply message IDs that need to be fetched
        var replyIdsToFetch = Set<String>()
        var replyChannelMap = [String: String]() // messageId -> channelId
        
        for message in messages {
            guard let replies = message.replies, !replies.isEmpty else { continue }
            
            for replyId in replies {
                // Check if already in cache or being fetched
                let isInCache = viewModel.viewState.messages[replyId] != nil
                let isBeingFetched = ongoingReplyFetches.contains(replyId)
                print("🔗 DEBUG: Reply \(replyId) - In cache: \(isInCache), Being fetched: \(isBeingFetched)")
                
                // Only fetch if not already in cache and not being fetched
                if !isInCache && !isBeingFetched {
                    replyIdsToFetch.insert(replyId)
                    replyChannelMap[replyId] = message.channel
                    ongoingReplyFetches.insert(replyId) // Mark as being fetched
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
        print("🌐 FETCH_REPLIES: Starting concurrent fetch of \(replyIdsToFetch.count) reply messages")
        await withTaskGroup(of: Void.self) { group in
            for replyId in replyIdsToFetch {
                group.addTask { [weak self] in
                    guard let self = self,
                          let channelId = replyChannelMap[replyId] else { 
                        print("❌ FETCH_REPLIES: Missing self or channelId for reply \(replyId)")
                        return 
                    }
                    
                    print("🔍 FETCH_REPLIES: Starting fetch for reply \(replyId) in channel \(channelId)")
                    if let replyMessage = await self.fetchMessageForReply(messageId: replyId, channelId: channelId) {
                        print("✅ FETCH_REPLIES: Successfully fetched reply \(replyId)")
                        
                        // Also fetch the author if needed
                        await MainActor.run {
                            if self.viewModel.viewState.users[replyMessage.author] == nil {
                                print("👥 FETCH_REPLIES: Fetching author \(replyMessage.author) for reply \(replyId)")
                                Task {
                                    await self.fetchUserForMessage(userId: replyMessage.author)
                                }
                            } else {
                                print("👥 FETCH_REPLIES: Author \(replyMessage.author) already cached for reply \(replyId)")
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
                print("🔗 FORCE_REFRESH: Forcing UI refresh after loading \(replyIdsToFetch.count) reply messages")
                
                // Force table view to reload data for messages with replies
                if let tableView = self.tableView {
                    // Find visible cells that might have replies
                    let visibleIndexPaths = tableView.indexPathsForVisibleRows ?? []
                    var indexPathsToReload: [IndexPath] = []
                    
                    for indexPath in visibleIndexPaths {
                        if indexPath.row < localMessages.count {
                            let messageId = localMessages[indexPath.row]
                            if let message = viewModel.viewState.messages[messageId],
                               let replies = message.replies, !replies.isEmpty {
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
                        print("🔗 FORCE_REFRESH: Reloading \(indexPathsToReload.count) cells with newly fetched replies")
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
    
    // Legacy method for compatibility (can be removed after testing)
    private func handleMessageActionLegacy(_ action: MessageCell.MessageAction, message: Types.Message) {
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
                        replyMessage = await fetchMessageForReply(messageId: replyId, channelId: viewModel.channel.id)
                    }
                    
                    if let replyMessage = replyMessage {
                        // Make sure we have the author too
                        if viewModel.viewState.users[replyMessage.author] == nil {
                            await fetchUserForMessage(userId: replyMessage.author)
                        }
                        
                        if let replyAuthor = viewModel.viewState.users[replyMessage.author] {
                        // Create reply object
                        let isMention = message.mentions?.contains(replyMessage.author) ?? false
                        replies.append(ReplyMessage(
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
               viewModel.viewState.users[message.author] != nil {
                // Message and author are cached, proceed immediately
                startReply(to: message)
            } else {
                // Message or author not in cache, fetch first
                Task {
                    var fetchedMessage = message
                    
                    // Try to fetch the message if not in cache
                    if viewModel.viewState.messages[message.id] == nil {
                        if let fetched = await fetchMessageForReply(messageId: message.id, channelId: message.channel) {
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
                    viewModel.viewState.showAlert(message: "Message Link Copied!", icon: .peptideLink)
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
                    self.safeScrollToRow(at: indexPath, at: .bottom, animated: false, reason: "new message sent - first scroll")
                    
                    // Then do an animated scroll to ensure visibility
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.safeScrollToRow(at: indexPath, at: .bottom, animated: true, reason: "new message sent - second scroll")
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
    
    // Load messages near a specific message ID
    private func loadMessagesNearby(messageId: String) async -> Bool {
        do {
            print("🔍 NEARBY_API: Fetching messages nearby \(messageId) using nearby API")
            print("🌐 NEARBY_API: Channel: \(viewModel.channel.id), Target: \(messageId)")
            
            // DB-FIRST: try database before making grouped API calls
            if let _ = await MessageRepository.shared.fetchMessage(id: messageId) {
                let dbMessages = await MessageRepository.shared.fetchMessages(forChannel: viewModel.channel.id)
                if !dbMessages.isEmpty {
                    await MainActor.run {
                        for m in dbMessages { viewModel.viewState.messages[m.id] = m }
                        viewModel.viewState.channelMessages[viewModel.channel.id] = dbMessages.map { $0.id }.sorted { createdAt(id: $0) < createdAt(id: $1) }
                        self.refreshMessages()
                    }
                    print("💾 NEARBY_GROUP: Served from database, skipping grouped API")
                    return true
                }
            }
            
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
                    try await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds
                    throw TimeoutError()
                }
                
                // Return the first result (either API response or timeout)
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            
            print("✅ NEARBY_API: Response received with \(result.messages.count) messages, \(result.users.count) users")
            
            // DEBUG: Check if any messages have replies
            let messagesWithReplies = result.messages.filter { $0.replies?.isEmpty == false }
            print("🔗 NEARBY_DEBUG: Out of \(result.messages.count) messages, \(messagesWithReplies.count) have replies")
            for message in messagesWithReplies {
                print("🔗 NEARBY_DEBUG: Message \(message.id) has replies: \(message.replies ?? [])")
            }
            
            // Check if we got messages and the target message is included
            if !result.messages.isEmpty {
                let targetFound = result.messages.contains { $0.id == messageId }
                print("🎯 NEARBY_API: Target message \(messageId) found in nearby results: \(targetFound)")
                
                // Debug: Print all message IDs we got
                let messageIds = result.messages.map { $0.id }
                print("🔍 NEARBY_API: Returned message IDs: \(messageIds.prefix(5))...\(messageIds.suffix(5))")
                
                if !targetFound {
                    print("⚠️ NEARBY_API: Target message not found in nearby results, trying direct fetch")
                    // Try to fetch the target message from DB first
                    if let dbTarget = await MessageRepository.shared.fetchMessage(id: messageId) {
                        await MainActor.run { viewModel.viewState.messages[dbTarget.id] = dbTarget }
                        print("💾 DIRECT_FETCH: Target message served from DB")
                    } else {
                        // Fallback to network
                    do {
                        print("🌐 DIRECT_FETCH: Attempting to fetch target message directly")
                        let targetMessage = try await viewModel.viewState.http.fetchMessage(
                            channel: viewModel.channel.id,
                            message: messageId
                        ).get()
                        
                        print("✅ DIRECT_FETCH: Successfully fetched target message directly: \(targetMessage.id)")
                        // Store it in viewState
                        viewModel.viewState.messages[targetMessage.id] = targetMessage
                    } catch {
                        print("❌ DIRECT_FETCH: Could not fetch target message directly: \(error)")
                        // Return false since we couldn't get the target message
                        return false
                        }
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
                            viewModel.viewState.members[member.id.server, default: [:]][member.id.user] = member
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
                        let existingMessages = viewModel.viewState.channelMessages[viewModel.channel.id] ?? []
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
                            viewModel.viewState.channelMessages[viewModel.channel.id] = allMessageIds
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
                        self.dataSource = LocalMessagesDataSource(viewModel: self.viewModel, viewController: self, localMessages: self.localMessages)
                        
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
    
    // Scroll to the target message if it exists
    private func scrollToTargetMessage() {
        // CRITICAL FIX: Reset processed flag when we have a target message to scroll to
        if let targetId = self.targetMessageId {
            print("🎯 scrollToTargetMessage called for target: \(targetId), resetting processed flag")
            targetMessageProcessed = false
        }
        
        // CRITICAL FIX: Check if already processed to prevent multiple highlighting
        if targetMessageProcessed {
            print("🎯 Target message already processed, skipping to prevent multiple highlights")
            return
        }
        
        // CRITICAL FIX: Reset processed flag for new target message
        if let targetId = self.targetMessageId {
            print("🎯 scrollToTargetMessage called for target: \(targetId)")
        }
        
        guard let targetId = self.targetMessageId else {
            // If no target message, scroll to bottom
            print("🚫 No target message ID, scrolling to bottom")
            scrollToBottom(animated: false)
            return
        }
        
        print("🎯 Attempting to scroll to target message: \(targetId)")
        print("📊 Current message count in localMessages: \(localMessages.count)")
        
        // Debug - print some message IDs to help diagnose
        if !localMessages.isEmpty {
            let firstMsg = localMessages[0]
            let lastMsg = localMessages[localMessages.count - 1]
            print("📑 First message ID: \(firstMsg)")
            print("📑 Last message ID: \(lastMsg)")
        }
        
        // Debug: Check current state
        let isInViewState = self.viewModel.viewState.messages[targetId] != nil
        let isInLocalMessages = self.localMessages.contains(targetId)
        let isInViewModelMessages = self.viewModel.messages.contains(targetId)
        let channelMessages = self.viewModel.viewState.channelMessages[self.viewModel.channel.id]
        let isInChannelMessages = channelMessages?.contains(targetId) ?? false
        
        print("🔍 Target message \(targetId) status:")
        print("   - In viewState.messages: \(isInViewState)")
        print("   - In localMessages: \(isInLocalMessages)")
        print("   - In viewModel.messages: \(isInViewModelMessages)")
        print("   - In channelMessages: \(isInChannelMessages)")
        print("   - LocalMessages count: \(localMessages.count)")
        print("   - ViewModelMessages count: \(viewModel.messages.count)")
        print("   - ChannelMessages count: \(channelMessages?.count ?? 0)")
        
        // Check if target message exists in localMessages but not in viewState.messages
        if isInLocalMessages && !isInViewState {
            // print("🔄 Target message exists in localMessages but not in viewState.messages")
            // This shouldn't happen, but let's handle it by syncing localMessages with current messages
            self.syncLocalMessagesWithViewState()
        }
        
        // First, make sure we have the target message in our arrays
        guard self.viewModel.viewState.messages[targetId] != nil else {
            // print("⚠️ Target message not in viewState.messages, fetching it first")
            
            // Fetch the message and nearby messages
            Task {
                let success = await self.loadMessagesNearby(messageId: targetId)
                
                DispatchQueue.main.async {
                    if success {
                        // print("✅ Successfully loaded target message, trying to scroll again")
                        self.scrollToTargetMessage() // Recursive call after loading
                    } else {
                        // print("❌ Failed to load target message")
                        self.scrollToBottom(animated: false) // Fallback
                    }
                }
            }
            
            return
        }
        
        // CRITICAL FIX: Force sync before finding index to prevent wrong scroll position
        print("🔄 SYNC_CHECK: Ensuring all message arrays are synced before scrolling")
        self.syncLocalMessagesWithViewState()
        
        // CRITICAL FIX: Use the most reliable source for finding index
        let referenceMessages: [String]
        if let channelMessages = self.viewModel.viewState.channelMessages[self.viewModel.channel.id], !channelMessages.isEmpty {
            referenceMessages = channelMessages
            print("🔍 Using viewState.channelMessages as reference (\(channelMessages.count) messages)")
        } else if !self.localMessages.isEmpty {
            referenceMessages = self.localMessages
            print("🔍 Using localMessages as reference (\(self.localMessages.count) messages)")
        } else {
            print("❌ No reference messages available for scrolling")
            self.scrollToBottom(animated: false)
            return
        }
        
        // CRITICAL FIX: Ensure localMessages matches reference for table view
        if self.localMessages != referenceMessages {
            print("⚠️ SYNC_FIX: localMessages was out of sync, updating from reference")
            self.localMessages = referenceMessages
            
            // Update data source to match
            if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                localDataSource.updateMessages(self.localMessages)
            }
        }
        
            // Find the target message in reference messages
    if let index = referenceMessages.firstIndex(of: targetId) {
        print("✅ Found target message at index \(index) in reference messages (total: \(referenceMessages.count))")
        print("🎯 Target message ID: \(targetId)")
        
        // VALIDATION: Verify the message at this index is actually our target
        if index < referenceMessages.count && referenceMessages[index] == targetId {
            print("✅ VALIDATION: Confirmed message at index \(index) is target \(targetId)")
        } else {
            print("❌ VALIDATION: Message at index \(index) is NOT target \(targetId)")
            // Try to find it again or fallback
            if let correctIndex = referenceMessages.firstIndex(of: targetId) {
                print("🔄 CORRECTION: Found target at correct index \(correctIndex)")
                // Update index variable (but can't reassign let, so we'll use correctIndex below)
            } else {
                print("❌ CORRECTION: Could not find target message, falling back to bottom")
                self.scrollToBottom(animated: false)
                return
            }
        }
        
        // Use the validated index
        let validatedIndex = referenceMessages.firstIndex(of: targetId) ?? index
        
        // Ensure the table has been reloaded with data
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Force complete data source recreation with correct messages
            print("🔄 DATASOURCE_FIX: Recreating data source with \(referenceMessages.count) messages")
            self.dataSource = LocalMessagesDataSource(viewModel: self.viewModel, 
                                                     viewController: self,
                                                     localMessages: referenceMessages)
            self.tableView.dataSource = self.dataSource
            
            // CRITICAL FIX: Use the new force update method
            if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                localDataSource.forceUpdateMessages(referenceMessages)
            }
            
            // Force table view to reload and layout subviews to ensure cells are available
            self.tableView.reloadData()
            self.tableView.layoutIfNeeded()
            
            // CRITICAL FIX: Check row count immediately and retry if mismatch
            let initialRowCount = self.tableView.numberOfRows(inSection: 0)
            print("📊 Initial table row count: \(initialRowCount), expected: \(referenceMessages.count)")
            
            if initialRowCount != referenceMessages.count {
                print("⚠️ MISMATCH: Table rows (\(initialRowCount)) don't match messages (\(referenceMessages.count)), forcing fix")
                
                // Force another complete reload
                self.tableView.reloadData()
                self.tableView.layoutIfNeeded()
                
                // Check again
                let secondRowCount = self.tableView.numberOfRows(inSection: 0)
                print("📊 Second attempt row count: \(secondRowCount)")
                
                if secondRowCount != referenceMessages.count {
                    print("⚠️ STILL_MISMATCH: Forcing data source update")
                    if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                        localDataSource.forceUpdateMessages(referenceMessages)
                    }
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()
                }
            }
            
            // The UI might need a moment to update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // CRITICAL FIX: Force another reload to ensure table is completely updated
                self.tableView.reloadData()
                self.tableView.layoutIfNeeded()
                
                // Get current row count - IMPORTANT for avoiding index out of bounds
                let rowCount = self.tableView.numberOfRows(inSection: 0)
                print("📊 Final table row count: \(rowCount), trying to scroll to index \(validatedIndex)")
                
                // CRITICAL FIX: If still mismatched, retry with delay
                if rowCount != referenceMessages.count {
                    print("❌ CRITICAL_MISMATCH: Table rows (\(rowCount)) still don't match messages (\(referenceMessages.count))")
                    print("🔄 RETRY: Will retry scroll after fixing data source")
                    
                    // Force sync again
                    self.localMessages = referenceMessages
                    if let localDataSource = self.dataSource as? LocalMessagesDataSource {
                        localDataSource.forceUpdateMessages(referenceMessages)
                    }
                    self.tableView.reloadData()
                    
                    // Retry scroll after another delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.scrollToTargetMessage()
                    }
                    return
                }
                
                // Make sure the index is valid
                if rowCount > 0 && validatedIndex < rowCount {
                    print("🔍 Scrolling to validated row \(validatedIndex)")
                    // Create an index path and scroll to it
                    let indexPath = IndexPath(row: validatedIndex, section: 0)
                    
                    // Use try-catch to handle any potential crashes
                    do {
                        // CRITICAL FIX: Cancel any existing scroll animations first
                        if self.tableView.layer.animationKeys()?.contains("position") == true {
                            self.tableView.layer.removeAllAnimations()
                        }
                        
                        // Scroll to the message WITHOUT animation for instant positioning - this is TARGET MESSAGE scroll, should not be blocked
                        print("🎯 SCROLL_TO_TARGET: Scrolling to target message at index \(validatedIndex)")
                        self.tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
                        // print("📍 scrollToRow completed")
                        
                        // CRITICAL FIX: Force immediate layout update to prevent any delay
                        self.tableView.layoutIfNeeded()
                        
                        // Remove excess contentInset that might cause empty space
                        if self.tableView.contentInset.top > 0 {
                            self.tableView.contentInset = .zero
                            // print("📏 Removed excess contentInset.top in scrollToTargetMessage")
                        }
                        
                        // CRITICAL FIX: Small delay to ensure scroll position is stable
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            // print("📍 Scroll completed, highlighting immediately")
                            // Highlight immediately without delay for instant feedback
                            self.highlightTargetMessage(at: indexPath)
                        }
                        
                        // print("✅ Successfully scrolled to target message")
                    } catch {
                        // print("❌ Error scrolling to target message: \(error)")
                        // Fall back to just scrolling to the bottom as a last resort
                        self.scrollToBottom(animated: false)
                    }
                } else {
                    print("⚠️ Index \(validatedIndex) is out of bounds or table is empty (rowCount: \(rowCount))")
                    if !self.localMessages.isEmpty {
                        // If we have messages but table is not ready, try again in a moment
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.scrollToTargetMessage()
                        }
                    } else {
                        // No messages, just scroll to bottom
                        self.scrollToBottom(animated: false)
                    }
                }
            }
        }
            } else {
            print("⚠️ Target message ID not found in reference messages array")
            print("🔍 Debugging: reference messages contains \(referenceMessages.count) messages")
            
            // Debug: Check if target message is in any of the loaded messages
            print("🔍 Target message ID: \(targetId)")
            print("🔍 Reference messages: \(referenceMessages)")
            
            // Check if the target message exists in viewState.messages but not in reference messages
            if viewModel.viewState.messages[targetId] != nil {
                print("✅ Target message found in viewState.messages but missing from reference messages")
            } else {
                print("❌ Target message not found in viewState.messages either")
            }
            // Debug: Print first and last 3 message IDs to help diagnose ordering issues
            if referenceMessages.count > 0 {
                let firstMessages = Array(referenceMessages.prefix(3))
                let lastMessages = Array(referenceMessages.suffix(3))
                print("🔍 First 3 messages: \(firstMessages)")
                print("🔍 Last 3 messages: \(lastMessages)")
                print("🔍 Target message ID: \(targetId)")
            }
            
            // If not in localMessages but in viewState.messages, add it to localMessages
            if self.viewModel.viewState.messages[targetId] != nil {
                // print("🔄 Adding target message to localMessages array")
                
                // Add to beginning or end based on timestamp
                let targetMessage = self.viewModel.viewState.messages[targetId]!
                let targetDate = createdAt(id: targetId)
                
                if !localMessages.isEmpty {
                    let firstMsgDate = createdAt(id: localMessages[0])
                    let lastMsgDate = createdAt(id: localMessages[localMessages.count - 1])
                    
                    if targetDate < firstMsgDate {
                        // Add to beginning
                        self.localMessages.insert(targetId, at: 0)
                    } else if targetDate > lastMsgDate {
                        // Add to end
                        self.localMessages.append(targetId)
                    } else {
                        // Insert in sorted position
                        var insertIndex = 0
                        for (i, msgId) in self.localMessages.enumerated() {
                            let msgDate = createdAt(id: msgId)
                            if targetDate < msgDate {
                                insertIndex = i
                                break
                            }
                            insertIndex = i + 1
                        }
                        self.localMessages.insert(targetId, at: insertIndex)
                    }
                } else {
                    // If empty, just add it
                    self.localMessages.append(targetId)
                }
                
                // Update data source and reload
                DispatchQueue.main.async {
                    self.dataSource = LocalMessagesDataSource(viewModel: self.viewModel,
                                                          viewController: self,
                                                          localMessages: self.localMessages)
                    self.tableView.dataSource = self.dataSource
                    
                    // CRITICAL FIX: Force complete table reload and layout
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()
                    
                    // CRITICAL FIX: Multiple reload attempts to ensure UI is updated
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.tableView.reloadData()
                        self.tableView.layoutIfNeeded()
                    
                        // Try scrolling again after ensuring table is updated - ONLY if not processed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if !self.targetMessageProcessed {
                        self.scrollToTargetMessage()
                            } else {
                                print("🎯 Skipping duplicate scrollToTargetMessage call - already processed")
                            }
                        }
                    }
                }
            } else {
                // Try loading nearby messages
                Task {
                    let success = await self.loadMessagesNearby(messageId: targetId)
                    
                    DispatchQueue.main.async {
                        if success {
                            // print("✅ Successfully loaded messages nearby target")
                            self.scrollToTargetMessage() // Try again after loading
                        } else {
                            // print("❌ Unable to load messages near target")
                            self.scrollToBottom(animated: false) // Fallback
                        }
                    }
                }
            }
        }
    }
    
    // Sync localMessages with viewState to ensure consistency
    private func syncLocalMessagesWithViewState() {
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
        let needsChannelMessagesSync = !localMessages.isEmpty && 
                                      (viewModel.viewState.channelMessages[viewModel.channel.id] ?? []) != localMessages
        
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
    private func highlightTargetMessage(at indexPath: IndexPath, retryCount: Int = 0) {
        print("🎯 highlightTargetMessage CALLED - indexPath: \(indexPath.row), retryCount: \(retryCount)")
        print("🎯 Table view visible cells count: \(tableView.visibleCells.count)")
        print("🎯 Table view total rows: \(tableView.numberOfRows(inSection: 0))")
        
        guard let cell = tableView.cellForRow(at: indexPath) as? MessageCell else {
            // print("⚠️ Could not find MessageCell at index path \(indexPath.row), retry: \(retryCount)")
            // print("⚠️ Available cell types at this index: \(type(of: tableView.cellForRow(at: indexPath)))")
            
            // Retry up to 3 times with increasing delays
            if retryCount < 3 {
                let delay = 0.2 + (Double(retryCount) * 0.2) // 0.2s, 0.4s, 0.6s
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
        clearTargetMessageTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
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
        UIView.animate(withDuration: 0.2, animations: {
            // Fade out
            cell.contentView.alpha = 0.7
        }) { _ in
            // print("✨ Fade out completed - starting fade in")
            UIView.animate(withDuration: 0.2, animations: {
                // Fade in
                cell.contentView.alpha = 1.0
            }) { _ in
                // print("✨ Fade in completed - scheduling next pulse")
                // Continue with next pulse
                self.pulseHighlight(cell: cell, pulseCount: pulseCount, currentPulse: currentPulse + 1)
            }
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
                            viewModel.viewState.channelMessages[viewModel.channel.id] = updatedMessages
                            
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
    

    
    // Helper method to extract retry_after value from JSON error response
    private func extractRetryAfterValue(from errorData: String?) -> Int? {
        guard let data = errorData else { return nil }
        
        do {
            // Try to parse the error data as JSON
            if let dataObj = try JSONSerialization.jsonObject(with: Data(data.utf8), options: []) as? [String: Any],
               let retryAfter = dataObj["retry_after"] as? Int {
                // print("📊 Extracted retry_after: \(retryAfter)")
                return retryAfter
            }
        } catch {
            // print("❌ Error parsing JSON from error data: \(error)")
        }
        
        return nil
    }
    
    // Public method to refresh messages with a specific target message ID
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
              let previousMessage = viewModel.viewState.messages[previousMessageId] else {
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
    private var lastMessageUpdateTime = Date()
    private let minimumUpdateInterval: TimeInterval = 5.0 // Minimum seconds between updates
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
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8)
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
    
    // MARK: - Reply Handling
    
    /// Handle clicking on a reply to jump to the original message
    func handleReplyClick(messageId: String, channelId: String) {
        print("🔗 REPLY_CLICK: User clicked on reply to message \(messageId) in channel \(channelId)")
        print("🔍 REPLY_CLICK: This is the main handleReplyClick method in MessageableChannelViewController!")
        
        // CRITICAL FIX: Clear target message protection first to allow new reply click
        print("🎯 REPLY_CLICK: Clearing target message protection to allow new reply click")
        clearTargetMessageProtection(reason: "user clicked on reply")
        
        // Check if it's the same channel
        if channelId == viewModel.channel.id {
            // Same channel - scroll to the message
            print("📍 REPLY_CLICK: Same channel, attempting to scroll to message")
            
            // Check if message is already loaded
            if localMessages.contains(messageId) {
                // Message is loaded, scroll directly
                print("✅ REPLY_CLICK: Message is already loaded, scrolling directly")
                scrollToMessage(messageId: messageId)
            } else {
                // Message not loaded, use target message functionality
                print("🎯 REPLY_CLICK: Message not loaded, using target message functionality")
                print("🌐 REPLY_CLICK: About to call refreshWithTargetMessage - this should trigger API calls!")
                print("🔍 REPLY_CLICK: Current localMessages count: \(localMessages.count)")
                print("🔍 REPLY_CLICK: Current viewState messages count: \(viewModel.viewState.messages.count)")
                print("🔍 REPLY_CLICK: Current channel messages count: \(viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0)")
                
                // Set target message and trigger load
                targetMessageId = messageId
                viewModel.viewState.currentTargetMessageId = messageId
                
                // Show loading indicator with more specific message
                DispatchQueue.main.async {
                    print("🔄 REPLY_CLICK: Loading original message...")
                }
                
                // Trigger target message refresh with enhanced error handling
                Task {
                    do {
                        print("🚀 REPLY_CLICK: Starting refreshWithTargetMessage for \(messageId)")
                        await refreshWithTargetMessage(messageId)
                        
                        // Check if the message was successfully loaded
                        await MainActor.run {
                            if self.localMessages.contains(messageId) {
                                print("✅ REPLY_CLICK: Message successfully loaded and should be visible")
                            } else {
                                print("❌ REPLY_CLICK: Message was not loaded successfully")
                                // Ensure loading state is reset
                                self.messageLoadingState = .notLoading
                                self.loadingHeaderView.isHidden = true
                                self.targetMessageId = nil
                                self.viewModel.viewState.currentTargetMessageId = nil
                                
                                // Show error message to user
                                print("❌ REPLY_CLICK: Could not load the original message. It may have been deleted.")
                            }
                        }
                    } catch {
                        print("❌ REPLY_CLICK: Error in refreshWithTargetMessage: \(error)")
                        // Ensure all loading states are reset on error
                        await MainActor.run {
                            self.messageLoadingState = .notLoading
                            self.loadingHeaderView.isHidden = true
                            self.targetMessageId = nil
                            self.viewModel.viewState.currentTargetMessageId = nil
                            self.tableView.alpha = 1.0
                            self.tableView.tableFooterView = nil
                            
                            print("❌ REPLY_CLICK_ERROR: Failed to load message. Please try again.")
                        }
                    }
                }
            }
        } else {
            // Different channel - navigate to that channel with target message
            print("🔄 REPLY_CLICK: Different channel, navigating to channel \(channelId)")
            
            // Set target message in ViewState for cross-channel navigation
            viewModel.viewState.currentTargetMessageId = messageId
            
            // Navigate to the channel
            if let channel = viewModel.viewState.channels[channelId] {
                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                // This ensures that when user presses back, they go to server list instead of previous channel
                print("🔄 REPLY_CLICK: Clearing navigation path to prevent back to previous channel")
                viewModel.viewState.path = []
                
                // Clear any existing channel messages for the target channel
                viewModel.viewState.channelMessages[channelId] = []
                viewModel.viewState.atTopOfChannel.remove(channelId)
                
                // Select the server and channel properly
                if let serverId = channel.server {
                    viewModel.viewState.selectServer(withId: serverId)
                    viewModel.viewState.selectChannel(inServer: serverId, withId: channelId)
                } else {
                    // It's a DM channel
                    viewModel.viewState.selectDm(withId: channelId)
                }
                
                // Add the channel view to the navigation path
                viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                
                // Show loading message
                DispatchQueue.main.async {
                    print("🔄 NAVIGATE: Navigating to message...")
                }
            } else {
                // Channel not found, show error
                DispatchQueue.main.async {
                    print("❌ NAVIGATE: Channel not found")
                }
            }
        }
    }
    
    /// Scroll to a specific message that's already loaded
    private func scrollToMessage(messageId: String) {
        guard let index = localMessages.firstIndex(of: messageId) else {
            print("❌ SCROLL_TO_MESSAGE: Message \(messageId) not found in local messages")
            return
        }
        
        let indexPath = IndexPath(row: index, section: 0)
        
        // Make sure the index is valid
        guard index < tableView.numberOfRows(inSection: 0) else {
            print("❌ SCROLL_TO_MESSAGE: Index \(index) out of bounds")
            return
        }
        
        print("🎯 SCROLL_TO_MESSAGE: Scrolling to message at index \(index)")
        
        // Scroll to the message
        safeScrollToRow(at: indexPath, at: .middle, animated: true, reason: "scroll to specific message")
        
        // Highlight the message briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let cell = self.tableView.cellForRow(at: indexPath) as? MessageCell {
                self.highlightMessageBriefly(cell: cell)
            }
        }
    }
    
    /// Briefly highlight a message cell
    private func highlightMessageBriefly(cell: MessageCell) {
        let originalBackgroundColor = cell.backgroundColor
        
        // Highlight with blue color
        UIView.animate(withDuration: 0.3, animations: {
            cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
        }) { _ in
            // Fade back to original color
            UIView.animate(withDuration: 1.0) {
                cell.backgroundColor = originalBackgroundColor
            }
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // MARK: - Reply Handling
    internal func addReply(_ message: Types.Message) {
        // This method is deprecated and will be removed
        // Use startReply(to:) instead
        let reply = ReplyMessage(message: message, mention: true)
        addReply(reply)
    }
    
    // Add a method to display replies when editing a message
    func showReplies(_ replies: [ReplyMessage]) {
        // print("📄 Showing \(replies.count) replies")
        
        // If repliesView has not been initialized, create it
        if repliesView == nil {
            repliesView = RepliesContainerView(frame: .zero)
            repliesView?.translatesAutoresizingMaskIntoConstraints = false
            if let repliesView = repliesView {
            view.addSubview(repliesView)
            
            // Setup constraints for repliesView - position it above messageInputView
            NSLayoutConstraint.activate([
                repliesView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                repliesView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                repliesView.bottomAnchor.constraint(equalTo: messageInputView.topAnchor),
            ])
            }
        }
        
        // Set the replies and show the view
        self.replies = replies
        repliesView?.configure(with: replies, viewState: viewModel.viewState)
        repliesView?.isHidden = false
        
        // Adjust layout to make space for the replies view
        updateLayoutForReplies(isVisible: true)
    }
    
    // Add a method to update layout when replies visibility changes
    private func updateLayoutForReplies(isVisible: Bool) {
        // Get the height of the replies view
        let repliesHeight: CGFloat = isVisible ? min(CGFloat(replies.count) * 60, 180) : 0
        
        // Update tableView bottom inset to make space for replies
        var insets = tableView.contentInset
        insets.bottom = messageInputView.frame.height + repliesHeight + (isKeyboardVisible ? keyboardHeight : 0)
        tableView.contentInset = insets
        
        // Also update the scroll indicator insets
        tableView.scrollIndicatorInsets = insets
        
        // Animate the change
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
    
    // Handle system log messages
    @objc private func handleSystemLog(_ notification: Notification) {
        if let logMessage = notification.object as? String {
            checkForNetworkErrors(in: logMessage)
        }
    }
    
    // Add a method to check for network errors in logs
    private func checkForNetworkErrors(in logMessage: String) {
        // Add the log message to our recent logs
        recentLogMessages.append(logMessage)
        
        // Keep only the last maxLogMessages
        if recentLogMessages.count > maxLogMessages {
            recentLogMessages.removeFirst()
        }
        
        // Check if we've detected a network error recently (avoid multiple detections)
        if let lastError = lastNetworkErrorTime, 
           Date().timeIntervalSince(lastError) < networkErrorCooldown {
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
        if timeSinceLastAdjustment < insetAdjustmentCooldown && 
           abs(messageCount - lastMessageCountForInsets) <= 1 {
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
    
    // MARK: - Helper method to update table view bouncing behavior
    internal func updateTableViewBouncing() {
        // First check if table view is ready
        guard tableView.window != nil else { return }
        
        // CRITICAL FIX: Don't update bouncing during target message operations
        if targetMessageProtectionActive {
            print("📏 BOUNCE_BLOCKED: Bouncing update blocked - target message protection active")
            return
        }
        
        let rowCount = tableView.numberOfRows(inSection: 0)
        
        // If no rows, disable scrolling completely
        guard rowCount > 0 else {
            tableView.isScrollEnabled = false
            tableView.alwaysBounceVertical = false
            tableView.bounces = false
            tableView.showsVerticalScrollIndicator = false
            tableView.contentInset = .zero
            tableView.scrollIndicatorInsets = .zero
            // Remove header to prevent scrolling
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }
            print("📏 Disabled scrolling - no messages")
            return
        }
        
        // Calculate actual content height by summing row heights
        var actualContentHeight: CGFloat = 0
        for i in 0..<rowCount {
            let indexPath = IndexPath(row: i, section: 0)
            actualContentHeight += tableView.rectForRow(at: indexPath).height
        }
        
        // Add header/footer heights only if they are visible
        if let header = tableView.tableHeaderView, !header.isHidden {
            actualContentHeight += header.frame.height
        }
        if let footer = tableView.tableFooterView, !footer.isHidden {
            actualContentHeight += footer.frame.height
        }
        
        // Calculate visible height
        let visibleHeight = tableView.bounds.height - keyboardHeight
        
        // Be very strict - only enable scrolling if content truly exceeds visible area
        let shouldEnableScrolling = actualContentHeight > visibleHeight + 10 // 10px margin
        
        // Force update scrolling and bouncing settings
        if shouldEnableScrolling {
            tableView.isScrollEnabled = true
            tableView.alwaysBounceVertical = true
            tableView.bounces = true
            tableView.showsVerticalScrollIndicator = true
            
            // Re-add header only if it was removed AND we are loading
            if tableView.tableHeaderView == nil && isLoadingMore {
                tableView.tableHeaderView = loadingHeaderView
            }
            
        } else {
            // Completely disable scrolling when content fits
            tableView.isScrollEnabled = false
            tableView.alwaysBounceVertical = false
            tableView.bounces = false
            tableView.showsVerticalScrollIndicator = false
            // CRITICAL: Remove all content insets when scrolling is disabled
            tableView.contentInset = .zero
            tableView.scrollIndicatorInsets = .zero
            
            // Remove header to prevent any scrolling
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }
            
            // CRITICAL FIX: Don't reset scroll position during target message operations
            if !targetMessageProtectionActive {
                // Reset scroll position to top
                tableView.contentOffset = .zero
            }
            
            print("📏 Disabled scrolling completely - actual content: \(actualContentHeight), visible: \(visibleHeight), rows: \(rowCount)")
        }
    }
    
    // MARK: - Position Table at Bottom Before Showing
    private func positionTableAtBottomBeforeShowing() {
        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            print("🎯 [POSITION] Target message protection active, just showing table without positioning")
            showTableViewWithFade()
            return
        }
        
        // Force layout to calculate content size
        tableView.layoutIfNeeded()
        
        let rowCount = tableView.numberOfRows(inSection: 0)
        let messagesCount = localMessages.count
        
        // print("📊 [POSITION] Positioning table: rows=\(rowCount), messages=\(messagesCount)")
        
        // If no messages, just show the table
        guard rowCount > 0, messagesCount > 0 else {
            // print("📊 [POSITION] No messages, showing empty table")
            showTableViewWithFade()
            return
        }
        
        // Update bouncing behavior based on content
        updateTableViewBouncing()
        
        // Position at bottom (newest messages) only if no target message
        let lastRowIndex = rowCount - 1
        let indexPath = IndexPath(row: lastRowIndex, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        // print("🔽 [POSITION] Positioned at bottom (newest messages)")
        
        // Show the table view now that it's properly positioned
        showTableViewWithFade()
        
        // CRITICAL FIX: Check for missing reply content after positioning with longer delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0 seconds
            await self.checkAndFetchMissingReplies()
        }
    }
    
    // Helper method to show table view with smooth fade-in
    private func showTableViewWithFade() {
        UIView.animate(withDuration: 0.2) {
            self.tableView.alpha = 1.0
        }
        // print("✨ [POSITION] Table view shown with fade-in")
    }
    
    // MARK: - Skeleton Loading Methods (DISABLED FOR PERFORMANCE)
    // TODO: Re-enable skeleton loading after performance optimization is complete
    // TODO: Identify optimal skeleton loading strategy for better UX
    
    private func showSkeletonView() {
        // DISABLED: Skeleton loading temporarily disabled for performance optimization
        print("💀 SKELETON: DISABLED - Skeleton loading temporarily disabled for performance")
        return
        
        // Original skeleton code commented out:
        /*
        // Only show skeleton if not already shown
        guard skeletonView == nil else { return }
        
        let skeleton = MessageSkeletonView()
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(skeleton)
        
        NSLayoutConstraint.activate([
            skeleton.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            skeleton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeleton.bottomAnchor.constraint(equalTo: messageInputView.topAnchor)
        ])
        
        skeletonView = skeleton
        
        // Hide table view while showing skeleton
        tableView.alpha = 0.0
        
        print("💀 SKELETON: Showing skeleton loading view")
        */
    }
    
    private func hideSkeletonView() {
        // DISABLED: Skeleton loading temporarily disabled for performance optimization
        print("💀 SKELETON: DISABLED - Skeleton hiding temporarily disabled for performance")
        return
        
        // Original skeleton code commented out:
        /*
        guard let skeleton = skeletonView else { return }
        
        UIView.animate(withDuration: 0.3, animations: {
            skeleton.alpha = 0.0
        }) { _ in
            skeleton.removeFromSuperview()
            self.skeletonView = nil
        }
        
        // Show table view
        UIView.animate(withDuration: 0.3) {
            self.tableView.alpha = 1.0
        }
        
        print("💀 SKELETON: Hiding skeleton loading view")
        */
    }
    
    // MARK: - Global Fix for Black Screen
    private func applyGlobalFix() {
        // print("🔧 [FIX] Applying global fix for black screen...")
        
        // CRITICAL FIX: Don't apply global fix if target message protection is active
        if targetMessageProtectionActive {
            print("🔧 [FIX] BLOCKED: Global fix blocked - target message protection active")
            return
        }
        
        // Store current scroll position before fix
        let currentOffset = self.tableView.contentOffset.y
        let wasNearBottom = self.isUserNearBottom()
        
        // Synchronize message arrays
        if let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id], !channelMessages.isEmpty {
            // CRITICAL: Check if actual message objects exist
            let hasActualMessages = channelMessages.first(where: { viewModel.viewState.messages[$0] != nil }) != nil
            
            if hasActualMessages {
                self.localMessages = channelMessages
                self.viewModel.messages = self.localMessages
                // print("🔄 [FIX] Synced all message arrays with \(self.localMessages.count) messages")
            } else {
                // print("⚠️ [FIX] Found message IDs but no actual messages - need to load from API")
                // Clear the arrays and load fresh
                self.localMessages = []
                self.viewModel.messages = []
                viewModel.viewState.channelMessages[viewModel.channel.id] = []
                
                // Trigger API load
                Task {
                    await loadInitialMessages()
                }
                return
            }
        } else if !self.localMessages.isEmpty {
            viewModel.viewState.channelMessages[viewModel.channel.id] = self.localMessages
            self.viewModel.messages = self.localMessages
            // print("🔄 [FIX] Populated viewState from localMessages with \(self.localMessages.count) messages")
        } else if !self.viewModel.messages.isEmpty {
            self.localMessages = self.viewModel.messages
            viewModel.viewState.channelMessages[viewModel.channel.id] = self.localMessages
            // print("🔄 [FIX] Populated from viewModel.messages with \(self.viewModel.messages.count) messages")
        }
        
        // Remove any excess contentInset
        if self.tableView.contentInset != .zero {
            UIView.animate(withDuration: 0.2) {
                self.tableView.contentInset = .zero
            }
            // print("📏 [FIX] Reset content insets to zero")
        }
        
        // Ensure DataSource is up-to-date
        self.dataSource = LocalMessagesDataSource(
            viewModel: self.viewModel,
            viewController: self,
            localMessages: self.localMessages
        )
        self.tableView.dataSource = self.dataSource
        
        // Reload and position properly
        DispatchQueue.main.async {
            // Reload table
            self.tableView.reloadData()
            // print("🔄 [FIX] Reloaded tableView")
            
            // Update table view bouncing behavior
            self.updateTableViewBouncing()
            
            // COMPREHENSIVE TARGET MESSAGE PROTECTION
            if self.targetMessageProtectionActive {
                print("🎯 [FIX] Target message protection active, maintaining current position")
                self.tableView.contentOffset = CGPoint(x: 0, y: currentOffset)
                return
            }
            
            // ONLY scroll to bottom if user was near bottom OR if table was empty before
            if wasNearBottom || currentOffset <= 0 {
                // print("🔽 [FIX] User was near bottom or at top, positioning at bottom")
                self.positionTableAtBottomBeforeShowing()
            } else {
                // Try to maintain scroll position if user was somewhere in the middle
                // print("📏 [FIX] User was not near bottom, attempting to maintain scroll position")
                self.tableView.contentOffset = CGPoint(x: 0, y: currentOffset)
            }
        }
    }
    
    // Enhanced version of scrollToTargetMessage that handles black screen issues
    private func scrollToTargetMessage(_ messageId: String? = nil, animated: Bool = false) {
        // Use the provided message ID or the target message ID from properties
        let targetMessageId = messageId ?? self.targetMessageId
        
        guard let targetId = targetMessageId,
              let targetIndex = viewModel.messages.firstIndex(of: targetId) else {
            // print("⚠️ Target message not found for scrolling")
            // Apply global fix if table is empty but we have messages
            if tableView.numberOfRows(inSection: 0) == 0, 
               let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id], 
               !channelMessages.isEmpty {
                applyGlobalFix()
            } else {
                scrollToBottom(animated: false)
            }
            return
        }
        
        // Reset contentInset to avoid empty space
        if tableView.contentInset != .zero {
            UIView.animate(withDuration: 0.2) {
                self.tableView.contentInset = .zero
            }
            // print("📏 Reset content insets before scrolling to target message")
        }
        
        // Calculate a safety target index within bounds of table view
        let tableRows = tableView.numberOfRows(inSection: 0)
        
        // If tableView has no rows but we have messages, apply global fix
        if tableRows == 0 && !viewModel.messages.isEmpty {
            // print("⚠️ Table has 0 rows but viewModel has \(viewModel.messages.count) messages - applying fix")
            applyGlobalFix()
            // Try scrolling again after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.scrollToTargetMessage(targetId, animated: animated)
            }
            return
        }
        
        let safeTargetIndex = min(targetIndex, tableRows - 1)
        if safeTargetIndex >= 0 && safeTargetIndex < tableRows {
            // Scroll to the target message
            let indexPath = IndexPath(row: safeTargetIndex, section: 0)
            tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
            // print("🎯 Scrolled to target message at index \(safeTargetIndex)")
            
            // For emphasis, highlight the message temporarily
            if let cell = tableView.cellForRow(at: indexPath) as? MessageCell {
                UIView.animate(withDuration: 0.3, animations: {
                    cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
                }) { _ in
                    UIView.animate(withDuration: 0.5) {
                        cell.backgroundColor = .clear
                    }
                }
            }
        } else {
            // print("⚠️ Target index \(safeTargetIndex) is out of bounds (0..\(tableRows-1))")
            scrollToBottom(animated: false)
        }
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
                    sort: "Oldest", // Add sort=Oldest parameter for after requests
                    server: viewModel.channel.server
                ).get()
                
                // print("⬇️⬇️⬇️ API call completed successfully, got \(result.messages.count) messages")
                
                // Fetch reply messages BEFORE MainActor.run
                print("🔗 CALLING fetchReplyMessagesContent (makeDirectAPICall) with \(result.messages.count) messages")
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
                            viewModel.viewState.channelMessages[viewModel.channel.id] = updatedMessages
                            
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
                            minimumAPICallInterval = max(minimumAPICallInterval, min(Double(retryAfter)/1000.0, 30.0))
                            
                            // Show user-friendly message with the retry time
                            print("⏳ RATE_LIMIT: Please wait \(formattedTime) seconds before loading more messages.")
                            
                            // Update the last API call time to enforce the retry_after delay
                            lastAPICallTime = Date().addingTimeInterval(-minimumAPICallInterval + Double(retryAfter)/1000.0)
                        } else {
                            // Fallback message if we couldn't extract the retry time
                            print("⏳ RATE_LIMIT: Please wait a few seconds before loading more messages.")
                            
                            // Set a default delay
                            minimumAPICallInterval = max(minimumAPICallInterval, 5.0)
                            lastAPICallTime = Date()
                        }
                    } else {
                        // Generic error handling for other errors
                        let banner = NotificationBanner(message: "Failed to load messages: \(error.localizedDescription)")
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
                    let banner = NotificationBanner(message: "Failed to load messages: \(error.localizedDescription)")
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
                task.cancel() // Try to cancel the task
            }
        }
    }
    

    
    // MARK: - Scroll Position Preservation
    
    /// Maintains the user's visual scroll position when inserting messages at the top of the table view.
    /// This ensures the user continues looking at the same message after new content is added above.
    ///
    /// - Parameters:
    ///   - insertionIndex: The index where new rows will be inserted (typically 0 for top insertion)
    ///   - count: The number of rows being inserted
    ///   - animated: Whether to animate the insertion
    private func maintainScrollPositionAfterInsertingMessages(at insertionIndex: Int, count: Int, animated: Bool) {
        guard count > 0 else { return }
        
        // Step 1: Find an anchor cell before insertion
        let anchorInfo = findAnchorCellBeforeInsertion()
        
        // Step 2: Perform the insertion
        let indexPaths = (0..<count).map { IndexPath(row: insertionIndex + $0, section: 0) }
        
        if animated {
            tableView.performBatchUpdates({
                self.tableView.insertRows(at: indexPaths, with: .none)
            }) { _ in
                // Step 3: Restore position after insertion completes
                if let anchor = anchorInfo {
                    self.restoreScrollPositionToAnchor(anchor, insertedCount: count)
                }
            }
        } else {
            // For non-animated updates, we need to handle this more carefully
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            
            tableView.beginUpdates()
            tableView.insertRows(at: indexPaths, with: .none)
            tableView.endUpdates()
            
            // Immediately restore position
            if let anchor = anchorInfo {
                restoreScrollPositionToAnchor(anchor, insertedCount: count)
            }
            
            CATransaction.commit()
        }
    }
    
    /// Represents information about an anchor cell used for scroll position preservation
    private struct AnchorCellInfo {
        let indexPath: IndexPath
        let distanceFromTop: CGFloat
        let cellFrame: CGRect
    }
    
    /// Finds a suitable anchor cell to use for maintaining scroll position.
    /// Returns the first fully visible cell that's not at the very top.
    private func findAnchorCellBeforeInsertion() -> AnchorCellInfo? {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              !visibleIndexPaths.isEmpty else {
            return nil
        }
        
        let contentOffset = tableView.contentOffset
        let topInset = tableView.contentInset.top
        
        // Find the first fully visible cell (not partially clipped)
        // We skip the very first visible cell as it might be partially visible
        for (index, indexPath) in visibleIndexPaths.enumerated() {
            let cellFrame = tableView.rectForRow(at: indexPath)
            let cellTop = cellFrame.origin.y
            let cellBottom = cellFrame.origin.y + cellFrame.height
            
            let visibleTop = contentOffset.y + topInset
            let visibleBottom = contentOffset.y + tableView.bounds.height - tableView.contentInset.bottom
            
            // Check if cell is fully visible
            let isFullyVisible = cellTop >= visibleTop && cellBottom <= visibleBottom
            
            // Use the second or third fully visible cell as anchor (more stable)
            if isFullyVisible && index >= 1 {
                let distanceFromTop = cellTop - contentOffset.y
                
                return AnchorCellInfo(
                    indexPath: indexPath,
                    distanceFromTop: distanceFromTop,
                    cellFrame: cellFrame
                )
            }
        }
        
        // Fallback: use the first visible cell if no fully visible cell found
        if let firstVisible = visibleIndexPaths.first {
            let cellFrame = tableView.rectForRow(at: firstVisible)
            let distanceFromTop = cellFrame.origin.y - contentOffset.y
            
            return AnchorCellInfo(
                indexPath: firstVisible,
                distanceFromTop: distanceFromTop,
                cellFrame: cellFrame
            )
        }
        
        return nil
    }
    
    /// Restores the scroll position so the anchor cell appears at the same visual position
    private func restoreScrollPositionToAnchor(_ anchor: AnchorCellInfo, insertedCount: Int) {
        // The anchor cell's index has shifted down by the number of inserted rows
        let newIndexPath = IndexPath(row: anchor.indexPath.row + insertedCount, section: 0)
        
        // Ensure the new index path is valid
        guard newIndexPath.row < tableView.numberOfRows(inSection: 0) else {
            // print("⚠️ Anchor cell index out of bounds after insertion")
            return
        }
        
        // Get the new frame of the anchor cell
        let newCellFrame = tableView.rectForRow(at: newIndexPath)
        
        // Calculate the new content offset to maintain the same visual position
        let newContentOffsetY = newCellFrame.origin.y - anchor.distanceFromTop
        
        // Apply the new content offset without animation to avoid visual jumps
        tableView.setContentOffset(CGPoint(x: 0, y: newContentOffsetY), animated: false)
        
        // print("📌 Maintained scroll position: anchor cell \(anchor.indexPath.row) → \(newIndexPath.row), offset: \(newContentOffsetY)")
    }
    
    /// Alternative implementation using a message ID as anchor instead of index path
    /// This is more robust when dealing with data source changes
    private func maintainScrollPositionWithMessageAnchor(insertedCount: Int) {
        guard insertedCount > 0 else {
            return
        }
        
        // Force layout to ensure frames are up to date
        tableView.layoutIfNeeded()
        
        // Get visible index paths before the change
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              !visibleIndexPaths.isEmpty else {
            // print("⚠️ No visible cells to use as anchor")
            return
        }
        
        // Find a stable message to use as anchor
        var anchorMessageId: String?
        var anchorDistanceFromTop: CGFloat = 0
        
        let contentOffset = tableView.contentOffset
        
        // print("📍 Looking for anchor cell among \(visibleIndexPaths.count) visible cells")
        
        // Look for a good anchor message (preferably the second or third visible)
        // IMPORTANT: At this point, localMessages already contains the new messages
        // We need to find a message that was visible BEFORE the insertion
        for (index, indexPath) in visibleIndexPaths.enumerated() {
            // Skip if the index is invalid
            if indexPath.row >= localMessages.count {
                continue
            }
            
            let messageId = localMessages[indexPath.row]
            let cellFrame = tableView.rectForRow(at: indexPath)
            
            // Prefer cells that are not at the very top for stability
            if index >= 1 || visibleIndexPaths.count == 1 {
                anchorMessageId = messageId
                anchorDistanceFromTop = cellFrame.origin.y - contentOffset.y
                // print("📍 Selected anchor: message at index \(indexPath.row), ID: \(messageId), distance from top: \(anchorDistanceFromTop)")
                break
            }
        }
        
        // Fallback to first visible if no suitable anchor found
        if anchorMessageId == nil, let firstVisible = visibleIndexPaths.first {
            if firstVisible.row < localMessages.count {
                anchorMessageId = localMessages[firstVisible.row]
                let cellFrame = tableView.rectForRow(at: firstVisible)
                anchorDistanceFromTop = cellFrame.origin.y - contentOffset.y
                // print("📍 Fallback anchor: message at index \(firstVisible.row)")
            }
        }
        
        // If we found an anchor, restore its position after the table updates
        if let anchorId = anchorMessageId {
            // Force another layout pass to ensure all cells are sized correctly
            tableView.layoutIfNeeded()
            
            // Find the anchor message's new position
            if let newIndex = localMessages.firstIndex(of: anchorId) {
                let newIndexPath = IndexPath(row: newIndex, section: 0)
                
                // Ensure the index is valid
                if newIndex < tableView.numberOfRows(inSection: 0) {
                    let newCellFrame = tableView.rectForRow(at: newIndexPath)
                    let newContentOffsetY = newCellFrame.origin.y - anchorDistanceFromTop
                    
                    // print("📍 Restoring position: anchor now at index \(newIndex), new offset: \(newContentOffsetY)")
                    
                    // Apply the new content offset without animation
                    tableView.setContentOffset(CGPoint(x: 0, y: newContentOffsetY), animated: false)
                } else {
                    // print("⚠️ New index \(newIndex) is out of bounds")
                }
            } else {
                // print("⚠️ Could not find anchor message in updated array")
            }
        } else {
            // print("⚠️ No anchor message selected")
        }
    }
    
    // Precise scroll to reference message with retry mechanism
    private func scrollToReferenceMessageWithRetry(referenceId: String?, messagesArray: [String], maxRetries: Int) {
        guard let referenceId = referenceId else {
            // print("⚠️ REFERENCE_SCROLL: No reference ID provided")
            return
        }
        
        // print("🎯 REFERENCE_SCROLL: Starting scroll to reference message '\(referenceId)'")
        
        // Attempt to scroll with retry logic
        attemptScrollToReference(referenceId: referenceId, messagesArray: messagesArray, attempt: 1, maxRetries: maxRetries)
    }
    
    private func attemptScrollToReference(referenceId: String, messagesArray: [String], attempt: Int, maxRetries: Int) {
        guard attempt <= maxRetries else {
            // print("❌ REFERENCE_SCROLL: Failed to scroll after \(maxRetries) attempts")
            // Clear the reference ID since we've exhausted retries
            self.lastBeforeMessageId = nil
            return
        }
        
        // print("🎯 REFERENCE_SCROLL: Attempt \(attempt)/\(maxRetries) to find and scroll to '\(referenceId)'")
        
        // Find the reference message in the array
        if let targetIndex = messagesArray.firstIndex(of: referenceId) {
            // print("✅ REFERENCE_SCROLL: Found reference message at index \(targetIndex)")
            
            // Verify table view has the expected number of rows
            let tableRowCount = self.tableView.numberOfRows(inSection: 0)
            // print("📊 REFERENCE_SCROLL: Table has \(tableRowCount) rows, array has \(messagesArray.count) items")
            
            // Make sure the index is valid for the table
            if targetIndex < tableRowCount {
                let indexPath = IndexPath(row: targetIndex, section: 0)
                
                // Calculate delay based on attempt number
                let delay = Double(attempt - 1) * 0.2 // 0s, 0.2s, 0.4s
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    // Double-check the table state before scrolling
                    let currentRowCount = self.tableView.numberOfRows(inSection: 0)
                    if targetIndex < currentRowCount {
                        // Force layout before scrolling
                        self.tableView.layoutIfNeeded()
                        
                                                 // Perform the scroll
                         self.tableView.scrollToRow(at: indexPath, at: .top, animated: false)
                        
                        // print("🎯 REFERENCE_SCROLL: Successfully scrolled to reference message at index \(targetIndex) (attempt \(attempt))")
                        
                        // Verify scroll position after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let visibleIndexPaths = self.tableView.indexPathsForVisibleRows ?? []
                            let isVisible = visibleIndexPaths.contains(indexPath)
                            
                            if isVisible {
                                // print("✅ REFERENCE_SCROLL: Reference message is now visible, clearing reference ID")
                                self.lastBeforeMessageId = nil
                            } else {
                                // print("⚠️ REFERENCE_SCROLL: Reference message not visible after scroll, retrying...")
                                // Retry with next attempt
                                self.attemptScrollToReference(referenceId: referenceId, messagesArray: messagesArray, attempt: attempt + 1, maxRetries: maxRetries)
                            }
                        }
                    } else {
                        // print("⚠️ REFERENCE_SCROLL: Index \(targetIndex) out of bounds (table has \(currentRowCount) rows), retrying...")
                        // Retry with next attempt
                        self.attemptScrollToReference(referenceId: referenceId, messagesArray: messagesArray, attempt: attempt + 1, maxRetries: maxRetries)
                    }
                }
            } else {
                // print("⚠️ REFERENCE_SCROLL: Index \(targetIndex) out of bounds for table with \(tableRowCount) rows, retrying...")
                // Retry with next attempt  
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.attemptScrollToReference(referenceId: referenceId, messagesArray: messagesArray, attempt: attempt + 1, maxRetries: maxRetries)
                }
            }
        } else {
            // print("⚠️ REFERENCE_SCROLL: Reference message '\(referenceId)' not found in array, retrying...")
            
            // print some debug info about the array
            if messagesArray.count > 0 {
                let first5 = Array(messagesArray.prefix(5))
                let last5 = Array(messagesArray.suffix(5))
                // print("🔍 REFERENCE_SCROLL: Array first 5: \(first5)")
                // print("🔍 REFERENCE_SCROLL: Array last 5: \(last5)")
            }
            
            // Retry with next attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Get fresh messages array in case it changed
                let freshArray = !self.viewModel.messages.isEmpty ? 
                    self.viewModel.messages : 
                    (self.viewModel.viewState.channelMessages[self.viewModel.channel.id] ?? [])
                self.attemptScrollToReference(referenceId: referenceId, messagesArray: freshArray, attempt: attempt + 1, maxRetries: maxRetries)
            }
        }
    }
    
//    private func loadInitialMessagesImmediate() async {
//        let channelId = viewModel.channel.id
//        print("💾 REACTIVE_IMMEDIATE: Delegating to ViewModel for channel \(channelId)")
//        
//        // Ensure table is visible at the end
//        defer {
//            DispatchQueue.main.async {
//                self.tableView.alpha = 1.0
//                self.tableView.tableFooterView = nil
//            }
//        }
//        
//        let startTime = Date()
//        
//        // Delegate to ViewModel
//        await viewModel.loadChannelMessages()
//        
//        let duration = Date().timeIntervalSince(startTime)
//        print("✅ REACTIVE_IMMEDIATE: ViewModel completed in \(String(format: "%.3f", duration))s")
//        
//        // Refresh UI
//        await MainActor.run {
//            self.hideSkeletonView()
//            self.refreshMessages()
//        }
//        
//        // Old network fetch code removed - all network happens via NetworkSyncService
//        if false {
//        let apiStartTime = Date()
//        print("🌐 API_LOAD: Fetching fresh data from server")
//        
//        do {
//            // Get server ID if this is a server channel
//            let serverId = viewModel.channel.server
//            
//            // SMART LIMIT: Use 10 for specific channel in specific server, 50 for others
//            let messageLimit = (channelId == "01J7QTT66242A7Q26A2FH5TD48" && serverId == "01J544PT4T3WQBVBSDK3TBFZW7") ? 10 : 50
//            
//            // Fetch from API only if DB did not provide any messages
//            print("🌐 API CALL: fetchHistory - Channel: \(channelId), Limit: \(messageLimit)")
//            let result = try await viewModel.viewState.http.fetchHistory(
//                channel: channelId,
//                limit: messageLimit,
//                sort: "Latest",
//                server: serverId,
//                include_users: true
//            ).get()
//            
//            let apiEndTime = Date()
//            let apiDuration = apiEndTime.timeIntervalSince(apiStartTime)
//            print("🌐 API_RESPONSE: Received \(result.messages.count) messages in \(String(format: "%.2f", apiDuration))s")
//            
//            // Save to database (DatabaseObserver will update ViewState automatically)
//            print("💾 Saving \(result.messages.count) messages, \(result.users.count) users to database")
//            Task.detached(priority: .utility) {
//                await NetworkRepository.shared.saveFetchHistoryResponse(
//                    messages: result.messages,
//                    users: result.users,
//                    members: result.members
//                )
//                print("✅ Data saved to Realm database")
//            }
//            
//            // IMMEDIATE PROCESSING for UI responsiveness
//            let processingStartTime = Date()
//            
//            // Process users immediately (for instant display)
//            for user in result.users {
//                viewModel.viewState.users[user.id] = user
//            }
//            
//            // Process members immediately
//            if let members = result.members {
//                for member in members {
//                    viewModel.viewState.members[member.id.server, default: [:]][member.id.user] = member
//                }
//            }
//            
//            // Process messages immediately
//            for message in result.messages {
//                viewModel.viewState.messages[message.id] = message
//            }
//            
//            // Fetch reply message content for messages that have replies
//            print("🔗 CALLING fetchReplyMessagesContentAndRefreshUI (immediate load) with \(result.messages.count) messages")
//            await fetchReplyMessagesContentAndRefreshUI(for: result.messages)
//            
//            // Sort messages immediately
//            let sortedIds = result.messages.map { $0.id }.sorted { id1, id2 in
//                let date1 = createdAt(id: id1)
//                let date2 = createdAt(id: id2)
//                return date1 < date2
//            }
//            
//            let processingEndTime = Date()
//            let processingDuration = processingEndTime.timeIntervalSince(processingStartTime)
//            print("⚡ PROCESSING_IMMEDIATE: Processed \(sortedIds.count) messages in \(String(format: "%.2f", processingDuration))s")
//            
//            // IMMEDIATE UI UPDATE
//            let uiStartTime = Date()
//            
//            await MainActor.run {
//                // Hide skeleton first
//                self.hideSkeletonView()
//                
//                // Update all data immediately
//                self.localMessages = sortedIds
//                self.viewModel.viewState.channelMessages[channelId] = sortedIds
//                self.viewModel.messages = sortedIds
//                
//                // Update data source immediately
//                if let localDataSource = self.dataSource as? LocalMessagesDataSource {
//                    localDataSource.updateMessages(sortedIds)
//                }
//                
//                // Reload table immediately
//                self.tableView.reloadData()
//                
//                // Position at bottom immediately
//                if !sortedIds.isEmpty {
//                    self.positionTableAtBottomBeforeShowing()
//                }
//                
//                let uiEndTime = Date()
//                let uiDuration = uiEndTime.timeIntervalSince(uiStartTime)
//                let totalDuration = uiEndTime.timeIntervalSince(apiStartTime)
//                
//                print("⚡ UI_UPDATE_IMMEDIATE: Updated UI in \(String(format: "%.2f", uiDuration))s")
//                print("⚡ TOTAL_IMMEDIATE_DURATION: \(String(format: "%.2f", totalDuration))s")
//                print("⚡ BREAKDOWN: API=\(String(format: "%.2f", apiDuration))s, Processing=\(String(format: "%.2f", processingDuration))s, UI=\(String(format: "%.2f", uiDuration))s")
//            }
//            
//        } catch {
//            print("❌ IMMEDIATE_LOAD_ERROR: \(error)")
//            
//            DispatchQueue.main.async {
//                self.hideSkeletonView()
//                self.updateEmptyStateVisibility()
//            }
//        }
//    }
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

// Helper method for showing error alerts
extension MessageableChannelViewController {
    func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIImagePickerControllerDelegate Implementation
// Note: UIImagePickerControllerDelegate is now handled by MessageInputHandler


// MARK: - UITableViewDataSourcePrefetching
extension MessageableChannelViewController: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        // Pre-cache message data for upcoming rows
        for indexPath in indexPaths {
            if indexPath.row < viewModel.messages.count {
                let messageId = viewModel.messages[indexPath.row]
                if let message = viewModel.viewState.messages[messageId],
                   let author = viewModel.viewState.users[message.author] {
                    
                    // Pre-load author's avatar
                    let member = viewModel.getMember(message: message).wrappedValue
                    let avatarInfo = viewModel.viewState.resolveAvatarUrl(user: author, member: member, masquerade: message.masquerade)
                    
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
                            let urlString = viewModel.viewState.formatUrl(fromId: attachment.id, withTag: "attachments")
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

// MARK: - Empty State Handling
extension MessageableChannelViewController {
    
    private func showEmptyStateView() {
        // If the empty state view already exists, just make sure it's visible
        if let existingView = view.viewWithTag(100) {
            existingView.isHidden = false
            return
        }
        
        // Create empty state container
        let emptyStateView = UIView()
        emptyStateView.tag = 100
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.backgroundColor = UIColor(named: "bgDefaultPurple13") ?? .systemBackground
        view.addSubview(emptyStateView)
        
        // Position between header and input view
        NSLayoutConstraint.activate([
            emptyStateView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: messageInputView.topAnchor)
        ])
        
        // Create container for content
        let contentContainer = UIStackView()
        contentContainer.axis = .vertical
        contentContainer.alignment = .center
        contentContainer.spacing = 16
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(contentContainer)
        
        // Center stack view in the empty state view
        NSLayoutConstraint.activate([
            contentContainer.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            contentContainer.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor, constant: -40), // Slight offset for better visual balance
            contentContainer.widthAnchor.constraint(lessThanOrEqualTo: emptyStateView.widthAnchor, multiplier: 0.8)
        ])
        
        // Channel Icon
        let channelIconView = UIImageView()
        channelIconView.translatesAutoresizingMaskIntoConstraints = false
        channelIconView.contentMode = .scaleAspectFit
        channelIconView.clipsToBounds = true
        channelIconView.layer.cornerRadius = 40
        channelIconView.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        channelIconView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        channelIconView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        
        // Load channel icon based on channel type
        switch viewModel.channel {
        case .text_channel(let c):
            if let icon = c.icon {
                // Try to get the full URL for the channel icon
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(with: iconUrl)
                }
            } else {
                // Use hashtag icon for text channels
                channelIconView.image = UIImage(systemName: "number")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor.clear
            }
            
        case .voice_channel(let c):
            if let icon = c.icon {
                // Try to get the full URL for the channel icon
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(with: iconUrl)
                }
            } else {
                // Use speaker icon for voice channels
                channelIconView.image = UIImage(systemName: "speaker.wave.2.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor.clear
            }
            
        case .group_dm_channel(let c):
            if let icon = c.icon {
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(with: iconUrl)
                }
            } else {
                // Use group icon for group DM channels
                channelIconView.image = UIImage(systemName: "person.2.circle.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor(named: "bgGreen07")
            }
            
        case .dm_channel(let c):
            // For DM channels, show the other user's avatar
            if let recipient = viewModel.viewState.getDMPartnerName(channel: c) {
                let avatarInfo = viewModel.viewState.resolveAvatarUrl(user: recipient, member: nil, masquerade: nil)
                
                // Always load avatar (either actual or default) from URL
                channelIconView.kf.setImage(with: avatarInfo.url)
                
                // Set background color based on whether user has avatar or not
                if !avatarInfo.isAvatarSet {
                    channelIconView.backgroundColor = UIColor(
                        hue: CGFloat(recipient.username.hashValue % 100) / 100.0,
                        saturation: 0.8,
                        brightness: 0.8,
                        alpha: 1.0
                    )
                } else {
                    channelIconView.backgroundColor = UIColor.clear
                }
            } else {
                // Fallback icon when recipient is nil
                channelIconView.image = UIImage(systemName: "person.circle.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor(named: "bgGray11")
            }
            
        case .saved_messages(_):
            // Use bookmark icon for saved messages
            channelIconView.image = UIImage(systemName: "bookmark.circle.fill")
            channelIconView.tintColor = .iconDefaultGray01
            channelIconView.backgroundColor = UIColor(named: "bgGreen07")
        }
        
        // Channel name label
        let channelNameLabel = UILabel()
        channelNameLabel.text = viewModel.channel.getName(viewModel.viewState)
        channelNameLabel.font = UIFont.boldSystemFont(ofSize: 24)
        channelNameLabel.textColor = UIColor(named: "textDefaultGray01") ?? .label
        channelNameLabel.textAlignment = .center
        
        // Message label
        let messageLabel = UILabel()
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 16)
        messageLabel.textColor = UIColor(named: "textGray06") ?? .secondaryLabel
        
        // Choose appropriate message based on channel type
        let title: String
        if viewModel.channel.isDM {
            title = "This space is ready for your words. Start the convo!"
        } else if viewModel.channel.isTextOrVoiceChannel {
            title = "Your Channel Awaits. Say hi and break the ice with your first message."
        } else {
            title = "Your Group Awaits. Say hi and break the ice with your first message."
        }
        messageLabel.text = title
        
        // Add views to container
        contentContainer.addArrangedSubview(channelIconView)
        contentContainer.addArrangedSubview(channelNameLabel)
        contentContainer.addArrangedSubview(messageLabel)
        
        // Add spacing
        contentContainer.setCustomSpacing(24, after: channelIconView)
        contentContainer.setCustomSpacing(8, after: channelNameLabel)
        
        // Bring to front
        view.bringSubviewToFront(emptyStateView)
    }
    
    private func hideEmptyStateView() {
        if let emptyStateView = view.viewWithTag(100) {
            emptyStateView.isHidden = true
        }
    }
}

// MARK: - NSFWOverlayView and Delegate
protocol NSFWOverlayViewDelegate: AnyObject {
    func nsfwOverlayViewDidConfirm(_ view: NSFWOverlayView)
}

class NSFWOverlayView: UIView {
    weak var delegate: NSFWOverlayViewDelegate?
    
    private let channelName: String
    
    // UI Components
    private let overlayView = UIView()
    private let stackView = UIStackView()
    private let warningSymbol = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let confirmButton = UIButton(type: .system)
    
    init(channelName: String) {
        self.channelName = channelName
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        setupOverlay()
        setupStackView()
        setupWarningSymbol()
        setupLabels()
        setupConfirmButton()
        setupConstraints()
    }
    
    private func setupOverlay() {
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlayView)
    }
    
    private func setupStackView() {
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(stackView)
    }
    
    private func setupWarningSymbol() {
        warningSymbol.image = UIImage(systemName: "exclamationmark.triangle.fill")
        warningSymbol.contentMode = .scaleAspectFit
        warningSymbol.tintColor = .textDefaultGray01
        warningSymbol.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupLabels() {
        // Title label
        titleLabel.text = channelName
        titleLabel.textColor = .textDefaultGray01
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.numberOfLines = 0
        
        // Message label
        messageLabel.text = "This channel is marked as NSFW"
        messageLabel.textColor = .textGray06
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 14)
        messageLabel.numberOfLines = 0
    }
    
    private func setupConfirmButton() {
        confirmButton.setTitle("I confirm that I am at least 18 years old", for: .normal)
        confirmButton.setTitleColor(.textDefaultGray01, for: .normal)
        confirmButton.backgroundColor = UIColor.systemBlue
        confirmButton.layer.cornerRadius = 8
        confirmButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        confirmButton.addTarget(self, action: #selector(confirmButtonTapped), for: .touchUpInside)
        confirmButton.titleLabel?.numberOfLines = 0
        confirmButton.titleLabel?.textAlignment = .center
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Overlay fills entire view
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Stack view centered in overlay
            stackView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: overlayView.widthAnchor, multiplier: 0.8),
            
            // Warning symbol size
            warningSymbol.heightAnchor.constraint(equalToConstant: 100),
            warningSymbol.widthAnchor.constraint(equalToConstant: 100)
        ])
        
        // Add arranged subviews
        stackView.addArrangedSubview(warningSymbol)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(confirmButton)
    }
    
    // MARK: - Actions
    
    @objc private func confirmButtonTapped() {
        delegate?.nsfwOverlayViewDidConfirm(self)
    }
    
    // MARK: - Public Methods
    
    func show(in parentView: UIView, animated: Bool = true) {
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            topAnchor.constraint(equalTo: parentView.topAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        
        if animated {
            alpha = 0
            UIView.animate(withDuration: 0.3) {
                self.alpha = 1
            }
        }
    }
    
    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                self.alpha = 0
            }) { _ in
                self.removeFromSuperview()
                completion?()
            }
        } else {
            removeFromSuperview()
            completion?()
        }
    }
    
    // MARK: - Static Convenience Method
    
    static func show(in parentView: UIView, channelName: String, delegate: NSFWOverlayViewDelegate?) -> NSFWOverlayView {
        let overlay = NSFWOverlayView(channelName: channelName)
        overlay.delegate = delegate
        overlay.show(in: parentView, animated: true)
        return overlay
    }
}

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
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
    }
    
    func show(duration: TimeInterval = 2.0) {
        guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return
        }
        
        keyWindow.addSubview(containerView)
        
        // Position at top center
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: keyWindow.safeAreaLayoutGuide.topAnchor, constant: 20),
            containerView.centerXAnchor.constraint(equalTo: keyWindow.centerXAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: keyWindow.widthAnchor, constant: -40)
        ])
        
        // Start with alpha 0
        containerView.alpha = 0.0
        
        // Animate in
        UIView.animate(withDuration: 0.3) {
            self.containerView.alpha = 1.0
        }
        
        // Auto dismiss after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(withDuration: 0.3, animations: {
                self.containerView.alpha = 0.0
            }) { _ in
                self.containerView.removeFromSuperview()
            }
        }
    }
}

// Add these extensions at the end of the file, just before the last curly brace

// Replace the existing extension for MessageCell with this one
extension MessageCell {
    private struct AssociatedKeys {
        static var reactionsEnabledKey = "reactionsEnabled"
    }
    
    // Add this property to MessageCell to control reaction button visibility
    var reactionsEnabled: Bool {
        get {
            // Get associated object or return default value
            return objc_getAssociatedObject(self, &AssociatedKeys.reactionsEnabledKey) as? Bool ?? true
        }
        set {
            // Store new value using associated object
            objc_setAssociatedObject(
                self,
                &AssociatedKeys.reactionsEnabledKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            // Update UI based on the new value
            updateReactionsVisibility()
        }
    }
    
    // Update the visibility of reaction buttons
    private func updateReactionsVisibility() {
        // Update any reaction buttons based on the enabled state
        reactionButton?.isHidden = !reactionsEnabled
    }
    
    // Add a property for the reaction button - you'll need to implement this
    private var reactionButton: UIButton? {
        // Return the actual reaction button from your view hierarchy
        return subviews.compactMap { $0 as? UIButton }.first(where: { $0.accessibilityIdentifier == "reactionButton" })
    }
}

// Add the uploadButtonEnabled property to MessageInputView class
extension MessageInputView {
    private struct AssociatedKeys {
        static var uploadButtonEnabledKey = "uploadButtonEnabled"
    }
    
    // Add this property to control upload button visibility
    var uploadButtonEnabled: Bool {
        get {
            // Return stored value or default
            return objc_getAssociatedObject(self, &AssociatedKeys.uploadButtonEnabledKey) as? Bool ?? true
        }
        set {
            // Store the value
            objc_setAssociatedObject(
                self,
                &AssociatedKeys.uploadButtonEnabledKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            // Update the upload button visibility
            uploadButton?.isHidden = !newValue
        }
    }
    
    // Optional upload button reference - implement as needed
    var uploadButton: UIButton? {
        // Return the actual upload button from your view hierarchy
        return subviews.compactMap { $0 as? UIButton }.first(where: { $0.accessibilityIdentifier == "uploadButton" })
    }
}

// MARK: - UITextViewDelegate (moved to extension)

// MARK: - MessageSkeletonView
class MessageSkeletonView: UIView {
    
    private let numberOfSkeletons = 9
    private let skeletonRowHeight: CGFloat = 60
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSkeletonView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSkeletonView()
    }
    
    private func setupSkeletonView() {
        backgroundColor = .bgDefaultPurple13
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])
        
        // Create skeleton rows
        for _ in 0..<numberOfSkeletons {
            let skeletonRow = createSkeletonRow()
            stackView.addArrangedSubview(skeletonRow)
        }
    }
    
    private func createSkeletonRow() -> UIView {
        let rowContainer = UIView()
        rowContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Avatar placeholder
        let avatarView = UIView()
        avatarView.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.8)
        avatarView.layer.cornerRadius = 20
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        rowContainer.addSubview(avatarView)
        
        // Content container
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        rowContainer.addSubview(contentStack)
        
        // Username placeholder
        let usernameView = UIView()
        usernameView.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.7)
        usernameView.layer.cornerRadius = 4
        usernameView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(usernameView)
        
        // Message content placeholder
        let messageView = UIView()
        messageView.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.6)
        messageView.layer.cornerRadius = 4
        messageView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(messageView)
        
        NSLayoutConstraint.activate([
            rowContainer.heightAnchor.constraint(equalToConstant: skeletonRowHeight),
            
            // Avatar constraints
            avatarView.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
            avatarView.topAnchor.constraint(equalTo: rowContainer.topAnchor, constant: 8),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            
            // Content stack constraints
            contentStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: rowContainer.topAnchor, constant: 8),
            
            // Username placeholder constraints
            usernameView.heightAnchor.constraint(equalToConstant: 16),
            usernameView.widthAnchor.constraint(equalToConstant: 120),
            
            // Message content placeholder constraints
            messageView.heightAnchor.constraint(equalToConstant: 20),
        ])
        
        return rowContainer
    }
}

// MARK: - Additional Memory Management
extension MessageableChannelViewController {
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        print("⚡ VIEW_DID_DISAPPEAR: User has completely left channel \(viewModel.channel.id) - performing FINAL instant cleanup")
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
        print("⚡ VIEW_DID_DISAPPEAR: Total final cleanup completed in \(String(format: "%.2f", finalCleanupDuration))ms")
        
        // Log final memory usage
        logMemoryUsage(prefix: "FINAL CLEANUP COMPLETE")
    }
    
    // NOTE: forceImmediateMemoryCleanup() moved to MessageableChannelViewController+MemoryManagement.swift
    // NOTE: performFinalInstantCleanup() moved to MessageableChannelViewController+MemoryManagement.swift
}

// MARK: - Scroll Position Preservation
extension MessageableChannelViewController {
    
    /// Reloads the table view while maintaining the user's scroll position using message IDs as anchors
    private func reloadTableViewMaintainingScrollPosition(messagesForDataSource: [String]) {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              !visibleIndexPaths.isEmpty else {
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
        if anchorMessageId == nil, let firstVisible = visibleIndexPaths.first, firstVisible.row < messagesForDataSource.count {
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
                let maxOffset = max(0, tableView.contentSize.height - tableView.bounds.height + tableView.contentInset.bottom)
                let clampedOffset = max(0, min(newContentOffsetY, maxOffset))
                
                tableView.setContentOffset(CGPoint(x: 0, y: clampedOffset), animated: false)
                // print("📍 SCROLL_PRESERVE: Restored position to anchor message at new index \(newIndex), offset: \(clampedOffset)")
            } else {
                // print("⚠️ SCROLL_PRESERVE: Could not find anchor message \(anchorId) in new data")
            }
        }
    }
}

// MARK: - Helper Functions
/// Generates a dynamic message link based on the current domain
private func generateMessageLink(serverId: String?, channelId: String, messageId: String, viewState: ViewState) async -> String {
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
           let host = url.host {
            webDomain = "https://\(host)"
        } else {
            webDomain = "https://app.revolt.chat" // Ultimate fallback
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

 
