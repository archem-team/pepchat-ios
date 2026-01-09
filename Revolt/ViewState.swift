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
#if canImport(Kingfisher)
import Kingfisher
#endif


enum UserStateError: Error {
    case signInError
    case signOutError
}

enum LoginState {
    case Success
    case Mfa(ticket: String, methods: [String])
    case Disabled
    case Invalid
    case Onboarding
}

struct LoginSuccess: Decodable {
    let result: String
    let _id: String
    let user_id: String
    let token: String
    let name: String
}

struct LoginMfa: Decodable {
    let result: String
    let ticket: String
    let allowed_methods: [String]
}

struct LoginDisabled: Decodable {
    let result: String
    let user_id: String
}

enum LoginResponse {
    case Success(LoginSuccess)
    case Mfa(LoginMfa)
    case Disabled(LoginDisabled)
}

extension LoginResponse: Decodable {
    enum CodingKeys: String, CodingKey { case result }
    enum Tag: String, Decodable { case Success, MFA, Disabled }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .result) {
        case .Success:
            self = .Success(try singleValueContainer.decode(LoginSuccess.self))
        case .MFA:
            self = .Mfa(try singleValueContainer.decode(LoginMfa.self))
        case .Disabled:
            self = .Disabled(try singleValueContainer.decode(LoginDisabled.self))
        }
    }
}

enum ConnectionState {
    case connecting, connected, signedOut
}


enum MainSelection: Hashable, Codable {
    case server(String)
    case dms
    case discover
    
    var id: String? {
        switch self {
        case .server(let id):
            id
        case .dms:
            nil
        case .discover:
            nil
        }
    }
}

enum ChannelSelection: Hashable, Codable {
    case channel(String)
    case home
    case friends
    case noChannel
    
    var id: String? {
        switch self {
        case .channel(let id): id
        default: nil
        }
    }
}

enum NavigationDestination: Hashable, Codable {
    case discover
    case settings
    case about_settings
    case developer_settings
    case server_settings(String)
    case channel_info(String,String?)
    case add_members_to_channel(String)
    case channel_settings(String)
    case add_friend
    case create_group([String])
    case channel_search(String)
    case invite(String)
    case maybeChannelView
    case create_group_name
    case create_group_add_memebers(String)
    case report(Types.User?,String?,String?)
    case channel_overview_setting(String,String?)
    case server_channel_overview_setting(String,String)
    case server_role_setting(String)
    case server_overview_settings(String)
    case server_channels(String)
    case server_category(String,String)
    case channel_category_create(String, ChannelCategoryCreateType)
    case profile_setting
    case server_emoji_settings(String)
    case validate_password_view(ValidatePasswordReason)
    case show_recovery_codes(String, Bool)
    case enable_authenticator_app(String)
    case blocked_users_view
    case user_settings
    case role_setting(serverId:String, channelId: String, roleId : String, roleTitle : String, value:ChannelRolePermissionsSettings.Value)
    case server_members_view(String)
    case member_permissions(String, Member)
    case server_invites(String)
    case server_banned_users(String)
    case create_server_role(serverId : String)
    case default_role_settings(serverId : String)
    case role_settings(serverId : String, roleId : String)
    case channel_permissions_settings(serverId : String?, channelId : String)
    case sessions_settings
    case username_view
    case change_email_view
    case change_password_view
}

struct UserMaybeMember: Identifiable {
    var user: Types.User
    var member: Member?
    
    var id: String { user.id }
    
    var avatar: File? {
        return member?.avatar ?? user.avatar
    }
    
    var nickname: String? {
        return member?.nickname ?? user.display_name ?? user.username
    }
}

class QueuedMessage: ObservableObject {
    let nonce: String
    let replies: [Revolt.ApiReply]
    let content: String
    let author: String // User ID of the sender
    let channel: String // Channel ID
    let timestamp: Date // When the message was sent locally
    let hasAttachments: Bool // Whether this message has attachments (affects when to show optimistically)
    let attachmentData: [(Data, String)] // Original attachment data for progress tracking
    @Published var uploadProgress: [String: Double] = [:] // Progress per attachment (filename -> progress 0.0-1.0)
    @Published var isUploading: Bool = false // Whether currently uploading
    
    init(nonce: String, replies: [Revolt.ApiReply], content: String, author: String, channel: String, timestamp: Date, hasAttachments: Bool, attachmentData: [(Data, String)] = []) {
        self.nonce = nonce
        self.replies = replies
        self.content = content
        self.author = author
        self.channel = channel
        self.timestamp = timestamp
        self.hasAttachments = hasAttachments
        self.attachmentData = attachmentData
        self.uploadProgress = [:]
        self.isUploading = hasAttachments
        
        // Initialize progress for each attachment
        for (_, filename) in attachmentData {
            self.uploadProgress[filename] = 0.0
        }
    }
    
    // Helper function to determine content type from filename
    private func getContentType(for filename: String) -> String {
        let lowercaseFilename = filename.lowercased()
        
        // Image types
        if lowercaseFilename.hasSuffix(".jpg") || lowercaseFilename.hasSuffix(".jpeg") {
            return "image/jpeg"
        } else if lowercaseFilename.hasSuffix(".png") {
            return "image/png"
        } else if lowercaseFilename.hasSuffix(".gif") {
            return "image/gif"
        } else if lowercaseFilename.hasSuffix(".webp") {
            return "image/webp"
        } else if lowercaseFilename.hasSuffix(".bmp") {
            return "image/bmp"
        } else if lowercaseFilename.hasSuffix(".svg") {
            return "image/svg+xml"
        }
        // Video types
        else if lowercaseFilename.hasSuffix(".mp4") {
            return "video/mp4"
        } else if lowercaseFilename.hasSuffix(".mov") {
            return "video/quicktime"
        } else if lowercaseFilename.hasSuffix(".avi") {
            return "video/x-msvideo"
        } else if lowercaseFilename.hasSuffix(".webm") {
            return "video/webm"
        }
        // Audio types
        else if lowercaseFilename.hasSuffix(".mp3") {
            return "audio/mpeg"
        } else if lowercaseFilename.hasSuffix(".wav") {
            return "audio/wav"
        } else if lowercaseFilename.hasSuffix(".m4a") {
            return "audio/mp4"
        }
        // Default
        else {
            return "application/octet-stream"
        }
    }
    
    // Convert to a temporary Message object for display
    func toTemporaryMessage() -> Message {
        // Create temporary File objects for display if uploading
        let tempAttachments: [Types.File]? = hasAttachments && isUploading ? 
            attachmentData.map { (data, filename) in
                // Determine content type based on file extension
                let contentType = getContentType(for: filename)
                
                return Types.File(
                    id: "\(nonce)_\(filename)", // Temporary ID
                    tag: "attachments", // Required tag parameter
                    size: Int64(data.count),
                    filename: filename,
                    metadata: Types.FileMetadata.file(Types.SimpleMetadata()), // Correct metadata type
                    content_type: contentType
                )
            } : nil
        
        return Message(
            id: nonce, // Use nonce as temporary ID
            content: content,
            author: author,
            channel: channel,
            system: nil,
            attachments: tempAttachments,
            mentions: nil,
            replies: replies.isEmpty ? nil : replies.map { $0.id },
            edited: nil,
            masquerade: nil,
            interactions: nil,
            reactions: nil,
            user: nil,
            member: nil,
            embeds: nil,
            webhook: nil
        )
    }
}

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
            let users = self.users
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                if let data = try? JSONEncoder().encode(users) {
                    await MainActor.run {
                        self.debouncedSave(key: "users", data: data)
                    }
                }
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
    // Tombstone tracking for deleted messages (per channel)
    var deletedMessageIds: [String: Set<String>] = [:]
    
    @Published var channelMessages: [String: [String]] {
        didSet {
            // MEMORY MANAGEMENT: Use debounced save for channelMessages
            // Move JSON encoding off main thread to prevent app hanging
            let channelMessages = self.channelMessages
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
            if let data = try? JSONEncoder().encode(channelMessages) {
                    await MainActor.run {
                        self.debouncedSave(key: "channelMessages", data: data)
                    }
                }
            }
            
            // Check if we should turn off loading state
            Task { @MainActor in
                if self.isLoadingChannelMessages {
                    if case .channel(let channelId) = self.currentChannel {
                        let hasMessages = (channelMessages[channelId]?.count ?? 0) > 0
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
    private var isLoadingDmBatch = false
    private var isDmListInitialized = false // Track if DM list has been initialized
    
    // SIMPLE LAZY LOADING: Just load more as needed, no complex virtual scrolling
    private let maxLoadedBatches = 50 // Maximum 50 batches (750 DMs) with increased memory limits
    @Published var emojis: [String: Emoji] {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            let emojis = self.emojis
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                if let data = try? JSONEncoder().encode(emojis) {
                    await MainActor.run {
                        self.debouncedSave(key: "emojis", data: data)
                    }
                }
            }
        }
    }
    
    @Published var currentUser: Types.User? = nil {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            let currentUser = self.currentUser
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                if let data = try? JSONEncoder().encode(currentUser) {
                    await MainActor.run {
                        self.debouncedSave(key: "currentUser", data: data)
                    }
                }
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
    private var saveWorkItems: [String: DispatchWorkItem] = [:]
    private let saveDebounceInterval: TimeInterval = 2.0 // Save after 2 seconds of no changes
    private let cleanupTriggeredAt = 800 // Start cleanup when 80% full (legacy, not used)
    private let maxChannelsInMemory = 2000 // Maximum channels to keep in memory (increased to load all servers)
    
    @Published var unreadsVersion: UUID = UUID()
    @Published var currentUserSheet: UserMaybeMember? = nil
    @Published var currentUserOptionsSheet: UserMaybeMember? = nil
    @Published var atTopOfChannel: Set<String> = []
    
    @Published var alert : (String?,SwiftUI.ImageResource?, Color?) = (nil,nil, nil)
    
    @Published var serverMembersCount : String? = nil
    
    @Published var mentionedUser : String? = nil
    
    
    @Published var currentSelection: MainSelection {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            let currentSelection = self.currentSelection
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                if let data = try? JSONEncoder().encode(currentSelection) {
                    await MainActor.run {
                        self.debouncedSave(key: "currentSelection", data: data)
                    }
                }
            }
        }
    }
    
    @Published var currentChannel: ChannelSelection {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            let currentChannel = self.currentChannel
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                if let data = try? JSONEncoder().encode(currentChannel) {
                    await MainActor.run {
                        self.debouncedSave(key: "currentChannel", data: data)
                    }
                }
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
            let theme = self.theme
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                if let data = try? JSONEncoder().encode(theme) {
                    await MainActor.run {
                        self.debouncedSave(key: "theme", data: data)
                    }
                }
            }
        }
    }
    
    @Published var currentLocale: Locale? {
        didSet {
            // OPTIMIZED: Move encoding to background thread with debouncing
            let currentLocale = self.currentLocale
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                if let data = try? JSONEncoder().encode(currentLocale) {
                    await MainActor.run {
                        self.debouncedSave(key: "locale", data: data)
                    }
                }
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
    private var previousChannelId: String? = nil
    
    // Loading state for channels when messages are being fetched
    @Published var isLoadingChannelMessages: Bool = false
    
    // CRITICAL FIX: Flag to prevent memory cleanup during older message loading
    private var isLoadingOlderMessages: Bool = false
    
    var userSettingsStore: UserSettingsData
    
    // MEMORY MANAGEMENT: Feature flags for staged rollout
    /// Feature flag to enable aggressive memory management. Default: true after rollout.
    private var enableAggressiveMemoryManagement: Bool {
        UserDefaults.standard.object(forKey: "enableAggressiveMemoryManagement") as? Bool ?? true // Fallback to true
    }
    
    /// Aggressive message limit per channel. Default: 50.
    private var aggressiveMessageLimit: Int {
        UserDefaults.standard.object(forKey: "aggressiveMessageLimit") as? Int ?? 50 // Fallback to 50
    }
    
    /// Aggressive user limit total. Default: 1000.
    private var aggressiveUserLimit: Int {
        UserDefaults.standard.object(forKey: "aggressiveUserLimit") as? Int ?? 1000 // Fallback to 1000
    }
    
    // MEMORY MANAGEMENT: Configuration for aggressive cleanup
    /// Maximum messages to keep in memory. Uses feature flag if enabled, otherwise old limit.
    /// Reduced from 2000 to 1500 to prevent memory from reaching 1GB+
    private var maxMessagesInMemory: Int {
        enableAggressiveMemoryManagement ? 1500 : 7000
    }
    
    /// Maximum users to keep in memory. Uses feature flag if enabled, otherwise old limit.
    private var maxUsersInMemory: Int {
        enableAggressiveMemoryManagement ? aggressiveUserLimit : 2000
    }
    
    /// Maximum messages per channel. Uses feature flag if enabled, otherwise old limit.
    /// Reduced from 100 to 75 to prevent memory buildup
    private var maxChannelMessages: Int {
        enableAggressiveMemoryManagement ? 75 : 800
    }
    
    private let maxServersInMemory = 50 // Maximum servers to keep in memory
    
    // MEMORY MANAGEMENT: Size-based eviction tracking
    /// Dictionary to track approximate memory size per message
    private var messageSizes: [String: Int] = [:]
    
    /// Total approximate memory size of all messages in bytes
    private var totalMessageMemorySize: Int = 0
    
    // MEMORY MANAGEMENT: User cache limits per channel
    /// Dictionary to track which users belong to which channels
    private var channelUserIds: [String: Set<String>] = [:]
    
    /// Maximum users to keep per channel
    private let maxUsersPerChannel = 100
    
    // MEMORY MANAGEMENT: Channel access tracking with persistence
    /// Dictionary to track when channels were last accessed (for cleanup prioritization)
    private var channelLastAccessTime: [String: Date] = [:]
    
    /// Multitasking awareness flags
    private var isAppInSplitView: Bool = false
    private var isAppInBackgroundFetch: Bool = false
    private var isAppInBackground: Bool = false
    
    // MEMORY MANAGEMENT: Per-channel memory cost instrumentation
    /// Structure to track memory costs per channel
    struct ChannelMemoryCost {
        var messageCount: Int
        var messageSizeBytes: Int
        var userCount: Int
        var imageCacheSizeBytes: Int // Always 0 - image cache is global, not per-channel
        var videoCacheSizeBytes: Int // Estimated (thumbnails, durations, AVAssets)
        var totalBytes: Int { messageSizeBytes + videoCacheSizeBytes } // Exclude imageCacheSizeBytes
    }
    
    /// Dictionary to track memory costs per channel
    private var channelMemoryCosts: [String: ChannelMemoryCost] = [:]
    
    // PRELOADING CONTROL: Configuration for automatic message preloading
    /// Set to false to disable all automatic message preloading when entering servers/channels
    private let enableAutomaticPreloading = false // DISABLED: No automatic preloading
    
    // MEMORY MANAGEMENT: Size calculation helper
    /// Calculates approximate memory size of a message in bytes
    /// Uses UTF-8 byte count for content, actual attachment sizes from metadata, and user object estimates
    private func calculateMessageSize(_ message: Message) -> Int {
        var size = 0
        
        // Content size: UTF-8 byte count (actual bytes, not character count)
        if let content = message.content {
            size += content.utf8.count
        }
        
        // Attachment size: Sum of actual file sizes from metadata
        if let attachments = message.attachments {
            for attachment in attachments {
                // attachment.size is Int64, not optional
                size += Int(attachment.size)
            }
        }
        
        // User object size: Estimate ~500 bytes per user referenced by message
        // Count unique users: author + mentions
        var uniqueUsers = Set<String>()
        uniqueUsers.insert(message.author)
        if let mentions = message.mentions {
            uniqueUsers.formUnion(mentions)
        }
        size += uniqueUsers.count * 500
        
        return size
    }
    
    /// Updates message size tracking when a message is added
    private func updateMessageSize(messageId: String, message: Message) {
        let size = calculateMessageSize(message)
        if let oldSize = messageSizes[messageId] {
            totalMessageMemorySize -= oldSize
        }
        messageSizes[messageId] = size
        totalMessageMemorySize += size
    }
    
    /// Removes message size tracking when a message is removed
    private func removeMessageSize(messageId: String) {
        if let size = messageSizes.removeValue(forKey: messageId) {
            totalMessageMemorySize -= size
        }
    }
    
    // MEMORY MANAGEMENT: Helper methods
    private func debouncedSave(key: String, data: Data) {
        // Cancel any existing save operation for this key
        saveWorkItems[key]?.cancel()
        
        // Create a new work item
        let workItem = DispatchWorkItem { [weak self] in
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
    
    @MainActor
    func enforceMemoryLimits() {
        // MEMORY MANAGEMENT: More aggressive thresholds to prevent memory growth to 1GB+
        // Trigger cleanup earlier to prevent memory buildup
        // Also check actual memory usage, not just message count/size
        let currentMemoryMB = getCurrentMemoryUsage()
        guard messages.count > 1000 || totalMessageMemorySize > 50 * 1024 * 1024 || currentMemoryMB > 700 else {
            return
        }
        
        print("🧹 MEMORY_CLEANUP: Starting cleanup - Messages: \(messages.count), Size: \(String(format: "%.2f", Double(totalMessageMemorySize) / 1024.0 / 1024.0))MB, Memory: \(String(format: "%.2f", currentMemoryMB))MB")
        
        // EMERGENCY MEMORY RESET if over 4GB
        if currentMemoryMB > 4000 {
            // print("🚨 EMERGENCY: Memory over 4GB (\(currentMemoryMB)MB)! Performing complete reset!")
            
            // Clear everything except current user
            let currentUserId = currentUser?.id
            let currentUserObject = currentUser
            
            messages.removeAll()
            channelMessages.removeAll()
            users.removeAll()
            channels.removeAll()
            servers.removeAll()
            members.removeAll()
            dms.removeAll()
            emojis.removeAll()
            unreads.removeAll()
            
            // Restore only current user
            if let currentUserId = currentUserId, let currentUserObject = currentUserObject {
                users[currentUserId] = currentUserObject
                currentUser = currentUserObject
            }
            
            // print("🚨 EMERGENCY RESET COMPLETED! Memory should now be minimal.")
            return
        }
        
                    // AGGRESSIVE MEMORY CLEANUP if over 2GB (increased threshold for better performance)
            if currentMemoryMB > 2000 {
                // print("🚨 AGGRESSIVE CLEANUP: Memory over 2GB (\(currentMemoryMB)MB)!")
                
                // VIRTUAL SCROLLING PROTECTION: Skip aggressive cleanup if in DM view
                if currentSelection == .dms {
                    // print("🔄 VIRTUAL_DM: Skipping aggressive cleanup - user is in DM view with Virtual Scrolling active")
                    return
                }
                
                                    // CRITICAL FIX: Keep ALL users to prevent black messages - only clear non-essential data
                    // print("🚨 EMERGENCY: Keeping ALL users to prevent black messages")
                    // Don't touch users at all - they are needed for message display
                
                // Keep only last 100 messages
                let sortedMessages = messages.sorted { $0.value.id > $1.value.id }
                let recentMessages = Array(sortedMessages.prefix(100))
                let messagesToRemove = Set(messages.keys).subtracting(recentMessages.map { $0.key })
                for messageId in messagesToRemove {
                    removeMessageSize(messageId: messageId)
                }
                messages = Dictionary(uniqueKeysWithValues: recentMessages)
                
                // Keep ALL DMs and current channel
                var channelsToKeep: [String: Channel] = [:]
                
                if case .channel(let currentChannelId) = currentChannel {
                    if let currentChannel = channels[currentChannelId] {
                        channelsToKeep[currentChannelId] = currentChannel
                    }
                }
                
                // Keep ALL DM and Group DM channels (don't limit to 10)
                for channel in channels.values {
                    switch channel {
                    case .dm_channel:
                        channelsToKeep[channel.id] = channel
                    case .group_dm_channel:
                        channelsToKeep[channel.id] = channel
                    default:
                        break
                    }
                }
                
                channels = channelsToKeep
                
                // Clear all but essential channel messages
                for (channelId, _) in channelMessages {
                    if channelsToKeep[channelId] != nil {
                        channelMessages[channelId] = Array((channelMessages[channelId] ?? []).suffix(10))
                    } else {
                        channelMessages.removeValue(forKey: channelId)
                    }
                }
                
                // Keep more servers in emergency cleanup (increased from 5 to 20)
                let topServers = Array(servers.prefix(20))
                servers = OrderedDictionary(uniqueKeysWithValues: topServers)
                
                // FIX: Don't clear DM list state during aggressive cleanup
                if isDmListInitialized {
                    // Keep DM list state intact, just reinitialize it
                    reinitializeDmListFromCache()
                }
                
                // print("🚨 AGGRESSIVE CLEANUP COMPLETED!")
                return
            }
        
        // NORMAL CLEANUP: Remove excess messages (consider both count AND size)
        let sizeLimitMB = 100 * 1024 * 1024 // 100MB
        let shouldCleanupByCount = messages.count > maxMessagesInMemory
        let shouldCleanupBySize = totalMessageMemorySize > sizeLimitMB
        
        if shouldCleanupByCount || shouldCleanupBySize {
            // print("🧠 MEMORY: Enforcing message limit. Current: \(messages.count), Max: \(maxMessagesInMemory)")
            
            // Get all message IDs sorted by size (largest first) and timestamp (older first)
            // Prioritize removing largest messages from least-recently-accessed channels
            let sortedMessageIds: [String]
            if shouldCleanupBySize {
                // Size-based: Sort by size (largest first), then by timestamp (oldest first)
                sortedMessageIds = messages.keys.sorted { id1, id2 in
                    let size1 = messageSizes[id1] ?? 0
                    let size2 = messageSizes[id2] ?? 0
                    if size1 != size2 {
                        return size1 > size2 // Largest first
                    }
                    let date1 = createdAt(id: id1)
                    let date2 = createdAt(id: id2)
                    return date1 < date2 // Oldest first
                }
            } else {
                // Count-based: Sort by timestamp (older first)
                sortedMessageIds = messages.keys.sorted { id1, id2 in
                    let date1 = createdAt(id: id1)
                    let date2 = createdAt(id: id2)
                    return date1 < date2
                }
            }
            
            // Calculate how many messages to remove
            let messagesToRemove = shouldCleanupByCount ? (messages.count - maxMessagesInMemory) : max(1, messages.count / 10) // Remove 10% if size-based
            let idsToRemove = Array(sortedMessageIds.prefix(messagesToRemove))
            
            // Remove messages
            for id in idsToRemove {
                messages.removeValue(forKey: id)
                removeMessageSize(messageId: id)
            }
            
            // Clean up channel message references
            for (channelId, messageIds) in channelMessages {
                let filteredIds = messageIds.filter { !idsToRemove.contains($0) }
                if filteredIds.count != messageIds.count {
                    channelMessages[channelId] = filteredIds
                }
            }
            
            // print("🧠 MEMORY: Removed \(messagesToRemove) old messages")
        }
        
        // AGGRESSIVE CHANNEL MESSAGE CLEANUP
        for (channelId, messageIds) in channelMessages {
            if messageIds.count > maxChannelMessages {
                let trimmedIds = Array(messageIds.suffix(maxChannelMessages))
                channelMessages[channelId] = trimmedIds
                // print("🧠 MEMORY: Trimmed channel \(channelId) messages from \(messageIds.count) to \(trimmedIds.count)")
            }
        }
    }
    
    // DISABLED: Smart message cleanup based on current channel and loading direction
    @MainActor
    private func smartMessageCleanup() {
        // CRITICAL FIX: Disable message cleanup to prevent black messages
        // print("🚫 MEMORY_CLEANUP: smartMessageCleanup DISABLED to prevent black messages")
        return
    }
    
    // Smart user cleanup to prevent excessive memory usage - DISABLED to prevent black messages
    @MainActor
    private func smartUserCleanup() {
        // CRITICAL FIX: Completely disable user cleanup to prevent black messages
        // print("🧠 MEMORY: User cleanup DISABLED to prevent black messages. Current users: \(users.count)")
        
        // Only log warning if we have too many users, but don't clean them up
        if users.count > maxUsersInMemory {
            // print("⚠️ MEMORY WARNING: \(users.count) users exceed limit of \(maxUsersInMemory), but cleanup is disabled")
        }
        
        return // Exit early, no cleanup
    }
    
    @MainActor
    private func cleanupMemory() {
        // CRITICAL FIX: Completely disable cleanupMemory to prevent infinite loop and black messages
        // print("🚫 MEMORY: cleanupMemory DISABLED to prevent infinite loop and black messages")
        return
    }
    
    // Smart channel cleanup to prevent excessive memory usage
    @MainActor
    private func smartChannelCleanup() {
        // FIX: Don't cleanup when in DM view or when DM list is being displayed
        if currentSelection == .dms {
            // print("🧠 MEMORY: Skipping channel cleanup - in DM view")
            return
        }
        
        // Clean up channels that haven't been accessed
        if channels.count > maxChannelsInMemory {
            // print("🧠 MEMORY: Enforcing channel limit. Current: \(channels.count), Max: \(maxChannelsInMemory)")
            
            var essentialChannelIds = Set<String>()
            
            // Keep current channel
            if case .channel(let channelId) = currentChannel {
                essentialChannelIds.insert(channelId)
            }
            
            // ALWAYS keep ALL DM and Group DM channels (NEVER remove these!)
            for channel in channels.values {
                switch channel {
                case .dm_channel:
                    essentialChannelIds.insert(channel.id)
                case .group_dm_channel:
                    essentialChannelIds.insert(channel.id)
                default:
                    break
                }
            }
            
            // Keep channels in current server only
            if case .server(let serverId) = currentSelection {
                if let server = servers[serverId] {
                    // Only keep current server's channels to free memory
                    for channelId in server.channels {
                        if essentialChannelIds.count < maxChannelsInMemory {
                            essentialChannelIds.insert(channelId)
                        }
                    }
                }
            }
            
            // Remove non-essential channels (only server channels from other servers)
            let channelsToRemove = channels.keys.filter { channelId in
                if essentialChannelIds.contains(channelId) {
                    return false
                }
                
                // Check if it's a server text channel from non-current server
                if let channel = channels[channelId] {
                    switch channel {
                    case .text_channel:
                        return true // Remove server channels that aren't essential
                    case .voice_channel:
                        return true // Remove voice channels
                    default:
                        return false // Never remove DMs
                    }
                }
                return false
            }
            
            for channelId in channelsToRemove {
                channels.removeValue(forKey: channelId)
                channelMessages.removeValue(forKey: channelId)
            }
            
            // print("🧠 MEMORY: Removed \(channelsToRemove.count) non-essential channels (kept all DMs)")
        }
        
        // Clean up empty channel message arrays for server channels only
        let emptyChannels = channelMessages.filter { channelId, messages in
            if messages.isEmpty {
                // Check if it's a DM - if so, don't remove
                if let channel = channels[channelId] {
                    switch channel {
                    case .dm_channel, .group_dm_channel:
                        return false // Never remove DM message arrays
                    default:
                        return true // Can remove server channel message arrays if empty
                    }
                }
                return true
            }
            return false
        }.map { $0.key }
        
        if emptyChannels.count > 100 {
            // print("🧠 MEMORY: Cleaning up \(emptyChannels.count) empty server channel message arrays")
            for channelId in emptyChannels {
                // Only remove if it's not current channel and not a DM
                if case .channel(let currentChannelId) = currentChannel, currentChannelId == channelId {
                    continue
                }
                channelMessages.removeValue(forKey: channelId)
            }
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
        
        // Determine if channel is active (current channel)
        let isActiveChannel: Bool
        if case .channel(let activeChannelId) = currentChannel {
            isActiveChannel = activeChannelId == channelId
        } else {
            isActiveChannel = false
        }
        
        // Use feature flag limits: 50 for active, 100 for inactive
        let maxMessagesToKeep = isActiveChannel ? 50 : 100
        
        if currentChannelMessages.count > maxMessagesToKeep {
            // UX PRESERVATION: Collect messages that must be preserved
            var messagesToPreserve = Set<String>()
            
            // 1. Preserve target message + 20 around it
            if let targetMessageId = currentTargetMessageId, 
               targetMessageId != channelId, // Ensure it's a message ID, not channel ID
               let targetIndex = currentChannelMessages.firstIndex(of: targetMessageId) {
                let startIndex = max(0, targetIndex - 20)
                let endIndex = min(currentChannelMessages.count, targetIndex + 21)
                messagesToPreserve.formUnion(currentChannelMessages[startIndex..<endIndex])
            }
            
            // 2. Preserve unread markers
            if let unread = unreads[channelId] {
                if let lastId = unread.last_id {
                    messagesToPreserve.insert(lastId)
                }
                if let mentions = unread.mentions {
                    messagesToPreserve.formUnion(mentions)
                }
            }
            
            // 3. Preserve reply context (parent messages)
            for messageId in currentChannelMessages {
                if let message = messages[messageId], let replies = message.replies, !replies.isEmpty {
                    // Add parent messages referenced in replies (replies is [String] of message IDs)
                    for replyId in replies {
                        messagesToPreserve.insert(replyId)
                    }
                }
            }
            
            // 4. Always preserve last 50 messages (or more if target/unread/replies require it)
            let lastMessages = Set(currentChannelMessages.suffix(50))
            messagesToPreserve.formUnion(lastMessages)
            
            // Build final list: preserved messages + recent messages up to limit
            var finalMessagesToKeep: [String] = []
            var seenMessages = Set<String>()
            
            // First, add preserved messages in order
            for messageId in currentChannelMessages {
                if messagesToPreserve.contains(messageId) && !seenMessages.contains(messageId) {
                    finalMessagesToKeep.append(messageId)
                    seenMessages.insert(messageId)
                }
            }
            
            // Then, add recent messages up to limit (if not already included)
            let recentMessages = currentChannelMessages.suffix(maxMessagesToKeep)
            for messageId in recentMessages {
                if !seenMessages.contains(messageId) {
                    finalMessagesToKeep.append(messageId)
                    seenMessages.insert(messageId)
                }
            }
            
            // Sort final list to maintain chronological order
            finalMessagesToKeep.sort { id1, id2 in
                guard let index1 = currentChannelMessages.firstIndex(of: id1),
                      let index2 = currentChannelMessages.firstIndex(of: id2) else {
                    return false
                }
                return index1 < index2
            }
            
            // Trim to limit if still over (prioritize preserved + recent)
            if finalMessagesToKeep.count > maxMessagesToKeep {
                // Keep preserved messages + most recent
                let preservedSet = Set(finalMessagesToKeep.filter { messagesToPreserve.contains($0) })
                let recentToKeep = finalMessagesToKeep.filter { !messagesToPreserve.contains($0) }.suffix(maxMessagesToKeep - preservedSet.count)
                finalMessagesToKeep = Array(preservedSet) + Array(recentToKeep)
                finalMessagesToKeep.sort { id1, id2 in
                    guard let index1 = currentChannelMessages.firstIndex(of: id1),
                          let index2 = currentChannelMessages.firstIndex(of: id2) else {
                        return false
                    }
                    return index1 < index2
                }
            }
            
            let messagesToRemove = Set(currentChannelMessages).subtracting(finalMessagesToKeep)
            
            // Update channel message list
            channelMessages[channelId] = finalMessagesToKeep
            
            // Remove the older messages from global messages dictionary
            for messageId in messagesToRemove {
                messages.removeValue(forKey: messageId)
                removeMessageSize(messageId: messageId)
            }
            
            // print("🧠 MEMORY: Channel \(channelId) - kept \(finalMessagesToKeep.count) messages (preserved: \(messagesToPreserve.count)), removed \(messagesToRemove.count) older messages")
            // print("🧠 MEMORY: Total messages in memory: \(messages.count)")
        } else {
            // print("🧠 MEMORY: Channel \(channelId) has \(originalMessageCount) messages (≤\(maxMessagesToKeep)), keeping all")
        }
        
        // Clean up orphaned messages (messages that don't belong to any channel anymore)
        cleanupOrphanedMessages()
        
        // Clean up users for this channel
        cleanupChannelUsers(channelId: channelId)
        
        // print("🧠 MEMORY: Channel cleanup completed for: \(channelId)")
    }
    
    /// Cleans up users that are no longer referenced by any channel's messages
    private func cleanupOrphanedUsers() {
        // Get all users referenced by any channel
        let allReferencedUsers = Set(channelUserIds.values.flatMap { $0 })
        
        // Also keep current user and friends
        var usersToKeep = allReferencedUsers
        if let currentUserId = currentUser?.id {
            usersToKeep.insert(currentUserId)
        }
        // TODO: Add friends list if available
        
        // Remove users not referenced by any channel (except current user and friends)
        let usersToRemove = users.keys.filter { !usersToKeep.contains($0) }
        for userId in usersToRemove {
            users.removeValue(forKey: userId)
        }
        
        if !usersToRemove.isEmpty {
            // print("🧠 MEMORY: Cleaned up \(usersToRemove.count) orphaned users")
        }
    }
    
    /// Cleans up users for a specific channel, keeping only those referenced by remaining messages
    private func cleanupChannelUsers(channelId: String) {
        guard let channelMessageIds = channelMessages[channelId] else {
            channelUserIds.removeValue(forKey: channelId)
            return
        }
        
        // Get users referenced by remaining messages in this channel
        var referencedUsers = Set<String>()
        for messageId in channelMessageIds {
            if let message = messages[messageId] {
                referencedUsers.insert(message.author)
                if let mentions = message.mentions {
                    referencedUsers.formUnion(mentions)
                }
            }
        }
        
        // Update channel user tracking
        channelUserIds[channelId] = referencedUsers
        
        // If channel has too many users, keep only most recent (by message count)
        if referencedUsers.count > maxUsersPerChannel {
            // Count messages per user in this channel
            var userMessageCounts: [String: Int] = [:]
            for messageId in channelMessageIds {
                if let message = messages[messageId] {
                    userMessageCounts[message.author, default: 0] += 1
                }
            }
            
            // Keep top maxUsersPerChannel users by message count
            let topUsers = userMessageCounts.sorted { $0.value > $1.value }.prefix(maxUsersPerChannel).map { $0.key }
            channelUserIds[channelId] = Set(topUsers)
        }
    }
    
    // Helper function to clean up messages that don't belong to any channel
    @MainActor
    private func cleanupOrphanedMessages() {
        let allChannelMessageIds = Set(channelMessages.values.flatMap { $0 })
        let messagesToRemove = messages.keys.filter { messageId in
            !allChannelMessageIds.contains(messageId)
        }
        
        for messageId in messagesToRemove {
            messages.removeValue(forKey: messageId)
        }
        
        if !messagesToRemove.isEmpty {
            // print("🧠 MEMORY: Cleaned up \(messagesToRemove.count) orphaned messages")
        }
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
    
    // Handle channel change and memory cleanup  
    @MainActor
    private func handleChannelChange(from previousChannelId: String?, to newChannel: ChannelSelection) {
        // Extract previous channel ID from current channel before change
        let actualPreviousChannelId: String?
        if case .channel(let channelId) = currentChannel {
            actualPreviousChannelId = channelId
        } else {
            actualPreviousChannelId = nil
        }
        
        // Extract new channel ID
        let newChannelId: String?
        if case .channel(let channelId) = newChannel {
            newChannelId = channelId
        } else {
            newChannelId = nil
        }
        
        // Clear messages from previous channel when switching channels
        if let actualPreviousChannelId = actualPreviousChannelId, actualPreviousChannelId != newChannelId {
            // print("🧠 MEMORY: Switching channels from \(actualPreviousChannelId) to \(newChannelId ?? "none")")
            clearChannelMessages(channelId: actualPreviousChannelId)
            
            // CRITICAL: Clear target message ID when switching channels to prevent re-targeting
            print("🎯 CHANNEL_CHANGE: Clearing currentTargetMessageId when switching channels")
            currentTargetMessageId = nil
        }
        
        // Update previous channel ID for next time
        self.previousChannelId = newChannelId
    }
    
    // Handle path changes to detect when leaving channel view
    @MainActor
    private func handlePathChange(oldPath: [NavigationDestination], newPath: [NavigationDestination]) {
        let wasInChannelView = oldPath.contains { destination in
            if case .maybeChannelView = destination {
                return true
            }
            return false
        }
        
        let isInChannelView = newPath.contains { destination in
            if case .maybeChannelView = destination {
                return true
            }
            return false
        }
        
        // Clear messages when leaving channel view to free memory
        if wasInChannelView && !isInChannelView {
            if case .channel(let channelId) = currentChannel {
                // print("🧠 MEMORY: Left channel view, clearing messages for channel: \(channelId) to free memory")
                clearChannelMessages(channelId: channelId)
            }
        }
        
        // If we're entering channel view, check if we need to show loading
        if !wasInChannelView && isInChannelView {
            if case .channel(let channelId) = currentChannel {
                let hasMessages = (channelMessages[channelId]?.count ?? 0) > 0
                if !hasMessages {
                    // print("🧠 LOADING: Entering channel with no messages, showing loading state")
                    setChannelLoadingState(isLoading: true)
                }
            }
        }
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
        
        self.baseEmojis = loadEmojis()
        
        // Load any pending notification token
        self.loadPendingNotificationToken()
        
        // MEMORY MANAGEMENT: Register feature flag defaults (CRITICAL: prevents false defaults)
        registerFeatureFlagDefaults()
        
        // MEMORY MANAGEMENT: Load channel access times from persistence
        loadChannelAccessTimes()
        
        // MEMORY MANAGEMENT: Load guardrail state from UserDefaults (for consistency across reinitializations)
        reducedFetchLimit = UserDefaults.standard.object(forKey: "reducedFetchLimit") as? Bool ?? false
        
        // MEMORY MANAGEMENT: Start periodic memory cleanup
        startPeriodicMemoryCleanup()
        
        // Cache schema migration check (backup check, primary check is in MessageCacheManager.init)
        // MessageCacheManager.shared will check schema on first access
        
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
    
    /// Preloads messages for important channels when the app starts or WebSocket reconnects
    @MainActor
    private func preloadImportantChannels() async {
        // Wait a bit for the WebSocket to fully authenticate
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Only preload if user is authenticated and WebSocket is connected
        guard sessionToken != nil, currentUser != nil, state == .connected else {
            return
        }
        
        // SMART PRELOADING: Get channels from user's current server and DMs
        var channelsToPreload: [String] = []
        
        // Add current server's channels
        if case .server(let serverId) = currentSelection,
           let server = servers[serverId] {
            // Add first few text channels from current server
            let textChannels = server.channels.compactMap { channelId in
                if case .text_channel(_) = channels[channelId] {
                    return channelId
                }
                return nil
            }.prefix(3) // Preload first 3 text channels
            
            channelsToPreload.append(contentsOf: textChannels)
        }
        
        // Add active DM channels
        let activeDMs = dms.compactMap { channel -> String? in
            switch channel {
            case .dm_channel(let dm):
                return dm.active ? dm.id : nil
            case .group_dm_channel(let group):
                return group.id
            default:
                return nil
            }
        }.prefix(5) // Preload first 5 DMs
        
        channelsToPreload.append(contentsOf: activeDMs)
        
        // Always include the specific channel mentioned by user
        let specificChannelId = "01J7QTT66242A7Q26A2FH5TD48"
        if !channelsToPreload.contains(specificChannelId) {
            channelsToPreload.append(specificChannelId)
        }
        
        // Preload channels in parallel for better performance
        await withTaskGroup(of: Void.self) { group in
            for channelId in channelsToPreload {
                group.addTask {
                    await self.preloadChannel(channelId: channelId)
        }
            }
        }
    }
    
    /// Public method to manually trigger preload for important channels
    @MainActor
    public func triggerPreloadImportantChannels() async {
        await preloadImportantChannels()
    }
    
    /// Public method to preload a specific channel by ID
    @MainActor
    public func preloadSpecificChannel(channelId: String) async {
        await preloadChannel(channelId: channelId)
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
    private func preloadChannel(channelId: String) async {
        // Check if channel has already been preloaded
        if preloadedChannels.contains(channelId) {
            return
        }
        
        // Check if channel exists in our channels dictionary
        guard let channel = channels[channelId] else {
            return
        }
        
        // Check if we already have messages for this channel
        if let existingMessages = channelMessages[channelId], !existingMessages.isEmpty {
            preloadedChannels.insert(channelId) // Mark as preloaded since it has messages
            return
        }
        
        do {
            // Get server ID if this is a server channel
            let serverId = channel.server
            
            // SMART LIMIT: Use 10 for specific channel in specific server, otherwise use effective fetch limit
            let baseLimit = (channelId == "01J7QTT66242A7Q26A2FH5TD48" && serverId == "01J544PT4T3WQBVBSDK3TBFZW7") ? 10 : getEffectiveFetchLimit()
            let messageLimit = baseLimit
            
            // Fetch messages for this channel
            let result = try await http.fetchHistory(
                channel: channelId,
                limit: messageLimit, // Uses getEffectiveFetchLimit() for guardrail support
                sort: "Latest",
                server: serverId,
                include_users: true
            ).get()
            
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
            
            // Mark channel as preloaded
            preloadedChannels.insert(channelId)
            
        } catch {
            // Silent failure for preload
        }
    }
    
    // MEMORY MANAGEMENT: Periodic cleanup timer
    private var memoryCleanupTimer: Timer?
    private var memoryMonitorTimer: Timer?
    
    /// Registers feature flag defaults to prevent false defaults when unset.
    /// CRITICAL: UserDefaults.standard.bool(forKey:) returns false when unset, which would keep aggressive mode OFF unintentionally.
    private func registerFeatureFlagDefaults() {
        // Register defaults if not already set (CRITICAL: prevents false defaults)
        if UserDefaults.standard.object(forKey: "enableAggressiveMemoryManagement") == nil {
            UserDefaults.standard.set(true, forKey: "enableAggressiveMemoryManagement") // Default: true after rollout
        }
        if UserDefaults.standard.object(forKey: "aggressiveMessageLimit") == nil {
            UserDefaults.standard.set(50, forKey: "aggressiveMessageLimit") // Default: 50
        }
        if UserDefaults.standard.object(forKey: "aggressiveUserLimit") == nil {
            UserDefaults.standard.set(1000, forKey: "aggressiveUserLimit") // Default: 1000
        }
    }
    
    // MARK: - Channel Access Tracking
    
    /// Loads channel access times from UserDefaults persistence
    private func loadChannelAccessTimes() {
        if let stored = UserDefaults.standard.dictionary(forKey: "channelLastAccessTimes") as? [String: TimeInterval] {
            channelLastAccessTime = stored.mapValues { Date(timeIntervalSince1970: $0) }
        } else {
            channelLastAccessTime = [:]
        }
    }
    
    /// Saves channel access times to UserDefaults persistence
    private func saveChannelAccessTimes() {
        let timestamps = channelLastAccessTime.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: "channelLastAccessTimes")
    }
    
    /// Updates the access time for a channel when it's viewed
    private func updateChannelAccessTime(channelId: String) {
        channelLastAccessTime[channelId] = Date()
        // Debounce saves to avoid excessive UserDefaults writes
        Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
            await MainActor.run {
                self?.saveChannelAccessTimes()
            }
        }
    }
    
    /// Checks if a channel is currently active (not eligible for aggressive cleanup)
    private func isChannelActive(channelId: String) -> Bool {
        // Channel is active if it's the current channel
        if case .channel(let currentId) = currentChannel, currentId == channelId {
            return true
        }
        
        // Channel is active if app is in split view and channel is visible
        if isAppInSplitView {
            // In split view, assume all channels might be visible
            return true
        }
        
        // Channel is active if app is performing background fetch for this channel
        if isAppInBackgroundFetch {
            // During background fetch, assume channels being fetched are active
            return true
        }
        
        return false
    }
    
    /// Gets the time since a channel was last accessed
    private func timeSinceChannelAccess(channelId: String) -> TimeInterval? {
        guard let accessTime = channelLastAccessTime[channelId] else {
            return nil
        }
        return Date().timeIntervalSince(accessTime)
    }
    
    private func startPeriodicMemoryCleanup() {
        // CRITICAL: Always invalidate existing timer before creating new one
        memoryCleanupTimer?.invalidate()
        
        // Clean up memory every 60 seconds (reduced from 15s to reduce CPU/battery impact)
        memoryCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // All cleanup work must be off-main-thread
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                
                // Check thresholds off-main-thread
                // MEMORY OPTIMIZATION: Use same thresholds as enforceMemoryLimits (1000 messages, 50MB)
                let messageCount = await MainActor.run { self.messages.count }
                let totalSize = await MainActor.run { self.totalMessageMemorySize }
                let currentMemoryMB = await MainActor.run { self.getCurrentMemoryUsage() }
                
                // Trigger cleanup if over message/size thresholds OR if memory is high (>700MB)
                let shouldCleanup = messageCount > 1000 || totalSize > 50 * 1024 * 1024 || currentMemoryMB > 700
                
                if shouldCleanup {
                    // Perform cleanup on main actor (for dictionary access)
                    await MainActor.run {
                        self.enforceMemoryLimits()
                        self.cleanupOrphanedUsers()
                    }
                }
            }
        }
        
        // Start memory monitoring
        startMemoryMonitoring()
    }
    
    /// Cancels the memory cleanup timer (called on background)
    @MainActor
    func cancelMemoryCleanupTimer() {
        memoryCleanupTimer?.invalidate()
        memoryCleanupTimer = nil
    }
    
    /// Restarts the memory cleanup timer (called on foreground)
    @MainActor
    func restartMemoryCleanupTimer() {
        startPeriodicMemoryCleanup()
    }
    
    // MARK: - Background/Foreground Handling
    
    /// Sets the app background state flag
    @MainActor
    func setAppInBackground(_ inBackground: Bool) {
        isAppInBackground = inBackground
    }
    
    /// Performs aggressive memory cleanup when app enters background
    @MainActor
    func performBackgroundMemoryCleanup() {
        // Conditional cache clearing: Only clear if RAM usage > 500MB threshold
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let memoryUsage = await MainActor.run { self.checkMemoryUsage() }
            
            if memoryUsage.usedMB > 500 {
                // Above threshold: Clear memory cache to free RAM
                await MainActor.run {
                    #if canImport(Kingfisher)
                    ImageCache.default.clearMemoryCache()
                    print("🧹 BACKGROUND: Cleared image cache (RAM > 500MB)")
                    #endif
                }
            } else {
                // Below threshold: Keep cache to prevent re-decoding/re-downloads on foreground
                print("💾 BACKGROUND: Preserving image cache (RAM < 500MB)")
            }
            
            // Aggressive trimming: Reduce inactive channel messages to 10
            await MainActor.run {
                self.aggressiveTrimInactiveChannels(targetMessages: 10)
            }
        }
    }
    
    /// Restores normal memory limits when app enters foreground
    @MainActor
    func restoreForegroundLimits() {
        // Limits are restored automatically via feature flags
        // This method is a placeholder for any additional restoration logic
        print("✅ FOREGROUND: Memory limits restored")
    }
    
    /// Aggressively trims inactive channels to target message count
    @MainActor
    private func aggressiveTrimInactiveChannels(targetMessages: Int) {
        let currentChannelId: String?
        if case .channel(let id) = currentChannel {
            currentChannelId = id
        } else {
            currentChannelId = nil
        }
        
        for (channelId, messageIds) in channelMessages {
            // Skip current channel
            if channelId == currentChannelId {
                continue
            }
            
            // Skip active channels
            if isChannelActive(channelId: channelId) {
                continue
            }
            
            // Check if channel hasn't been accessed recently
            if let timeSinceAccess = timeSinceChannelAccess(channelId: channelId),
               timeSinceAccess > 120 { // 2 minutes
                // Trim to target message count, preserving UX-critical messages
                if messageIds.count > targetMessages {
                    let messagesToKeep = preserveUXCriticalMessages(
                        channelId: channelId,
                        messageIds: messageIds,
                        targetCount: targetMessages
                    )
                    
                    // Remove messages not in keep list
                    let messagesToRemove = Set(messageIds).subtracting(messagesToKeep)
                    for messageId in messagesToRemove {
                        messages.removeValue(forKey: messageId)
                        removeMessageSize(messageId: messageId)
                    }
                    
                    channelMessages[channelId] = Array(messagesToKeep)
                    print("🧹 BACKGROUND: Trimmed channel \(channelId) from \(messageIds.count) to \(messagesToKeep.count) messages")
                }
            }
        }
    }
    
    /// Preserves UX-critical messages (target, unread, reply context)
    private func preserveUXCriticalMessages(channelId: String, messageIds: [String], targetCount: Int) -> Set<String> {
        var messagesToKeep = Set<String>()
        
        // Always keep last N messages
        let recentMessages = Array(messageIds.suffix(targetCount))
        messagesToKeep.formUnion(recentMessages)
        
        // Preserve target message + 20 messages around it
        if let targetId = currentTargetMessageId,
           let targetMessage = messages[targetId],
           targetMessage.channel == channelId {
            if let targetIndex = messageIds.firstIndex(of: targetId) {
                let startIndex = max(0, targetIndex - 10)
                let endIndex = min(messageIds.count, targetIndex + 11)
                messagesToKeep.formUnion(messageIds[startIndex..<endIndex])
            }
        }
        
        // Preserve unread markers
        if let unread = unreads[channelId] {
            if let lastId = unread.last_id, messages[lastId] != nil {
                messagesToKeep.insert(lastId)
                // Keep 10 messages around unread marker
                if let unreadIndex = messageIds.firstIndex(of: lastId) {
                    let startIndex = max(0, unreadIndex - 5)
                    let endIndex = min(messageIds.count, unreadIndex + 6)
                    messagesToKeep.formUnion(messageIds[startIndex..<endIndex])
                }
            }
            // Preserve mention messages
            if let mentions = unread.mentions {
                for mentionId in mentions {
                    if messages[mentionId] != nil {
                        messagesToKeep.insert(mentionId)
                    }
                }
            }
        }
        
        // Preserve reply context
        for messageId in messageIds {
            if let message = messages[messageId],
               let replies = message.replies,
               !replies.isEmpty {
                // Keep parent messages referenced in replies
                for replyId in replies {
                    if messages[replyId] != nil {
                        messagesToKeep.insert(replyId)
                    }
                }
                // Keep the message with replies
                messagesToKeep.insert(messageId)
            }
        }
        
        return messagesToKeep
    }
    
    // MEMORY MONITORING: Track memory usage
    private func startMemoryMonitoring() {
        memoryMonitorTimer?.invalidate()
        
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor [weak self] in
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
            
            // Check memory usage with thresholds and guardrails
            let memoryCheck = self.checkMemoryUsage()
            
            if memoryCheck.critical {
                // Activate guardrails when critical threshold is hit
                self.activateMemoryGuardrails()
            }
            
            // Warning if memory usage is high (only for non-DM views)
            if memoryUsage > 1500 { // Increased threshold to 1.5GB for better performance
                // print("⚠️ MEMORY WARNING: High memory usage detected!")
                
                // Force immediate aggressive cleanup
                self.enforceMemoryLimits()
                self.smartUserCleanup()
                self.smartChannelCleanup()
            }
            }
        }
    }
    
    private func getCurrentMemoryUsage() -> Double {
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
    
    // MARK: - Memory Monitoring with Thresholds and Guardrails
    
    /// Cached memory usage result (5 second cache to avoid frequent system calls)
    private var cachedMemoryUsage: (usedMB: Double, timestamp: Date)?
    private let memoryUsageCacheInterval: TimeInterval = 5.0
    
    /// Memory monitoring guardrail flags
    private var disableImagePreviews: Bool = false
    private var reducedFetchLimit: Bool = false
    private var memoryWarningRestoreTimer: Timer?
    
    /// Checks memory usage with thresholds and returns warning/critical status
    /// Runs off-main-thread to avoid blocking UI
    func checkMemoryUsage() -> (usedMB: Double, warning: Bool, critical: Bool) {
        // Check cache first
        if let cached = cachedMemoryUsage,
           Date().timeIntervalSince(cached.timestamp) < memoryUsageCacheInterval {
            let usedMB = cached.usedMB
            let warning = usedMB > 600 || messages.count > 1800 || Double(totalMessageMemorySize) / 1024.0 / 1024.0 > 90 || users.count > 900
            let critical = usedMB > 800 || messages.count > 1900 || Double(totalMessageMemorySize) / 1024.0 / 1024.0 > 95 || users.count > 950
            return (usedMB, warning, critical)
        }
        
        // Calculate fresh memory usage
        let usedMB = getCurrentMemoryUsage()
        let messageSizeMB = Double(totalMessageMemorySize) / 1024.0 / 1024.0
        
        // Update cache
        cachedMemoryUsage = (usedMB, Date())
        
        // Thresholds
        let warning = usedMB > 600 || messages.count > 1800 || messageSizeMB > 90 || users.count > 900
        let critical = usedMB > 800 || messages.count > 1900 || messageSizeMB > 95 || users.count > 950
        
        return (usedMB, warning, critical)
    }
    
    /// Gets the effective fetch limit based on guardrails
    /// Nonisolated to allow calling from any context
    nonisolated func getEffectiveFetchLimit() -> Int {
        // Load from UserDefaults to ensure consistency across reinitializations
        if UserDefaults.standard.object(forKey: "reducedFetchLimit") as? Bool == true {
            return 25 // Guardrail: reduced limit
        }
        // Access feature flag directly from UserDefaults (nonisolated)
        let enableAggressive = UserDefaults.standard.object(forKey: "enableAggressiveMemoryManagement") as? Bool ?? true
        return enableAggressive ? 50 : 100 // Normal limit based on feature flag
    }
    
    /// Activates guardrails when critical threshold is hit
    @MainActor
    private func activateMemoryGuardrails() {
        guard !disableImagePreviews && !reducedFetchLimit else { return } // Already activated
        
        print("🚨 MEMORY GUARDRAILS: Activating emergency measures")
        
        disableImagePreviews = true
        reducedFetchLimit = true
        
        // Persist guardrail state
        UserDefaults.standard.set(true, forKey: "reducedFetchLimit")
        
        // Aggressive cleanup: Reduce inactive channel messages to 10
        aggressiveTrimInactiveChannels(targetMessages: 10)
        
        // Log critical memory state with per-channel attribution
        let attribution = getChannelMemoryAttribution()
        print("🚨 MEMORY CRITICAL: Per-channel attribution:")
        for (channelId, cost) in attribution {
            print("  Channel \(channelId): \(cost.messageCount) msgs, \(cost.userCount) users, \(String(format: "%.2f", Double(cost.totalBytes) / 1024.0 / 1024.0))MB")
        }
        
        // Schedule restore after 60 seconds of normal memory
        memoryWarningRestoreTimer?.invalidate()
        memoryWarningRestoreTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreMemoryGuardrails()
            }
        }
    }
    
    /// Restores guardrails after memory pressure subsides
    @MainActor
    private func restoreMemoryGuardrails() {
        let memoryUsage = checkMemoryUsage()
        
        // Only restore if memory is back to normal
        if !memoryUsage.critical && !memoryUsage.warning {
            print("✅ MEMORY GUARDRAILS: Restoring normal limits")
            disableImagePreviews = false
            reducedFetchLimit = false
            UserDefaults.standard.set(false, forKey: "reducedFetchLimit")
        } else {
            // Schedule another check in 60 seconds
            memoryWarningRestoreTimer?.invalidate()
            memoryWarningRestoreTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.restoreMemoryGuardrails()
                }
            }
        }
    }
    
    // MARK: - Memory Instrumentation
    
    /// Updates memory costs for a channel when messages/users are added/removed
    private func updateChannelMemoryCost(channelId: String) {
        let messageIds = channelMessages[channelId] ?? []
        var messageCount = 0
        var messageSizeBytes = 0
        var uniqueUsers = Set<String>()
        
        for messageId in messageIds {
            if let message = messages[messageId] {
                messageCount += 1
                messageSizeBytes += messageSizes[messageId] ?? 0
                uniqueUsers.insert(message.author)
                if let mentions = message.mentions {
                    uniqueUsers.formUnion(mentions)
                }
            }
        }
        
        // Video cache size estimation (thumbnails + durations)
        // Note: This is an estimate since VideoPlayerView and AudioPlayerManager use static caches
        let videoCacheSizeBytes = 0 // Per-channel attribution not feasible without refactoring
        
        channelMemoryCosts[channelId] = ChannelMemoryCost(
            messageCount: messageCount,
            messageSizeBytes: messageSizeBytes,
            userCount: uniqueUsers.count,
            imageCacheSizeBytes: 0, // Image cache is global, not per-channel
            videoCacheSizeBytes: videoCacheSizeBytes
        )
    }
    
    /// Logs memory costs per channel and total memory usage
    func logChannelMemoryCosts() {
        // Update all channel costs
        for channelId in channelMessages.keys {
            updateChannelMemoryCost(channelId: channelId)
        }
        
        // Calculate totals
        var totalMessages = 0
        var totalMessageSize = 0
        var totalUsers = 0
        var totalVideoCache = 0
        
        for cost in channelMemoryCosts.values {
            totalMessages += cost.messageCount
            totalMessageSize += cost.messageSizeBytes
            totalUsers += cost.userCount
            totalVideoCache += cost.videoCacheSizeBytes
        }
        
        // Get total image cache size (global, not per-channel)
        #if canImport(Kingfisher)
        let totalImageCacheMB = Double(ImageCache.default.memoryStorage.config.totalCostLimit) / 1024.0 / 1024.0
        #else
        let totalImageCacheMB = 0.0
        #endif
        
        print("📊 MEMORY INSTRUMENTATION:")
        print("  Total Messages: \(totalMessages) (\(String(format: "%.2f", Double(totalMessageSize) / 1024.0 / 1024.0))MB)")
        print("  Total Users: \(totalUsers)")
        print("  Total Image Cache: \(String(format: "%.2f", totalImageCacheMB))MB (shared across all channels)")
        print("  Total Video Cache: \(String(format: "%.2f", Double(totalVideoCache) / 1024.0 / 1024.0))MB")
        print("  Per-Channel Breakdown:")
        for (channelId, cost) in channelMemoryCosts.sorted(by: { $0.key < $1.key }) {
            print("    Channel \(channelId):")
            print("      Messages: \(cost.messageCount) (\(String(format: "%.2f", Double(cost.messageSizeBytes) / 1024.0 / 1024.0))MB)")
            print("      Users: \(cost.userCount)")
            print("      Video Cache: \(String(format: "%.2f", Double(cost.videoCacheSizeBytes) / 1024.0 / 1024.0))MB")
        }
    }
    
    /// Returns current memory costs per channel (without image cache per-channel)
    func getChannelMemoryAttribution() -> [String: ChannelMemoryCost] {
        // Update all channel costs before returning
        for channelId in channelMessages.keys {
            updateChannelMemoryCost(channelId: channelId)
        }
        return channelMemoryCosts
    }
    
    // MARK: - Memory Pressure Handling
    
    /// Handles system memory warnings with temporary limits that restore
    @MainActor
    func didReceiveMemoryWarning() {
        print("🚨 MEMORY WARNING: System memory pressure detected")
        
        // Clear memory cache (only on memory warnings, not on channel exit)
        #if canImport(Kingfisher)
        ImageCache.default.clearMemoryCache()
        print("🧹 MEMORY WARNING: Cleared image memory cache")
        #endif
        
        // Clear video caches
        VideoPlayerView.clearCachesOnMemoryWarning()
        AudioPlayerManager.shared.clearCachesOnMemoryWarning()
        
        // Reduce current channel messages to 30 (from 50), preserving UX-critical messages
        if case .channel(let channelId) = currentChannel,
           let messageIds = channelMessages[channelId],
           messageIds.count > 30 {
            let messagesToKeep = preserveUXCriticalMessages(
                channelId: channelId,
                messageIds: messageIds,
                targetCount: 30
            )
            
            let messagesToRemove = Set(messageIds).subtracting(messagesToKeep)
            for messageId in messagesToRemove {
                messages.removeValue(forKey: messageId)
                removeMessageSize(messageId: messageId)
            }
            
            channelMessages[channelId] = Array(messagesToKeep)
            print("🧹 MEMORY WARNING: Reduced current channel from \(messageIds.count) to \(messagesToKeep.count) messages")
        }
        
        // Clear all inactive channel messages (keep only 20 per channel), preserving UX-critical messages
        aggressiveTrimInactiveChannels(targetMessages: 20)
        
        // Set temporary memory limit flag
        // Note: This is handled via guardrails now, but keeping for compatibility
        activateMemoryGuardrails()
        
        // Restore path: After 30 seconds of no memory warnings, restore normal limits
        memoryWarningRestoreTimer?.invalidate()
        memoryWarningRestoreTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreMemoryGuardrails()
            }
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
    
    /// INSTANT cleanup for a specific channel when leaving it - NO DELAYS
    @MainActor
    func cleanupChannelFromMemory(channelId: String, preserveForNavigation: Bool = false) {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⚡ VIEWSTATE_INSTANT_CLEANUP: Starting IMMEDIATE cleanup for channel \(channelId)")
        
        let initialMessageCount = messages.count
        let initialUserCount = users.count
        let channelMessageCount = channelMessages[channelId]?.count ?? 0
        
        // 1. IMMEDIATE: Clear channel messages list
        channelMessages.removeValue(forKey: channelId)
        
        // 2. IMMEDIATE: Remove all message objects for this channel
        let messagesToRemove = messages.keys.filter { messageId in
            if let message = messages[messageId] {
                return message.channel == channelId
            }
            return false
        }
        
        for messageId in messagesToRemove {
            messages.removeValue(forKey: messageId)
        }
        
        // 3. IMMEDIATE: Clear all related data
        currentlyTyping.removeValue(forKey: channelId)
        preloadedChannels.remove(channelId)
        atTopOfChannel.remove(channelId)
        
        // 4. IMMEDIATE: Clean up users if not preserving for navigation
        if !preserveForNavigation {
            cleanupUnusedUsersInstant(excludingChannelId: channelId)
        }
        
        // 5. IMMEDIATE: Force garbage collection
        _ = messages.count + users.count + channelMessages.count
        
        let finalMessageCount = messages.count
        let finalUserCount = users.count
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        
        print("⚡ VIEWSTATE_INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms")
        print("⚡ FREED: \(initialMessageCount - finalMessageCount) messages, \(initialUserCount - finalUserCount) users, \(channelMessageCount) channel messages")
    }
    
    /// INSTANT cleanup of unused users - NO DELAYS
    @MainActor
    private func cleanupUnusedUsersInstant(excludingChannelId: String) {
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
    
    /// Clean up users that are no longer needed after leaving a channel
    @MainActor
    private func cleanupUnusedUsers(excludingChannelId: String) {
        print("👥 USER_CLEANUP: Starting cleanup of unused users")
        
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
        
        // Remove users that are no longer needed
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
        print("👥 USER_CLEANUP: Removed \(usersToRemove.count) unused users (\(initialUserCount) -> \(finalUserCount))")
    }
    
    /// INSTANT force memory cleanup - IMMEDIATE execution
    @MainActor
    func forceMemoryCleanup() {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⚡ FORCE_INSTANT_CLEANUP: Starting IMMEDIATE memory cleanup")
        
        let initialStats = (
            messages: messages.count,
            users: users.count,
            channels: channelMessages.count
        )
        
        // 1. IMMEDIATE: Enforce message limits aggressively
        if messages.count > maxMessagesInMemory {
            let sortedMessageIds = messages.keys.sorted { id1, id2 in
                let date1 = createdAt(id: id1)
                let date2 = createdAt(id: id2)
                return date1 < date2
            }
            
            let messagesToRemove = messages.count - maxMessagesInMemory
            let idsToRemove = Array(sortedMessageIds.prefix(messagesToRemove))
            
            for id in idsToRemove {
                messages.removeValue(forKey: id)
            }
            
            // Clean up channel message references
            for (channelId, messageIds) in channelMessages {
                let filteredIds = messageIds.filter { !idsToRemove.contains($0) }
                channelMessages[channelId] = filteredIds
            }
        }
        
        // 2. IMMEDIATE: Enforce user limits
        if users.count > maxUsersInMemory {
            cleanupUnusedUsersInstant(excludingChannelId: "")
        }
        
        // 3. IMMEDIATE: Clean up empty channel message arrays
        for (channelId, messageIds) in channelMessages {
            if messageIds.isEmpty {
                channelMessages.removeValue(forKey: channelId)
            }
        }
        
        // 4. IMMEDIATE: Force garbage collection
        _ = messages.count + users.count + channelMessages.count
        
        let finalStats = (
            messages: messages.count,
            users: users.count,
            channels: channelMessages.count
        )
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        
        print("⚡ FORCE_INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms")
        print("   Messages: \(initialStats.messages) -> \(finalStats.messages)")
        print("   Users: \(initialStats.users) -> \(finalStats.users)")
        print("   Channels: \(initialStats.channels) -> \(finalStats.channels)")
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
    
    func signIn(mfa_ticket: String, mfa_response: [String: String], callback: @escaping((LoginState) -> ())) async {
        let body = ["mfa_ticket": mfa_ticket, "mfa_response": mfa_response, "friendly_name": "Revolt iOS"] as [String : Any]
        
        await innerSignIn(body, callback)
    }
    
    func signIn(email: String, password: String, callback: @escaping((LoginState) -> ())) async {
        let body = ["email": email, "password":  password, "friendly_name": "Revolt IOS"]
        
        await innerSignIn(body, callback)
    }
    
    private func innerSignIn(_ body: [String: Any], _ callback: @escaping((LoginState) -> ())) async {
        AF.request("\(http.baseURL)/auth/session/login", method: .post, parameters: body, encoding: JSONEncoding.default)
            .responseData { response in
                
                switch response.result {
                case .success(let data):
                    if [401, 403, 500].contains(response.response!.statusCode) {
                        return callback(.Invalid)
                    }
                    if let result = try? JSONDecoder().decode(LoginResponse.self, from: data){
                        switch result {
                        case .Success(let success):
                            Task {
                                self.isOnboarding = true
                                self.currentSessionId = success._id
                                self.sessionToken = success.token
                                self.http.token = success.token
                                
                                await self.promptForNotifications()
                                
                                // If we already have a device notification token, try to upload it
                                if let existingToken = self.deviceNotificationToken {
                                    // print("📱 LOGIN_SUCCESS: Found existing device token, uploading...")
                                    Task {
                                        let response = await self.http.uploadNotificationToken(token: existingToken)
                                        switch response {
                                            case .success:
                                                print("✅ LOGIN_SUCCESS: Successfully uploaded existing token")
                                            case .failure(let error):
                                                print("❌ LOGIN_SUCCESS: Failed to upload existing token: \(error)")
                                                self.storePendingNotificationToken(existingToken)
                                        }
                                    }
                                }
                                
                                do {
                                    let onboardingState = try await self.http.checkOnboarding().get()
                                    if onboardingState.onboarding {
                                        self.isOnboarding = true
                                        callback(.Onboarding)
                                    } else {
                                        self.isOnboarding = false
                                        callback(.Success)
                                        self.state = .connecting
                                    }
                                } catch {
                                    self.isOnboarding = false
                                    self.state = .connecting
                                    return callback(.Success) // if the onboard check dies, just try to go for it
                                }
                            }
                            
                        case .Mfa(let mfa):
                            return callback(.Mfa(ticket: mfa.ticket, methods: mfa.allowed_methods))
                            
                        case .Disabled:
                            return callback(.Disabled)
                        }
                    } else {
                        return callback(.Invalid)
                    }
                    
                case .failure(_):
                    ()
                }
            }
    }
    
    
    
    /// A successful result here means pending (the session has been destroyed but the client still has data cached)
    func signOut(afterRemoveSession : Bool = false) async -> Result<(), UserStateError>  {
        
        if !afterRemoveSession {
            let status = try? await http.signout().get()
            guard let status = status else { return .failure(.signOutError)}
        }
        
        self.ws?.stop()
        /*withAnimation {
         state = .signedOut
         }*/
        // IMPORTANT: do not destroy the cache/session here. It'll cause the app to crash before it can transition to the welcome screen.
        // The cache is destroyed in RevoltApp.swift:ApplicationSwitcher
        
        // MEMORY MANAGEMENT: Teardown cleanup timer on logout
        memoryCleanupTimer?.invalidate()
        memoryCleanupTimer = nil
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
        
        // Clear message cache on sign-out
        MessageCacheManager.shared.clearAllCaches()
        
        state = .signedOut
        return .success(())
    }
    
    
    /// A workaround for the UserSettingStore finding out we're not authenticated, since not a main actor.
    func setSignedOutState() {
        withAnimation {
            state = .signedOut
        }
    }
    
    func destroyCache() {
        // In future this'll need to delete files too
        path = []
        
        // MEMORY MANAGEMENT: Stop cleanup timer
        memoryCleanupTimer?.invalidate()
        memoryCleanupTimer = nil
        
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
        
        // Cancel all pending saves
        for workItem in saveWorkItems.values {
            workItem.cancel()
        }
        saveWorkItems.removeAll()
        
        users.removeAll()
        servers.removeAll()
        channels.removeAll()
        messages.removeAll()
        members.removeAll()
        emojis.removeAll()
        dms.removeAll()
        currentlyTyping.removeAll()
        channelMessages.removeAll()
        preloadedChannels.removeAll()
        
        currentUser = nil
        currentSelection = .discover
        currentChannel = .home
        currentSessionId = nil
        
        userSettingsStore.isLoggingOut()
        self.ws = nil
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
    
    func queueMessage(channel: String, replies: [Reply], content: String, attachments: [(Data, String)]) async {
        var queue = self.queuedMessages[channel]
        
        if queue == nil {
            queue = []
            self.queuedMessages[channel] = queue
        }
        
        let nonce = UUID().uuidString
        
        let r: [Revolt.ApiReply] = replies.map { reply in
            Revolt.ApiReply(id: reply.message.id, mention: reply.mention)
        }
        
        queue?.append(QueuedMessage(nonce: nonce, replies: r, content: content, author: currentUser?.id ?? "", channel: channel, timestamp: Date(), hasAttachments: !attachments.isEmpty, attachmentData: attachments))
        
        let _ = await http.sendMessage(channel: channel, replies: r, content: content, attachments: attachments, nonce: nonce)
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
    
    private func processEvent(_ event: WsMessage) async {
        switch event {
        case .ready(let event):
            // print("🚀 VIEWSTATE: Processing READY event")
            // print("   - Users: \(event.users.count)")
            // print("   - Servers: \(event.servers.count)")
            // print("   - Channels: \(event.channels.count)")
            // print("   - Members: \(event.members.count)")
            // print("   - Emojis: \(event.emojis.count)")
            
            // CRITICAL FIX: Preserve current channel and selection during ready event
            let savedCurrentChannel = currentChannel
            let savedCurrentSelection = currentSelection
            // print("💾 READY: Saving current state - channel: \(savedCurrentChannel), selection: \(savedCurrentSelection)")
            
            // CRITICAL FIX: Don't clear servers/channels/users completely - merge with existing data
            // print("🔄 READY: Merging servers with existing data (current: \(servers.count), incoming: \(event.servers.count))")
            
            // Only clear messages as they should be fresh from server
            messages.removeAll()
            channelMessages.removeAll()
            
            // For users, channels, and servers: merge instead of clearing completely
            // This preserves any data loaded from UserDefaults
            // print("🔄 READY: Preserving existing servers/channels/users, will merge with server data")
            
            // MEMORY FIX: Extract only needed data and process immediately
            // This allows the large event object to be released from memory
            let neededData = extractNeededDataFromReadyEvent(event)
            
            // Process the extracted data
            await processReadyData(neededData)
            
            // CRITICAL FIX: Restore saved state after ready event processing
            // print("🔄 READY: Restoring saved state - channel: \(savedCurrentChannel), selection: \(savedCurrentSelection)")
            currentChannel = savedCurrentChannel
            currentSelection = savedCurrentSelection
            
            // If the saved channel is from a server, make sure that server's channels are loaded
            if case .channel(let channelId) = savedCurrentChannel {
                if let restoredChannel = allEventChannels[channelId] {
                    // Make sure the channel is in active channels
                    channels[channelId] = restoredChannel
                    
                    if let serverId = restoredChannel.server {
                        // Make sure we're in the right selection and server channels are loaded
                        if savedCurrentSelection != .server(serverId) {
                            // print("🔄 READY: Correcting selection to server \(serverId) for channel \(channelId)")
                            currentSelection = .server(serverId)
                        }
                        loadServerChannels(serverId: serverId)
                    }
                    // print("✅ READY: Successfully restored channel \(channelId)")
                } else {
                    // print("⚠️ READY: Could not restore channel \(channelId) - not found in stored channels")
                }
            }
            
            // CONDITIONAL: Only preload after Ready event if automatic preloading is enabled
            if self.enableAutomaticPreloading {
                // PRELOAD: Trigger preload of important channels after Ready event
                Task {
                    await self.preloadImportantChannels()
                }
            }
            
            // CLEANUP: Clean up stale unreads after Ready event
            // This ensures that unreads for deleted channels are removed after server sync
            Task {
                await MainActor.run {
                    self.cleanupStaleUnreads()
                }
            }

        case .message(let m):
            // print("📥 VIEWSTATE: Processing new message - id: \(m.id), channel: \(m.channel)")
            // print("📥 VIEWSTATE: Current messages count BEFORE: \(messages.count)")
            
            if let user = m.user {
                // CRITICAL FIX: Always add/update message authors to prevent black messages
                users[user.id] = user
                // CRITICAL FIX: Also store in allEventUsers for permanent access
                allEventUsers[user.id] = user
                // print("📥 VIEWSTATE: Added/updated user \(user.username) for message author to both dictionaries")
            } else {
                // CRITICAL FIX: If user data not provided, try to load from stored data or create placeholder
                if users[m.author] == nil {
                    if let storedUser = allEventUsers[m.author] {
                        users[m.author] = storedUser
                        // print("📥 VIEWSTATE: Loaded message author \(storedUser.username) from stored data")
                    } else {
                        // Create placeholder to prevent black messages
                        let placeholderUser = Types.User(
                            id: m.author,
                            username: "Unknown User",
                            discriminator: "0000",
                            relationship: .None
                        )
                        users[m.author] = placeholderUser
                        allEventUsers[m.author] = placeholderUser
                        // print("⚠️ VIEWSTATE: Created placeholder for missing message author: \(m.author)")
                    }
                }
            }
            
            if let member = m.member {
                members[member.id.server]?[member.id.user] = member
            }
            
            let userMentioned = m.mentions?.contains(where: {
                $0 == currentUser?.id
            }) ?? false
            
            // Check if message is from current user
            let isFromCurrentUser = m.author == currentUser?.id
                        
            if let unread = unreads[m.channel]{
                // Don't update unread for messages sent by the current user
                if !isFromCurrentUser {
                    // Update last_id for messages from other users
                    // This ensures unread count properly reflects new messages
                    unreads[m.channel]?.last_id = m.id
                    
                    if userMentioned {
                        if unreads[m.channel]?.mentions != nil {
                            unreads[m.channel]?.mentions?.append(m.id)
                        } else {
                            unreads[m.channel]!.mentions = [m.id]
                        }
                    }
                }
            } else if !isFromCurrentUser {
                // Only create unread entry for messages from other users
                unreads[m.channel] = .init(id: .init(channel: m.channel, user: currentUser?.id ?? ""),
                                           last_id: m.id,
                                           mentions: userMentioned ? [m.id]:[])
            }
            
            // Check if message already exists
            if messages[m.id] != nil {
                // print("⚠️ VIEWSTATE: Message \(m.id) already exists, updating")
            }
            
            messages[m.id] = m
            // Update message size tracking
            updateMessageSize(messageId: m.id, message: m)
            
            // Update per-channel user tracking
            if channelUserIds[m.channel] == nil {
                channelUserIds[m.channel] = Set<String>()
            }
            channelUserIds[m.channel]?.insert(m.author)
            if let mentions = m.mentions {
                channelUserIds[m.channel]?.formUnion(mentions)
            }
            
            // Check if this message matches a queued message and clean it up
            if let channelQueuedMessages = queuedMessages[m.channel],
               let queuedIndex = channelQueuedMessages.firstIndex(where: { queued in
                   // Match by content, author, and channel for safety
                   return queued.content == m.content && 
                          queued.author == m.author && 
                          queued.channel == m.channel
               }) {
                let queuedMessage = channelQueuedMessages[queuedIndex]
                print("📥 VIEWSTATE: Found matching queued message, cleaning up nonce: \(queuedMessage.nonce)")
                
                // Remove the temporary message from messages dictionary (if it exists)
                messages.removeValue(forKey: queuedMessage.nonce)
                
                // For messages without attachments: Replace nonce with real ID in channel messages
                // For messages with attachments: Add to channel messages for the first time
                if let nonceMsgIndex = channelMessages[m.channel]?.firstIndex(of: queuedMessage.nonce) {
                    // This was an optimistic message (no attachments), replace it
                    channelMessages[m.channel]?[nonceMsgIndex] = m.id
                    print("📥 VIEWSTATE: Replaced optimistic nonce \(queuedMessage.nonce) with real ID \(m.id)")
                } else if queuedMessage.hasAttachments {
                    // This was an attachment message (not shown optimistically), add it now
                    if channelMessages[m.channel] == nil {
                        channelMessages[m.channel] = []
                    }
                    channelMessages[m.channel]?.append(m.id)
                    print("📥 VIEWSTATE: Added attachment message \(m.id) to channel messages for first time")
                }
                
                // Remove from queued messages for this channel
                queuedMessages[m.channel]?.remove(at: queuedIndex)
                if queuedMessages[m.channel]?.isEmpty == true {
                    queuedMessages.removeValue(forKey: m.channel)
                }
                print("📥 VIEWSTATE: Removed queued message from channel \(m.channel)")
            } else {
                // Check channel messages array
                if channelMessages[m.channel] == nil {
                    // print("📥 VIEWSTATE: Creating new channelMessages array for channel \(m.channel)")
                    channelMessages[m.channel] = []
                }
                
                // MEMORY FIX: Check if message already exists in channel to avoid duplicates
                if !(channelMessages[m.channel]?.contains(m.id) ?? false) {
                    channelMessages[m.channel]?.append(m.id)
                } else {
                    // print("⚠️ VIEWSTATE: Message \(m.id) already exists in channelMessages, skipping append")
                }
            }
            
            let channelMessagesAfter = channelMessages[m.channel]?.count ?? 0
            
            // print("📥 VIEWSTATE: Channel messages count - before: \(channelMessagesBefore), after: \(channelMessagesAfter)")
            // print("📥 VIEWSTATE: Total messages count AFTER: \(messages.count)")
            // print("📥 VIEWSTATE: Total channel message arrays: \(channelMessages.count)")
            
            // Log memory info
            let totalChannelMessages = channelMessages.values.reduce(0) { $0 + $1.count }
            // print("📥 VIEWSTATE: Total messages across all channels: \(totalChannelMessages)")
            
            // DISABLED: MEMORY MANAGEMENT: Proactive cleanup
            // checkAndCleanupIfNeeded() - Disabled to prevent black messages
            
            NotificationCenter.default.post(name: NSNotification.Name("NewMessagesReceived"), object: nil)
            
            if let index = dms.firstIndex(where: { $0.id == m.channel }) {
                let dmChannel = dms.remove(at: index)

                let updatedDM: Channel
                switch dmChannel {
                    case .dm_channel(var c):
                        c.last_message_id = m.id
                        updatedDM = .dm_channel(c)
                    case .group_dm_channel(var c):
                        c.last_message_id = m.id
                        updatedDM = .group_dm_channel(c)
                    default:
                        updatedDM = dmChannel
                }

                dms.insert(updatedDM, at: 0)
                
                // FIX: Ensure DM list state is maintained
                if isDmListInitialized && currentSelection == .dms {
                    // When a DM moves to top, ensure we maintain the loaded batches
                    // because this change might affect the order
                    let channelIdIndex = allDmChannelIds.firstIndex(of: m.channel)
                    if let channelIdIndex = channelIdIndex {
                        allDmChannelIds.remove(at: channelIdIndex)
                        allDmChannelIds.insert(m.channel, at: 0)
                    }
                }
            }
            
            if var existing = channels[m.channel] {
                switch existing {
                case .dm_channel(var c):
                    c.last_message_id = m.id
                    channels[m.channel] = .dm_channel(c)
                case .group_dm_channel(var c):
                    c.last_message_id = m.id
                    channels[m.channel] = .group_dm_channel(c)
                case .text_channel(var c):
                    c.last_message_id = m.id
                    channels[m.channel] = .text_channel(c)
                default:
                    break
                }
            }
            
            
        case .message_update(let event):
            let message = messages[event.id]
            
            if var message = message {
                message.edited = event.data.edited
                
                
                if let content = event.data.content {
                    message.content = content
                }
                
                messages[event.id] = message
                
                // Update cache (background, non-blocking)
                if let userId = currentUser?.id, let baseURL = baseURL {
                    let editedAt = ISO8601DateFormatter().date(from: event.data.edited)
                    MessageCacheManager.shared.updateCachedMessage(
                        id: event.id,
                        content: event.data.content,
                        editedAt: editedAt,
                        channelId: message.channel,
                        userId: userId,
                        baseURL: baseURL
                    )
                }
            }
            
        case .authenticated:
            print("authenticated")
            
        case .invalid_session:
            Task {
                await self.signOut()
            }
            
        case .logout:
            Task {
                await self.signOut(afterRemoveSession: true)
            }
        case .channel_start_typing(let e):
            var typing = currentlyTyping[e.id] ?? []
            typing.append(e.user)
            
            currentlyTyping[e.id] = typing
            
        case .channel_stop_typing(let e):
            currentlyTyping[e.id]?.removeAll(where: { $0 == e.user })
            
        case .message_delete(let e):
            if var channel = channelMessages[e.channel] {
                if let index = channel.firstIndex(of: e.id) {
                    channel.remove(at: index)
                    channelMessages[e.channel] = channel
                }
            }
            
            // Add to tombstone set
            deletedMessageIds[e.channel, default: Set<String>()].insert(e.id)
            
            // Delete from cache (background, non-blocking)
            if let userId = currentUser?.id, let baseURL = baseURL {
                MessageCacheManager.shared.deleteCachedMessage(
                    id: e.id,
                    channelId: e.channel,
                    userId: userId,
                    baseURL: baseURL
                )
            }
            
        case .channel_ack(let e):
            unreads[e.id]?.last_id = e.message_id
            unreads[e.id]?.mentions?.removeAll { $0 <= e.message_id }
            
        case .message_react(let e):
            if var message = messages[e.id] {
                var reactions = message.reactions ?? [:]
                var users = reactions[e.emoji_id] ?? []
                
                // Check if user is not already in the reaction list to avoid duplicates
                if !users.contains(e.user_id) {
                    users.append(e.user_id)
                    reactions[e.emoji_id] = users
                    message.reactions = reactions
                    messages[e.id] = message
                    
                    // print("🔥 VIEWSTATE: Added reaction \(e.emoji_id) from user \(e.user_id) to message \(e.id) in channel \(e.channel_id)")
                    
                    // Post notification to update UI
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MessagesDidChange"), 
                            object: ["channelId": e.channel_id, "messageId": e.id, "type": "reaction_added"]
                        )
                    }
                } else {
                    // print("🔥 VIEWSTATE: User \(e.user_id) already reacted with \(e.emoji_id) on message \(e.id)")
                }
            } else {
                // print("🔥 VIEWSTATE: Message \(e.id) not found for reaction add")
            }
            
        case .message_unreact(let e):
            if var message = messages[e.id] {
                if var reactions = message.reactions {
                    if var users = reactions[e.emoji_id] {
                        users.removeAll { $0 == e.user_id }
                        
                        if users.isEmpty {
                            reactions.removeValue(forKey: e.emoji_id)
                        } else {
                            reactions[e.emoji_id] = users
                        }
                        message.reactions = reactions
                        messages[e.id] = message
                        
                        // print("🔥 VIEWSTATE: Removed reaction \(e.emoji_id) from user \(e.user_id) on message \(e.id) in channel \(e.channel_id)")
                        
                        // Post notification to update UI
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("MessagesDidChange"), 
                                object: ["channelId": e.channel_id, "messageId": e.id, "type": "reaction_removed"]
                            )
                        }
                    } else {
                        // print("🔥 VIEWSTATE: No users found for emoji \(e.emoji_id) on message \(e.id)")
                    }
                } else {
                    // print("🔥 VIEWSTATE: No reactions found on message \(e.id)")
                }
            } else {
                // print("🔥 VIEWSTATE: Message \(e.id) not found for reaction remove")
            }
        case .message_append(let e):
            if var message = messages[e.id] {
                var embeds = message.embeds ?? []
                embeds.append(e.append)
                message.embeds = embeds
                messages[e.id] = message
            }
        case .user_update(let e):
            updateUser(with: e)
        case .server_create(let e):
            self.servers[e.id] = e.server
            for channel in e.channels {
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
            }
            
        case .server_delete(let e):
            if case .server(let string) = currentSelection {
                if string == e.id {
                    self.path = .init()
                    self.selectDms()
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                self.servers.removeValue(forKey: e.id)
            }
            
            
        case .server_update(let e):
            
            if let tmpServer = self.servers[e.id] {
                
                var t = tmpServer
                
                if let icon = e.data?.icon {
                    t.icon = icon
                }
                
                if let name = e.data?.name  {
                    t.name = name
                }
                
                if let description = e.data?.description {
                    t.description = description
                }
                
                if let banner = e.data?.banner {
                    t.banner = banner
                }
                
                if let systemMessage = e.data?.system_messages {
                    t.system_messages = systemMessage
                }
                
                if let categories = e.data?.categories {
                    t.categories = categories
                }
                
                if let default_permissions = e.data?.default_permissions {
                    t.default_permissions = default_permissions
                }
                
                if let owner = e.data?.owner {
                    t.owner = owner
                }
                
                if let nsfw = e.data?.nsfw {
                    t.nsfw = nsfw
                }
                
                
                if e.clear?.contains(ServerEdit.Remove.icon) == true {
                    t.icon = nil
                }
                
                if e.clear?.contains(ServerEdit.Remove.banner) == true {
                    t.banner = nil
                }
                
                self.servers[e.id] = t
            }
            
        case .channel_create(let channel):
            // Store the channel in our event channels for lazy loading
            allEventChannels[channel.id] = channel
            
            // Handle different channel types
            switch channel {
            case .dm_channel(_):
                // DMs are always loaded immediately
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
                self.dms.insert(channel, at: 0)
                // print("📥 VIEWSTATE: Added new DM channel \(channel.id) immediately")
                
            case .group_dm_channel(_):
                // Group DMs are always loaded immediately
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
                self.dms.insert(channel, at: 0)
                // print("📥 VIEWSTATE: Added new Group DM channel \(channel.id) immediately")
                
            case .text_channel(let textChannel):
                // Server channels: only load if server is currently active
                if case .server(let currentServerId) = currentSelection, 
                   currentServerId == textChannel.server {
                    // Load immediately if this server is active
                    self.channels[channel.id] = channel
                    self.channelMessages[channel.id] = []
                    // print("📥 VIEWSTATE: Added new text channel \(channel.id) immediately (server active)")
                } else {
                    // Just store for lazy loading later
                    // print("🔄 LAZY_CHANNEL: Stored new text channel \(channel.id) for lazy loading")
                }
                
                // Update server's channel list
                if let serverId = channel.server {
                    self.servers[serverId]?.channels.append(channel.id)
                }
                
            case .voice_channel(let voiceChannel):
                // Voice channels: only load if server is currently active
                if case .server(let currentServerId) = currentSelection,
                   currentServerId == voiceChannel.server {
                    // Load immediately if this server is active
                    self.channels[channel.id] = channel
                    // print("📥 VIEWSTATE: Added new voice channel \(channel.id) immediately (server active)")
                } else {
                    // Just store for lazy loading later
                    // print("🔄 LAZY_CHANNEL: Stored new voice channel \(channel.id) for lazy loading")
                }
                
                // Update server's channel list
                if let serverId = channel.server {
                    self.servers[serverId]?.channels.append(channel.id)
                }
                
            default:
                // Other channel types - store in event channels
                print("📥 VIEWSTATE: Stored unknown channel type \(channel.id)")
            }
            
            // Update app badge count when new channel is created
            // This ensures unread messages in the new channel are counted
            updateAppBadgeCount()
            
        case .channel_update(let e):
            
            if let index = self.dms.firstIndex(where: { $0.id == e.id }),
               case .group_dm_channel(var groupDMChannel) = self.dms[index] {
                
                
                if let name = e.data?.name {
                    groupDMChannel.name = name
                }
                
                if let icon = e.data?.icon {
                    groupDMChannel.icon = icon
                }
                
                if let description = e.data?.description {
                    groupDMChannel.description = description
                }
                
                if let nsfw = e.data?.nsfw {
                    groupDMChannel.nsfw = nsfw
                }
                
                if let permission = e.data?.permissions {
                    groupDMChannel.permissions = permission
                }
                
                if let owner = e.data?.owner {
                    groupDMChannel.owner = owner
                }
                
                if e.clear?.contains(.icon) == true {
                    groupDMChannel.icon = nil
                }
                
                if e.clear?.contains(.description) == true {
                    groupDMChannel.description = nil
                }
                
                
                
                self.dms[index] = .group_dm_channel(groupDMChannel)
                
            } else if let index = self.dms.firstIndex(where: { $0.id == e.id }),
                      case .dm_channel(let dmChannel) = self.dms[index] {
                
                //TODO
                
                self.dms[index] = .dm_channel(dmChannel)
                
            }
            
            if let channel = self.channels[e.id] {
                
                
                if case .group_dm_channel(var t) = channel {
                    if let name = e.data?.name {
                        t.name = name
                    }
                    
                    if let icon = e.data?.icon {
                        t.icon = icon
                    }
                    
                    
                    if let description = e.data?.description {
                        t.description = description
                    }
                    
                    if let nsfw = e.data?.nsfw {
                        t.nsfw = nsfw
                    }
                    
                    if let permission = e.data?.permissions {
                        t.permissions = permission
                    }
                    
                    if let owner = e.data?.owner {
                        t.owner = owner
                    }
                    
                    
                    if e.clear?.contains(.icon) == true {
                        t.icon = nil
                    }
                    
                    if e.clear?.contains(.description) == true {
                        t.description = nil
                    }
                    
                    
                    self.channels[e.id] = .group_dm_channel(t)
                    
                    
                } else if case .text_channel(var t) = channel {
                    if let name = e.data?.name {
                        t.name = name
                    }
                    
                    if let icon = e.data?.icon {
                        t.icon = icon
                    }
                    
                    if let description = e.data?.description {
                        t.description = description
                    }
                    
                    if let nsfw = e.data?.nsfw {
                        t.nsfw = nsfw
                    }
                    
                    if let default_permissions = e.data?.default_permissions {
                        t.default_permissions = default_permissions
                    }
                    
                    if let newRolePermissions = e.data?.role_permissions {
                        if t.role_permissions == nil {
                            t.role_permissions = newRolePermissions
                        } else {
                            for (roleId, permission) in newRolePermissions {
                                t.role_permissions?[roleId] = permission
                            }
                        }
                    }
                    
                    if e.clear?.contains(.icon) == true {
                        t.icon = nil
                    }
                    
                    if e.clear?.contains(.description) == true {
                        t.description = nil
                    }
                    
                    self.channels[e.id] = .text_channel(t)
                    
                }
            }
            
        case .channel_delete(let e):
            self.deleteChannel(channelId: e.id)
            
        case .channel_group_leave(let e):
            if e.user == currentUser?.id {
                deleteChannel(channelId: e.id)
            } else {
                
                if case .group_dm_channel(var channel) = self.channels[e.id] {
                    channel.recipients.removeAll { $0 == e.user }
                    self.channels[e.id] = .group_dm_channel(channel)
                    if let index = dms.firstIndex(where: { $0.id == e.id }) {
                        dms[index] = .group_dm_channel(channel)
                    }
                } else {
                    //Todo
                }
                
            }
            
        case .channel_group_join(let e):
            if case .group_dm_channel(var channel) = self.channels[e.id] {
                channel.recipients.append(e.user)
                self.channels[e.id] = .group_dm_channel(channel)
                if let index = dms.firstIndex(where: { $0.id == e.id }) {
                    dms[index] = .group_dm_channel(channel)
                }
                
                //TOOD
                //fetch user
                let response = await self.http.fetchUser(user: e.user)
                switch response {
                    case .success(let user):
                        // MEMORY FIX: Only add users if we have space
                        if self.users.count < self.maxUsersInMemory {
                            self.users[user.id] = user
                            // print("📥 VIEWSTATE: Added user \(user.id) during channel_group_join")
                        }
                        self.checkAndCleanupIfNeeded()
                        
                    case .failure(let error):
                        print(error)
                }
                
            } else {
                //Todo other types channel
            }
            
            // MEMORY MANAGEMENT: Cleanup after new user
            checkAndCleanupIfNeeded()
            
            
            
        case .server_member_update(let e):
            let serverId = e.id.server
            let userId = e.id.user

            guard var serverMembers = members[serverId], var member = serverMembers[userId] else {
                return
            }

            // Apply updates only to non-nil fields
            if let newNickname = e.data?.nickname {
                member.nickname = newNickname
            }
            
            if let newAvatar = e.data?.avatar {
                member.avatar = newAvatar
            }
            
            if let newRoles = e.data?.roles {
                member.roles = newRoles
            }
            
            if let newJoinedAt = e.data?.joined_at {
                member.joined_at = newJoinedAt
            }
            
            if let newTimeout = e.data?.timeout {
                member.timeout = newTimeout
            }

            // Handle `clean` fields (removing values if specified)
            for field in e.clear {
                switch field {
                case .nickname:
                    member.nickname = nil
                case .avatar:
                    member.avatar = nil
                case .roles:
                    member.roles = nil
                case .timeout:
                    member.timeout = nil
                }
            }

            // Update the local members dictionary
            serverMembers[userId] = member
            members[serverId] = serverMembers
            
        case .server_member_join(let e):

            Task {
                async let fetchedUser = self.http.fetchUser(user: e.user)
                async let fetchedMember = self.http.fetchMember(server: e.id, member: e.user)

                // Wait for both API calls to complete
                let (userResult, memberResult) = await (fetchedUser, fetchedMember)
                
                
                switch userResult {
                    case .success(let user):
                        // MEMORY FIX: Only add users if we have space
                        if self.users.count < self.maxUsersInMemory {
                            self.users[e.user] = user
                            // print("📥 VIEWSTATE: Added user \(e.user) during server_member_join")
                        }
                        self.checkAndCleanupIfNeeded()
                    case .failure(_):
                         print("error fetching user")
                }
                
                switch memberResult {
                    case .success(let member):
                        var serverMembers = self.members[e.id, default: [:]]
                        serverMembers[e.user] = member
                        self.members[e.id] = serverMembers
                    case .failure(_):
                         print("error fetching member")
                }

            }
            
        case .server_member_leave(let e):
                guard var serverMembers = self.members[e.id] else {
                    return
                }
                serverMembers.removeValue(forKey: e.user)
                self.members[e.id] = serverMembers
            
        case .server_role_update(let e):
                // Ensure the server exists
                guard var server = self.servers[e.id] else {
                    return
                }
                
                // Ensure the roles dictionary exists
                var serverRoles = server.roles ?? [:]
                
                // Check if the role already exists
                var role = serverRoles[e.role_id] ?? Role(
                    name: e.data.name ?? "New Role",
                    permissions: e.data.permissions ?? Overwrite(a: .none, d: .none),
                    colour: e.data.colour,
                    hoist: e.data.hoist,
                    rank: e.data.rank ?? 0
                )

                // Update fields if they exist in the event
                if let name = e.data.name {
                    role.name = name
                }
                if let permissions = e.data.permissions as Overwrite? {
                    role.permissions = permissions
                }
                if let colour = e.data.colour {
                    role.colour = colour
                }
                if let hoist = e.data.hoist {
                    role.hoist = hoist
                }
                if let rank = e.data.rank {
                    role.rank = rank
                }

                // Remove fields specified in `clear`
                for field in e.clear {
                    switch field {
                    case .colour:
                        role.colour = nil
                    }
                }

                // Save the updated role
                serverRoles[e.role_id] = role
                server.roles = serverRoles
                self.servers[e.id] = server
            
            
        case .server_role_delete(let e):
                // Ensure the server exists
                guard var server = self.servers[e.id] else {
                    return
                }
                
                // Ensure the roles dictionary exists
                guard var serverRoles = server.roles else {
                    return
                }
            
                serverRoles.removeValue(forKey: e.role_id)
               
                // Update the server's roles
                server.roles = serverRoles
                self.servers[e.id] = server
            
        case .user_relationship(let event):
            updateUserRelationship(with: event)
            
        case .user_setting_update(let event):
            
            if let update = event.update {
                self.userSettingsStore.storeFetchData(settingsValues: update)
                
                if update["ordering"] != nil {
                    DispatchQueue.main.async {
                        self.applyServerOrdering()
                    }
                }
            }
            
        }
        
    }
    


    
    private func processUsers(_ eventUsers: [Types.User]) {
        // print("🚀 VIEWSTATE: Processing \(eventUsers.count) users from WebSocket")
        // print("🚀 VIEWSTATE: Existing users count: \(users.count)")
        
        // Store ALL users for lazy loading (this is our data source)
        allEventUsers = Dictionary(uniqueKeysWithValues: eventUsers.map { ($0.id, $0) })
        // print("🔄 LAZY_USER: Stored \(allEventUsers.count) users for lazy loading")
        
        // CRITICAL FIX: Don't clear existing users - merge instead
        // Keep existing users and add/update new ones from WebSocket
        
        var addedCount = 0
        var updatedCount = 0
        var currentUserFound = false
        
        // 1. Update/Add current user
        for user in eventUsers {
            if user.relationship == .User {
                currentUser = user
                if users[user.id] == nil {
                    users[user.id] = user
                    addedCount += 1
                    // print("🚀 VIEWSTATE: Added current user: \(user.id)")
                } else {
                    users[user.id] = user
                    updatedCount += 1
                    // print("🚀 VIEWSTATE: Updated current user: \(user.id)")
                }
                currentUserFound = true
                break
            }
        }
        
        // 2. Update/Add friends (always important)
        for user in eventUsers {
            if addedCount >= 50 {
                break
            }
            
            if user.relationship == .Friend {
                if users[user.id] == nil {
                    users[user.id] = user
                    addedCount += 1
                    // print("🚀 VIEWSTATE: Added friend: \(user.id)")
                } else {
                    users[user.id] = user
                    updatedCount += 1
                    // print("🚀 VIEWSTATE: Updated friend: \(user.id)")
                }
            }
        }
        
        // 3. Add users needed for visible DMs only (lazy approach)
        // Note: This will be called later in processDMs after allDmChannelIds is set
        
        // print("🚀 VIEWSTATE: FINAL USER COUNT: \(users.count) (added: \(addedCount), updated: \(updatedCount)) out of \(eventUsers.count) total")
        // print("🔄 LAZY_USER: Remaining users will be loaded on-demand")
        
        if !currentUserFound {
            // print("⚠️ VIEWSTATE: Current user not found in event users!")
        }
    }
    
    // Load users needed for currently visible DMs
    private func loadUsersForVisibleDms(from userDict: [String: Types.User], maxCount: Int) {
        var loadedCount = 0
        
        // Get IDs for first batch of DMs that will be visible
        let visibleDmIds = Array(allDmChannelIds.prefix(dmBatchSize))
        
        for dmId in visibleDmIds {
            if loadedCount >= maxCount {
                break
            }
            
            if let channel = channels[dmId] {
                var recipientIds: [String] = []
                
                switch channel {
                case .dm_channel(let dm):
                    recipientIds = dm.recipients
                case .group_dm_channel(let group):
                    recipientIds = group.recipients
                default:
                    continue
                }
                
                // Load users for this DM
                for userId in recipientIds {
                    if loadedCount >= maxCount {
                        break
                    }
                    
                    if users[userId] == nil, let user = userDict[userId] {
                        users[userId] = user
                        loadedCount += 1
                        // print("🔄 LAZY_USER: Loaded DM participant: \(userId)")
                    }
                }
            }
        }
        
        // print("🔄 LAZY_USER: Loaded \(loadedCount) users for visible DMs")
    }
    
    // Store user data for lazy loading
    var allEventUsers: [String: Types.User] = [:]
    
    // LAZY LOADING: Server channel management
    var allEventChannels: [String: Channel] = [:] // Store all channels for lazy loading
    var loadedServerChannels: Set<String> = [] // Track which servers have loaded channels
    
    // Load users for the first batch of DMs (called during processDMs)
    private func loadUsersForFirstDmBatch() {
        var loadedCount = 0
        let maxUsersToLoad = 50 // Limit to prevent memory issues
        
        // Get IDs for first batch of DMs that will be visible
        let visibleDmIds = Array(allDmChannelIds.prefix(dmBatchSize))
        
        for dmId in visibleDmIds {
            if loadedCount >= maxUsersToLoad {
                break
            }
            
            if let channel = channels[dmId] {
                var recipientIds: [String] = []
                
                switch channel {
                case .dm_channel(let dm):
                    recipientIds = dm.recipients
                case .group_dm_channel(let group):
                    recipientIds = group.recipients
                default:
                    continue
                }
                
                // Load actual users from stored event data
                for userId in recipientIds {
                    if loadedCount >= maxUsersToLoad {
                        break
                    }
                    
                    if users[userId] == nil {
                        if let actualUser = allEventUsers[userId] {
                            // Load the real user data
                            users[userId] = actualUser
                            loadedCount += 1
                            // print("🔄 LAZY_USER: Loaded actual user \(actualUser.username) for DM participant: \(userId)")
                        } else {
                            // Create placeholder only if we can't find the real user
                            let placeholderUser = Types.User(
                                id: userId,
                                username: "Unknown User",
                                discriminator: "0000",
                                relationship: .None
                            )
                            users[userId] = placeholderUser
                            loadedCount += 1
                            // print("⚠️ LAZY_USER: Created placeholder for missing user: \(userId)")
                        }
                    }
                }
            }
        }
        
        // print("🔄 LAZY_USER: Loaded \(loadedCount) users for first DM batch")
    }
    
    // Load users on-demand when a new DM batch is loaded
    @MainActor
    func loadUsersForDmBatch(_ batchIndex: Int) {
        let startIndex = batchIndex * dmBatchSize
        let endIndex = min(startIndex + dmBatchSize, allDmChannelIds.count)
        
        guard startIndex < allDmChannelIds.count else {
            return
        }
        
        let batchIds = Array(allDmChannelIds[startIndex..<endIndex])
        var loadedCount = 0
        var skippedCount = 0
        let maxUsersToLoad = 10 // REDUCED to 10 users per batch for debugging
        
        for dmId in batchIds {
            if loadedCount >= maxUsersToLoad {
                break
            }
            
            if let channel = channels[dmId] {
                var recipientIds: [String] = []
                
                switch channel {
                case .dm_channel(let dm):
                    recipientIds = dm.recipients
                case .group_dm_channel(let group):
                    recipientIds = group.recipients
                default:
                    continue
                }
                
                // Load actual users from stored event data
                for userId in recipientIds {
                    if loadedCount >= maxUsersToLoad {
                        break
                    }
                    
                    // DUPLICATE PREVENTION: Skip if user already exists
                    if users[userId] != nil {
                        skippedCount += 1
                        continue
                    }
                    
                    if let actualUser = allEventUsers[userId] {
                        // Load the real user data
                        users[userId] = actualUser
                        loadedCount += 1
                        // print("🔄 LAZY_USER: Loaded NEW user \(actualUser.username) for DM batch \(batchIndex)")
                    } else {
                        // print("⚠️ LAZY_USER: User \(userId) not found in event data for batch \(batchIndex)")
                    }
                }
            }
        }
        
        // print("🔄 LAZY_USER: Batch \(batchIndex) - Loaded \(loadedCount) NEW users, skipped \(skippedCount) existing users. Total users now: \(users.count)")
    }
    
    // Load users for visible messages to prevent black messages
    @MainActor
    func loadUsersForVisibleMessages(channelId: String) {
        guard let messageIds = channelMessages[channelId] else {
            return
        }
        
        var loadedUsers = 0
        var missingUsers: [String] = []
        
        for messageId in messageIds {
            if let message = messages[messageId] {
                if users[message.author] == nil {
                    missingUsers.append(message.author)
                    
                    // Try to load from event data first
                    if let user = allEventUsers[message.author] {
                        users[message.author] = user
                        loadedUsers += 1
                        // print("🔄 LAZY_USER: Loaded message author \(user.username) from event data")
                    } else {
                        // Create placeholder user to prevent black messages
                        let placeholderUser = Types.User(
                            id: message.author,
                            username: "Unknown User",
                            discriminator: "0000",
                            relationship: .None
                        )
                        users[message.author] = placeholderUser
                        loadedUsers += 1
                        // print("⚠️ LAZY_USER: Created placeholder for missing user: \(message.author)")
                    }
                }
            }
        }
        
        if loadedUsers > 0 {
            // print("🔄 LAZY_USER: Loaded \(loadedUsers) users for channel \(channelId), missing: \(missingUsers.count)")
        }
    }
    
    // CRITICAL FIX: Restore missing users from allEventUsers to prevent black messages
    @MainActor
    func restoreMissingUsersForMessages() {
        var restoredCount = 0
        var placeholderCount = 0
        
        // print("🔄 RESTORE_USERS: Starting restoration of missing users")
        
        // Check all messages in memory
        for (messageId, message) in messages {
            if users[message.author] == nil {
                // Try to restore from allEventUsers
                if let storedUser = allEventUsers[message.author] {
                    users[message.author] = storedUser
                    restoredCount += 1
                    // print("🔄 RESTORE_USERS: Restored \(storedUser.username) for message \(messageId)")
                } else {
                    // Create placeholder as last resort
                    let placeholderUser = Types.User(
                        id: message.author,
                        username: "Unknown User",
                        discriminator: "0000",
                        relationship: .None
                    )
                    users[message.author] = placeholderUser
                    allEventUsers[message.author] = placeholderUser // Store for future use
                    placeholderCount += 1
                    // print("⚠️ RESTORE_USERS: Created placeholder for \(message.author) in message \(messageId)")
                }
            }
        }
        
        if restoredCount > 0 || placeholderCount > 0 {
            // print("🔄 RESTORE_USERS: Restoration complete - restored: \(restoredCount), placeholders: \(placeholderCount)")
        }
    }
    
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
    
    private func processMembers(_ eventMembers: [Member]) {
        for member in eventMembers {
            members[member.id.server]?[member.id.user] = member
        }
    }
    
    private func processDMs(channels: [Channel]) {
        // LAZY LOADING: Store all DM IDs but only load the first batch
        let dmChannels: [Channel] = channels.filter {
            switch $0 {
            case .dm_channel:
                return true // Include both active and inactive DMs
            case .group_dm_channel:
                return true
            default:
                return false
            }
        }
        
        // print("🚀 VIEWSTATE: Processing \(dmChannels.count) DM channels with lazy loading")
        
        // Sort all DM channels
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
        
        // Store all DM IDs in order
        allDmChannelIds = sortedDmChannels.map { $0.id }
        
        // Load users for visible DMs after we have the sorted list
        loadUsersForFirstDmBatch()
        
        // Simple lazy loading: start fresh
        loadedDmBatches.removeAll()
        dms.removeAll() // Clear existing DMs
        loadDmBatch(0) // Load first batch
        
        isDmListInitialized = true
        // print("🚀 VIEWSTATE: Stored \(allDmChannelIds.count) DM IDs, loaded first batch")
    }
    
    // Load a specific batch of DMs
    @MainActor
    func loadDmBatch(_ batchIndex: Int) {
        guard !isLoadingDmBatch else {
            // print("🔄 LAZY_DM: Already loading, skipping batch \(batchIndex)")
            return
        }
        
        // DUPLICATE PREVENTION: Check if this batch is already loaded
        if loadedDmBatches.contains(batchIndex) {
            // print("🔄 LAZY_DM: Batch \(batchIndex) already loaded, skipping")
            return
        }
        
        let startIndex = batchIndex * dmBatchSize
        let endIndex = min(startIndex + dmBatchSize, allDmChannelIds.count)
        
        guard startIndex < allDmChannelIds.count else {
            return
        }
        
        isLoadingDmBatch = true
        
        let memoryBefore = getCurrentMemoryUsage()
        // print("🔄 LAZY_DM: Loading batch \(batchIndex) (DMs \(startIndex) to \(endIndex-1)) - Memory: \(memoryBefore)MB")
        
        // Get batch IDs to load
        let batchIds = Array(allDmChannelIds[startIndex..<endIndex])
        var newDms: [Channel] = []
        
        for dmId in batchIds {
            if let channel = channels[dmId] {
                newDms.append(channel)
            }
        }
        
        // FIXED: Rebuild the entire DMs list from allDmChannelIds to maintain correct order
        // Mark this batch as loaded first
        loadedDmBatches.insert(batchIndex)
        
        // Now rebuild the DMs list from all loaded batches in correct order
        var rebuiltDms: [Channel] = []
        var addedChannelIds = Set<String>() // Prevent duplicates
        
        for loadedBatch in loadedDmBatches.sorted() {
            let batchStart = loadedBatch * dmBatchSize
            let batchEnd = min(batchStart + dmBatchSize, allDmChannelIds.count)
            
            for i in batchStart..<batchEnd {
                let channelId = allDmChannelIds[i]
                if !addedChannelIds.contains(channelId), let channel = channels[channelId] {
                    rebuiltDms.append(channel)
                    addedChannelIds.insert(channelId)
                }
            }
        }
        
        // Replace the entire DMs list with the rebuilt one
        dms = rebuiltDms
        
        // Load users for this batch
        loadUsersForDmBatch(batchIndex)
        
        // Simple memory protection: if too many batches, stop loading
        if loadedDmBatches.count >= maxLoadedBatches {
            // print("⚠️ LAZY_DM: Reached max batches limit (\(maxLoadedBatches)). No more loading.")
        }
        
        let memoryAfter = getCurrentMemoryUsage()
        let memoryDiff = memoryAfter - memoryBefore
        
        isLoadingDmBatch = false
        // print("🔄 LAZY_DM: Loaded batch \(batchIndex), total DMs: \(dms.count), Memory: \(memoryBefore)MB → \(memoryAfter)MB (\(memoryDiff > 0 ? "+" : "")\(memoryDiff)MB)")
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
    
    // Load next batch when user scrolls to bottom
    @MainActor
    func loadMoreDmsIfNeeded() {
        // Find the highest loaded batch and load the next one
        let maxLoadedBatch = loadedDmBatches.max() ?? -1
        let nextBatchIndex = maxLoadedBatch + 1
        let totalBatches = (allDmChannelIds.count + dmBatchSize - 1) / dmBatchSize
        
        // Check if we haven't reached the limit and there are more batches
        if nextBatchIndex < totalBatches && loadedDmBatches.count < maxLoadedBatches {
            loadDmBatch(nextBatchIndex)
        }
    }
    
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
    
    // Ensure there are no gaps in loaded batches that could cause missing DMs
    @MainActor
    func ensureNoBatchGaps() {
        guard !loadedDmBatches.isEmpty else { return }
        
        let sortedBatches = loadedDmBatches.sorted()
        let minBatch = sortedBatches.first!
        let maxBatch = sortedBatches.last!
        
        // Fill any gaps between min and max loaded batches
        for batchIndex in minBatch...maxBatch {
            if !loadedDmBatches.contains(batchIndex) {
                // print("🔄 LAZY_DM: Found gap at batch \(batchIndex), loading to fill gap")
                loadDmBatch(batchIndex)
            }
        }
    }
    
    // Reset and reload DMs list (useful for fixing display issues)
    @MainActor
    func resetAndReloadDms() {
        // print("🔄 DM_RESET: Resetting and reloading DMs list")
        
        // Clear current state
        dms.removeAll()
        loadedDmBatches.removeAll()
        isLoadingDmBatch = false
        
        // Reload first batch
        if !allDmChannelIds.isEmpty {
            loadDmBatch(0)
        }
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
    
    
    func getUnreadCountFor(channel: Channel) -> UnreadCount? {
        /*if let unread = unreads[channel.id] {
         if let mentions = unread.mentions {
         return .mentions(formattedMentionCount(mentions.count))
         }
         
         if let last_unread_id = unread.last_id, let last_message_id = channel.last_message_id {
         if last_unread_id < last_message_id {
         return .unread
         }
         }
         }
         
         return nil*/
        
        guard let unread = unreads[channel.id] else {
            return nil
        }
        
        let hasMentions = (unread.mentions != nil && unread.mentions?.count ?? 0 > 0)
        
        
        
        let hasUnread: Bool = {
            if let lastUnreadId = unread.last_id, let lastMessageId = channel.last_message_id {
                return lastUnreadId < lastMessageId
            }
            return false
        }()
        
        if (hasMentions) && hasUnread {
            return .unreadWithMentions(
                mentionsCount: formattedMentionCount(unread.mentions!.count)
            )
        } else if hasMentions {
            return .mentions(formattedMentionCount(unread.mentions!.count))
        } else if hasUnread {
            return .unread
        }

        return nil
        
    }
    
    func getUnreadCountFor(server: Server) -> UnreadCount? {
        if let serverNotificationValue = userSettingsStore.cache.notificationSettings.server[server.id] {
            if serverNotificationValue == .muted && serverNotificationValue == .none {
                return nil
            }
        }
        
        // FIXED: Use allEventChannels to check unreads for all channels, not just loaded ones
        let serverChannelIds = server.channels
        let channelUnreads = serverChannelIds.compactMap { channelId -> (Channel, UnreadCount?)? in
            // First try from loaded channels, then from stored channels
            if let channel = channels[channelId] {
                return (channel, getUnreadCountFor(channel: channel))
            } else if let channel = allEventChannels[channelId] {
                // For unloaded channels, check unreads directly
                let unread = unreads[channelId]
                if let unread = unread {
                    let unreadCount = getUnreadCountFromUnread(unread: unread, channel: channel)
                    return (channel, unreadCount)
                }
                return (channel, nil)
            }
            return nil
        }
        
        var mentionCount = 0
        var hasUnread = false
        
        for (channel, unread) in channelUnreads {
            let channelNotificationValue = userSettingsStore.cache.notificationSettings.channel[channel.id]
            
            if let unread = unread {
                switch unread {
                case .unread:
                    if channelNotificationValue != NotificationState.none && channelNotificationValue != .muted {
                        hasUnread = true
                    }
                    
                case .mentions(let count):
                    if channelNotificationValue != NotificationState.none && channelNotificationValue != .mention {
                        mentionCount += (Int(count) ?? 0)
                    }
                case .unreadWithMentions(let count):
                    if channelNotificationValue != NotificationState.none && channelNotificationValue != .mention {
                        hasUnread = true
                        mentionCount += (Int(count) ?? 0)
                    }
                    
                }
                
            }
        }
        
        if mentionCount > 0 && hasUnread {
            return .unreadWithMentions(mentionsCount: formattedMentionCount(mentionCount))
        }else if mentionCount > 0 {
            return .mentions(formattedMentionCount(mentionCount))
        } else if hasUnread {
            return .unread
        }
        
        return nil
    }
    
    
    func formattedMentionCount(_ input: Int) -> String {
        if input > 10 {
            return "+9"
        } else {
            return "\(input)"
        }
    }
    
    // Helper function to convert Unread object to UnreadCount for lazy loaded channels
    func getUnreadCountFromUnread(unread: Unread, channel: Channel) -> UnreadCount? {
        // Check channel notification settings
        let channelNotificationValue = userSettingsStore.cache.notificationSettings.channel[channel.id]
        
        if channelNotificationValue == NotificationState.none || channelNotificationValue == .muted {
            return nil
        }
        
        // Check if channel has last message
        guard let lastMessageId = channel.last_message_id else {
            return nil
        }
        
        // Check if there are unread messages
        let hasUnreadMessages = unread.last_id != lastMessageId
        
        // Check for mentions
        let mentionCount = unread.mentions?.count ?? 0
        let hasMentions = mentionCount > 0
        
        if hasUnreadMessages && hasMentions {
            return .unreadWithMentions(mentionsCount: formattedMentionCount(mentionCount))
        } else if hasMentions {
            return .mentions(formattedMentionCount(mentionCount))
        } else if hasUnreadMessages {
            return .unread
        }
        
        return nil
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
    
    func selectServer(withId id: String) {
        // Unload previous server's channels if switching servers
        if case .server(let previousServerId) = currentSelection, previousServerId != id {
            unloadServerChannels(serverId: previousServerId)
        }
        
        currentSelection = .server(id)
        
        // LAZY LOADING: Load channels for this server
        loadServerChannels(serverId: id)
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // PERFORMANCE: Start preloading messages for this server's channels
            preloadMessagesForServer(serverId: id)
            
            // ENHANCED: Also trigger smart preloading for important channels
            Task {
                await preloadImportantChannels()
            }
        }
        
        if let last = userSettingsStore.store.lastOpenChannels[id] {
            currentChannel = .channel(last)
        } else if let server = servers[id] {
            if let firstChannel = server.channels.compactMap({
                switch channels[$0] {
                case .text_channel(let c):
                    return c
                default:
                    return nil
                }
            }).first {
                currentChannel = .channel(firstChannel.id)
            } else {
                currentChannel = .noChannel
            }
        }
    }
    
    func selectChannel(inServer server: String, withId id: String) {
        // Clear messages from previous channel before switching
        if case .channel(let previousChannelId) = currentChannel, previousChannelId != id {
            clearChannelMessages(channelId: previousChannelId)
        }
        
        // CRITICAL FIX: Only clear target message ID if we're navigating to a DIFFERENT channel
        // Don't clear it if we're navigating TO the target channel (from links/replies)
        if let targetId = currentTargetMessageId {
            // If target message is for current channel, keep it; otherwise clear it
            if let targetMessage = messages[targetId], targetMessage.channel != id {
                print("🎯 SELECT_CHANNEL: Clearing currentTargetMessageId - target is for different channel")
                currentTargetMessageId = nil
            } else if messages[targetId] == nil {
                // Target message not loaded yet, assume it might be for this channel - keep it
                print("🎯 SELECT_CHANNEL: Keeping currentTargetMessageId for channel \(id) - target message not loaded yet")
            } else {
                print("🎯 SELECT_CHANNEL: Keeping currentTargetMessageId for target channel \(id)")
            }
        }
        
        currentChannel = .channel(id)
        userSettingsStore.store.lastOpenChannels[server] = id
        
        // MEMORY MANAGEMENT: Update channel access time
        updateChannelAccessTime(channelId: id)
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // AGGRESSIVE PRELOADING: Immediately preload this channel
            Task {
                await preloadSpecificChannel(channelId: id)
            }
        }
        
        // CRITICAL FIX: Load users for visible messages when entering channel
        loadUsersForVisibleMessages(channelId: id)
    }
    
    func selectDms() {
        DispatchQueue.main.async {
            // Unload current server's channels when switching to DMs
            if case .server(let serverId) = self.currentSelection {
                self.unloadServerChannels(serverId: serverId)
            }
            
            self.currentSelection = .dms
            
            if let last = self.userSettingsStore.store.lastOpenChannels["dms"] {
                self.currentChannel = .channel(last)
            } else {
                // print("🏠 HOME_REDIRECT: Going to home because no last DM channel saved")
                self.currentChannel = .home
            }
            
            // FIX: Reinitialize DM list if it was cleared or not initialized
            if !self.isDmListInitialized || self.dms.isEmpty {
                self.reinitializeDmListFromCache()
            }
            
            // CRITICAL FIX: Load users for visible messages when entering DM view
            if case .channel(let channelId) = self.currentChannel {
                self.loadUsersForVisibleMessages(channelId: channelId)
            }
        }
    }
    
    func selectDiscover() {
        DispatchQueue.main.async {
            // Unload current server's channels when switching to Discover
            if case .server(let serverId) = self.currentSelection {
                self.unloadServerChannels(serverId: serverId)
            }
            
            self.currentSelection = .discover
            self.currentChannel = .home
            
            // Clear navigation path to go back to home/discover view
            self.path.removeAll()
        }
    }
    
    @MainActor
    func selectDm(withId id: String) {
        // Clear messages from previous channel before switching
        if case .channel(let previousChannelId) = self.currentChannel, previousChannelId != id {
            self.clearChannelMessages(channelId: previousChannelId)
        }
        
        // CRITICAL FIX: Only clear target message ID if we're navigating to a DIFFERENT channel
        // Don't clear it if we're navigating TO the target channel (from links/replies)
        if let targetId = currentTargetMessageId {
            // If target message is for current channel, keep it; otherwise clear it
            if let targetMessage = messages[targetId], targetMessage.channel != id {
                print("🎯 SELECT_DM: Clearing currentTargetMessageId - target is for different channel")
                currentTargetMessageId = nil
            } else if messages[targetId] == nil {
                // Target message not loaded yet, assume it might be for this channel - keep it
                print("🎯 SELECT_DM: Keeping currentTargetMessageId for DM \(id) - target message not loaded yet")
            } else {
                print("🎯 SELECT_DM: Keeping currentTargetMessageId for target DM \(id)")
            }
        }
        
        self.currentChannel = .channel(id)
        guard let channel = self.channels[id] else { return }
        
        switch channel {
        case .dm_channel, .group_dm_channel:
            self.userSettingsStore.store.lastOpenChannels["dms"] = id
        default:
            self.userSettingsStore.store.lastOpenChannels.removeValue(forKey: "dms")
            
        }
        
        // MEMORY MANAGEMENT: Update channel access time
        updateChannelAccessTime(channelId: id)
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // AGGRESSIVE PRELOADING: Immediately preload this DM
            Task {
                await preloadSpecificChannel(channelId: id)
            }
        }
        
        // CRITICAL FIX: Load users for visible messages when entering DM
        self.loadUsersForVisibleMessages(channelId: id)
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
    
    func showAlert(message : String, icon : SwiftUI.ImageResource, color: Color = .iconDefaultGray01){
        self.alert = (message, icon, color)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.snappy) {
                self.alert = (nil,nil, nil)
            }
        }
    }
    
    func showLoadingAlert(message : String, icon : SwiftUI.ImageResource, color: Color = .blue){
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
    
    /// Retry uploading pending notification token
    func retryUploadNotificationToken() async {
        guard let token = pendingNotificationToken else { return }
        
        // print("🔄 RETRY_NOTIFICATION_TOKEN: Attempting to upload previously failed token...")
        
        let response = await http.uploadNotificationToken(token: token)
        switch response {
            case .success:
                // print("✅ RETRY_NOTIFICATION_TOKEN: Successfully uploaded pending token")
                pendingNotificationToken = nil // Clear pending token after success
                UserDefaults.standard.removeObject(forKey: "pendingNotificationToken")
            case .failure(let error):
                print("❌ RETRY_NOTIFICATION_TOKEN: Failed again: \(error)")
                // Keep the pending token for next retry
        }
    }
    
    /// Store notification token for later retry
    func storePendingNotificationToken(_ token: String) {
        pendingNotificationToken = token
        UserDefaults.standard.set(token, forKey: "pendingNotificationToken")
    }
    
    /// Load any pending notification token from storage
    func loadPendingNotificationToken() {
        pendingNotificationToken = UserDefaults.standard.string(forKey: "pendingNotificationToken")
        if pendingNotificationToken != nil {
            // print("📱 PENDING_TOKEN_FOUND: Found pending notification token to upload")
        }
    }
    
    // MARK: - Message Preloading System
    private let messagePreloadingQueue = DispatchQueue(label: "messagePreloading", qos: .utility)
    private var preloadingTasks: [String: Task<Void, Never>] = [:]
    private let maxPreloadedMessagesPerChannel = 20
    
    /// Preload recent messages for channels in a server to improve performance
    private func preloadMessagesForServer(serverId: String) {
        // Cancel any existing preloading task for this server
        preloadingTasks[serverId]?.cancel()
        
        guard let server = servers[serverId] else { return }
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            // Get text channels that don't have messages loaded yet
            let channelsToPreload = server.channels.compactMap { channelId -> String? in
                guard let channel = self.channels[channelId] else { return nil }
                
                // Only preload text channels
                switch channel {
                case .text_channel(_):
                    // Only preload if we don't have messages or have very few
                    let existingMessageCount = self.channelMessages[channelId]?.count ?? 0
                    return existingMessageCount < 5 ? channelId : nil
                default:
                    return nil
                }
            }
            
            // Limit concurrent preloading to avoid overwhelming the API
            let maxConcurrentPreloads = 3
            for channelBatch in channelsToPreload.chunked(into: maxConcurrentPreloads) {
                await withTaskGroup(of: Void.self) { group in
                    for channelId in channelBatch {
                        group.addTask {
                            await self.preloadChannelMessages(channelId: channelId, serverId: serverId)
                        }
                    }
                }
                
                // Small delay between batches to be respectful to the API
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
        
        preloadingTasks[serverId] = task
    }
    
    private func preloadChannelMessages(channelId: String, serverId: String) async {
        // Check if task was cancelled
        guard !Task.isCancelled else { return }
        
        do {
            // SMART LIMIT: Use 10 for specific channel in specific server, 20 for others in preload
            let messageLimit = (channelId == "01J7QTT66242A7Q26A2FH5TD48" && serverId == "01J544PT4T3WQBVBSDK3TBFZW7") ? 10 : maxPreloadedMessagesPerChannel
            
            let result = try await http.fetchHistory(
                channel: channelId,
                limit: messageLimit,
                before: nil,
                server: serverId,
                messages: []
            ).get()
            
            // Check if task was cancelled after API call
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                // Store users and members
                for user in result.users {
                    self.users[user.id] = user
                }
                
                if let members = result.members {
                    for member in members {
                        self.members[member.id.server, default: [:]][member.id.user] = member
                    }
                }
                
                // Store messages
                var messageIds: [String] = []
                for message in result.messages {
                    self.messages[message.id] = message
                    messageIds.append(message.id)
                }
                
                // Store message IDs in channel (sorted by creation time)
                let sortedIds = messageIds.sorted { id1, id2 in
                    let date1 = createdAt(id: id1)
                    let date2 = createdAt(id: id2)
                    return date1 < date2
                }
                
                self.channelMessages[channelId] = sortedIds
                
                // print("📥 PRELOAD: Cached \(result.messages.count) messages for channel \(channelId)")
            }
        } catch {
            // Silently handle errors - preloading is a performance optimization, not critical
            // print("⚠️ PRELOAD: Failed to preload messages for channel \(channelId): \(error)")
        }
    }
    
    // MARK: - App Badge Management
    
    /// Calculates the total unread count across all channels and updates the app badge
    func updateAppBadgeCount() {
        guard let application = ViewState.application else { return }
        
        var totalUnreadCount = 0
        var totalMentionCount = 0
        
        // Iterate through all unreads
        for (channelId, unread) in unreads {
            // Get channel info
            let channel = channels[channelId] ?? allEventChannels[channelId]
            
            // Skip if channel doesn't exist
            guard let channel = channel else {
                continue
            }
            
            // Check if channel is muted
            let channelNotificationState = userSettingsStore.cache.notificationSettings.channel[channelId]
            let isChannelMuted = channelNotificationState == .muted || channelNotificationState == .none
            
            // Check if server is muted (only for server channels, not DMs or group DMs)
            var isServerMuted = false
            if let serverId = channel.server {
                let serverNotificationState = userSettingsStore.cache.notificationSettings.server[serverId]
                isServerMuted = serverNotificationState == .muted || serverNotificationState == .none
            }
            // For DMs and group DMs, server is nil, so isServerMuted stays false
            
            // Skip if channel or server is muted
            if isChannelMuted || isServerMuted {
                continue
            }
            
            // Count unread channels (including group DMs)
            if let lastUnreadId = unread.last_id, let lastMessageId = channel.last_message_id {
                if lastUnreadId < lastMessageId {
                    totalUnreadCount += 1
                    
                    // Debug log for group DMs
                    if case .group_dm_channel(let groupDM) = channel {
                    }
                }
            }
        }
        
        // Total badge count is only unread channels (not mentions)
        let finalBadgeCount = totalUnreadCount
        
        // Update app badge count
        DispatchQueue.main.async {
            application.applicationIconBadgeNumber = finalBadgeCount
        }
    }
    
    /// Clears the app badge count
    func clearAppBadge() {
        guard let application = ViewState.application else { return }
        
        DispatchQueue.main.async {
            application.applicationIconBadgeNumber = 0
        }
    }
    
    /// Manually refreshes the app badge count - useful for debugging or when the count seems incorrect
    func refreshAppBadge() {
        updateAppBadgeCount()
    }
    
    /// Debug badge count and print detailed analysis to console
    func debugBadgeCount() {
        // Debug function - no logging
    }
    
    /// Clean up stale unread entries for channels that no longer exist
    func cleanupStaleUnreads() {
        var removedCount = 0
        var staleChannels: [String] = []
        
        for channelId in unreads.keys {
            // Check if channel exists in our channels dictionary or allEventChannels
            if channels[channelId] == nil && allEventChannels[channelId] == nil {
                staleChannels.append(channelId)
                removedCount += 1
            }
        }
        
        // Remove stale entries
        for channelId in staleChannels {
            unreads.removeValue(forKey: channelId)
        }
        
        // Update badge count after cleanup
        updateAppBadgeCount()
    }
    
    /// Force mark all channels as read and clear the app badge
    func forceMarkAllAsRead() {
        print("📖 Force marking all channels as read...")
        let channelCount = unreads.count
        
        // Clear all unreads
        unreads.removeAll()
        
        // Clear the app badge
        clearAppBadge()
    }
    
    /// Show detailed unread message counts for each channel
    func showUnreadCounts() {
        var totalUnreadMessages = 0
        var totalMentions = 0
        var channelsWithUnread: [(name: String, id: String, unreadCount: Int, mentionCount: Int)] = []
        
        for (channelId, unread) in unreads {
            let channel = channels[channelId] ?? allEventChannels[channelId]
            let channelName = channel?.name ?? "Unknown Channel"
            
            // Skip if channel doesn't exist
            guard let channel = channel else {
                continue
            }
            
            // Check notification settings
            let isChannelMuted = userSettingsStore.cache.notificationSettings.channel[channelId] == .muted || 
                                userSettingsStore.cache.notificationSettings.channel[channelId] == .none
            let serverIdForChannel = channel.server
            let isServerMuted = serverIdForChannel != nil ? 
                (userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .muted || 
                 userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .none) : false
            
            // Calculate unread count
            var unreadCount = 0
            if let lastUnreadId = unread.last_id, let lastMessageId = channel.last_message_id {
                if lastUnreadId < lastMessageId {
                    // We can't get exact count without fetching messages, but we know there are unread messages
                    unreadCount = -1 // -1 means "has unread but count unknown"
                }
            }
            
            let mentionCount = unread.mentions?.count ?? 0
            
            if unreadCount != 0 || mentionCount > 0 {
                let mutedIndicator = (isChannelMuted || isServerMuted) ? " 🔇" : ""
                channelsWithUnread.append((
                    name: channelName + mutedIndicator,
                    id: channelId,
                    unreadCount: unreadCount,
                    mentionCount: mentionCount
                ))
                
                if !(isChannelMuted || isServerMuted) {
                    if unreadCount == -1 {
                        totalUnreadMessages += 1 // Count as at least 1
                    } else if unreadCount > 0 {
                        totalUnreadMessages += unreadCount
                    }
                    totalMentions += mentionCount
                }
            }
        }
        
        // Sort by mention count first, then by name
        channelsWithUnread.sort { 
            if $0.mentionCount != $1.mentionCount {
                return $0.mentionCount > $1.mentionCount
            }
            return $0.name < $1.name
        }
        
    }
    
    /// Get unread counts as a formatted string for UI display
    func getUnreadCountsString() -> String {
        var result = "📊 UNREAD MESSAGE COUNTS\n\n"
        
        var channelsWithUnread: [(name: String, id: String, unreadCount: Int, mentionCount: Int, isMuted: Bool)] = []
        
        for (channelId, unread) in unreads {
            let channel = channels[channelId] ?? allEventChannels[channelId]
            let channelName = channel?.name ?? "Unknown Channel"
            
            // Skip if channel doesn't exist
            guard let channel = channel else {
                continue
            }
            
            // Check notification settings
            let isChannelMuted = userSettingsStore.cache.notificationSettings.channel[channelId] == .muted || 
                                userSettingsStore.cache.notificationSettings.channel[channelId] == .none
            let serverIdForChannel = channel.server
            let isServerMuted = serverIdForChannel != nil ? 
                (userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .muted || 
                 userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .none) : false
            
            let isMuted = isChannelMuted || isServerMuted
            
            // Calculate unread count
            var unreadCount = 0
            if let lastUnreadId = unread.last_id, let lastMessageId = channel.last_message_id {
                if lastUnreadId < lastMessageId {
                    unreadCount = -1 // -1 means "has unread but count unknown"
                }
            }
            
            let mentionCount = unread.mentions?.count ?? 0
            
            if unreadCount != 0 || mentionCount > 0 {
                channelsWithUnread.append((
                    name: channelName,
                    id: channelId,
                    unreadCount: unreadCount,
                    mentionCount: mentionCount,
                    isMuted: isMuted
                ))
            }
        }
        
        // Sort by muted status first, then mention count, then name
        channelsWithUnread.sort { 
            if $0.isMuted != $1.isMuted {
                return !$0.isMuted // Unmuted first
            }
            if $0.mentionCount != $1.mentionCount {
                return $0.mentionCount > $1.mentionCount
            }
            return $0.name < $1.name
        }
        
        if channelsWithUnread.isEmpty {
            result += "✅ No channels with unread messages!"
        } else {
            var unmutedCount = 0
            var mutedCount = 0
            
            result += "📌 Unmuted channels:\n"
            for channel in channelsWithUnread where !channel.isMuted {
                let unreadText = channel.unreadCount == -1 ? "Has unread" : "\(channel.unreadCount) unread"
                let mentionText = channel.mentionCount > 0 ? ", \(channel.mentionCount) mention(s)" : ""
                result += "• \(channel.name): \(unreadText)\(mentionText)\n"
                unmutedCount += 1
            }
            
            if unmutedCount == 0 {
                result += "None\n"
            }
            
            result += "\n🔇 Muted channels:\n"
            for channel in channelsWithUnread where channel.isMuted {
                let unreadText = channel.unreadCount == -1 ? "Has unread" : "\(channel.unreadCount) unread"
                let mentionText = channel.mentionCount > 0 ? ", \(channel.mentionCount) mention(s)" : ""
                result += "• \(channel.name): \(unreadText)\(mentionText)\n"
                mutedCount += 1
            }
            
            if mutedCount == 0 {
                result += "None\n"
            }
            
            result += "\n📊 Summary:\n"
            result += "• Total channels with unread: \(channelsWithUnread.count)\n"
            result += "• Unmuted channels: \(unmutedCount)\n"
            result += "• Muted channels: \(mutedCount)\n"
            result += "• Current badge: \(ViewState.application?.applicationIconBadgeNumber ?? 0)"
        }
        
        return result
    }
    // MARK: - Message queue processing state
    private var isProcessingQueue: [String: Bool] = [:] // Prevent concurrent processing per channel
    
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
    
    // Function to send the queuing of messages
    func trySendingQueuedMessages() {
        print("👍🏻 Entered trySendingQueuedMessages")
        guard InternetMonitor.shared.isConnected else { 
            print("❌ Not connected, aborting queue send")
            return 
        }

        print("📌 queuedMessages count:", queuedMessages.count)
        
        // Get a snapshot of channels to process (avoid concurrent modification)
        let channelsToProcess = Array(queuedMessages.keys)
        
        // Process each channel sequentially with concurrency guard
        for channelId in channelsToProcess {
            // Skip if already processing this channel
            if isProcessingQueue[channelId] == true {
                print("⏭️ Skipping channel \(channelId) - already processing")
                continue
            }
            
            // Create a task for this channel to maintain message order
            Task {
                // Mark channel as being processed
                await MainActor.run {
                    self.isProcessingQueue[channelId] = true
                }
                
                defer {
                    // Always clear the processing flag when done
                    Task { @MainActor in
                        self.isProcessingQueue[channelId] = false
                    }
                }
                
                var sentCount = 0
                
                // Keep sending from the front of the queue until it's empty or send fails
                while await MainActor.run(body: { self.queuedMessages[channelId]?.isEmpty == false }) {
                    // Safely get and remove the first message atomically
                    let msg = await MainActor.run { () -> QueuedMessage? in
                        guard let first = self.queuedMessages[channelId]?.first else {
                            return nil
                        }
                        // Remove it immediately to prevent duplicate sends
                        self.queuedMessages[channelId]?.removeFirst()
                        return first
                    }
                    
                    guard let msg = msg else {
                        break
                    }
                    
                    sentCount += 1
                    print("📌 Sending queued message \(sentCount) for channel \(channelId) - nonce: \(msg.nonce)")
                    
                    do {
                        print("👍🏻 Sending message: \(msg.content)")
                        let _ = try await http.sendMessage(
                            channel: channelId,
                            replies: msg.replies,
                            content: msg.content,
                            attachments: [],
                            nonce: msg.nonce
                        ).get()
                        print("📤 Sent queued message \(sentCount) successfully - nonce: \(msg.nonce)")
                    } catch {
                        print("❌ Failed to send queued message - nonce: \(msg.nonce), error: \(error)")
                        // Re-add the message back to the front of the queue on failure
                        await MainActor.run {
                            self.queuedMessages[channelId]?.insert(msg, at: 0)
                        }
                        // Stop trying to send remaining messages in this channel if one fails
                        break
                    }
                }
                
                // Clean up empty queue entries
                await MainActor.run {
                    if self.queuedMessages[channelId]?.isEmpty == true {
                        self.queuedMessages.removeValue(forKey: channelId)
                    }
                    print("👍🏻 Finished processing channel \(channelId) - sent \(sentCount) messages")
                }
            }
        }
        print("👍🏻 Exiting trySendingQueueMessage")
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


extension ViewState {
    
    // Defining the path of the cache and type of the cache
    static func serversCacheURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ZekoChat")
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create Application Support directory:", error)
            return nil
        }
        return dir.appendingPathComponent("servers_cache.json")
    }
    
    // Load the cache when app boots up
    static func loadServersCacheSync() -> OrderedDictionary <String, Server> {
        guard let url = serversCacheURL(), FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        do {
            let data  = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(OrderedDictionary<String, Server>.self, from: data)
        } catch {
            print("❌ Failed to load servers cache:", error)
            return [:]
        }
    }
    
    func saveServersCacheAsync() {
        let serversSnapshot = self.servers
        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(serversSnapshot)
                if let url = await ViewState.serversCacheURL() {
                    try data.write(to: url, options: .atomic)
                    print("✅ Saved servers cache to \(url.path)")
                }
            } catch {
                print("❌ Failed to write servers cache:", error)
            }
        }
    }
    
    
    func applyServerOrdering() {
        let ordering = self.userSettingsStore.cache.orderSettings.servers
        let allServers = Array(self.servers.values)

        let serverDict = Dictionary(uniqueKeysWithValues: allServers.map { ($0.id, $0) })
        let orderedServers = ordering.compactMap { serverDict[$0] }
        let remainingServers = allServers.filter { !ordering.contains($0.id) }

        let finalServers = orderedServers + remainingServers

        // Update `servers` preserving key-value order
        var newServers = OrderedDictionary<String, Server>()
        for server in finalServers {
            newServers[server.id] = server
        }
        self.servers = newServers
    }
}


extension ViewState {
    /// Sets the `active` property of a DMChannel with the given ID to `false`.
    /// - Parameter id: The ID of the channel to update.
    func deactivateDMChannel(with id: String) {
        Task { @MainActor in
            if let index = dms.firstIndex(where: {
                if case let .dm_channel(dmChannel) = $0 {
                    return dmChannel.id == id && dmChannel.active
                }
                return false
            }) {
                if case var .dm_channel(dmChannel) = dms[index] {
                    // Update the active state to false
                    dmChannel.active = false
                    dms[index] = .dm_channel(dmChannel) // Update the channel in the list
                }
            }
        }
    }
    
    /// Closes the DM group by calling an API and deactivating the DM channel in the `dms` list.
    /// - Parameter channelId: The ID of the channel to close.
    func closeDMGroup(channelId: String) async {
        do {
            // Call the API to close the DM group
            let _ = try await self.http.closeDMGroup(channelId: channelId).get()
            
            // Deactivate the DM channel in the list
            await MainActor.run {
                self.deactivateDMChannel(with: channelId)
            }
        } catch let error {
            print("Error closing DM group: \(error)")
        }
    }
    
    
    func isCurrentUserOwner(of serverID: String) -> Bool {
        guard let currentUser = currentUser else {
            return false
        }
        
        guard let server = servers[serverID] else {
            return false
        }
        
        return server.owner == currentUser.id
    }
    
    
    func removeServer(with serverID: String) {
        Task { @MainActor in
            servers.removeValue(forKey: serverID)
            selectDms()
        }
    }
    
    @MainActor
    func removeChannel(with channelID : String, initPath: Bool = true){
        if(initPath){
            self.path = .init()
            selectDms()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            //TODO
            self.channels.removeValue(forKey: channelID)
            self.dms = self.dms.filter { $0.id != channelID }
        }
        
    }
    
    // MARK: - Ready Event Processing Functions
    
    // Structure to hold only the data we need
    private struct ReadyEventData {
        let channels: [Channel]
        let servers: [Server]
        let users: [Types.User]
        let members: [Member]
        let emojis: [Emoji]
    }
    
    // Extract only needed data from the large event
    private func extractNeededDataFromReadyEvent(_ event: ReadyEvent) -> ReadyEventData {
        // print("🚀 VIEWSTATE: Extracting needed data from ready event")
        
        // Process all servers (removed limitation)
        let ordering = self.userSettingsStore.cache.orderSettings.servers
        let serverDict = Dictionary(uniqueKeysWithValues: event.servers.map { ($0.id, $0) })
        let orderedServers: [Server] = ordering.compactMap { serverDict[$0] }
        let remainingServers = event.servers.filter { !ordering.contains($0.id) }
        let allServers = orderedServers + remainingServers
        
        // print("   - Processing all \(event.servers.count) servers (no limitation)")
        
        // Get server IDs for channel filtering
        let serverIds = Set(allServers.map { $0.id })
        
        // LAZY LOADING: Store ALL channels but only load DMs immediately
        allEventChannels.removeAll() // Clear existing stored channels
        
        var neededChannels: [Channel] = [] // Only DMs will be loaded immediately
        var dmCount = 0
        var storedServerChannels = 0
        
        for channel in event.channels {
            // Store ALL channels for lazy loading
            allEventChannels[channel.id] = channel
            
            var shouldLoadNow = false
            
            switch channel {
            case .dm_channel(let dm):
                // ALWAYS load DMs immediately (both active and inactive)
                shouldLoadNow = true
                dmCount += 1
                // print("🚀 VIEWSTATE: Loading DM channel \(channel.id) immediately (active: \(dm.active))")
            case .group_dm_channel:
                // ALWAYS load Group DMs immediately
                shouldLoadNow = true
                dmCount += 1
                // print("🚀 VIEWSTATE: Loading Group DM channel \(channel.id) immediately")
            case .text_channel(let textChannel):
                // Store server channels but don't load them yet
                if serverIds.contains(textChannel.server) {
                    storedServerChannels += 1
                    // print("🔄 LAZY_CHANNEL: Stored text channel \(channel.id) for server \(textChannel.server)")
                }
            case .voice_channel(let voiceChannel):
                // Store voice channels but don't load them yet
                if serverIds.contains(voiceChannel.server) {
                    storedServerChannels += 1
                    // print("🔄 LAZY_CHANNEL: Stored voice channel \(channel.id) for server \(voiceChannel.server)")
                }
            default:
                break
            }
            
            if shouldLoadNow {
                neededChannels.append(channel)
            }
        }
        
        // print("   - Stored \(allEventChannels.count) total channels for lazy loading")
        // print("   - Loading immediately: \(neededChannels.count) channels (DMs: \(dmCount))")
        // print("   - Stored for lazy loading: \(storedServerChannels) server channels")
        
        // Return only the data we need
        return ReadyEventData(
            channels: neededChannels,
            servers: allServers,
            users: event.users, // Keep all users for now
            members: event.members,
            emojis: event.emojis
        )
    }
    
    // Process the extracted data
    private func processReadyData(_ data: ReadyEventData) async {
        let processReadySpan = launchTransaction?.startChild(operation: "processReady")
        
        // Process channels
        processChannelsFromData(data.channels)
        
        // Process servers  
        processServersFromData(data.servers)
        
        // Process users
        processUsers(data.users)
        
        // EMERGENCY: If still too many users, force immediate cleanup
        if users.count > maxUsersInMemory {
            // print("🚨 EMERGENCY: Still have \(users.count) users after processing, forcing cleanup!")
            let currentUserId = currentUser?.id
            let currentUserObject = currentUser
            
            users.removeAll()
            
            if let currentUserId = currentUserId, let currentUserObject = currentUserObject {
                users[currentUserId] = currentUserObject
                currentUser = currentUserObject
            }
            
            // print("🚨 EMERGENCY CLEANUP: Reduced users to \(users.count)")
        }
        
        // Process members
        processMembers(data.members)
        
        // Process DMs
        processDMs(channels: Array(channels.values))
        
        // Process emojis
        for emoji in data.emojis {
            self.emojis[emoji.id] = emoji
        }
        
        // MEMORY FIX: Don't fetch unreads here - it might trigger another ready event
        // We'll fetch them separately after full initialization
        // print("🚀 VIEWSTATE: Skipping unreads fetch during ready processing to prevent memory spike")
        
        // Update state
        state = .connected
        wsCurrentState = .connected
        ws?.currentState = .connected
        ws?.retryCount = 0
        
        await verifyStateIntegrity()
        
        processReadySpan?.finish()
        launchTransaction?.finish()
        
        // Check for stale messages
        for channel in channels.values {
            if let last_message_id = channel.last_message_id,
               let last_cached_message = channelMessages[channel.id]?.last,
               last_message_id != last_cached_message
            {
                channelMessages[channel.id] = []
            }
        }
        
        // print("🚀 VIEWSTATE: Ready event processing completed")
        // print("   - Final channels: \(channels.count)")
        // print("   - Final users: \(users.count)")
        // print("   - Final servers: \(servers.count)")
        
        // Retry any pending notification token upload
        if pendingNotificationToken != nil {
            // print("🔄 READY_EVENT: Found pending notification token, attempting retry...")
            Task {
                await retryUploadNotificationToken()
            }
        }
        
        // MEMORY FIX: Fetch unreads separately to prevent memory spike
        Task {
            // print("🚀 VIEWSTATE: Starting unreads fetch after ready completion")
            if let remoteUnreads = try? await http.fetchUnreads().get() {
                await MainActor.run {
                    for unread in remoteUnreads {
                        unreads[unread.id.channel] = unread
                    }
                    // print("🚀 VIEWSTATE: Unreads loaded: \(remoteUnreads.count)")
                    
                    // Update app badge count after loading unreads from server
                    updateAppBadgeCount()
                }
            }
        }
    }
    
    private func processChannelsFromData(_ eventChannels: [Channel]) {
        // print("🚀 VIEWSTATE: Processing \(eventChannels.count) channels from WebSocket")
        // print("🚀 VIEWSTATE: Existing channels count: \(channels.count)")
        
        // CRITICAL FIX: Don't clear existing channels - merge instead
        // Only clear channelMessages as they should be fresh from server
        channelMessages.removeAll()
        
        var messageArrayCount = 0
        var dmChannels = 0
        var groupDmChannels = 0
        var textChannels = 0
        
        // Process all channels (already filtered)
        for channel in eventChannels {
            channels[channel.id] = channel
            
            // Create message array for messageable channels
            switch channel {
            case .dm_channel(let dm):
                // Create message array for ALL DMs (active and inactive)
                channelMessages[channel.id] = []
                messageArrayCount += 1
                dmChannels += 1
                // print("🚀 VIEWSTATE: Added DM channel \(channel.id) (active: \(dm.active))")
            case .group_dm_channel:
                channelMessages[channel.id] = []
                messageArrayCount += 1
                groupDmChannels += 1
                // print("🚀 VIEWSTATE: Added Group DM channel \(channel.id)")
            case .text_channel:
                channelMessages[channel.id] = []
                messageArrayCount += 1
                textChannels += 1
            default:
                break
            }
        }
        
        // print("🚀 VIEWSTATE: Stored \(channels.count) channels, created \(messageArrayCount) message arrays")
        // print("🚀 VIEWSTATE: Channel breakdown - DMs: \(dmChannels), Group DMs: \(groupDmChannels), Text: \(textChannels)")
    }
    
    private func processServersFromData(_ servers: [Server]) {
        // print("🚀 VIEWSTATE: Processing \(servers.count) servers from WebSocket")
        // print("🚀 VIEWSTATE: Existing servers count: \(self.servers.count)")
        
        // CRITICAL FIX: Don't clear existing servers - merge instead
        // Keep existing servers and update/add new ones from WebSocket
        for server in servers {
            self.servers[server.id] = server
            if members[server.id] == nil {
                members[server.id] = [:]
            }
        }
        
        // print("🚀 VIEWSTATE: Final servers count after merge: \(self.servers.count)")
        self.saveServersCacheAsync()
    }
}


enum UnreadCount : Equatable {
    case unread
    case mentions(String)
    case unreadWithMentions(mentionsCount: String)
}

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
