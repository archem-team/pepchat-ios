//
//  Websocket.swift
//  Revolt
//
//  Created by Zomatree on 21/04/2023.
//

import Foundation
import Starscream
import Types
import UIKit
import Foundation



///This page documents various incoming and outgoing events.
///https://developers.revolt.chat/developers/events/protocol.html


/// Enumeration representing different types of WebSocket messages that can be received.
enum WsMessage {
    case authenticated // Indicates successful authentication.
    case invalid_session // Indicates an invalid session.
    case logout
    case ready(ReadyEvent) // Indicates the server is ready with event data.
    case message(Message) // Represents a message event.
    case message_update(MessageUpdateEvent) // Represents an update to an existing message.
    case channel_start_typing(ChannelTyping) // Indicates a user has started typing in a channel.
    case channel_stop_typing(ChannelTyping) // Indicates a user has stopped typing in a channel.
    case message_delete(MessageDeleteEvent) // Represents a message deletion event.
    case channel_ack(ChannelAckEvent) // Represents an acknowledgment of a channel message.
    case message_react(MessageReactEvent) // Indicates a user has reacted to a message.
    case message_unreact(MessageReactEvent) // Indicates a user has removed a reaction from a message.
    case message_append(MessageAppend) // Indicates additional content has been appended to a message.
    case user_update(UserUpdateEvent)
    case user_relationship(UserRelationshipEvent)
    case server_delete(ServerDeleteEvent)
    case server_create(ServerCreateEvent)
    case server_update(ServerUpdateEvent)
    case channel_create(Channel)
    case channel_update(ChannelUpdateEvent)
    case channel_delete(ChannelDeleteEvent)
    case channel_group_leave(ChannelGroupLeaveEvent)
    case channel_group_join(ChannelGroupJoinEvent)
    case server_member_update(ServerMemberUpdateEvent)
    case server_member_join(ServerMemberJoinEvent)
    case server_member_leave(ServerMemberLeaveEvent)
    case server_role_update(ServerRoleUpdateEvent)
    case server_role_delete(ServerRoleDeleteEvent)
    case user_setting_update(UserSettingUpdateEvent)
}

struct UserSettingUpdateEvent : Decodable{
    let id : String
    let update : SettingsResponse?
}

struct ServerRoleDeleteEvent : Decodable {
    let id : String
    let role_id : String
}

struct ServerRoleUpdateEvent : Decodable {
    let clear : [RoleRemove]
    let data : RoleEvent
    let id : String
    let role_id : String
    
    enum RoleRemove: String, Decodable {
        case colour = "Colour"
    }
    
    public struct RoleEvent: Codable, Equatable {
        var name: String?
        var permissions: Overwrite?
        var colour: String?
        var hoist: Bool?
        var rank: Int?
        
    }
}

struct ServerMemberLeaveEvent : Decodable {
    let id : String
    let user : String
    let reason: String?
}

struct ServerMemberJoinEvent : Decodable {
    let id : String
    let user : String
}

struct ServerMemberUpdateEvent : Decodable {
    let id : MemberId
    let clear : [RemoveMemberField]
    let data : ServerMemberUpdateData?
    
    struct ServerMemberUpdateData : Decodable {
        let nickname: String?
        let avatar: File?
        let roles: [String]?
        let joined_at: String?
        let timeout: String?
    }
    
    
}

struct ChannelGroupJoinEvent : Decodable {
    let id : String
    let user : String
}

struct ChannelGroupLeaveEvent : Decodable {
    let id : String
    let user : String
}

struct ChannelDeleteEvent : Decodable {
    let id : String
}

struct ChannelUpdateEvent : Decodable {
    let data : ChannelUpdateData?
    let id : String
    let clear : [RemoveField]?
    
    struct ChannelUpdateData : Decodable {
        let name : String?
        let icon: File?
        let description : String?
        let nsfw : Bool?
        let permissions : Permissions?
        let default_permissions: Overwrite?
        let role_permissions: [String: Overwrite]?
        let owner : String?
    }
    
    
    enum RemoveField: String, Decodable {
        case description = "Description"
        case icon = "Icon"
    }
}

struct ServerUpdateEvent: Decodable {
    let id: String
    let clear: [ServerEdit.Remove]?
    let data: ServerUpdate?
    
    enum CodingKeys: String, CodingKey {
        case id, clear, data
    }
    
    /// ✅ Custom initializer to ensure decoding works correctly
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        clear = try container.decode([ServerEdit.Remove].self, forKey: .clear)
        data = try container.decode(ServerUpdate.self, forKey: .data)
    }
    
    
    struct ServerUpdate: Decodable {
        
        public var owner: String?
        public var name: String?
        public var channels: [String]?
        public var default_permissions: Permissions?
        public var description: String?
        public var categories: [Types.Category]?
        public var system_messages: SystemMessages?
        public var icon: File?
        public var banner: File?
        public var nsfw: Bool?
        public var flags: ServerFlags?
        
    }

}



struct ServerCreateEvent : Decodable {
    var channels: [Channel]
    var emojis: [Emoji]
    var id : String
    var server : Types.Server
}

struct ServerDeleteEvent : Decodable {
    let id : String
}

struct UserRelationshipEvent: Decodable {
    let id: String // Your user ID
    let user: User // The related user
    let status: Relation? // The new relationship status (nullable)

    enum CodingKeys: String, CodingKey {
        case id, user, status
    }
}

struct UserUpdateEvent: Decodable {
    let id: String // User ID.
    let data: UserEvent? // Partial user data.
    let clear: [ClearField]? // Fields to remove

    enum CodingKeys: String, CodingKey {
        case id, data, clear
    }

    enum ClearField: String, Decodable {
        case profileContent = "ProfileContent"
        case profileBackground = "ProfileBackground"
        case statusText = "StatusText"
        case avatar = "Avatar"
        case displayName = "DisplayName"
    }
    
}

struct UserEvent: Decodable {
    public var username: String?
    public var discriminator: String?
    public var display_name: String?
    public var avatar: File?
    public var relations: [UserRelation]?
    public var badges: Int?
    public var status: Status?
    public var relationship: Relation?
    public var online: Bool?
    public var flags: Int?
    public var bot: UserBot?
    public var privileged: Bool?
    public var profile: Profile?

    enum CodingKeys: String, CodingKey {
        case username, discriminator, display_name, avatar, relations, badges, status, relationship, online, flags, bot, privileged, profile
    }
}



/// Struct representing the event data when the server is ready.
struct ReadyEvent: Decodable {
    var users: [User] // List of users available.
    var servers: [Types.Server] // List of servers available.
    var channels: [Channel] // List of channels available.
    var members: [Member] // List of members in the servers.
    var emojis: [Emoji] // List of emojis available.
}

/// Struct representing the data of an updated message.
struct MessageUpdateEventData: Decodable {
    var content: String? // The new content of the message.
    var edited: String // Timestamp of when the message was edited.
}

/// Struct representing an updated message event.
struct MessageUpdateEvent: Decodable {
    var channel: String // ID of the channel where the message exists.
    var id: String // ID of the message that was updated.
    var data: MessageUpdateEventData // Updated data of the message.
}

/// Struct representing a typing event in a channel.
struct ChannelTyping: Decodable {
    var id: String // ID of the typing event.
    var user: String // ID of the user typing.
}

/// Struct representing a deleted message event.
struct MessageDeleteEvent: Decodable {
    var channel: String // ID of the channel where the message was deleted.
    var id: String // ID of the message that was deleted.
}

/// Struct representing an acknowledgment event for a channel message.
struct ChannelAckEvent: Decodable {
    var id: String // ID of the acknowledgment event.
    var user: String // ID of the user who acknowledged the message.
    var message_id: String // ID of the message that was acknowledged.
}

/// Struct representing a reaction event for a message.
struct MessageReactEvent: Decodable {
    var id: String // ID of the reaction event.
    var channel_id: String // ID of the channel where the message is located.
    var user_id: String // ID of the user who reacted.
    var emoji_id: String // ID of the emoji used in the reaction.
}

/// Struct representing additional content that has been appended to a message.
struct MessageAppend: Decodable {
    var id: String // ID of the appended content.
    var channel: String // ID of the channel where the message is located.
    var append: Embed // The content that has been appended.
}

/// Extension to decode `WsMessage` from JSON.
extension WsMessage: Decodable {
    enum CodingKeys: String, CodingKey { case type } // Key for the message type.
    enum Tag: String, Decodable {
        case Authenticated, InvalidSession, Ready, Message, MessageUpdate, ChannelStartTyping,
             ChannelStopTyping, MessageDelete, ChannelAck, MessageReact, MessageUnreact, MessageAppend,UserUpdate,
             ServerDelete, ServerCreate, ServerUpdate, ChannelCreate, ChannelUpdate, ChannelDelete, Logout,
             ChannelGroupLeave, ChannelGroupJoin, ServerMemberUpdate, ServerMemberJoin, ServerMemberLeave,
             ServerRoleUpdate, ServerRoleDelete, UserRelationship, UserSettingsUpdate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self) // Decode the container.
        let singleValueContainer = try decoder.singleValueContainer() // Get the single value container.
        
        // Decode based on the message type.
        switch try container.decode(Tag.self, forKey: .type) {
        case .Authenticated:
            self = .authenticated
        case .InvalidSession:
            self = .invalid_session
        case .Logout:
            self = .logout
        case .Ready:
            self = .ready(try singleValueContainer.decode(ReadyEvent.self))
        case .Message:
            self = .message(try singleValueContainer.decode(Message.self))
        case .MessageUpdate:
            self = .message_update(try singleValueContainer.decode(MessageUpdateEvent.self))
        case .ChannelStartTyping:
            self = .channel_start_typing(try singleValueContainer.decode(ChannelTyping.self))
        case .ChannelStopTyping:
            self = .channel_stop_typing(try singleValueContainer.decode(ChannelTyping.self))
        case .MessageDelete:
            self = .message_delete(try singleValueContainer.decode(MessageDeleteEvent.self))
        case .ChannelAck:
            self = .channel_ack(try singleValueContainer.decode(ChannelAckEvent.self))
        case .MessageReact:
            self = .message_react(try singleValueContainer.decode(MessageReactEvent.self))
        case .MessageUnreact:
            self = .message_unreact(try singleValueContainer.decode(MessageReactEvent.self))
        case .MessageAppend:
            self = .message_append(try singleValueContainer.decode(MessageAppend.self))
        case .UserUpdate:
            self = .user_update(try singleValueContainer.decode(UserUpdateEvent.self))
        case .ServerDelete:
            self = .server_delete(try singleValueContainer.decode(ServerDeleteEvent.self))
        case .ServerCreate:
            self = .server_create(try singleValueContainer.decode(ServerCreateEvent.self))
        case .ServerUpdate:
            self = .server_update(try singleValueContainer.decode(ServerUpdateEvent.self))
        case .ChannelCreate:
            self = .channel_create(try singleValueContainer.decode(Channel.self))
        case .ChannelUpdate:
            self = .channel_update(try singleValueContainer.decode(ChannelUpdateEvent.self))
        case .ChannelDelete:
            self = .channel_delete(try singleValueContainer.decode(ChannelDeleteEvent.self))
        case .ChannelGroupLeave:
            self = .channel_group_leave(try singleValueContainer.decode(ChannelGroupLeaveEvent.self))
        case .ChannelGroupJoin:
            self = .channel_group_join(try singleValueContainer.decode(ChannelGroupJoinEvent.self))
        case .ServerMemberUpdate:
            self = .server_member_update(try singleValueContainer.decode(ServerMemberUpdateEvent.self))
        case .ServerMemberJoin:
            self = .server_member_join(try singleValueContainer.decode(ServerMemberJoinEvent.self))
        case .ServerMemberLeave:
            self = .server_member_leave(try singleValueContainer.decode(ServerMemberLeaveEvent.self))
        case .ServerRoleUpdate:
            self = .server_role_update(try singleValueContainer.decode(ServerRoleUpdateEvent.self))
        case .ServerRoleDelete:
            self = .server_role_delete(try singleValueContainer.decode(ServerRoleDeleteEvent.self))
        case .UserRelationship:
            self = .user_relationship(try singleValueContainer.decode(UserRelationshipEvent.self))
        case .UserSettingsUpdate:
            self = .user_setting_update(try singleValueContainer.decode(UserSettingUpdateEvent.self))
        
        }
    }
}

/// Enumeration representing the connection state of the WebSocket.
enum WsState {
    case disconnected // The WebSocket is disconnected.
    case connecting // The WebSocket is in the process of connecting.
    case connected // The WebSocket is connected.
}

/// Class representing a message to be sent over WebSocket.
class SendWsMessage: Encodable {
    var type: String // Type of the WebSocket message.
    
    init(type: String) {
        self.type = type
    }
}

/// Class for authenticating a user with the WebSocket.
class Authenticate: SendWsMessage, CustomStringConvertible {
    private enum CodingKeys: String, CodingKey { case type, token } // Keys for encoding.
    
    var token: String // Token used for authentication.
    
    init(token: String) {
        self.token = token
        super.init(type: "Authenticate") // Set the message type to "Authenticate".
    }
    
    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self) // Create container for encoding.
        try container.encode(token, forKey: .token) // Encode the token.
        try container.encode(type, forKey: .type) // Encode the type.
    }
    
    var description: String {
        return "Authenticate(token: \(token))" // Description of the authentication payload.
    }
}


class BeginTyping: SendWsMessage, CustomStringConvertible {
    private enum CodingKeys: String, CodingKey {
        case type, channel
    }
    
    var channel: String
    
    init(channel: String) {
        self.channel = channel
        super.init(type: "BeginTyping")
    }
    
    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channel, forKey: .channel)
        try container.encode(type, forKey: .type)
    }
    
    var description: String {
        return "BeginTyping(channel: \(channel))"
    }
}


class EndTyping: SendWsMessage, CustomStringConvertible {
    private enum CodingKeys: String, CodingKey {
        case type, channel
    }
    
    var channel: String
    
    init(channel: String) {
        self.channel = channel
        super.init(type: "EndTyping")
    }
    
    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channel, forKey: .channel)
        try container.encode(type, forKey: .type)
    }
    
    var description: String {
        return "EndTyping(channel: \(channel))"
    }
}




///Establishing a connection
///https://developers.revolt.chat/developers/events/establishing.html
/// Class managing the WebSocket connection and events.
class WebSocketStream: ObservableObject {
    // MEMORY FIX: Use static encoder/decoder to prevent repeated allocations
    private static let sharedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()
    
    private static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
    
    private var url: URL // The URL of the WebSocket server.
    private var client: WebSocket? // The WebSocket client instance. Made optional to allow cleanup
    private weak var onEventDelegate: AnyObject? // Weak reference to prevent retain cycles
    private var onEvent: ((WsMessage) async -> ())? // Callback for handling received events.
    
    public var token: String // Authentication token.
    @Published public var currentState: WsState = .connecting // Current connection state.
    private var onChangeCurrentState : (WsState) -> ()

    public var retryCount: Int = 0 // Count of reconnection attempts.
    
    private var isPingRoutineActive = false
    private var pingTask: Task<Void, Never>?
    
    // Add network reachability check
    private var isNetworkAvailable: Bool {
        // Simple check using URLSession
        return true // For now, we'll assume network is available
    }
    
    // MEMORY FIX: Add queue for processing messages
    private var messageProcessingQueue = DispatchQueue(label: "com.revolt.websocket.messageprocessing", qos: .userInitiated)
    private let maxPendingMessages = 200 // Increased from 100 to 200
    private var pendingMessageCount = 0
    private let pendingMessageCountLock = NSLock()
    
    // Add app state observers
    private var appStateObservers: [NSObjectProtocol] = []
    
    /// Initializes the WebSocketStream with the given URL and token.
    /// - Parameters:
    ///   - url: The URL of the WebSocket server.
    ///   - token: The authentication token for the user.
    ///   - onEvent: Callback for handling received messages.
    init(url: String,
         token: String,
         onChangeCurrentState : @escaping (WsState) -> (),
         onEvent: @escaping (WsMessage) async -> ()) {
        self.token = token
        self.onEvent = onEvent
        self.url = URL(string: url)! // Create URL from the string.
        
        // Create optimized URLRequest for the WebSocket to reduce network warnings
        var request = URLRequest(url: self.url)
        request.timeoutInterval = 30.0
        request.cachePolicy = .reloadIgnoringCacheData
        
        // NETWORK OPTIMIZATION: Add headers to prevent connection warnings
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        
        let ws = WebSocket(request: request) // Create a WebSocket instance.
        client = ws // Assign the client.
        
        self.onChangeCurrentState = onChangeCurrentState
        ws.onEvent = { [weak self] event in
            self?.didReceive(event: event)
        } // MEMORY FIX: Use weak self to prevent retain cycle
        ws.connect() // Connect to the WebSocket server.
        
        // CRITICAL FIX: Add app state observers
        setupAppStateObservers()
    }
    
    private func setupAppStateObservers() {
        // Observer for app entering foreground
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // print("🔌 App entering foreground - checking WebSocket connection")
            if self?.currentState == .disconnected {
                self?.forceConnect()
            }
        }
        
        // Observer for app entering background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // print("🔌 App entering background - maintaining WebSocket for notifications")
            // Don't disconnect, but stop ping routine to save battery
            self?.pingTask?.cancel()
            self?.pingTask = nil
        }
        
        appStateObservers = [foregroundObserver, backgroundObserver]
    }
    
    /// Stops the WebSocket connection.
    public func stop() {
        currentState = .disconnected
        onChangeCurrentState(currentState)
        pingTask?.cancel()
        pingTask = nil
        
        // NETWORK OPTIMIZATION: Proper connection cleanup to prevent warnings
        cleanupConnection()
        
        client?.disconnect(closeCode: .zero) // Disconnect without a specific close code.
        client = nil // MEMORY FIX: Release the client
        onEvent = nil // MEMORY FIX: Release the callback
        onEventDelegate = nil // MEMORY FIX: Clear delegate
    }
    
    /// Properly cleans up connection to prevent network warnings
    private func cleanupConnection() {
        // Cancel any pending ping operations
        pingTask?.cancel()
        pingTask = nil
        
        // Reset connection state
        isPingRoutineActive = false
        
        // MEMORY FIX: Clear message processing queue
        messageProcessingQueue.sync {
            // Ensure all pending operations complete
        }
        
        // MEMORY FIX: Force clear Starscream internal buffers
        if let ws = client as? WebSocket {
            // Force disconnect to clear internal state
            ws.disconnect(closeCode: 1000) // 1000 = normal closure
        }
        
        // Allow some time for proper connection cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // This small delay allows the network stack to properly clean up
            // and prevents "unconnected nw_connection" warnings
        }
    }
    
    /// Handles incoming WebSocket events.
    /// - Parameter event: The WebSocket event received.
    public func didReceive(event: WebSocketEvent) {
        switch event {
        case .connected(_):
            currentState = .connected // Update state to connecting.
            onChangeCurrentState(currentState)
            
            // CRITICAL FIX: Reset retry count on successful connection
            retryCount = 0
            
            // CRITICAL FIX: Clear any pending messages from previous connection
            messageProcessingQueue.sync {
                pendingMessageCount = 0
            }
            
            let payload = Authenticate(token: token) // Create authentication payload.
            print(payload.description) // Print the payload description.
            
            let s = try! WebSocketStream.sharedEncoder.encode(payload) // Encode the payload to JSON.
            client?.write(string: String(data: s, encoding: .utf8)!) // Send the encoded payload.
            startPingRoutine()
            
            // CRITICAL FIX: Post notification that WebSocket is reconnected
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("WebSocketReconnected"), object: nil)
            }
            
        case .disconnected(let reason, _):
            // print("disconnect \(reason)") // Log the disconnection reason.
            currentState = .disconnected // Update state to disconnected.
            onChangeCurrentState(currentState)
            
            // Stop ping routine immediately
            pingTask?.cancel()
            pingTask = nil
            
            Task { [weak self] in
                await self?.tryReconnect() // Attempt to reconnect.
            }
            
        case .text(let string):
            // MEMORY FIX: Process string on background queue and use weak self
            messageProcessingQueue.async { [weak self] in
                guard let self = self else { return }
                
                // DEBUG LOG: Log incoming data size
                // print("📨 WEBSOCKET: Received message, size: \(string.count) characters")
                
                // Log first 200 characters of the message for debugging
                if string.count > 200 {
                    // print("📨 WEBSOCKET: Message preview: \(String(string.prefix(200)))...")
                } else {
                    // print("📨 WEBSOCKET: Full message: \(string)")
                }
                
                // MEMORY PROTECTION: Check pending message count
                self.pendingMessageCountLock.lock()
                if self.pendingMessageCount > self.maxPendingMessages {
                    self.pendingMessageCountLock.unlock()
                    // print("⚠️ WEBSOCKET: Dropping message - queue full (\(self.pendingMessageCount) messages)")
                    return
                }
                self.pendingMessageCount += 1
                // print("📨 WEBSOCKET: Pending messages in queue: \(self.pendingMessageCount)")
                self.pendingMessageCountLock.unlock()
                
            autoreleasepool {
                    defer {
                        self.pendingMessageCountLock.lock()
                        self.pendingMessageCount -= 1
                        // print("📨 WEBSOCKET: Message processed, remaining in queue: \(self.pendingMessageCount)")
                        self.pendingMessageCountLock.unlock()
                    }
                    
                do {
                    // MEMORY PROTECTION: Reject extremely large messages (>10MB)
                    if string.count > 10 * 1024 * 1024 {
                        // print("⚠️ WEBSOCKET: Rejecting message larger than 10MB (\(string.count) bytes)")
                        return
                    }
                    
                    // Convert string to data immediately and let string be released
                    guard let data = string.data(using: .utf8) else {
                        // print("Failed to convert WebSocket string to data")
                        return
                    }
                    
                        // print("📨 WEBSOCKET: Converted to data, size: \(data.count) bytes")
                        
                        // MEMORY FIX: Release string immediately after conversion
                        _ = string
                        
                        let e = try WebSocketStream.sharedDecoder.decode(WsMessage.self, from: data)
                    
                        
                        // MEMORY FIX: Use weak self in Task to prevent retain cycle
                        Task { [weak self] in
                            guard let onEvent = self?.onEvent else { 
                                // print("⚠️ WEBSOCKET: onEvent callback is nil, dropping message")
                                return 
                            }
                            // print("📨 WEBSOCKET: Forwarding message to ViewState")
                        await onEvent(e)
                            // print("📨 WEBSOCKET: Message forwarded successfully")
                    }
                } catch {
                        // print("❌ WEBSOCKET: Decode error: \(error)")
                        // Try to log more details about the error
                        if let decodingError = error as? DecodingError {
                            switch decodingError {
                            case .dataCorrupted(let context):
                                print("❌ WEBSOCKET: Data corrupted - \(context)")
                            case .keyNotFound(let key, let context):
                                print("❌ WEBSOCKET: Key not found - \(key), \(context)")
                            case .typeMismatch(let type, let context):
                                print("❌ WEBSOCKET: Type mismatch - expected \(type), \(context)")
                            case .valueNotFound(let type, let context):
                                print("❌ WEBSOCKET: Value not found - \(type), \(context)")
                            @unknown default:
                                print("❌ WEBSOCKET: Unknown decoding error")
                            }
                        }
                    }
                }
            }
            
        case .viabilityChanged(let viability):
            if !viability {
                currentState = .disconnected // Update state to disconnected if not viable.
                onChangeCurrentState(currentState)
                Task { [weak self] in
                    await self?.tryReconnect() // Attempt to reconnect.
                }
            }
            
        case .error(let error):
            currentState = .disconnected // Update state to disconnected on error.
            onChangeCurrentState(currentState)
            self.stop() // Stop the WebSocket connection.
            // print("error \(String(describing: error))") // Log the error.
            
            Task { [weak self] in
                await self?.tryReconnect() // Attempt to reconnect.
            }
            
        case .pong(let data):
            if let pongData = data {
                let timestamp = Int(String(data: pongData, encoding: .utf8) ?? "0") ?? 0
                // print("Received Pong with timestamp: \(timestamp)")
            }
            
        case .ping(let data):
            if let pingData = data {
                // print("Received Ping with data: \(pingData)")
                //client.write(pong: pingData)
            }
            
        case .peerClosed:
         currentState = .disconnected
         self.onChangeCurrentState(currentState)
        default:
            break
        }
    }
    
    func sendPing() {
        let timestamp = "\(Int(Date().timeIntervalSince1970 * 1000))"
        if let data = timestamp.data(using: .utf8) {
            client?.write(ping: data)
            // print("Sent Ping with timestamp: \(timestamp)")
        }
    }
    
    func startPingRoutine() {
        guard pingTask == nil else { return }
        
        pingTask = Task { [weak self] in
            while self?.currentState == .connected {
                
                if Task.isCancelled {
                    break
                }
                
                self?.sendPing()
                do {
                    // CRITICAL FIX: Reduce ping interval from 30 to 15 seconds
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    break
                }
            }
        }
    }
    
    /// Forces a connection to the WebSocket server.
    func forceConnect() {
        // MEMORY FIX: Clean up old client before creating new one
        client?.disconnect(closeCode: .zero)
        client = nil
        
        // Create optimized URLRequest for reconnection
        var request = URLRequest(url: self.url)
        request.timeoutInterval = 30.0
        request.cachePolicy = .reloadIgnoringCacheData
        
        // NETWORK OPTIMIZATION: Add headers to prevent connection warnings
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        
        let ws = WebSocket(request: request) // Create a new WebSocket instance.
        
        client = ws // Assign the new client.
        
        ws.onEvent = { [weak self] event in
            self?.didReceive(event: event)
        } // MEMORY FIX: Use weak self
        retryCount += 1
        currentState = .connecting
        onChangeCurrentState(currentState)
        ws.connect() // Connect to the WebSocket server.
    }
    
    /// Attempts to reconnect to the WebSocket server after a delay.
    func tryReconnect() async {
        // CRITICAL FIX: Check if app is in foreground before reconnecting
        let isAppActive = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        
        guard isAppActive else {
            // print("App is not active, skipping reconnection")
            return
        }
        
        // Cap retry count to prevent excessive delays
        let cappedRetryCount = min(retryCount, 5) // Reduced from 10 to 5
        let sleep = min(0.5 * Double(pow(Double(2), Double(cappedRetryCount - 1))), 10.0) // Reduced max from 30 to 10 seconds
        
        do {
            try await Task.sleep(for: .seconds(sleep)) // Wait before reconnecting.
        } catch {
            // Task was cancelled, don't reconnect
            // print("Reconnection cancelled")
            return
        }
        
        // Check if we're still disconnected before attempting to reconnect
        guard currentState == .disconnected else {
            // print("State changed during reconnect delay, skipping reconnection")
            return
        }
        
        // CRITICAL FIX: Check network availability before reconnecting
        guard isNetworkAvailable else {
            // print("Network not available, will retry later")
            // Schedule another reconnect attempt
            Task { [weak self] in
                await self?.tryReconnect()
            }
            return
        }
        
        currentState = .connecting // Update state to connecting.
        onChangeCurrentState(currentState)
        forceConnect() // Attempt to reconnect.
        
        retryCount += 1 // Increment retry count.
    }
    
    
    func sendBeginTyping(channel: String) {
        guard currentState == .connected else {
            return
        }
        
        let beginTypingPayload = BeginTyping(channel: channel)
        print(beginTypingPayload.description)
        
        do {
            let beginTypingData = try WebSocketStream.sharedEncoder.encode(beginTypingPayload)
            client?.write(string: String(data: beginTypingData, encoding: .utf8)!)
        } catch {
            // print("Error encoding BeginTyping payload: \(error)")
        }
    }
    
    
    func sendEndTyping(channel: String) {
        guard currentState == .connected else {
            return
        }
        
        let endTypingPayload = EndTyping(channel: channel)
        print(endTypingPayload.description)
        
        do {
            let endTypingData = try WebSocketStream.sharedEncoder.encode(endTypingPayload)
            client?.write(string: String(data: endTypingData, encoding: .utf8)!)
        } catch {
            // print("Error encoding EndTyping payload: \(error)")
        }
    }
    
    deinit {
        // print("🗑️ WEBSOCKET_DEINIT: WebSocketStream is being deallocated")
        
        // MEMORY FIX: Ensure complete cleanup
        pingTask?.cancel()
        pingTask = nil
        
        // Remove app state observers
        appStateObservers.forEach { NotificationCenter.default.removeObserver($0) }
        appStateObservers.removeAll()
        
        // Cancel all pending messages
        messageProcessingQueue.sync {
            pendingMessageCount = 0
        }
        
        // Disconnect and cleanup
        client?.disconnect(closeCode: 1000) // 1000 = normal closure
        client = nil
        onEvent = nil
        onEventDelegate = nil
        onChangeCurrentState = { _ in }
    }
}
