import Foundation
import Combine
import SwiftUI
import Alamofire
import ULID
import Collections
import Sentry
@preconcurrency import Types
import UserNotifications
import KeychainAccess
import Darwin
import Network


@MainActor
public class ViewState: ObservableObject {
    var cancellables = Set<AnyCancellable>()
    static var shared: ViewState? = nil
    
#if os(iOS)
    static var application: UIApplication? = nil
#elseif os(macOS)
    static var application: NSApplication? = nil
#endif
    
    let defaultBaseURL: String = "https://peptide.chat/api"
    
    
    let keychain = Keychain(service: "chat.peptide.app")
    var http: HTTPClient
    var launchTransaction: (any Sentry.Span)?
    
    @Published var baseURL: String? = nil {
        didSet {
            if let baseURL {
                http.baseURL = baseURL
                DispatchQueue.global(qos: .background).async {
                    UserDefaults.standard.set(try! JSONEncoder().encode(baseURL), forKey: "baseURL")
                }
            }
        }
    }
    
    @Published var wsCurrentState : WsState = .connecting
    @Published var ws: WebSocketStream? = nil
    
    @Published var apiInfo: ApiInfo? = nil {
        didSet {
            let apiInfo = apiInfo
            DispatchQueue.global(qos: .background).async {
                UserDefaults.standard.set(try! JSONEncoder().encode(apiInfo), forKey: "apiInfo")
            }
        }
    }
    
    @Published var sessionToken: String? = nil {
        didSet {
            keychain["sessionToken"] = sessionToken
        }
    }
    @Published var users: [String: Types.User] {
        didSet {
            // MEMORY MANAGEMENT: Use debounced save (memory limits disabled for users)
            // Move JSON encoding off main thread to prevent app hanging
            // CRITICAL FIX: Capture value directly and perform encoding ONLY in the debounced work item.
            // This ensures we don't re-encode on every tiny change or for each user removal.
            let usersSnapshot = self.users
            debouncedSave(key: "users") {
                try? JSONEncoder().encode(usersSnapshot)
            }
//            saveUsersToSharedContainer()
        }
    }
    
    func updateRelationship(for userId: String, with newRelationship: Relation) {
        if var user = users[userId] {
            user.relationship = newRelationship
            users[userId] = user  // Update the dictionary
            
            // The didSet will trigger automatically and save to UserDefaults
        }
    }
    
    @Published var servers: OrderedDictionary<String, Server> {
        didSet {
            // DISABLED: Don't save servers to UserDefaults to force refresh from backend
            // let servers = self.servers
            // Task.detached(priority: .background) { [weak self] in
            //     guard let self = self else { return }
            //     if let data = try? JSONEncoder().encode(servers) {
            //         await MainActor.run {
            //             self.debouncedSave(key: "servers", data: data)
            //         }
            //     }
            // }
        }
    }
    @Published var channels: [String: Channel] {
        didSet {
            // DISABLED: Don't save channels to UserDefaults to force refresh from backend
            // let channels = self.channels
            // Task.detached(priority: .background) { [weak self] in
            //     guard let self = self else { return }
            //     if let data = try? JSONEncoder().encode(channels) {
            //         await MainActor.run {
            //             self.debouncedSave(key: "channels", data: data)
            //         }
            //     }
            // }
        }
    }
    @Published var messages: [String: Message] {
        didSet {
            // MEMORY MANAGEMENT: Don't persist messages to UserDefaults - they're loaded from server
            // This prevents memory spikes from encoding large dictionaries
            Task { @MainActor in
                // If we have messages and loading was active, turn off loading
                if self.isLoadingChannelMessages && !messages.isEmpty {
                    self.setChannelLoadingState(isLoading: false)
                }
                self.enforceMemoryLimits()
            }
        }
    }
    @Published var channelMessages: [String: [String]] {
        didSet {
            // MEMORY MANAGEMENT: Use debounced save for channelMessages
            // Move JSON encoding off main thread to prevent app hanging
            // CRITICAL FIX: Capture value directly and encode only once per debounce window.
            let channelMessagesSnapshot = self.channelMessages
            debouncedSave(key: "channelMessages") {
                try? JSONEncoder().encode(channelMessagesSnapshot)
            }
            
            // Check if we should turn off loading state
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isLoadingChannelMessages {
                    if case .channel(let channelId) = self.currentChannel {
                        let hasMessages = (self.channelMessages[channelId]?.count ?? 0) > 0
                        if hasMessages {
                            self.setChannelLoadingState(isLoading: false)
                        }
                    }
                }
            }
        }
    }
    @Published var members: [String: [String: Member]] {
        didSet {
            // DISABLED: Don't save members to UserDefaults to force refresh from backend
            // let members = self.members
            // Task.detached(priority: .background) { [weak self] in
            //     guard let self = self else { return }
            //     if let data = try? JSONEncoder().encode(members) {
            //         await MainActor.run {
            //             self.debouncedSave(key: "members", data: data)
            //         }
            //     }
            // }
        }
    }
    @Published var dms: [Channel] {
        didSet {
            // DISABLED: Don't save DMs to UserDefaults to force refresh from backend
            // let dms = self.dms
            // Task.detached(priority: .background) { [weak self] in
            //     guard let self = self else { return }
            //     if let data = try? JSONEncoder().encode(dms) {
            //         await MainActor.run {
            //             self.debouncedSave(key: "dms", data: data)
            //         }
            //     }
            // }
        }
    }
    
    // LAZY LOADING: DM Management
    @Published var allDmChannelIds: [String] = [] // All DM channel IDs in order
    @Published var loadedDmBatches: Set<Int> = [] // Track which batches are loaded
    let dmBatchSize = 15 // Load 15 DMs per batch
    internal var isLoadingDmBatch = false
    internal var isDmListInitialized = false // Track if DM list has been initialized
    
    // SIMPLE LAZY LOADING: Just load more as needed, no complex virtual scrolling
    internal let maxLoadedBatches = 50 // Maximum 50 batches (750 DMs) with increased memory limits
    @Published var emojis: [String: Emoji] {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            // CRITICAL FIX: Capture value directly and encode only inside debounced work item.
            let emojisSnapshot = self.emojis
            debouncedSave(key: "emojis") {
                try? JSONEncoder().encode(emojisSnapshot)
            }
        }
    }
    
    @Published var currentUser: Types.User? = nil {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            // CRITICAL FIX: Capture value directly and encode only inside debounced work item.
            let currentUserSnapshot = self.currentUser
            debouncedSave(key: "currentUser") {
                try? JSONEncoder().encode(currentUserSnapshot)
            }
        }
    }
    
    @Published var state: ConnectionState = .connecting
    @Published var forceMainScreen: Bool = false
    @Published var queuedMessages: [String: [QueuedMessage]] = [:]
    @Published var loadingMessages: Set<String> = Set()
    @Published var currentlyTyping: [String: OrderedSet<String>] = [:]
    @Published var isOnboarding: Bool = false
    @Published var unreads: [String: Unread] = [:] {
        didSet {
            unreadsVersion = UUID()
            // Update app badge count when unreads change
            updateAppBadgeCount()
        }
    }
    
    // MARK: - Mark Unread Protection
    // Temporarily disable automatic acknowledgment after marking as unread
    var isAutoAckDisabled = false
    var autoAckDisableTime: Date?
    private let autoAckDisableDuration: TimeInterval = 30.0 // Disable for 30 seconds after mark unread
    
    /// Temporarily disable automatic acknowledgment after marking as unread
    func disableAutoAcknowledgment() {
        print("🚫 ViewState: Disabling auto-acknowledgment for \(autoAckDisableDuration) seconds")
        isAutoAckDisabled = true
        autoAckDisableTime = Date()
    }
    
    /// Check if auto-acknowledgment should be disabled
    func shouldDisableAutoAck() -> Bool {
        guard let disableTime = autoAckDisableTime else {
            return false
        }
        
        let now = Date()
        if now.timeIntervalSince(disableTime) < autoAckDisableDuration {
            return true
        } else {
            // Disable period has expired, re-enable auto-ack
            print("✅ ViewState: Auto-acknowledgment re-enabled after disable period")
            isAutoAckDisabled = false
            autoAckDisableTime = nil
            return false
        }
    }
    
    // MEMORY MANAGEMENT: Add debouncing for UserDefaults saves
    internal var saveWorkItems: [String: DispatchWorkItem] = [:]
    private let saveDebounceInterval: TimeInterval = 2.0 // Save after 2 seconds of no changes
    private let cleanupTriggeredAt = 800 // Start cleanup when 80% full (legacy, not used)
    internal let maxChannelsInMemory = 2000 // Maximum channels to keep in memory (increased to load all servers)
    
    @Published var unreadsVersion: UUID = UUID()
    @Published var currentUserSheet: UserMaybeMember? = nil
    @Published var currentUserOptionsSheet: UserMaybeMember? = nil
    @Published var atTopOfChannel: Set<String> = []
    
    @Published var alert : (String?,ImageResource?, Color?) = (nil,nil, nil)
    
    @Published var serverMembersCount : String? = nil
    
    @Published var mentionedUser : String? = nil
    
    
    @Published var currentSelection: MainSelection {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            // CRITICAL FIX: Capture value directly and encode only inside debounced work item.
            let currentSelectionSnapshot = self.currentSelection
            debouncedSave(key: "currentSelection") {
                try? JSONEncoder().encode(currentSelectionSnapshot)
            }
        }
    }
    
    @Published var currentChannel: ChannelSelection {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            // CRITICAL FIX: Capture value directly and encode only inside debounced work item.
            let currentChannelSnapshot = self.currentChannel
            debouncedSave(key: "currentChannel") {
                try? JSONEncoder().encode(currentChannelSnapshot)
            }
            
            // MEMORY MANAGEMENT: Clear messages from previous channel when switching channels
            handleChannelChange(from: previousChannelId, to: currentChannel)
        }
    }
    
    @Published var currentSessionId: String? = nil {
        didSet {
            UserDefaults.standard.set(currentSessionId, forKey: "currentSessionId")
        }
    }
    @Published var theme: Theme {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            // CRITICAL FIX: Capture value directly and encode only inside debounced work item.
            let themeSnapshot = self.theme
            debouncedSave(key: "theme") {
                try? JSONEncoder().encode(themeSnapshot)
            }
        }
    }
    
    @Published var currentLocale: Locale? {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            // CRITICAL FIX: Capture value directly and encode only inside debounced work item.
            let currentLocaleSnapshot = self.currentLocale
            debouncedSave(key: "locale") {
                try? JSONEncoder().encode(currentLocaleSnapshot)
            }
        }
    }
    
    @Published var path: [NavigationDestination] {
        didSet {
            // MEMORY MANAGEMENT: Clear messages when leaving channel view
            handlePathChange(oldPath: oldValue, newPath: path)
        }
    }
    
    // Add property to store target message ID when navigating to a channel
    @Published var currentTargetMessageId: String? = nil {
        didSet {
            if currentTargetMessageId != oldValue {
                // print("🎯 ViewState: currentTargetMessageId changed from \(oldValue ?? "nil") to \(currentTargetMessageId ?? "nil")")
            }
        }
    }
    
    @Published var launchNotificationChannelId: String? = nil
    @Published var launchNotificationServerId: String? = nil
    @Published var launchNotificationHandled: Bool = false
    
    // Track the server context when accepting an invite
    @Published var lastInviteServerContext: String? = nil
    
    // MEMORY MANAGEMENT: Track previous channel for cleanup
    internal var previousChannelId: String? = nil
    
    // Loading state for channels when messages are being fetched
    @Published var isLoadingChannelMessages: Bool = false
    
    // CRITICAL FIX: Flag to prevent memory cleanup during older message loading
    private var isLoadingOlderMessages: Bool = false
    
    var userSettingsStore: UserSettingsData
    
    // MEMORY MANAGEMENT: Configuration for aggressive cleanup
    internal let maxMessagesInMemory = 7000 // Maximum messages to keep in memory
    internal let maxUsersInMemory = 2000 // Increased to handle 300+ messages with users
    internal let maxChannelMessages = 800 // Maximum messages per channel (reduced for better memory management)
    private let maxServersInMemory = 50 // Maximum servers to keep in memory
    
    // PRELOADING CONTROL: Configuration for automatic message preloading
    /// Set to false to disable all automatic message preloading when entering servers/channels
    internal let enableAutomaticPreloading = false // DISABLED: No automatic preloading
    
    // MEMORY MANAGEMENT: Helper methods
    /// Debounced save helper that defers heavy JSON encoding to the background queue
    /// and ensures only the *latest* snapshot for a given key is encoded.
    private func debouncedSave(key: String, makeData: @escaping () -> Data?) {
        // Cancel any existing save operation for this key
        saveWorkItems[key]?.cancel()
        
        // Create a new work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let data = makeData() else { return }
            
            UserDefaults.standard.set(data, forKey: key)
            DispatchQueue.main.async {
                self?.saveWorkItems.removeValue(forKey: key)
            }
        }
        
        // Store and schedule the work item
        saveWorkItems[key] = workItem
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }
    
    /// Force immediate save of users data without debouncing
    /// Used when app is terminating to ensure data is persisted
    public func forceSaveUsers() {
        // Cancel any pending save for users
        saveWorkItems["users"]?.cancel()
        saveWorkItems.removeValue(forKey: "users")
        
        // Immediately encode and save users data
        if let data = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(data, forKey: "users")
            UserDefaults.standard.synchronize() // Force synchronization
            print("💾 Forced save of users data completed")
        }
    }
    
    
    // Clear messages when leaving a channel to free memory, keeping only last 100 messages
    @MainActor
    func clearChannelMessages(channelId: String) {
        // print("🧠 MEMORY: Starting channel cleanup for: \(channelId)")
        
        // Get current channel messages
        guard let currentChannelMessages = channelMessages[channelId] else {
            // print("🧠 MEMORY: No messages found for channel: \(channelId)")
            return
        }
        
        let originalMessageCount = currentChannelMessages.count
        
        // Keep only last 100 messages in channel
        let maxMessagesToKeep = 100
        if currentChannelMessages.count > maxMessagesToKeep {
            let messagesToKeep = Array(currentChannelMessages.suffix(maxMessagesToKeep))
            let messagesToRemove = Array(currentChannelMessages.prefix(currentChannelMessages.count - maxMessagesToKeep))
            
            // Update channel message list to keep only last 100
            channelMessages[channelId] = messagesToKeep
            
            // Remove the older messages from global messages dictionary
            for messageId in messagesToRemove {
                messages.removeValue(forKey: messageId)
            }
            
            // print("🧠 MEMORY: Channel \(channelId) - kept last \(messagesToKeep.count) messages, removed \(messagesToRemove.count) older messages")
            // print("🧠 MEMORY: Total messages in memory: \(messages.count)")
        } else {
            // print("🧠 MEMORY: Channel \(channelId) has \(originalMessageCount) messages (≤100), keeping all")
        }
        
        // Clean up orphaned messages (messages that don't belong to any channel anymore)
        cleanupOrphanedMessages()
        
        // print("🧠 MEMORY: Channel cleanup completed for: \(channelId)")
    }
    
    
    // Clean all channel messages to keep only last 100 per channel
    @MainActor
    func cleanupAllChannelMessages() {
        // print("🧠 MEMORY: Starting cleanup of all channel messages (keeping last 100 per channel)")
        
        let maxMessagesToKeep = 100
        var totalMessagesRemoved = 0
        
        for (channelId, messageIds) in channelMessages {
            if messageIds.count > maxMessagesToKeep {
                let messagesToKeep = Array(messageIds.suffix(maxMessagesToKeep))
                let messagesToRemove = Array(messageIds.prefix(messageIds.count - maxMessagesToKeep))
                
                // Update channel message list
                channelMessages[channelId] = messagesToKeep
                
                // Remove older messages from global messages dictionary
                for messageId in messagesToRemove {
                    messages.removeValue(forKey: messageId)
                }
                
                totalMessagesRemoved += messagesToRemove.count
                // print("🧠 MEMORY: Channel \(channelId) - kept \(messagesToKeep.count), removed \(messagesToRemove.count)")
            }
        }
        
        // Clean up any orphaned messages
        cleanupOrphanedMessages()
        
        // print("🧠 MEMORY: Cleanup completed - removed \(totalMessagesRemoved) messages total")
        // print("🧠 MEMORY: Final message count: \(messages.count)")
    }
    
    // Set loading state when entering a channel that needs message loading
    @MainActor
    func setChannelLoadingState(isLoading: Bool) {
        isLoadingChannelMessages = isLoading
        // print("🧠 LOADING: Channel loading state changed to: \(isLoading)")
    }
    
    static func decodeUserDefaults<T: Decodable>(forKey key: String, withDecoder decoder: JSONDecoder) throws -> T? {
        if let value = UserDefaults.standard.data(forKey: key) {
            // print("📱 DECODE: Found data for key '\(key)' - size: \(value.count) bytes")
            do {
                let result = try decoder.decode(T.self, from: value)
                // print("📱 DECODE: Successfully decoded key '\(key)'")
                return result
            } catch {
                // print("❌ DECODE: Failed to decode key '\(key)' - error: \(error)")
                throw error
            }
        } else {
            // print("📱 DECODE: No data found for key '\(key)' in UserDefaults")
            return nil
        }
    }
    
    static func decodeUserDefaults<T: Decodable>(forKey key: String, withDecoder decoder: JSONDecoder, defaultingTo def: T) -> T {
        do {
            if let result: T = try decodeUserDefaults(forKey: key, withDecoder: decoder) {
                // print("📱 DECODE: Using loaded data for key '\(key)'")
                return result
            } else {
                // print("📱 DECODE: Using default value for key '\(key)'")
                return def
            }
        } catch {
            // print("❌ DECODE: Error decoding key '\(key)', using default - error: \(error)")
            return def
        }
    }
    
    var baseEmojis : [EmojiGroup] = []
    
    init() {
        // Create launch transaction only if Sentry is enabled
        if SentrySDK.isEnabled {
            launchTransaction = SentrySDK.startTransaction(name: "launch", operation: "launch")
        } else {
            launchTransaction = nil
        }
        let decoder = JSONDecoder()
        
        // Initialize HTTPClient with self reference for immediate state updates
        self.http = HTTPClient(token: nil, baseURL: "https://peptide.chat/api", viewState: nil)
        
        self.apiInfo = ViewState.decodeUserDefaults(forKey: "apiInfo", withDecoder: decoder, defaultingTo: nil)
        self.baseURL = ViewState.decodeUserDefaults(forKey: "baseURL", withDecoder: decoder, defaultingTo: defaultBaseURL)
        
        self.userSettingsStore = UserSettingsData.maybeRead(viewState: nil, isLoginUser: keychain["sessionToken"] != nil)
        self.sessionToken = keychain["sessionToken"]
        self.userSettingsStore = UserSettingsData.maybeRead(viewState: nil, isLoginUser: true)
        

        // CRITICAL DEBUG: Add logging for data loading from UserDefaults
        // print("📱 INIT: Loading data from UserDefaults...")
        
        self.users = ViewState.decodeUserDefaults(forKey: "users", withDecoder: decoder, defaultingTo: [:])
        // Force refresh servers and channels from backend instead of using cached data
        /*self.servers = [:]*/ // ViewState.decodeUserDefaults(forKey: "servers", withDecoder: decoder, defaultingTo: [:])
        let cachedServers = ViewState.loadServersCacheSync()
        
        if !cachedServers.isEmpty {
            self.servers = cachedServers
        } else {
            self.servers = [:]
        }
        
        self.channels = [:] // ViewState.decodeUserDefaults(forKey: "channels", withDecoder: decoder, defaultingTo: [:])
        /*self.messages = ViewState.decodeUserDefaults(forKey: "messages", withDecoder: decoder, defaultingTo: [:])
         self.channelMessages = ViewState.decodeUserDefaults(forKey: "channelMessages", withDecoder: decoder, defaultingTo: [:])*/
        self.messages = [:]
        self.channelMessages = [:]
        // Force refresh members from backend
        self.members = [:] // ViewState.decodeUserDefaults(forKey: "members", withDecoder: decoder, defaultingTo: [:])
        // Force refresh DMs from backend
        self.dms = [] // ViewState.decodeUserDefaults(forKey: "dms", withDecoder: decoder, defaultingTo: [])
        self.emojis = ViewState.decodeUserDefaults(forKey: "emojis", withDecoder: decoder, defaultingTo: [:])
        
        //self.currentSelection = ViewState.decodeUserDefaults(forKey: "currentSelection", withDecoder: decoder, defaultingTo: .dms)
        //self.currentChannel = ViewState.decodeUserDefaults(forKey: "currentChannel", withDecoder: decoder, defaultingTo: .home)
        
        self.currentSelection = .discover
        self.currentChannel = .home
        
        self.currentLocale = ViewState.decodeUserDefaults(forKey: "locale", withDecoder: decoder, defaultingTo: nil)
        
        self.currentSessionId = UserDefaults.standard.string(forKey: "currentSessionId")
        
        self.theme = ViewState.decodeUserDefaults(forKey: "theme", withDecoder: decoder, defaultingTo: .dark)
        
        self.currentUser = ViewState.decodeUserDefaults(forKey: "currentUser", withDecoder: decoder, defaultingTo: nil)
        
        /*if let value = UserDefaults.standard.data(forKey: "path"), let path = try? decoder.decode(NavigationPath.CodableRepresentation.self, from: value) {
         self.path = NavigationPath(path)
         } else {
         self.path = NavigationPath()
         }*/
        
        self.path = []
        if self.currentUser != nil, self.apiInfo != nil {
            self.forceMainScreen = true
        }

        self.users["00000000000000000000000000"] = User(id: "00000000000000000000000000", username: "Revolt", discriminator: "0000")
        
        self.http.token = self.sessionToken
        
       
        // Set viewState reference after initialization
        self.http.viewState = self
        
        self.userSettingsStore.viewState = self // this is a cursed workaround
        ViewState.shared = self
        
        // Apply server ordering after all properties are initialized
        if !self.servers.isEmpty && !self.userSettingsStore.cache.orderSettings.servers.isEmpty {
            self.applyServerOrdering()
        }
        
        self.baseEmojis = loadEmojis()
        
        // Load any pending notification token
        self.loadPendingNotificationToken()
        
        // MEMORY MANAGEMENT: Start periodic memory cleanup
        startPeriodicMemoryCleanup()
        
        // Log loaded data counts after all initialization is complete
        // print("📱 INIT: Loaded \(users.count) users from UserDefaults")
        // print("📱 INIT: Loaded \(servers.count) servers from UserDefaults")
        // print("📱 INIT: Loaded \(channels.count) channels from UserDefaults")
        // print("📱 INIT: ViewState initialization completed")
        
        // PRELOAD: Start preloading important channels after initialization
        Task {
            await preloadImportantChannels()
        }
        
        // PRELOAD: Listen for WebSocket reconnection to trigger preload
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WebSocketReconnected"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.preloadImportantChannels()
            }
        }
        
        // CLEANUP: Clean up stale unreads on startup
        // This ensures badge count is accurate even if channels were deleted while app was closed
        Task {
            await MainActor.run { [weak self] in
                self?.cleanupStaleUnreads()
            }
        }
        self.setupInternetObservation()
    }
    
    // MARK: - Channel Preloading
    
    /// Set to track which channels have been preloaded to avoid duplicates
    var preloadedChannels: Set<String> = Set()
    
    
    /// Public method to manually trigger preload for important channels
    @MainActor
    public func triggerPreloadImportantChannels() async {
        await preloadImportantChannels()
    }
    
    
    /// Public method to preload multiple channels by IDs
    @MainActor
    public func preloadChannels(channelIds: [String]) async {
        for channelId in channelIds {
            await preloadChannel(channelId: channelId)
        }
    }
    
    /// Preloads messages for a specific channel
    @MainActor
    internal func preloadChannel(channelId: String) async {
        // Check if channel has already been preloaded
        if preloadedChannels.contains(channelId) {
            print("🚀 PRELOAD: Channel \(channelId) has already been preloaded, skipping")
            return
        }
        
        // Check if channel exists in our channels dictionary
        guard let channel = channels[channelId] else {
            print("🚀 PRELOAD: Channel \(channelId) not found in channels dictionary")
            return
        }
        
        // Check if we already have messages for this channel
        if let existingMessages = channelMessages[channelId], !existingMessages.isEmpty {
            print("🚀 PRELOAD: Channel \(channelId) already has \(existingMessages.count) messages, skipping preload")
            preloadedChannels.insert(channelId) // Mark as preloaded since it has messages
            return
        }
        
        print("🚀 PRELOAD: Loading messages for channel: \(channelId)")
        
        do {
            // Get server ID if this is a server channel
            let serverId = channel.server
            
            // SMART LIMIT: Use 10 for specific channel in specific server, 50 for others
            let messageLimit = (channelId == "01J7QTT66242A7Q26A2FH5TD48" && serverId == "01J544PT4T3WQBVBSDK3TBFZW7") ? 10 : 50
            
            // Fetch messages for this channel
            let result = try await http.fetchHistory(
                channel: channelId,
                limit: messageLimit, // Smart limit based on channel
                sort: "Latest",
                server: serverId,
                include_users: true
            ).get()
            
            print("🚀 PRELOAD: Successfully loaded \(result.messages.count) messages for channel \(channelId)")
            
            // Process users from the response
            for user in result.users {
                users[user.id] = user
            }
            
            // Process members if present
            if let members = result.members {
                for member in members {
                    self.members[member.id.server, default: [:]][member.id.user] = member
                }
            }
            
            // Process messages
            var messageIds: [String] = []
            for message in result.messages {
                messages[message.id] = message
                messageIds.append(message.id)
            }
            
            // Sort messages by creation date (oldest first)
            let sortedIds = messageIds.sorted { id1, id2 in
                let date1 = createdAt(id: id1)
                let date2 = createdAt(id: id2)
                return date1 < date2
            }
            
            // Store sorted message IDs in channelMessages
            channelMessages[channelId] = sortedIds
            
            print("🚀 PRELOAD: Successfully stored \(sortedIds.count) messages for channel \(channelId) in memory")
            
            // Mark channel as preloaded
            preloadedChannels.insert(channelId)
            
        } catch {
            print("🚀 PRELOAD: Failed to load messages for channel \(channelId): \(error)")
        }
    }
    
    // MEMORY MANAGEMENT: Periodic cleanup timer
    internal var memoryCleanupTimer: Timer?
    internal var memoryMonitorTimer: Timer?

    
    // MEMORY MONITORING: Track memory usage
    internal func startMemoryMonitoring() {
        memoryMonitorTimer?.invalidate()
        
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let memoryUsage = self.getCurrentMemoryUsage()
            // print("📊 MEMORY MONITOR: Current usage: \(String(format: "%.2f", memoryUsage)) MB")
            // print("   - Messages: \(self.messages.count)")
            // print("   - Users: \(self.users.count)")
            // print("   - Channels: \(self.channels.count)")
            // print("   - Servers: \(self.servers.count)")
            // print("   - Channel messages lists: \(self.channelMessages.count)")
            
            // COMPLETE PROTECTION for DM View - NO CLEANUP at all
            if currentSelection == .dms {
                // print("🔄 VIRTUAL_DM: DM view active - ALL automatic memory management DISABLED")
                return // Skip all cleanup when in DM view
            }
            
            // CRITICAL FIX: Skip cleanup when loading older messages
            if isLoadingOlderMessages {
                // print("🔄 LOADING_PROTECTION: Loading older messages - skipping cleanup")
                return
            }
            
            // DISABLED: No immediate user cleanup to prevent black messages
            if users.count > maxUsersInMemory {
                // print("⚠️ MEMORY WARNING: \(users.count) users exceed limit of \(maxUsersInMemory), but cleanup is disabled")
                // Don't call smartUserCleanup() to prevent black messages
            }
            
            // Warning if memory usage is high (only for non-DM views)
            if memoryUsage > 1500 { // Increased threshold to 1.5GB for better performance
                // print("⚠️ MEMORY WARNING: High memory usage detected!")
                
                // Force immediate aggressive cleanup
                enforceMemoryLimits()
                smartUserCleanup()
                smartChannelCleanup()
            }
        }
    }
    
    func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
        } else {
            return 0
        }
    }
    
    // DISABLED: Add proactive cleanup when adding new messages/users
    @MainActor
    func checkAndCleanupIfNeeded() {
        // CRITICAL FIX: Disable all proactive cleanup to prevent black messages
        // print("🧠 MEMORY: Proactive cleanup DISABLED to prevent black messages")
        
        // Only log warnings if approaching limits
        if messages.count > Int(Double(maxMessagesInMemory) * 0.9) {
            // print("⚠️ MEMORY WARNING: Approaching message limit (\(messages.count)/\(maxMessagesInMemory))")
        }
        
        if users.count > Int(Double(maxUsersInMemory) * 0.9) {
            // print("⚠️ MEMORY WARNING: Approaching user limit (\(users.count)/\(maxUsersInMemory))")
        }
        
        return // Exit early, no cleanup
    }
    
    // Helper function to extract timestamp from ULID
    private func createdAt(id: String) -> Date {
        // ULID has timestamp in first 10 characters (48 bits as base32)
        let timestampPart = String(id.prefix(10))
        
        // Convert base32 to timestamp
        let base32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
        var timestamp: UInt64 = 0
        
        for char in timestampPart {
            if let index = base32.firstIndex(of: char) {
                timestamp = timestamp * 32 + UInt64(base32.distance(from: base32.startIndex, to: index))
            }
        }
        
        // Convert milliseconds to Date
        return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }
    
    
    /// INSTANT cleanup of unused users - NO DELAYS
    @MainActor
    internal func cleanupUnusedUsersInstant(excludingChannelId: String) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var usersToKeep = Set<String>()
        
        // Always keep current user
        if let currentUserId = currentUser?.id {
            usersToKeep.insert(currentUserId)
        }
        
        // Keep users from all active channels (except the one we're leaving)
        for (otherChannelId, messageIds) in channelMessages {
            if otherChannelId == excludingChannelId { continue }
            
            // Keep users from channel recipients (for DMs)
            if let channel = channels[otherChannelId] {
                usersToKeep.formUnion(channel.recipients)
            }
            
            // Keep message authors and mentioned users
            for messageId in messageIds {
                if let message = messages[messageId] {
                    usersToKeep.insert(message.author)
                    if let mentions = message.mentions {
                        usersToKeep.formUnion(mentions)
                    }
                }
            }
        }
        
        // Keep users from servers (owners and members)
        for server in servers.values {
            usersToKeep.insert(server.owner)
            if let serverMembers = members[server.id] {
                usersToKeep.formUnion(serverMembers.keys)
            }
        }
        
        // Keep users from DM list
        for dm in dms {
            usersToKeep.formUnion(dm.recipients)
        }
        
        // IMMEDIATE: Remove users that are no longer needed
        let initialUserCount = users.count
        let usersToRemove = users.keys.filter { userId in
            !usersToKeep.contains(userId) && userId != currentUser?.id
        }
        
        for userId in usersToRemove {
            users.removeValue(forKey: userId)
            
            // Also remove from members if they exist
            for serverId in members.keys {
                members[serverId]?.removeValue(forKey: userId)
            }
        }
        
        let finalUserCount = users.count
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        
        print("⚡ USER_INSTANT_CLEANUP: Removed \(usersToRemove.count) users in \(String(format: "%.2f", duration))ms (\(initialUserCount) -> \(finalUserCount))")
    }
    
    
    func setBaseUrlToHttp() {
        http.baseURL = baseURL ?? defaultBaseURL
    }
    
    
    
    func applySystemScheme(theme: ColorScheme, followSystem: Bool = false) -> Self {
        var theme: Theme = theme == .dark ? .dark : .light
        theme.shouldFollowiOSTheme = followSystem
        self.theme = theme
        return self
    }
    
    class func preview() -> ViewState {
        let this = ViewState()
        this.state = .connected
        this.currentUser = User(id: "0", username: "Zomatree", discriminator: "0000", badges: Int.max, status: Status(text: "hello world", presence: .Busy), relationship: .User, profile: Profile(content: "hello world"))
        this.users["0"] = this.currentUser!
        this.users["1"] = User(id: "1", username: "Other Person", discriminator: "0001", relationship: .Blocked, profile: Profile(content: "Balls"))
        
        
        
        let adminPermissions = Overwrite(
            a: [.manageServer, .manageRole, .banMembers, .kickMembers, .manageMessages],
            d: [.video]
        )
        
        let moderatorPermissions = Overwrite(
            a: [.manageMessages, .kickMembers, .assignRoles],
            d: [.banMembers]
        )
        
        let memberPermissions = Overwrite(
            a: [.viewChannel, .sendMessages, .react],
            d: [.manageServer, .manageRole, .kickMembers]
        )
        
        
        
        let adminRole = Role(
            name: "Administrator",
            permissions: adminPermissions,
            colour: "#FF0000",
            hoist: true,
            rank: 1
        )
        
        let moderatorRole = Role(
            name: "Moderator",
            permissions: moderatorPermissions,
            colour: "#00FF00",
            hoist: true,
            rank: 2
        )
        
        let memberRole = Role(
            name: "Member",
            permissions: memberPermissions,
            colour: "#0000FF",
            hoist: false,
            rank: 3
        )
        
        
        this.servers["0"] = Server(id: "0", owner: "0", name: "Testing Server", channels: ["0"], default_permissions: Permissions.all, categories: [Types.Category(id: "0", title: "Channels", channels: ["0", "1"]), Types.Category(id: "1", title: "Channelsssssss", channels: [])], roles: [
            "admin": adminRole,
            "moderator": moderatorRole,
            "member": memberRole
        ])
        
        this.servers["1"] = Server(id: "1", owner: "0", name: "Seting Server", channels: ["0"], default_permissions: Permissions.all, categories: [Types.Category(id: "0", title: "Channels", channels: ["0", "1"])])
        
        this.channels["0"] = .text_channel(TextChannel(id: "0", server: "0", name: "General"))
        this.channels["1"] = .voice_channel(VoiceChannel(id: "1", server: "0", name: "Voice General"))
        this.channels["2"] = .saved_messages(SavedMessages(id: "2", user: "0"))
        this.channels["3"] = .dm_channel(DMChannel(id: "3", active: true, recipients: ["0", "1"]))
        this.channels["4"] = .group_dm_channel(.init(id: "4", recipients: ["1", "2"], name: "Group DM", owner: "3"))
        
        
        this.messages["01HD4VQY398JNRJY60JDY2QHA5"] = Message(id: "01HD4VQY398JNRJY60JDY2QHA5", content: String(repeating: "HelloWorld", count: 1), author: "0", channel: "0", mentions: ["0"])
        this.messages["01HDEX6M2E3SHY8AC2S6B9SEAW"] = Message(id: "01HDEX6M2E3SHY8AC2S6B9SEAW", content: "reply", author: "0", channel: "0", replies: ["01HD4VQY398JNRJY60JDY2QHA5"])
        this.messages["01HZ3CFEG10WH52YVXG34WZ9EM"] = Message(id: "01HZ3CFEG10WH52YVXG34WZ9EM", content: "Followup", author: "0", channel: "0")
        this.channelMessages["0"] = ["01HD4VQY398JNRJY60JDY2QHA5", "01HDEX6M2E3SHY8AC2S6B9SEAW", "01HZ3CFEG10WH52YVXG34WZ9EM"]
        this.members["0"] = ["0": Member(id: MemberId(server: "0", user: "0"), joined_at: "")]
        this.emojis = ["0": Emoji(id: "01GX773A8JPQ0VP64NWGEBMQ1E", parent: .server(EmojiParentServer(id: "0")), creator_id: "0", name: "balls")]
        this.currentSelection = /*.server("0")*/ .dms
        this.currentChannel = .channel("0")
        this.dms.append(contentsOf: [this.channels["2"]!, this.channels["3"]!])
        
        for i in (1...2) {
            this.users["\(i)"] = User(id: "\(i)", username: "\(i)", discriminator: "\(i)\(i)\(i)\(i)", relationship: .Friend)
        }
        
        this.currentlyTyping["0"] = ["0", "1", "2", "3", "4"]
        
        this.apiInfo = ApiInfo(revolt: "0.6.6", features: ApiFeatures(captcha: CaptchaFeature(enabled: true, key: "3daae85e-09ab-4ff6-9f24-e8f4f335e433"), email: true, invite_only: false, autumn: RevoltFeature(enabled: true, url: "https://autumn.revolt.chat"), january: RevoltFeature(enabled: true, url: "https://jan.revolt.chat"), voso: VortexFeature(enabled: true, url: "https://vortex.revolt.chat", ws: "wss://vortex.revolt.chat")), ws: "wss://ws.revolt.chat", app: "https://app.revolt.chat", vapid: "BJto1I_OZi8hOkMfQNQJfod2osWBqcOO7eEOqFMvCfqNhqgxqOr7URnxYKTR4N6sR3sTPywfHpEsPXhrU9zfZgg=")
        
        // Set viewState reference for immediate state updates
        this.http.viewState = this
        
        return this
    }
    
    func signInWithVerify(code: String, email: String, password: String) async -> Bool {
        do {
            _ = try await self.http.createAccount_VerificationCode(code: code).get()
        } catch {
            return false
        }
        
        await signIn(email: email, password: password, callback: {a in print(String(describing: a))})
        // awful workaround for the verification endpoint returning invalid session tokens
        return true
    }
    
    func promptForNotifications() async {
        let notificationsGranted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .providesAppNotificationSettings])
        if notificationsGranted != nil && notificationsGranted! {
            ViewState.application?.registerForRemoteNotifications()
            self.userSettingsStore.store.notifications.rejectedRemoteNotifications = false
        } else {
            self.userSettingsStore.store.notifications.rejectedRemoteNotifications = true
        }
        self.userSettingsStore.writeStoreToFile()
    }
    
    func formatUrl(with: File) -> String {
        
        if case .video(_) = with.metadata {
            return "\(apiInfo!.features.autumn.url)/\(with.tag)/\(with.id)/\(with.filename)"
        } else {
            return "\(apiInfo!.features.autumn.url)/\(with.tag)/\(with.id)"
        }
        
    }
    
    func formatUrl(fromEmoji emojiId: String) -> String {
        "\(apiInfo!.features.autumn.url)/emojis/\(emojiId)"
    }
    
    func formatUrl(fromId id: String, withTag tag: String) -> String {
        "\(apiInfo!.features.autumn.url)/\(tag)/\(id)"
    }
    
    func backgroundWsTask() async {
        if ws != nil {
            // If ws already exists, stop it first to prevent duplicates
            ws?.stop()
            ws = nil
        }
        
        guard let token = sessionToken else {
            state = .signedOut
            return
        }
        
        let fetchApiInfoSpan = launchTransaction?.startChild(operation: "fetchApiInfo")
        
        do {
            let apiInfo = try await self.http.fetchApiInfo().get()
            self.http.apiInfo = apiInfo
            self.apiInfo = apiInfo
        } catch {
            // DISABLED: SentrySDK.capture(error: error) - was causing timeout errors
            // print("Error fetching API info: \(error)")
            state = .connecting
            fetchApiInfoSpan?.finish()
            return
        }
        
        fetchApiInfoSpan?.finish()
        
        let ws = WebSocketStream(url: apiInfo!.ws,
                                 token: token,
                                 onChangeCurrentState: { [weak self] state in
            Task {@MainActor in
                self?.wsCurrentState = state
                
                // CRITICAL FIX: If disconnected while in DM list, try to reconnect
                if state == .disconnected && self?.currentSelection == .dms {
                    // print("🔌 WebSocket disconnected while in DM list - will reconnect")
                }
            }
        },
                                 onEvent: { [weak self] event in
            await self?.onEvent(event)
        })
        self.ws = ws
    }
    
    /// Temporarily suspends WebSocket connection to reduce network conflicts when opening external URLs
    func temporarilySuspendWebSocket() {
        // print("🔌 Temporarily suspending WebSocket to prevent network conflicts")
        
        ws?.stop()
        
        // Resume connection after a short delay (when Safari likely has established its connection)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.resumeWebSocketAfterSuspension()
        }
    }
    
    /// Resumes WebSocket connection after temporary suspension
    private func resumeWebSocketAfterSuspension() {
        // print("🔌 Resuming WebSocket after suspension")
        
        // Only resume if we have a valid session token and are not signed out
        guard let token = sessionToken, state != .signedOut else {
            return
        }
        
        Task {
            await backgroundWsTask()
        }
    }
    
    func getChannelChannelMessage(channelId: String) -> Binding<[String]> {
        return Binding(
            get: {
                self.channelMessages[channelId] ?? []
            },
            set: { newValue in
                self.channelMessages[channelId] = newValue
            }
        )
    }
    
    func onEvent(_ event: WsMessage) async {
        // print("🔄 VIEWSTATE: Processing WebSocket event: \(String(describing: event).prefix(50))...")
        
        // CRITICAL FIX: Always process events regardless of current view
        // This ensures messages are updated even when in DM list
        await processEvent(event)
        
        // Post notification for UI updates when in DM list
        if case .message(let msg) = event {
            // Check if this message is for a DM channel
            if let channel = channels[msg.channel] {
                switch channel {
                case .dm_channel(_), .group_dm_channel(_):
                    // This is a DM message - notify DM list to update
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("DMListNeedsUpdate"),
                            object: ["channelId": msg.channel, "messageId": msg.id]
                        )
                    }
                default:
                    break
                }
            }
        }
    }
    
    // Store user data for lazy loading
    var allEventUsers: [String: Types.User] = [:]
    
    // LAZY LOADING: Server channel management
    var allEventChannels: [String: Channel] = [:] // Store all channels for lazy loading
    var loadedServerChannels: Set<String> = [] // Track which servers have loaded channels
    
    // EMERGENCY FIX: Force restore all users for specific channel to prevent black messages
    @MainActor
    func forceRestoreUsersForChannel(channelId: String) {
        guard let messageIds = channelMessages[channelId] else {
            // print("🚨 FORCE_RESTORE: No messages found for channel \(channelId)")
            return
        }
        
        var fixedCount = 0
        // print("🚨 FORCE_RESTORE: Checking \(messageIds.count) messages in channel \(channelId)")
        
        for messageId in messageIds {
            if let message = messages[messageId] {
                if users[message.author] == nil {
                    // Try allEventUsers first
                    if let storedUser = allEventUsers[message.author] {
                        users[message.author] = storedUser
                        fixedCount += 1
                        // print("🚨 FORCE_RESTORE: Restored \(storedUser.username) for message \(messageId)")
                    } else {
                        // Create emergency placeholder with better identifier
                        let authorId = message.author
                        let shortId = String(authorId.suffix(4))
                        let placeholder = Types.User(
                            id: authorId,
                            username: "User#\(shortId)",
                            discriminator: "0000",
                            relationship: .None
                        )
                        users[authorId] = placeholder
                        allEventUsers[authorId] = placeholder
                        fixedCount += 1
                        // print("🚨 FORCE_RESTORE: Created emergency placeholder User#\(shortId) for \(authorId)")
                    }
                }
            }
        }
        
        // print("🚨 FORCE_RESTORE: Fixed \(fixedCount) missing users for channel \(channelId)")
    }
    
    // ULTIMATE FIX: Ensure a specific message has its author available
    @MainActor
    func ensureMessageAuthorExists(messageId: String) -> Types.User? {
        guard let message = messages[messageId] else {
            return nil
        }
        
        // Check if user already exists
        if let existingUser = users[message.author] {
            return existingUser
        }
        
        // Try to restore from allEventUsers
        if let storedUser = allEventUsers[message.author] {
            users[message.author] = storedUser
            // print("🔄 ENSURE_AUTHOR: Restored \(storedUser.username) from allEventUsers for message \(messageId)")
            return storedUser
        }
        
        // Create emergency placeholder
        let placeholderUser = Types.User(
            id: message.author,
            username: "Loading User...",
            discriminator: "0000",
            relationship: .None
        )
        users[message.author] = placeholderUser
        allEventUsers[message.author] = placeholderUser
        // print("🚨 ENSURE_AUTHOR: Created emergency placeholder for \(message.author) of message \(messageId)")
        
        return placeholderUser
    }
    
    // LAZY LOADING: Load channels for a specific server when user enters it
    @MainActor
    func loadServerChannels(serverId: String) {
        // Check if already loaded
        if loadedServerChannels.contains(serverId) {
            // print("🔄 LAZY_CHANNEL: Server \(serverId) channels already loaded, skipping")
            return
        }
        
        // print("🔄 LAZY_CHANNEL: Loading channels for server \(serverId)")
        
        // Get all channels for this server from stored data
        let serverChannels = allEventChannels.values.filter { channel in
            switch channel {
            case .text_channel(let textChannel):
                return textChannel.server == serverId
            case .voice_channel(let voiceChannel):
                return voiceChannel.server == serverId
            default:
                return false
            }
        }
        
        var loadedCount = 0
        
        // Add channels to active channels dictionary
        for channel in serverChannels {
            channels[channel.id] = channel
            
            // Create message array for text channels
            if case .text_channel = channel {
                channelMessages[channel.id] = []
            }
            
            loadedCount += 1
        }
        
        // Mark server as loaded
        loadedServerChannels.insert(serverId)
        
        // print("🔄 LAZY_CHANNEL: Loaded \(loadedCount) channels for server \(serverId)")
        // print("🔄 LAZY_CHANNEL: Total active channels now: \(channels.count)")
        
        // Update app badge count after loading server channels
        // This ensures unread messages in the newly loaded channels are counted
        updateAppBadgeCount()
    }
    
    // LAZY LOADING: Unload channels for a server when user leaves it
    @MainActor
    func unloadServerChannels(serverId: String) {
        guard loadedServerChannels.contains(serverId) else {
            return
        }
        
        // CRITICAL FIX: Don't unload if we're currently in a channel from this server
        if case .channel(let currentChannelId) = currentChannel {
            if let currentChannelData = channels[currentChannelId] ?? allEventChannels[currentChannelId] {
                if currentChannelData.server == serverId {
                    // print("🔄 LAZY_CHANNEL: NOT unloading server \(serverId) channels - currently active in channel \(currentChannelId)")
                    return
                }
            }
        }
        
        // print("🔄 LAZY_CHANNEL: Unloading channels for server \(serverId)")
        
        // Find and remove channels for this server
        let channelsToRemove = channels.values.filter { channel in
            switch channel {
            case .text_channel(let textChannel):
                return textChannel.server == serverId
            case .voice_channel(let voiceChannel):
                return voiceChannel.server == serverId
            default:
                return false
            }
        }
        
        var removedCount = 0
        
        for channel in channelsToRemove {
            channels.removeValue(forKey: channel.id)
            channelMessages.removeValue(forKey: channel.id)
            removedCount += 1
        }
        
        // Mark server as unloaded
        loadedServerChannels.remove(serverId)
        
        // print("🔄 LAZY_CHANNEL: Unloaded \(removedCount) channels for server \(serverId)")
        // print("🔄 LAZY_CHANNEL: Total active channels now: \(channels.count)")
    }
    
    /* DISABLED: Virtual Scrolling functions
    // Update visible batch range for virtual scrolling
    private func updateVisibleBatchRange(newBatch: Int) {
        let oldStart = visibleStartBatch
        let oldEnd = visibleEndBatch
        
        // Expand range to include new batch
        let newStart = max(0, min(visibleStartBatch, newBatch))
        let newEnd = min(
            max(visibleEndBatch, newBatch),
            (allDmChannelIds.count - 1) / dmBatchSize
        )
        
        // If we're exceeding max visible batches, slide the window
        if newEnd - newStart >= maxVisibleDmBatches {
            if newBatch > visibleEndBatch {
                // Scrolling down - move window down
                visibleStartBatch = newEnd - maxVisibleDmBatches + 1
                visibleEndBatch = newEnd
            } else if newBatch < visibleStartBatch {
                // Scrolling up - move window up
                visibleStartBatch = newStart
                visibleEndBatch = newStart + maxVisibleDmBatches - 1
            }
        } else {
            visibleStartBatch = newStart
            visibleEndBatch = newEnd
        }
        
        // print("🔄 VIRTUAL_DM: Updated visible range: \(oldStart)-\(oldEnd) → \(visibleStartBatch)-\(visibleEndBatch) for new batch \(newBatch)")
        
                 // AGGRESSIVE CLEANUP: Force immediate cleanup when window slides significantly
         let windowMoved = abs(oldStart - visibleStartBatch) > 0 || abs(oldEnd - visibleEndBatch) > 0
         if windowMoved {
             // print("🔄 VIRTUAL_DM: Window slid (\(oldStart)-\(oldEnd) → \(visibleStartBatch)-\(visibleEndBatch)) - CLEANUP DISABLED for debugging")
             
             // Clear loaded batches that are no longer visible
             let visibleBatches = Set(visibleStartBatch...visibleEndBatch)
             let oldLoadedBatches = loadedDmBatches
             loadedDmBatches = loadedDmBatches.intersection(visibleBatches)
             
             let removedBatches = oldLoadedBatches.subtracting(loadedDmBatches)
             if !removedBatches.isEmpty {
                 // print("🗑️ VIRTUAL_DM: Removed batches \(removedBatches) from loaded set")
             }
             
             // TEMPORARILY DISABLED: aggressiveVirtualCleanup()
             // print("🚨 CLEANUP DISABLED: aggressiveVirtualCleanup() temporarily disabled for debugging")
         }
    }
    
    // Rebuild DMs list with only visible batches
    @MainActor
    private func rebuildVisibleDmsList() {
        var visibleDms: [Channel] = []
        
        for batchIndex in visibleStartBatch...visibleEndBatch {
            let startIndex = batchIndex * dmBatchSize
            let endIndex = min(startIndex + dmBatchSize, allDmChannelIds.count)
            
            for i in startIndex..<endIndex {
                if i < allDmChannelIds.count,
                   let channel = channels[allDmChannelIds[i]] {
                    visibleDms.append(channel)
                }
            }
        }
        
        dms = visibleDms
        // print("🔄 VIRTUAL_DM: Rebuilt DMs list with \(dms.count) visible DMs from batches \(visibleStartBatch)-\(visibleEndBatch)")
        
        // TEMPORARILY DISABLED: Clean up users from invisible DMs (gentle cleanup here)
        // cleanupUsersFromInvisibleDms(aggressive: false)
        // print("🚨 CLEANUP DISABLED: cleanupUsersFromInvisibleDms() temporarily disabled for debugging")
    }
    
    // AGGRESSIVE cleanup for Virtual Scrolling - force immediate RAM reduction
    private func aggressiveVirtualCleanup() {
        let memoryBefore = getCurrentMemoryUsage()
        let usersBefore = users.count
        let messagesBefore = messages.count
        // print("🚨 AGGRESSIVE_VIRTUAL: Starting cleanup - Memory: \(memoryBefore)MB, Users: \(usersBefore), Messages: \(messagesBefore)")
        
        // 1. Force clean users from invisible DMs
        cleanupUsersFromInvisibleDms(aggressive: true)
        
        // 2. Force clean channel messages from invisible DMs
        cleanupChannelMessagesFromInvisibleDms()
        
        // 3. Force cleanup old messages globally (aggressive)
        if messages.count > 100 {
            let sortedMessages = messages.sorted { $0.value.id > $1.value.id }
            let keepMessages = Array(sortedMessages.prefix(100))
            messages = Dictionary(uniqueKeysWithValues: keepMessages)
            // print("🗑️ AGGRESSIVE_VIRTUAL: Reduced messages from \(messagesBefore) to \(messages.count)")
        }
        
        // 4. Force garbage collection
        forceGarbageCollection()
        
        let memoryAfter = getCurrentMemoryUsage()
        let usersAfter = users.count
        let messagesAfter = messages.count
        let memorySaved = memoryBefore - memoryAfter
        
        // print("🚨 AGGRESSIVE_VIRTUAL: Completed")
        // print("   Memory: \(memoryBefore)MB → \(memoryAfter)MB (saved \(memorySaved)MB)")
        // print("   Users: \(usersBefore) → \(usersAfter) (removed \(usersBefore - usersAfter))")
        // print("   Messages: \(messagesBefore) → \(messagesAfter) (removed \(messagesBefore - messagesAfter))")
    }
    
    // Clean up channel messages from invisible DMs
    private func cleanupChannelMessagesFromInvisibleDms() {
        let visibleDmIds = Set(dms.map { $0.id })
        var messagesToRemove: [String] = []
        var channelMessagesToRemove: [String] = []
        
        // Find messages and channel message arrays from invisible DMs
        for (channelId, messageIds) in channelMessages {
            if !visibleDmIds.contains(channelId) {
                // This channel is not visible - remove its messages
                channelMessagesToRemove.append(channelId)
                messagesToRemove.append(contentsOf: messageIds)
            }
        }
        
        // Remove channel message arrays
        for channelId in channelMessagesToRemove {
            channelMessages.removeValue(forKey: channelId)
        }
        
        // Remove individual messages
        for messageId in messagesToRemove {
            messages.removeValue(forKey: messageId)
        }
        
        if !messagesToRemove.isEmpty {
            // print("🗑️ VIRTUAL_DM: Removed \(messagesToRemove.count) messages and \(channelMessagesToRemove.count) channel arrays from invisible DMs")
        }
    }
    
    // Force garbage collection
    private func forceGarbageCollection() {
        autoreleasepool {
            // Force Swift to clean up temporary objects
            _ = NSString()
        }
    }
    
    // Clean up users from DMs that are no longer visible (gentle cleanup)
    private func cleanupUsersFromInvisibleDms(aggressive: Bool = false) {
        // GENTLE CLEANUP: Only clean if we have too many users
        if !aggressive && users.count <= 200 {
            // print("🔄 VIRTUAL_DM: User count (\(users.count)) within safe limits, skipping cleanup")
            return
        }
        
        let visibleDmIds = Set(dms.map { $0.id })
        var usersToKeep: Set<String> = []
        
        // Collect users from visible DMs
        for dm in dms {
            switch dm {
            case .dm_channel(let dmChannel):
                usersToKeep.formUnion(dmChannel.recipients)
            case .group_dm_channel(let groupDm):
                usersToKeep.formUnion(groupDm.recipients)
            default:
                break
            }
        }
        
        // Keep current user
        if let currentUserId = currentUser?.id {
            usersToKeep.insert(currentUserId)
        }
        
        // Keep important relationship users (but limit to 20 in aggressive mode)
        let importantUsers = users.filter { _, user in
            user.relationship == .Friend || 
            user.relationship == .Incoming || 
            user.relationship == .Outgoing ||
            user.relationship == .Blocked
        }
        
        var addedImportantUsers = 0
        for (userId, _) in importantUsers {
            if aggressive && addedImportantUsers >= 20 {
                break // Limit important users in aggressive mode
            }
            usersToKeep.insert(userId)
            addedImportantUsers += 1
        }
        
        // Remove users not in visible DMs or important relationships
        let usersBefore = users.count
        users = users.filter { userId, _ in usersToKeep.contains(userId) }
        let usersAfter = users.count
        
        if usersBefore != usersAfter {
            let mode = aggressive ? "AGGRESSIVE" : "GENTLE"
            // print("🗑️ VIRTUAL_DM (\(mode)): Cleaned up \(usersBefore - usersAfter) users (kept \(usersAfter) from \(usersBefore))")
        }
    }
    */ // END DISABLED Virtual Scrolling functions
    
    // Check if there are more DMs to load
    var hasMoreDmsToLoad: Bool {
        let nextBatchIndex = loadedDmBatches.count
        let totalBatches = (allDmChannelIds.count + dmBatchSize - 1) / dmBatchSize
        return nextBatchIndex < totalBatches && loadedDmBatches.count < maxLoadedBatches
    }
    
    // Load missing batches between current loaded batches
    @MainActor
    func loadDmBatchesIfNeeded(visibleIndex: Int) {
        // Calculate which batch this index belongs to
        let batchIndex = visibleIndex / dmBatchSize
        
        // Load the batch if it's not already loaded
        if !loadedDmBatches.contains(batchIndex) {
            loadDmBatch(batchIndex)
            // print("🔄 LAZY_DM: Loading missing batch \(batchIndex) for visible index \(visibleIndex)")
        }
        
        // Also load adjacent batches for smooth scrolling
        let previousBatch = batchIndex - 1
        let nextBatch = batchIndex + 1
        
        if previousBatch >= 0 && !loadedDmBatches.contains(previousBatch) {
            loadDmBatch(previousBatch)
            // print("🔄 LAZY_DM: Loading missing previous batch \(previousBatch)")
        }
        
        if nextBatch * dmBatchSize < allDmChannelIds.count && !loadedDmBatches.contains(nextBatch) {
            loadDmBatch(nextBatch)
            // print("🔄 LAZY_DM: Loading missing next batch \(nextBatch)")
        }
        
        // CRITICAL FIX: Check if we have gaps in loaded batches and fill them
        ensureNoBatchGaps()
    }
    
    // Ensure all visible batches are loaded based on current visible range
    @MainActor
    func ensureVisibleBatchesLoaded(visibleRange: Range<Int>) {
        guard !allDmChannelIds.isEmpty else { return }
        
        let startBatch = visibleRange.lowerBound / dmBatchSize
        let endBatch = min(visibleRange.upperBound / dmBatchSize, (allDmChannelIds.count - 1) / dmBatchSize)
        
        // print("🔄 LAZY_DM: Ensuring batches \(startBatch) to \(endBatch) are loaded for visible range \(visibleRange)")
        
        for batchIndex in startBatch...endBatch {
            if !loadedDmBatches.contains(batchIndex) {
                // print("🔄 LAZY_DM: Loading missing batch \(batchIndex) for visible range")
                loadDmBatch(batchIndex)
            }
        }
        
        // Also ensure no gaps exist
        ensureNoBatchGaps()
    }
    
    // Check if DM list is consistent and fix any issues
    @MainActor
    func validateAndFixDmListConsistency() {
        guard isDmListInitialized else { return }
        
        let expectedMinDms = min(allDmChannelIds.count, dmBatchSize) // At least first batch should be loaded
        let currentDms = dms.count
        
        if currentDms < expectedMinDms && !allDmChannelIds.isEmpty {
            // print("🔄 LAZY_DM: DM list inconsistency detected - expected at least \(expectedMinDms), got \(currentDms)")
            // print("🔄 LAZY_DM: Total DM channels: \(allDmChannelIds.count), Loaded batches: \(loadedDmBatches)")
            
            // Fix by reloading first batch
            if !loadedDmBatches.contains(0) {
                loadDmBatch(0)
            }
            
            // Rebuild DM list
            reinitializeDmListFromCache()
        }
    }
    
    // Reinitialize DM list from cached data when returning to DM view
    @MainActor
    func reinitializeDmListFromCache() {
        // print("🔄 DM_REINIT: Reinitializing DM list from cache")
        
        // If we don't have DM channel IDs, rebuild from channels
        if allDmChannelIds.isEmpty {
            let dmChannels: [Channel] = channels.values.filter {
                switch $0 {
                case .dm_channel:
                    return true
                case .group_dm_channel:
                    return true
                default:
                    return false
                }
            }
            
            // Sort DM channels
            let sortedDmChannels = dmChannels.sorted { first, second in
                let firstLast = first.last_message_id
                let secondLast = second.last_message_id
                
                let firstUnreadLast = unreads[first.id]?.last_id
                let secondUnreadLast = unreads[second.id]?.last_id
                
                let firstIsUnread = firstLast != nil && firstLast != firstUnreadLast
                let secondIsUnread = secondLast != nil && secondLast != secondUnreadLast
                
                // Show unread DMs first
                if firstIsUnread && !secondIsUnread {
                    return true
                } else if !firstIsUnread && secondIsUnread {
                    return false
                } else {
                    return (firstLast ?? "") > (secondLast ?? "")
                }
            }
            
            allDmChannelIds = sortedDmChannels.map { $0.id }
            // print("🔄 DM_REINIT: Rebuilt \(allDmChannelIds.count) DM channel IDs")
        }
        
        // Rebuild DMs list from loaded batches
        if !loadedDmBatches.isEmpty {
            var rebuiltDms: [Channel] = []
            for loadedBatch in loadedDmBatches.sorted() {
                let batchStart = loadedBatch * dmBatchSize
                let batchEnd = min(batchStart + dmBatchSize, allDmChannelIds.count)
                
                for i in batchStart..<batchEnd {
                    if let channel = channels[allDmChannelIds[i]] {
                        rebuiltDms.append(channel)
                    }
                }
            }
            dms = rebuiltDms
            // print("🔄 DM_REINIT: Rebuilt \(dms.count) DMs from \(loadedDmBatches.count) loaded batches")
        } else {
            // No batches loaded, load first batch
            loadDmBatch(0)
        }
        
        isDmListInitialized = true
    }
    
    func updateUserRelationship(with event: UserRelationshipEvent) {
            
            let userId = event.user.id

            if var existingUser = self.users[userId] {
                if let newStatus = event.status {
                    existingUser.relationship = newStatus
                } else if let newStatus = event.user.relationship {
                    existingUser.relationship = newStatus
                }
                
                self.users[userId] = existingUser
                
            } else {
                // MEMORY FIX: Only add new users if we have space and they're important relationships
                if self.users.count < self.maxUsersInMemory {
                    let relationship = event.status ?? event.user.relationship
                    if relationship == .Friend || relationship == .Incoming || 
                       relationship == .Outgoing || relationship == .Blocked {
                        var newUser = event.user
                        newUser.relationship = relationship
                        self.users[userId] = newUser
                        // print("📥 VIEWSTATE: Added user \(userId) during relationship update with status \(String(describing: relationship))")
                    }
                }
            }
            
            // DISABLED: Memory cleanup was causing UI freezes
            // checkAndCleanupIfNeeded()
        
    }

    
    func deleteChannel(channelId id: String) {
        if case .channel(let channelId) = currentChannel, channelId == id {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                self.path = .init()
            }
        }
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            self.channels.removeValue(forKey: id)
            self.dms = self.dms.filter{$0.id != id}
        }
    }
    
    
    func updateUser(with event: UserUpdateEvent) {
            guard var existingUser = self.users[event.id] else {
                return
            }

            if let userData = event.data {
                if let username = userData.username { existingUser.username = username }
                if let discriminator = userData.discriminator { existingUser.discriminator = discriminator }
                if let displayName = userData.display_name { existingUser.display_name = displayName }
                if let avatar = userData.avatar { existingUser.avatar = avatar }
                if let relations = userData.relations { existingUser.relations = relations }
                if let badges = userData.badges { existingUser.badges = badges }
                if let status = userData.status { existingUser.status = status }
                if let relationship = userData.relationship { existingUser.relationship = relationship }
                if let online = userData.online { existingUser.online = online }
                if let flags = userData.flags { existingUser.flags = flags }
                if let bot = userData.bot { existingUser.bot = bot }
                if let privileged = userData.privileged { existingUser.privileged = privileged }
                if let profile = userData.profile { existingUser.profile = profile }
            }

            if let clearFields = event.clear {
                for field in clearFields {
                    switch field {
                    case .profileContent:
                        existingUser.profile?.content = nil
                    case .profileBackground:
                        existingUser.profile?.background = nil
                    case .statusText:
                        existingUser.status?.text = nil
                    case .avatar:
                        existingUser.avatar = nil
                    case .displayName:
                        existingUser.display_name = nil
                    }
                }
            }

            self.users[event.id] = existingUser
            
            // DISABLED: Memory cleanup was causing UI freezes
            // checkAndCleanupIfNeeded()
        
    }

    
    func joinServer(code: String) async -> JoinResponse {
        let response = try! await http.joinServer(code: code).get()
        
        for channel in response.channels {
            channels[channel.id] = channel
            channelMessages[channel.id] = []
        }
        
        servers[response.server.id] = response.server
        
        // Update app badge count after joining a server
        // This ensures unread messages in the new channels are counted
        await MainActor.run {
            updateAppBadgeCount()
        }
        
        return response
    }
    
    func markServerAsRead(serverId: String) async -> Bool {
        do {
            _ = try await http.markServerAsRead(serverId: serverId).get()
            
            // Clear unreads for all channels in this server
            if let server = servers[serverId] {
                for channelId in server.channels {
                    // Clear unread state for each channel in the server
                    if let channel = channels[channelId] ?? allEventChannels[channelId] {
                        if let lastMessageId = channel.last_message_id {
                            // Set the last_id to the channel's last message to mark as read
                            if var unread = unreads[channelId] {
                                unread.last_id = lastMessageId
                                unread.mentions?.removeAll() // Clear all mentions
                                unreads[channelId] = unread
                            } else if let currentUserId = currentUser?.id {
                                // Create new unread entry with last message as read
                                let unreadId = Unread.Id(channel: channelId, user: currentUserId)
                                unreads[channelId] = Unread(id: unreadId, last_id: lastMessageId, mentions: [])
                            }
                        } else {
                            // If there's no last message, remove the unread entry entirely
                            unreads.removeValue(forKey: channelId)
                        }
                    }
                }
            }
            
            // Update app badge count after marking server as read
            await MainActor.run {
                updateAppBadgeCount()
            }
            
            return true
        } catch {
            print("Failed to mark server as read: \(error)")
            return false
        }
    }
    
    func openDm(with user: String) async {
        var channel = dms.first(where: { switch $0 {
        case .dm_channel(let dm):
            return dm.recipients.contains(user)
        case _:
            return false
        } })
        
        if channel == nil {
            // Try to open DM without force-unwrapping to avoid crashes when the API fails
            let openDmResult = await http.openDm(user: user)
            switch openDmResult {
            case .success(let openedChannel):
                channel = openedChannel
                await MainActor.run {
                    dms.append(openedChannel)
                }
            case .failure(let error):
                // Log and show a safe error to the user instead of crashing
                print("⚠️ openDm failed for user \(user): \(error)")
                await MainActor.run {
                    showAlert(message: "Failed to open DM.", icon: .peptideWarningCircle)
                }
                // Keep channel as nil and continue gracefully
            }
        }
        
        if let safeChannel = channel {
            await MainActor.run {
                currentSelection = .dms
                currentChannel = .channel(safeChannel.id)
            }
        } else {
            // Failed to open DM — avoid force-unwrapping and crash.
            await MainActor.run {
                showAlert(message: "Failed to open DM.", icon: .peptideWarningCircle)
            }
        }
    }
    
    func navigateToDm(with user: String){
        
        Task { @MainActor in
            await openDm(with: user)
            path.append(NavigationDestination.maybeChannelView)
        }
        
    }
    
    func openUserSheet(withId id: String, server: String?) {
        if let user = users[id] {
            let member = server
                .flatMap { members[$0] }
                .flatMap { $0[id] }
            
            currentUserSheet = UserMaybeMember(user: user, member: member)
        }
    }
    
    func openUserOptionsSheet(withId id: String) {
        if let user = users[id] {
            
            currentUserOptionsSheet = UserMaybeMember(user: user, member: nil)
        }
    }
    
    func openUserSheet(user: Types.User, member: Member? = nil) {
        currentUserSheet = UserMaybeMember(user: user, member: member)
    }
    
    func closeUserSheet() {
        currentUserSheet = nil
    }
    
    func closeUserOptionsSheet() {
        currentUserOptionsSheet = nil
    }
    
    public func currentUserCanAddMember(channel: Channel) -> Bool {
        if currentUser != nil {
        
            switch channel {
                case .saved_messages(_):
                    return false
                case .dm_channel(_):
                    return false
                case .group_dm_channel(let c):
                    return c.owner == self.currentUser?.id
                case .text_channel(_):
                        return false
                case .voice_channel(_):
                        return false
            }
            
        } else {
            return false
        }
        
    }
    
    public var openServer: Server? {
        if case .server(let serverId) = currentSelection {
            return servers[serverId]
        }
        
        return nil
    }
    
    public var openServerMember: Member? {
        if case .server(let serverId) = currentSelection, let userId = currentUser?.id {
            return members[serverId]?[userId]
        }
        
        return nil
    }
    
    func verifyStateIntegrity() async {
        // print("🔍 VERIFY_STATE: Starting state integrity verification")
        // print("   - Current selection: \(currentSelection)")
        // print("   - Current channel: \(currentChannel)")
        // print("   - Active channels count: \(channels.count)")
        // print("   - Stored channels count: \(allEventChannels.count)")
        
        if currentUser == nil {
            logger.warning("Current user is empty, logging out")
            try? await signOut().get()
        }
        
        if let token = UserDefaults.standard.string(forKey: "sessionToken") {
            UserDefaults.standard.removeObject(forKey: "sessionToken")
            keychain["sessionToken"] = token
        }
        
        if case .channel(let id) = currentChannel {
            if let channel = channels[id] {
                if let serverId = channel.server, currentSelection == .dms {
                    logger.warning("Current channel is a server channel but selection is dms")
                    
                    currentSelection = .server(serverId)
                }
            } else {
                // CRITICAL FIX: Check if channel exists in stored data before declaring it missing
                if let storedChannel = allEventChannels[id] {
                    // print("🔄 VERIFY_STATE: Channel \(id) found in stored data, reloading to active channels")
                    channels[id] = storedChannel
                    
                    // If it's a server channel, make sure we're in the right selection
                    if let serverId = storedChannel.server {
                        if currentSelection == .dms {
                            // print("🔄 VERIFY_STATE: Switching from DMs to server \(serverId) for channel \(id)")
                            currentSelection = .server(serverId)
                        }
                        // Make sure server channels are loaded
                        loadServerChannels(serverId: serverId)
                    }
                } else {
                    logger.warning("Current channel no longer exists even in stored data")
                    // print("🏠 HOME_REDIRECT: Going to discover because current channel no longer exists")
                    currentSelection = .discover
                    currentChannel = .home
                }
            }
        }
        
        if case .server(let id) = currentSelection {
            if servers[id] == nil {
                logger.warning("Current server no longer exists")
                // print("🏠 HOME_REDIRECT: Going to discover because current server no longer exists")
                currentSelection = .discover
                currentChannel = .home
            }
        }
    }
    
    func resolveAvatarUrl(user: Types.User, member: Member?, masquerade: Masquerade?) -> (url: URL, username: String, isAvatarSet : Bool) {
        
        let username = user.username
        
        if let avatar = masquerade?.avatar, let url = URL(string: avatar) {
            return (url, username, true)
        }
        
        if let avatar = member?.avatar, let url = URL(string: formatUrl(with: avatar)) {
            return (url, username, true)
        }
        
        if let avatar = user.avatar, let url = URL(string: formatUrl(with: avatar)) {
            return (url, username, true)
        }
        
        return (URL(string: "\(http.baseURL)/users/\(user.id)/default_avatar")!, username, false)
    }
    
    
    func isURLSet() -> Bool {
        if let baseURL {
            self.http.baseURL = baseURL
            return true
        } else {
            return false
        }
    }
    
    
    func sendBeginTyping(channel: String) {
        guard let webSocket = ws else{
            return
        }
        
        webSocket.sendBeginTyping(channel: channel)
        
    }
    
    
    func sendEndTyping(channel: String) {
        guard let webSocket = ws else {
            return
        }
        webSocket.sendEndTyping(channel: channel)
    }
    
    
    func findEmojiBase(by shortcode: String) -> [Int] {
        // First check our new emoji dictionary
        if let emoji = EmojiParser.findEmojiByShortcode(shortcode) {
            // Convert Unicode emoji to code points
            if !emoji.hasPrefix("custom:") {
                let codePoints = emoji.unicodeScalars.map { Int($0.value) }
                return codePoints
            }
        }
        
        // Fallback to the existing JSON-based emoji lookup
        for group in baseEmojis {
            if let emoji = group.emoji.first(where: { $0.shortcodes.contains(shortcode) }) {
                return emoji.base
            }
        }
        return []
    }
    
    @MainActor
    func loadEmojis() -> [EmojiGroup] {
        let file = Bundle.main.url(forResource: "emoji_15_1_ordering.json", withExtension: nil)!
        let data = try! Data(contentsOf: file)
        
        let baseEmojis = try! JSONDecoder().decode([EmojiGroup].self, from: data)
        
        return baseEmojis
    }
    
    
    func getDMPartnerName(channel : DMChannel) -> Types.User? {
        guard let currentUserId = currentUser?.id else {
            return nil
        }
        
        guard let otherUserId = channel.recipients.first(where: { $0 != currentUserId }) else {
            return nil
        }
        
        // Check if user exists
        if let user = users[otherUserId] {
            return user
        }
        
        // Try to load from stored event data
        if let storedUser = allEventUsers[otherUserId] {
            users[otherUserId] = storedUser
            return storedUser
        }
        
        // Create placeholder user to prevent empty spaces
        let placeholderUser = Types.User(
            id: otherUserId,
            username: "Unknown User",
            discriminator: "0000",
            relationship: .None
        )
        users[otherUserId] = placeholderUser
        return placeholderUser
    }
    
    /// Checks if the current user has a friendship with the specified user
    /// - Parameter userId: The ID of the target user
    /// - Returns: A boolean indicating if the relationship is a friendship
    func isFriend(userId: String) -> Bool {
        // Find the target user in the list
        guard let targetUser = users[userId] else {
            return false // Return false if the user does not exist
        }
        
        // Check if the relationship is a friendship
        return targetUser.relationship == .Friend
    }
    
    func getUserRelation(userId: String) -> Relation? {
        
        guard let targetUser = users[userId] else {
            return .None
        }
        
        return targetUser.relationship
    }
    
    func showAlert(message : String, icon : ImageResource, color: Color = .iconDefaultGray01){
        self.alert = (message, icon, color)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.snappy) {
                self.alert = (nil,nil, nil)
            }
        }
    }
    
    func showLoadingAlert(message : String, icon : ImageResource, color: Color = .blue){
        self.alert = (message, icon, color)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            withAnimation(.snappy) {
                self.alert = (nil,nil, nil)
            }
        }
    }
    
    
    func getServerMembers(target : String) async{
        // FAST: Update UI immediately with loading state
        await MainActor.run {
            serverMembersCount = nil
        }
        
        let serverMembers = await self.http.fetchServerMembers(target: target)
        
        // OPTIMIZED: Process data in background, then update UI on main thread
        switch serverMembers {
            case .success(let success):
                // Process data in background
                var newUsers = self.users
                var newMembers = self.members

                for user in success.users {
                    newUsers[user.id] = user
                }

                for member in success.members {
                    let serverId = member.id.server
                    let userId = member.id.user

                    if newMembers[serverId] == nil {
                        newMembers[serverId] = [:]
                    }
                    newMembers[serverId]?[userId] = member
                }
                
                // FAST: Update UI on main thread
                await MainActor.run {
                    self.serverMembersCount = success.members.count.formattedWithSeparator()
                    self.users = newUsers
                    self.members = newMembers
                }
            
            case .failure(_):
                await MainActor.run {
                    self.serverMembersCount = nil
                }
        }
    }
    
    
    func addOrReplaceMember(_ member: Member) {
        let serverId = member.id.server
        let userId = member.id.user
        
        if members[serverId] == nil {
            members[serverId] = [:]
        }
        
        members[serverId]?[userId] = member
        
    }
    
    func getMember(byServerId serverId: String, userId: String ) -> Member? {
        return members[serverId]?[userId]
    }
    
    
    func isSelectedChannel(_ id: String) -> Bool {
        if case .channel(let selectedId) = self.currentChannel {
            return selectedId == id
        }
        return false
    }
    
    
    func isInsideChannelPage(for channelId: String) -> Bool {
        return pathContainsMaybeChannelView() && isSelectedChannel(channelId)
    }
    
    func pathContainsMaybeChannelView() -> Bool {
        return self.path.contains(where: {
            if case .maybeChannelView = $0 {
                return true
            }
            return false
        })
    }

    func shouldPerformAction(for channelId: String) -> Bool {
        return !isInsideChannelPage(for: channelId)
    }
    
    
    func reorderServers(from sourceId: String, to destinationId: String) {
        guard let sourceIndex = servers.elements.firstIndex(where: { $0.key == sourceId }),
              let destinationIndex = servers.elements.firstIndex(where: { $0.key == destinationId }) else {
            return
        }
        
        // Convert to array, reorder, and convert back to OrderedDictionary
        var elementsArray = Array(servers.elements)
        let element = elementsArray.remove(at: sourceIndex)
        elementsArray.insert(element, at: destinationIndex)
        
        // Create a new OrderedDictionary with the reordered elements
        servers = OrderedDictionary(uniqueKeysWithValues: elementsArray)
    }
    
    @Published var deviceNotificationToken: String? = nil
    @Published var pendingNotificationToken: String? = nil

    
    // MARK: - Message Preloading System
    private let messagePreloadingQueue = DispatchQueue(label: "messagePreloading", qos: .utility)
    internal var preloadingTasks: [String: Task<Void, Never>] = [:]
    internal let maxPreloadedMessagesPerChannel = 20
    
    /// Debug badge count and print detailed analysis to console
    func debugBadgeCount() {
        print("🔍 === BADGE COUNT DEBUG ===")
        print("📊 Total unreads entries: \(unreads.count)")
        
        var totalCount = 0
        var mutedCount = 0
        var validCount = 0
        var missingChannels = 0
        var channelsWithUnread = 0
        
        for (channelId, unread) in unreads {
            let channel = channels[channelId] ?? allEventChannels[channelId]
            let channelName = channel?.name ?? "Unknown"
            let channelExists = channel != nil
            let isChannelMuted = userSettingsStore.cache.notificationSettings.channel[channelId] == .muted
            let serverIdForChannel = channel?.server
            let isServerMuted = serverIdForChannel != nil ? userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .muted : false
            
            print("  📌 Channel: \(channelName) (\(channelId))")
            print("     - Channel exists: \(channelExists)")
            print("     - Last read ID: \(unread.last_id ?? "nil")")
            print("     - Last message ID: \(channel?.last_message_id ?? "nil")")
            
            // Check if has unread
            var hasUnread = false
            if let lastUnreadId = unread.last_id, let lastMessageId = channel?.last_message_id {
                hasUnread = lastUnreadId < lastMessageId
                print("     - Has unread: \(hasUnread) (\(lastUnreadId) < \(lastMessageId))")
            }
            
            if let mentions = unread.mentions {
                print("     - Mentions: \(mentions.count) - \(mentions)")
            }
            print("     - Channel Muted: \(isChannelMuted)")
            print("     - Server Muted: \(isServerMuted)")
            
            totalCount += 1
            if !channelExists {
                missingChannels += 1
            } else if isChannelMuted || isServerMuted {
                mutedCount += 1
            } else {
                validCount += 1
                if hasUnread || (unread.mentions?.count ?? 0) > 0 {
                    channelsWithUnread += 1
                }
            }
        }
        
        print("\n📊 Summary:")
        print("  - Total unread entries: \(totalCount)")
        print("  - Missing channels: \(missingChannels)")
        print("  - Muted channels: \(mutedCount)")
        print("  - Valid (unmuted) channels: \(validCount)")
        print("  - Channels with actual unread: \(channelsWithUnread)")
        print("  - Current app badge: \(ViewState.application?.applicationIconBadgeNumber ?? -1)")
        print("  - Total channels loaded: \(channels.count)")
        print("  - Total channels stored: \(allEventChannels.count)")
        print("🔍 === END DEBUG ===\n")
    }
    // MARK: - Message queue processing state
    internal var isProcessingQueue: [String: Bool] = [:] // Prevent concurrent processing per channel
    
    // Check the internet status
    func setupInternetObservation() {
        InternetMonitor.shared.$isConnected
            .sink { isConnected in
                if isConnected {
                    print("🌐 Internet restored → trying to flush queue")
                    self.trySendingQueuedMessages()
                }
            }
            .store(in: &cancellables)
        }
}

// This is used for notifications @mention issue fetches the corresponding @mention user from users.json. Testing is pending.
//extension ViewState {
//    func saveUsersToSharedContainer() {
//        guard let sharedURL = FileManager.default
//            .containerURL(forSecurityApplicationGroupIdentifier: "group.pepchat.shared")?
//            .appendingPathComponent("users.json") else {
//            print("❌ Failed to get App Group container URL")
//            return
//        }
//
//        do {
//            let data = try JSONEncoder().encode(self.users)
//            try data.write(to: sharedURL, options: .atomic)
//            print("✅ Shared users.json updated")
//        } catch {
//            print("❌ Failed to write users.json:", error)
//        }
//    }
//}


extension Dictionary {
    mutating func setDefault(key: Key, default def: Value) -> Value {
        var value = self[key]
        
        if value == nil {
            value = def
            self[key] = value
        }
        
        return value!
    }
}

extension Channel {
    @MainActor
    public func getName(_ viewState: ViewState) -> String {
        switch self {
        case .saved_messages(_):
            return "Saved Messages"
        case .dm_channel(let c):
            // CRITICAL FIX: Safe unwrapping to prevent crash
            guard let currentUserId = viewState.currentUser?.id else {
                return "Unknown DM"
            }
            
            guard let otherUserId = c.recipients.first(where: { $0 != currentUserId }) else {
                return "Unknown DM"
            }
            
            if let otherUser = viewState.users[otherUserId] {
                return otherUser.username
            } else {
                // Try to load user if missing
                if let storedUser = viewState.allEventUsers[otherUserId] {
                    viewState.users[otherUserId] = storedUser
                    return storedUser.username
                }
                return "Unknown User"
            }
        case .group_dm_channel(let c):
            return c.name
        case .text_channel(let c):
            return c.name
        case .voice_channel(let c):
            return c.name
        }
    }
}
