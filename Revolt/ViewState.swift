import Foundation
import OSLog
import SwiftUI
import Alamofire
import ULID
import Collections
import Sentry
@preconcurrency import Types
import UserNotifications
import KeychainAccess
import Darwin



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
    
    // MARK: - Database Integration
    /// DatabaseObserver for Realm integration
    /// Observes Realm database changes and updates ViewState
    var databaseObserver: DatabaseObserver?
    
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
    @Published var users: [String: Types.User]
    
    func updateRelationship(for userId: String, with newRelationship: Relation) {
        if var user = users[userId] {
            user.relationship = newRelationship
            users[userId] = user  // Update the dictionary
            
            // The didSet will trigger automatically and save to UserDefaults
        }
    }
    
    @Published var servers: OrderedDictionary<String, Server>
    @Published var channels: [String: Channel]
    @Published var messages: [String: Message]
    @Published var channelMessages: [String: [String]]
    @Published var members: [String: [String: Member]]
    @Published var dms: [Channel]
    
    // DM Management (database-first architecture)
    private var isDmListInitialized = false // Track if DM list has been initialized
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
            isAutoAckDisabled = false
            autoAckDisableTime = nil
            return false
        }
    }
    
    // MEMORY MANAGEMENT: Add debouncing for UserDefaults saves (main-actor only)
    private var saveWorkItems: [String: DispatchWorkItem] = [:]
    #if DEBUG
    private let saveLogger = Logger(subsystem: "chat.revolt.app", category: "UserDefaultsSave")
    #endif
    private let saveDebounceInterval: TimeInterval = 2.0 // Save after 2 seconds of no changes
    private let cleanupTriggeredAt = 800 // Start cleanup when 80% full (legacy, not used)
    private let maxChannelsInMemory = 2000 // Maximum channels to keep in memory (increased to load all servers)
    
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
    
    // MEMORY MANAGEMENT: Configuration for aggressive cleanup
    private let maxMessagesInMemory = 7000 // Maximum messages to keep in memory
    private let maxUsersInMemory = 2000 // Increased to handle 300+ messages with users
    private let maxChannelMessages = 800 // Maximum messages per channel (reduced for better memory management)
    private let maxServersInMemory = 50 // Maximum servers to keep in memory
    
    // PRELOADING CONTROL: Configuration for automatic message preloading
    /// Set to false to disable all automatic message preloading when entering servers/channels
    private let enableAutomaticPreloading = false // DISABLED: No automatic preloading
    
    // MEMORY MANAGEMENT: Helper methods
    @MainActor
    private func debouncedSave(key: String, data: Data) {
        #if DEBUG
        saveLogger.debug("Scheduling debounced save for key=\(key, privacy: .public) on main thread")
        #endif
        // Cancel any existing save operation for this key
        saveWorkItems[key]?.cancel()

        // Create a new work item that writes on main (we are already on main)
        let workItem = DispatchWorkItem { [weak self] in
            #if DEBUG
            self?.saveLogger.debug("Writing defaults for key=\(key, privacy: .public) on main thread")
            #endif
            UserDefaults.standard.set(data, forKey: key)
            self?.saveWorkItems.removeValue(forKey: key)
        }

        // Store and schedule the work item on main after debounce interval
        saveWorkItems[key] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }
    
    /// Force immediate save of users data without debouncing
    /// Used when app is terminating to ensure data is persisted
    @MainActor
    public func forceSaveUsers() {
        // Cancel any pending save for users
        saveWorkItems["users"]?.cancel()
        saveWorkItems.removeValue(forKey: "users")

        if let data = try? JSONEncoder().encode(users) {
            #if DEBUG
            saveLogger.debug("Force saving users on main thread")
            #endif
            UserDefaults.standard.set(data, forKey: "users")
            UserDefaults.standard.synchronize()
        }
    }
    
    @MainActor
    private func enforceMemoryLimits() {
        // DATABASE-FIRST: Memory limits no longer needed - data lives in database, not memory
        // ViewState only holds temporary/session data that naturally stays small
        return
        
        // Check current memory usage
        let currentMemoryMB = getCurrentMemoryUsage()
        
        // EMERGENCY MEMORY RESET if over 4GB
        if currentMemoryMB > 4000 {
            
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
            
            return
        }
        
                    // AGGRESSIVE MEMORY CLEANUP if over 2GB (increased threshold for better performance)
            if currentMemoryMB > 2000 {
                
                // VIRTUAL SCROLLING PROTECTION: Skip aggressive cleanup if in DM view
                if currentSelection == .dms {
                    return
                }
                
                                    // CRITICAL FIX: Keep ALL users to prevent black messages - only clear non-essential data
                    // Don't touch users at all - they are needed for message display
                
                // Keep only last 100 messages
                let sortedMessages = messages.sorted { $0.value.id > $1.value.id }
                let recentMessages = Array(sortedMessages.prefix(100))
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
                    // DMs are already loaded from database, no need to reinitialize
                    // Database-first approach keeps state consistent
                }
                
                return
            }
        
        // NORMAL CLEANUP: Remove excess messages
        if messages.count > maxMessagesInMemory {
            
            // Get all message IDs sorted by timestamp (older first)
            let sortedMessageIds = messages.keys.sorted { id1, id2 in
                let date1 = createdAt(id: id1)
                let date2 = createdAt(id: id2)
                return date1 < date2
            }
            
            // Calculate how many messages to remove
            let messagesToRemove = messages.count - maxMessagesInMemory
            let idsToRemove = Array(sortedMessageIds.prefix(messagesToRemove))
            
            // Remove messages
            for id in idsToRemove {
                messages.removeValue(forKey: id)
            }
            
            // Clean up channel message references
            for (channelId, messageIds) in channelMessages {
                let filteredIds = messageIds.filter { !idsToRemove.contains($0) }
                if filteredIds.count != messageIds.count {
                    channelMessages[channelId] = filteredIds
                }
            }
            
        }
        
        // AGGRESSIVE CHANNEL MESSAGE CLEANUP
        for (channelId, messageIds) in channelMessages {
            if messageIds.count > maxChannelMessages {
                let trimmedIds = Array(messageIds.suffix(maxChannelMessages))
                channelMessages[channelId] = trimmedIds
            }
        }
    }
    
    // DATABASE-FIRST: All cleanup functions removed - data managed by ChannelDataManager per-view
    @MainActor
    private func smartMessageCleanup() {
        // No longer needed - messages loaded on-demand from database
        return
    }
    
    @MainActor
    private func smartUserCleanup() {
        // No longer needed - users loaded on-demand from database
        return
    }
    
    @MainActor
    private func cleanupMemory() {
        // No longer needed - memory naturally bounded by per-view data managers
        return
    }
    
    // Smart channel cleanup to prevent excessive memory usage
    @MainActor
    private func smartChannelCleanup() {
        // FIX: Don't cleanup when in DM view or when DM list is being displayed
        if currentSelection == .dms {
            return
        }
        
        // Clean up channels that haven't been accessed
        if channels.count > maxChannelsInMemory {
            
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
        
        // Get current channel messages
        guard let currentChannelMessages = channelMessages[channelId] else {
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
            
        } else {
        }
        
        // Clean up orphaned messages (messages that don't belong to any channel anymore)
        cleanupOrphanedMessages()
        
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
        }
    }
    
    // Clean all channel messages to keep only last 100 per channel
    @MainActor
    func cleanupAllChannelMessages() {
        
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
            }
        }
        
        // Clean up any orphaned messages
        cleanupOrphanedMessages()
        
    }
    
    // Set loading state when entering a channel that needs message loading
    @MainActor
    func setChannelLoadingState(isLoading: Bool) {
        isLoadingChannelMessages = isLoading
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
            clearChannelMessages(channelId: actualPreviousChannelId)
            
            // CRITICAL: Clear target message ID when switching channels to prevent re-targeting
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
                clearChannelMessages(channelId: channelId)
            }
        }
        
        // If we're entering channel view, check if we need to show loading
        if !wasInChannelView && isInChannelView {
            if case .channel(let channelId) = currentChannel {
                let hasMessages = (channelMessages[channelId]?.count ?? 0) > 0
                if !hasMessages {
                    setChannelLoadingState(isLoading: true)
                }
            }
        }
    }
    
    static func decodeUserDefaults<T: Decodable>(forKey key: String, withDecoder decoder: JSONDecoder) throws -> T? {
        if let value = UserDefaults.standard.data(forKey: key) {
            do {
                let result = try decoder.decode(T.self, from: value)
                return result
            } catch {
                throw error
            }
        } else {
            return nil
        }
    }
    
    static func decodeUserDefaults<T: Decodable>(forKey key: String, withDecoder decoder: JSONDecoder, defaultingTo def: T) -> T {
        do {
            if let result: T = try decodeUserDefaults(forKey: key, withDecoder: decoder) {
                return result
            } else {
                return def
            }
        } catch {
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
        

        // DATABASE-FIRST: Remove UserDefaults data loading to prevent memory spikes at launch
        // All data now loaded from Realm database on-demand through repositories
        
        // Initialize empty - data will be loaded from database when needed
        self.users = [:]
        self.servers = [:]
        self.channels = [:]
        self.messages = [:]
        self.channelMessages = [:]
        self.members = [:]
        self.dms = []
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
        
        // MEMORY MANAGEMENT: Start periodic memory cleanup
        startPeriodicMemoryCleanup()
        
        // Log loaded data counts after all initialization is complete
        
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
        
        // MARK: - Database Cleanup Service
        // Start periodic database cleanup to prevent unbounded growth
        Task {
            await DatabaseCleanupService.shared.startPeriodicCleanup()
        }
        
        // MARK: - Database Observer Setup
        // Initialize DatabaseObserver after ViewState is fully set up
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Give ViewState a moment to fully initialize
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            self.databaseObserver = DatabaseObserver(viewState: self)
            
            // Load channels and servers from database
            await self.loadChannelsAndServersFromDatabase()
        }
    }
    
    // MARK: - Database Loading
    
    /// Loads channels and servers from database on app start
    @MainActor
    func loadChannelsAndServersFromDatabase() async {
        
        // Load servers
        let dbServers = await ServerRepository.shared.fetchAllServers()
        for server in dbServers {
            self.servers[server.id] = server
            if members[server.id] == nil {
                members[server.id] = [:]
            }
        }
        
        // Load channels
        let dbChannels = await ChannelRepository.shared.fetchAllChannels()
        for channel in dbChannels {
            self.channels[channel.id] = channel
            
            // Populate DMs array
            switch channel {
            case .dm_channel(_), .group_dm_channel(_):
                if !self.dms.contains(where: { $0.id == channel.id }) {
                    self.dms.append(channel)
                }
            default:
                break
            }
            
            // Create message arrays for messageable channels
            if self.channelMessages[channel.id] == nil {
                self.channelMessages[channel.id] = []
            }
        }
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
        }
    }
    
    // MEMORY MANAGEMENT: Periodic cleanup timer
    private var memoryCleanupTimer: Timer?
    private var memoryMonitorTimer: Timer?
    
    private func startPeriodicMemoryCleanup() {
        memoryCleanupTimer?.invalidate()
        
        // Clean up memory every 15 seconds for better stability
        memoryCleanupTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor [weak self] in
                self?.cleanupMemory()
            }
        }
        
        // Start memory monitoring
        startMemoryMonitoring()
    }
    
    // MEMORY MONITORING: Track memory usage
    private func startMemoryMonitoring() {
        memoryMonitorTimer?.invalidate()
        
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let memoryUsage = self.getCurrentMemoryUsage()
            
            // COMPLETE PROTECTION for DM View - NO CLEANUP at all
            if currentSelection == .dms {
                return // Skip all cleanup when in DM view
            }
            
            // CRITICAL FIX: Skip cleanup when loading older messages
            if isLoadingOlderMessages {
                return
            }
            
            // DISABLED: No immediate user cleanup to prevent black messages
            if users.count > maxUsersInMemory {
                // Don't call smartUserCleanup() to prevent black messages
            }
            
            // Warning if memory usage is high (only for non-DM views)
            if memoryUsage > 1500 { // Increased threshold to 1.5GB for better performance
                
                // Force immediate aggressive cleanup
                enforceMemoryLimits()
                smartUserCleanup()
                smartChannelCleanup()
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
    
    // DISABLED: Add proactive cleanup when adding new messages/users
    @MainActor
    func checkAndCleanupIfNeeded() {
        // CRITICAL FIX: Disable all proactive cleanup to prevent black messages
        
        // Only log warnings if approaching limits
        if messages.count > Int(Double(maxMessagesInMemory) * 0.9) {
        }
        
        if users.count > Int(Double(maxUsersInMemory) * 0.9) {
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
        
    }
    
    /// Clean up users that are no longer needed after leaving a channel
    @MainActor
    private func cleanupUnusedUsers(excludingChannelId: String) {
        
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
    }
    
    /// INSTANT force memory cleanup - IMMEDIATE execution
    @MainActor
    func forceMemoryCleanup() {
        let startTime = CFAbsoluteTimeGetCurrent()
        
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
                                    Task {
                                        let response = await self.http.uploadNotificationToken(token: existingToken)
                                        switch response {
                                            case .success:
                                                break
                                            case .failure(let error):
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
                    break
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
        
        ws?.stop()
        
        // Resume connection after a short delay (when Safari likely has established its connection)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.resumeWebSocketAfterSuspension()
        }
    }
    
    /// Resumes WebSocket connection after temporary suspension
    private func resumeWebSocketAfterSuspension() {
        
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
            
            // CRITICAL FIX: Preserve current channel and selection during ready event
            let savedCurrentChannel = currentChannel
            let savedCurrentSelection = currentSelection
            
            // CRITICAL FIX: Don't clear servers/channels/users completely - merge with existing data
            
            // Only clear messages as they should be fresh from server
            messages.removeAll()
            channelMessages.removeAll()
            
            // For users, channels, and servers: merge instead of clearing completely
            // This preserves any data loaded from UserDefaults
            
            // MEMORY FIX: Extract only needed data and process immediately
            // This allows the large event object to be released from memory
            let neededData = extractNeededDataFromReadyEvent(event)
            
            // Process the extracted data
            await processReadyData(neededData)
            
            // CRITICAL FIX: Restore saved state after ready event processing
            currentChannel = savedCurrentChannel
            currentSelection = savedCurrentSelection
            
            // If the saved channel is from a server, make sure that server's channels are loaded
            if case .channel(let channelId) = savedCurrentChannel {
                if let restoredChannel = channels[channelId] {
                    // Channel already loaded from database
                    // No action needed
                    
                    if let serverId = restoredChannel.server {
                        // Make sure we're in the right selection
                        if savedCurrentSelection != .server(serverId) {
                            currentSelection = .server(serverId)
                        }
                        // Channels already loaded from database, no need to load
                    }
                } else {
                }
            }
            
            // CONDITIONAL: Only preload after Ready event if automatic preloading is enabled
            if self.enableAutomaticPreloading {
                // PRELOAD: Trigger preload of important channels after Ready event
                Task {
                    await self.preloadImportantChannels()
                }
            } else {
            }
            
            // CLEANUP: Clean up stale unreads after Ready event
            // This ensures that unreads for deleted channels are removed after server sync
            Task {
                await MainActor.run {
                    self.cleanupStaleUnreads()
                }
            }

        case .message(let m):
            
            
            // ✅ REALM INTEGRATION: Save message to Realm database
            Task.detached(priority: .utility) {
                await MessageRepository.shared.saveMessage(m)
                
                // Save related user if present
                if let user = m.user {
                    await UserRepository.shared.saveUser(user)
                }
                
                // Save related member if present
                if let member = m.member {
                    await MemberRepository.shared.saveMember(member)
                }
            }

            if let user = m.user {
                // CRITICAL FIX: Always add/update message authors to prevent black messages
                users[user.id] = user
                // CRITICAL FIX: Also store in allEventUsers for permanent access
                allEventUsers[user.id] = user
            } else {
                // CRITICAL FIX: If user data not provided, try to load from stored data or create placeholder
                if users[m.author] == nil {
                    if let storedUser = allEventUsers[m.author] {
                        users[m.author] = storedUser
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
            }
            
            messages[m.id] = m
            
            // Check if this message matches a queued message and clean it up
            if let channelQueuedMessages = queuedMessages[m.channel],
               let queuedIndex = channelQueuedMessages.firstIndex(where: { queued in
                   // Match by content, author, and channel for safety
                   return queued.content == m.content && 
                          queued.author == m.author && 
                          queued.channel == m.channel
               }) {
                let queuedMessage = channelQueuedMessages[queuedIndex]
                
                // Remove the temporary message from messages dictionary (if it exists)
                messages.removeValue(forKey: queuedMessage.nonce)
                
                // For messages without attachments: Replace nonce with real ID in channel messages
                // For messages with attachments: Add to channel messages for the first time
                if let nonceMsgIndex = channelMessages[m.channel]?.firstIndex(of: queuedMessage.nonce) {
                    // This was an optimistic message (no attachments), replace it
                    channelMessages[m.channel]?[nonceMsgIndex] = m.id
                } else if queuedMessage.hasAttachments {
                    // This was an attachment message (not shown optimistically), add it now
                    if channelMessages[m.channel] == nil {
                        channelMessages[m.channel] = []
                    }
                    channelMessages[m.channel]?.insert(m.id, at: 0)
                }
                
                // Remove from queued messages for this channel
                queuedMessages[m.channel]?.remove(at: queuedIndex)
                if queuedMessages[m.channel]?.isEmpty == true {
                    queuedMessages.removeValue(forKey: m.channel)
                }
            } else {
                // Check channel messages array
                if channelMessages[m.channel] == nil {
                    channelMessages[m.channel] = []
                }
                
                // MEMORY FIX: Check if message already exists in channel to avoid duplicates
                if !(channelMessages[m.channel]?.contains(m.id) ?? false) {
                    channelMessages[m.channel]?.insert(m.id, at: 0)
                } else {
                }
            }
            
            let channelMessagesAfter = channelMessages[m.channel]?.count ?? 0
            
            
            // Log memory info
            let totalChannelMessages = channelMessages.values.reduce(0) { $0 + $1.count }
            
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
                
                // FIX: Ensure DM list state is maintained (database-first)
                if isDmListInitialized && currentSelection == .dms {
                    // DMs will be re-sorted by processDMs when needed
                    // No manual ordering needed with database-first approach
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
            }
            
        case .authenticated:
            break
            
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
                    
                    
                    // Post notification to update UI
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MessagesDidChange"), 
                            object: ["channelId": e.channel_id, "messageId": e.id, "type": "reaction_added"],
                            userInfo: ["channelId": e.channel_id]
                        )
                    }
                } else {
                }
            } else {
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
                        
                        
                        // Post notification to update UI
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MessagesDidChange"), 
                            object: ["channelId": e.channel_id, "messageId": e.id, "type": "reaction_removed"],
                            userInfo: ["channelId": e.channel_id]
                        )
                    }
                    } else {
                    }
                } else {
                }
            } else {
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
            
            // ✅ REALM INTEGRATION: Save updated user to Realm
            Task.detached(priority: .utility) {
                // Get updated user from ViewState and save to Realm
				if let updatedUser = await self.users[e.id] {
                    await UserRepository.shared.saveUser(updatedUser)
                }
            }
            
        case .server_create(let e):
            self.servers[e.id] = e.server
            for channel in e.channels {
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
            }
            
            // ✅ REALM INTEGRATION: Save new server and its channels to Realm
            Task.detached(priority: .utility) {
                await ServerRepository.shared.saveServer(e.server)
                await ChannelRepository.shared.saveChannels(e.channels)
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
            
            // ✅ REALM INTEGRATION: Delete server from Realm
            Task.detached(priority: .utility) {
                await ServerRepository.shared.deleteServer(id: e.id)
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
            
            // ✅ REALM INTEGRATION: Save updated server to Realm
            if let updatedServer = self.servers[e.id] {
                Task.detached(priority: .utility) {
                    await ServerRepository.shared.saveServer(updatedServer)
                }
            }
            
        case .channel_create(let channel):
            // Add channel directly to active channels (database-first)
            channels[channel.id] = channel
            
            // ✅ REALM INTEGRATION: Save new channel to Realm
            Task.detached(priority: .utility) {
                await ChannelRepository.shared.saveChannel(channel)
            }

            
            // Handle different channel types
            switch channel {
            case .dm_channel(_):
                // DMs are always loaded immediately
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
                self.dms.insert(channel, at: 0)
                
            case .group_dm_channel(_):
                // Group DMs are always loaded immediately
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
                self.dms.insert(channel, at: 0)
                
            case .text_channel(let textChannel):
                // Server channels: only load if server is currently active
                if case .server(let currentServerId) = currentSelection, 
                   currentServerId == textChannel.server {
                    // Load immediately if this server is active
                    self.channels[channel.id] = channel
                    self.channelMessages[channel.id] = []
                } else {
                    // Just store for lazy loading later
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
                } else {
                    // Just store for lazy loading later
                }
                
                // Update server's channel list
                if let serverId = channel.server {
                    self.servers[serverId]?.channels.append(channel.id)
                }
                
            default:
               break
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
            
            // ✅ REALM INTEGRATION: Save updated channel to Realm
            if let updatedChannel = self.channels[e.id] {
                Task.detached(priority: .utility) {
                    await ChannelRepository.shared.saveChannel(updatedChannel)
                }
            }

        case .channel_delete(let e):
            self.deleteChannel(channelId: e.id)
            
            // ✅ REALM INTEGRATION: Delete channel from Realm
            Task.detached(priority: .utility) {
                await ChannelRepository.shared.deleteChannel(id: e.id)
            }
            
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
                        }
                        self.checkAndCleanupIfNeeded()
                    case .failure(_):
						break
                }
                
                switch memberResult {
                    case .success(let member):
                        var serverMembers = self.members[e.id, default: [:]]
                        serverMembers[e.user] = member
                        self.members[e.id] = serverMembers
                    case .failure(_):
						break
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
        
        // Store ALL users for lazy loading (this is our data source)
        allEventUsers = Dictionary(uniqueKeysWithValues: eventUsers.map { ($0.id, $0) })
        
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
                } else {
                    users[user.id] = user
                    updatedCount += 1
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
                } else {
                    users[user.id] = user
                    updatedCount += 1
                }
            }
        }
        
        // 3. Add users needed for visible DMs only (database-first approach)
        // Note: This will be called later in processDMs after dms array is populated
        
        
        if !currentUserFound {
        }
    }
    
    // Load users needed for currently visible DMs
    private func loadUsersForVisibleDms(from userDict: [String: Types.User], maxCount: Int) {
        var loadedCount = 0
        
        // Get first set of DMs (database-first, no batching)
        let visibleDmIds = Array(dms.prefix(15).map { $0.id })
        
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
                    }
                }
            }
        }
        
    }
    
    // Store user data for lazy loading
    var allEventUsers: [String: Types.User] = [:]
    
    // Load users for the first batch of DMs (called during processDMs)
    private func loadUsersForFirstDmBatch() {
        // Prefetch recipients for the first visible set of DMs from DB first, then network
        let maxUsersToLoad = 50
        let visibleDmIds = Array(dms.prefix(15).map { $0.id })
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            var candidateUserIds: [String] = []
            
            for dmId in visibleDmIds {
                if candidateUserIds.count >= maxUsersToLoad { break }
                if let channel = await MainActor.run(body: { self.channels[dmId] }) {
                    var recipientIds: [String] = []
                    switch channel {
                    case .dm_channel(let dm):
                        recipientIds = dm.recipients
                    case .group_dm_channel(let group):
                        recipientIds = group.recipients
                    default:
                        continue
                    }
                    for userId in recipientIds {
                        if candidateUserIds.count >= maxUsersToLoad { break }
                        // Skip if already in memory
                        let inMemory = await MainActor.run(body: { self.users[userId] != nil })
                        if !inMemory {
                            candidateUserIds.append(userId)
                        }
                    }
                }
            }
            
            if candidateUserIds.isEmpty { return }
            
            // 1) Try to resolve from Database in batch
            let dbUsers = await UserRepository.shared.fetchUsers(ids: candidateUserIds)
            if !dbUsers.isEmpty {
                await MainActor.run {
                    for (userId, user) in dbUsers {
                        self.users[userId] = user
                    }
                }
            }
            
            // 2) For any missing, trigger network sync which will also update memory
            let resolvedIds = Set(dbUsers.keys)
            let remaining = candidateUserIds.filter { !resolvedIds.contains($0) }
            if !remaining.isEmpty {
                for userId in remaining {
                    await NetworkSyncService.shared.syncUser(userId: userId, viewState: self)
                }
            }
        }
    }

    // Public wrapper to prefetch users for visible DM items
    func prefetchVisibleDmUsers() {
        loadUsersForFirstDmBatch()
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
                    }
                }
            }
        }
        
        if loadedUsers > 0 {
        }
    }
    
    // CRITICAL FIX: Restore missing users from allEventUsers to prevent black messages
    @MainActor
    func restoreMissingUsersForMessages() {
        var restoredCount = 0
        var placeholderCount = 0
        
        
        // Check all messages in memory
        for (messageId, message) in messages {
            if users[message.author] == nil {
                // Try to restore from allEventUsers
                if let storedUser = allEventUsers[message.author] {
                    users[message.author] = storedUser
                    restoredCount += 1
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
                }
            }
        }
        
        if restoredCount > 0 || placeholderCount > 0 {
        }
    }
    
    // EMERGENCY FIX: Force restore all users for specific channel to prevent black messages
    @MainActor
    func forceRestoreUsersForChannel(channelId: String) {
        guard let messageIds = channelMessages[channelId] else {
            return
        }
        
        var fixedCount = 0
        
        for messageId in messageIds {
            if let message = messages[messageId] {
                if users[message.author] == nil {
                    // Try allEventUsers first
                    if let storedUser = allEventUsers[message.author] {
                        users[message.author] = storedUser
                        fixedCount += 1
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
                    }
                }
            }
        }
        
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
        
        return placeholderUser
    }
    
    
    private func processMembers(_ eventMembers: [Member]) {
        for member in eventMembers {
            members[member.id.server]?[member.id.user] = member
        }
    }
    
    private func processDMs(channels: [Channel]) {
        // Database-first: All DMs loaded directly, no batching
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
        
        // Load all DMs directly (database-first, no batching)
        dms = sortedDmChannels
        
        // Load users for DMs
        loadUsersForFirstDmBatch()
        
        isDmListInitialized = true
    }
    
    // Load a specific batch of DMs
    
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
        
        
                 // AGGRESSIVE CLEANUP: Force immediate cleanup when window slides significantly
         let windowMoved = abs(oldStart - visibleStartBatch) > 0 || abs(oldEnd - visibleEndBatch) > 0
         if windowMoved {
             
             // Clear loaded batches that are no longer visible
             let visibleBatches = Set(visibleStartBatch...visibleEndBatch)
             let oldLoadedBatches = loadedDmBatches
             loadedDmBatches = loadedDmBatches.intersection(visibleBatches)
             
             let removedBatches = oldLoadedBatches.subtracting(loadedDmBatches)
             if !removedBatches.isEmpty {
             }
             
             // TEMPORARILY DISABLED: aggressiveVirtualCleanup()
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
        
        // TEMPORARILY DISABLED: Clean up users from invisible DMs (gentle cleanup here)
        // cleanupUsersFromInvisibleDms(aggressive: false)
    }
    
    // AGGRESSIVE cleanup for Virtual Scrolling - force immediate RAM reduction
    private func aggressiveVirtualCleanup() {
        let memoryBefore = getCurrentMemoryUsage()
        let usersBefore = users.count
        let messagesBefore = messages.count
        
        // 1. Force clean users from invisible DMs
        cleanupUsersFromInvisibleDms(aggressive: true)
        
        // 2. Force clean channel messages from invisible DMs
        cleanupChannelMessagesFromInvisibleDms()
        
        // 3. Force cleanup old messages globally (aggressive)
        if messages.count > 100 {
            let sortedMessages = messages.sorted { $0.value.id > $1.value.id }
            let keepMessages = Array(sortedMessages.prefix(100))
            messages = Dictionary(uniqueKeysWithValues: keepMessages)
        }
        
        // 4. Force garbage collection
        forceGarbageCollection()
        
        let memoryAfter = getCurrentMemoryUsage()
        let usersAfter = users.count
        let messagesAfter = messages.count
        let memorySaved = memoryBefore - memoryAfter
        
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
        }
    }
    */ // END DISABLED Virtual Scrolling functions
    
    // Load next batch when user scrolls to bottom
    
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
                    if let channel = channels[channelId] {
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
            channel = try! await http.openDm(user: user).get()
            await MainActor.run {
                dms.append(channel!)
            }
        }
        
        await MainActor.run {
            currentSelection = .dms
            currentChannel = .channel(channel!.id)
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
        
        // Check unreads for all channels in the server (all loaded from database)
        let serverChannelIds = server.channels
        let channelUnreads = serverChannelIds.compactMap { channelId -> (Channel, UnreadCount?)? in
            // All channels are loaded from database
            if let channel = channels[channelId] {
                return (channel, getUnreadCountFor(channel: channel))
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
                // CRITICAL FIX: Check if channel exists in database
                if let storedChannel = channels[id] {
                    // Channel already in active channels
                    
                    // If it's a server channel, make sure we're in the right selection
                    if let serverId = storedChannel.server {
                        if currentSelection == .dms {
                            currentSelection = .server(serverId)
                        }
                        // Channels already loaded from database
                    }
                } else {
                    logger.warning("Current channel no longer exists even in stored data")
                    currentSelection = .discover
                    currentChannel = .home
                }
            }
        }
        
        if case .server(let id) = currentSelection {
            if servers[id] == nil {
                logger.warning("Current server no longer exists")
                currentSelection = .discover
                currentChannel = .home
            }
        }
    }
    
    func selectServer(withId id: String) {
        // Switch to the server (all channels already loaded from database)
        currentSelection = .server(id)
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // PERFORMANCE: Start preloading messages for this server's channels
            preloadMessagesForServer(serverId: id)
            
            // ENHANCED: Also trigger smart preloading for important channels
            Task {
                await preloadImportantChannels()
            }
        } else {
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
                currentTargetMessageId = nil
            } else if messages[targetId] == nil {
                // Target message not loaded yet, assume it might be for this channel - keep it
            } else {
            }
        }
        
        currentChannel = .channel(id)
        userSettingsStore.store.lastOpenChannels[server] = id
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // AGGRESSIVE PRELOADING: Immediately preload this channel
            Task {
                await preloadSpecificChannel(channelId: id)
            }
        } else {
        }
        
        // CRITICAL FIX: Load users for visible messages when entering channel
        loadUsersForVisibleMessages(channelId: id)
    }
    
    func selectDms() {
        DispatchQueue.main.async {
            // Switch to DMs (channels already loaded from database)
            self.currentSelection = .dms
            
            if let last = self.userSettingsStore.store.lastOpenChannels["dms"] {
                self.currentChannel = .channel(last)
            } else {
                self.currentChannel = .home
            }
            
            // Database-first: DMs are already loaded from database
            // No need to reinitialize - they're kept in sync via DatabaseObserver
            
            // CRITICAL FIX: Load users for visible messages when entering DM view
            if case .channel(let channelId) = self.currentChannel {
                self.loadUsersForVisibleMessages(channelId: channelId)
            }
        }
    }
    
    func selectDiscover() {
        DispatchQueue.main.async {
            // Switch to Discover (channels already loaded from database)
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
                currentTargetMessageId = nil
            } else if messages[targetId] == nil {
                // Target message not loaded yet, assume it might be for this channel - keep it
            } else {
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
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // AGGRESSIVE PRELOADING: Immediately preload this DM
            Task {
                await preloadSpecificChannel(channelId: id)
            }
        } else {
        }
        
        // CRITICAL FIX: Load users for visible messages when entering DM
        self.loadUsersForVisibleMessages(channelId: id)
    }
    
    /// Navigate to a specific channel/message and proactively fetch target context if missing
    @MainActor
    func navigateToChannelMessage(serverId: String?, channelId: String, messageId: String) {
        // Preserve target message for the destination view
        self.currentTargetMessageId = messageId
        
        // Prepare channel state
        self.channelMessages[channelId] = []
        self.atTopOfChannel.remove(channelId)
        
        // Select appropriate context
        if let serverId = serverId, !serverId.isEmpty {
            self.selectServer(withId: serverId)
            self.selectChannel(inServer: serverId, withId: channelId)
        } else {
            self.selectDm(withId: channelId)
        }
        
        // Push channel view
        self.path = []
        self.path.append(NavigationDestination.maybeChannelView)
        
        // Proactively fetch target and nearby context if DB is empty
        NetworkSyncService.shared.syncTargetMessage(
            messageId: messageId,
            channelId: channelId,
            viewState: self
        )
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
        
        // Create placeholder user to prevent empty spaces (will be replaced asynchronously)
        let placeholderUser = Types.User(
            id: otherUserId,
            username: "Loading...",
            discriminator: "0000",
            relationship: .None
        )
        users[otherUserId] = placeholderUser

        // Asynchronously resolve from Database, then Network, and persist
        Task { [weak self] in
            guard let self = self else { return }
            // 1) Try database first
            if let dbUser = await UserRepository.shared.fetchUser(id: otherUserId) {
                await MainActor.run {
                    self.users[otherUserId] = dbUser
                }
                return
            }
            // 2) Fetch from network, then save to DB and update memory
            let result = await self.http.fetchUser(user: otherUserId)
            if case .success(let remoteUser) = result {
                await UserRepository.shared.saveUser(remoteUser)
                await MainActor.run {
                    self.users[otherUserId] = remoteUser
                }
            }
        }
        
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
    
    /// Retry uploading pending notification token
    func retryUploadNotificationToken() async {
        guard let token = pendingNotificationToken else { return }
        
        
        let response = await http.uploadNotificationToken(token: token)
        switch response {
            case .success:
                pendingNotificationToken = nil // Clear pending token after success
                UserDefaults.standard.removeObject(forKey: "pendingNotificationToken")
            case .failure(let error):
                break
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
                
            }
        } catch {
            // Silently handle errors - preloading is a performance optimization, not critical
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
            let channel = channels[channelId]
            
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
            let currentBadge = application.applicationIconBadgeNumber
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
        
        var totalCount = 0
        var mutedCount = 0
        var validCount = 0
        var missingChannels = 0
        var channelsWithUnread = 0
        
        for (channelId, unread) in unreads {
            let channel = channels[channelId]
            let channelName = channel?.name ?? "Unknown"
            let channelExists = channel != nil
            let isChannelMuted = userSettingsStore.cache.notificationSettings.channel[channelId] == .muted
            let serverIdForChannel = channel?.server
            let isServerMuted = serverIdForChannel != nil ? userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .muted : false
            
            
            // Check if has unread
            var hasUnread = false
            if let lastUnreadId = unread.last_id, let lastMessageId = channel?.last_message_id {
                hasUnread = lastUnreadId < lastMessageId
            }
            
            if let mentions = unread.mentions {
            }
            
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
        
    }
    
    /// Clean up stale unread entries for channels that no longer exist
    func cleanupStaleUnreads() {
        var removedCount = 0
        var staleChannels: [String] = []
        
        for channelId in unreads.keys {
            // Check if channel exists in our channels dictionary
            if channels[channelId] == nil {
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
            let channel = channels[channelId]
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
        
        // Print results
        if channelsWithUnread.isEmpty {
        } else {
            for channel in channelsWithUnread {
                let unreadText = channel.unreadCount == -1 ? "Has unread" : "\(channel.unreadCount) unread"
                let mentionText = channel.mentionCount > 0 ? ", \(channel.mentionCount) mention(s)" : ""
            }
        }
        
    }
    
    /// Get unread counts as a formatted string for UI display
    func getUnreadCountsString() -> String {
        var result = "📊 UNREAD MESSAGE COUNTS\n\n"
        
        var channelsWithUnread: [(name: String, id: String, unreadCount: Int, mentionCount: Int, isMuted: Bool)] = []
        
        for (channelId, unread) in unreads {
            let channel = channels[channelId]
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
}


extension ViewState {
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
        
        // Process all servers (removed limitation)
        let ordering = self.userSettingsStore.cache.orderSettings.servers
        let serverDict = Dictionary(uniqueKeysWithValues: event.servers.map { ($0.id, $0) })
        let orderedServers: [Server] = ordering.compactMap { serverDict[$0] }
        let remainingServers = event.servers.filter { !ordering.contains($0.id) }
        let allServers = orderedServers + remainingServers
        
        
        // DATABASE-FIRST: Save all channels and servers to database
        // DatabaseObserver will update ViewState reactively
        Task.detached(priority: .userInitiated) {
            do {
                
                await ChannelRepository.shared.saveChannels(event.channels)
                
                await ServerRepository.shared.saveServers(allServers)
                
            } catch {
            }
        }
        
        // Return all data for immediate processing (will also be in database)
        return ReadyEventData(
            channels: event.channels,
            servers: allServers,
            users: event.users,
            members: event.members,
            emojis: event.emojis
        )
    }
    
    // Process the extracted data
    private func processReadyData(_ data: ReadyEventData) async {
        let processReadySpan = launchTransaction?.startChild(operation: "processReady")
        
        
        // ✅ REALM INTEGRATION: Save all ready event data to Realm database
        // This is the heart of our reactive architecture: Network → Realm → Observer → ViewState → UI
        Task.detached(priority: .background) {
            await NetworkRepository.shared.saveReadyEvent(
                users: data.users,
                servers: data.servers,
                channels: data.channels,
                members: data.members,
                emojis: data.emojis
            )
        }

        // Process channels
        processChannelsFromData(data.channels)
        
        // Process servers  
        processServersFromData(data.servers)
        
        // Process users
        processUsers(data.users)
        
        // EMERGENCY: If still too many users, force immediate cleanup
        if users.count > maxUsersInMemory {
            let currentUserId = currentUser?.id
            let currentUserObject = currentUser
            
            users.removeAll()
            
            if let currentUserId = currentUserId, let currentUserObject = currentUserObject {
                users[currentUserId] = currentUserObject
                currentUser = currentUserObject
            }
            
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
        
        
        // Retry any pending notification token upload
        if pendingNotificationToken != nil {
            Task {
                await retryUploadNotificationToken()
            }
        }
        
        // MEMORY FIX: Fetch unreads separately to prevent memory spike
        Task {
            if let remoteUnreads = try? await http.fetchUnreads().get() {
                // Save unreads to Realm; DatabaseObserver will update ViewState.unreads
                await UnreadRepository.shared.saveAll(remoteUnreads)
                await MainActor.run {
                    // Update app badge count after loading unreads from server (will also be triggered by observer)
                    updateAppBadgeCount()
                }
            }
        }
    }
    
    private func processChannelsFromData(_ eventChannels: [Channel]) {
        
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
            case .group_dm_channel:
                channelMessages[channel.id] = []
                messageArrayCount += 1
                groupDmChannels += 1
            case .text_channel:
                channelMessages[channel.id] = []
                messageArrayCount += 1
                textChannels += 1
            default:
                break
            }
        }
        
    }
    
    private func processServersFromData(_ servers: [Server]) {
        
        // CRITICAL FIX: Don't clear existing servers - merge instead
        // Keep existing servers and update/add new ones from WebSocket
        for server in servers {
            self.servers[server.id] = server
            if members[server.id] == nil {
                members[server.id] = [:]
            }
        }
        
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

// MARK: - Database-First Accessor Methods (Backward Compatibility)
// These methods allow views to access data from repositories without breaking existing code

extension ViewState {
    /// Get a channel by ID from database (async)
    func getChannel(id: String) async -> Types.Channel? {
        return await ChannelRepository.shared.fetchChannel(id: id)
    }
    
    /// Get a user by ID from database (async)
    func getUser(id: String) async -> Types.User? {
        return await UserRepository.shared.fetchUser(id: id)
    }
    
    /// Get a message by ID from database (async)
    func getMessage(id: String) async -> Types.Message? {
        return await MessageRepository.shared.fetchMessage(id: id)
    }
    
    /// Batch fetch users by IDs from database (async)
    func getUsers(ids: [String]) async -> [String: Types.User] {
        return await UserRepository.shared.fetchUsers(ids: ids)
    }
    
    /// Get latest messages for a channel (async, paginated)
    func getChannelMessages(channelId: String, limit: Int = 50) async -> [Types.Message] {
        return await MessageRepository.shared.fetchLatestMessages(forChannel: channelId, limit: limit)
    }
    
    /// Get all DM channels from database (async)
    func getDMChannels() async -> [Types.Channel] {
        return await ChannelRepository.shared.fetchAllDMs()
    }
    
    // Synchronous accessors for backward compatibility (fallback to dict if exists)
    /// Get channel synchronously from in-memory cache (may be empty in database-first mode)
    func getChannelSync(id: String) -> Types.Channel? {
        return channels[id]
    }
    
    /// Get user synchronously from in-memory cache (may be empty in database-first mode)
    func getUserSync(id: String) -> Types.User? {
        return users[id]
    }
    
    /// Get message synchronously from in-memory cache (may be empty in database-first mode)
    func getMessageSync(id: String) -> Types.Message? {
        return messages[id]
    }
}
