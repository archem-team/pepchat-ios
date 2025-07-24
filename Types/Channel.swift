//
//  Channel.swift
//  Revolt
//
//  Created by Zomatree on 21/04/2023.
//

import Foundation

// MARK: - SavedMessages Structure

/// Represents a saved message in the application.
public struct SavedMessages: Codable, Equatable, Identifiable {
    /// Initializes a new instance of `SavedMessages`.
    /// - Parameters:
    ///   - id: Unique identifier for the saved message.
    ///   - user: The identifier of the user who saved the message.
    public init(id: String, user: String) {
        self.id = id
        self.user = user
    }
    
    public var id: String // Unique identifier for the saved message.
    public var user: String // The identifier of the user who saved the message.
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case user
    }
}

// MARK: - DMChannel Structure

/// Represents a direct message channel between users.
public struct DMChannel: Codable, Equatable, Identifiable {
    /// Initializes a new instance of `DMChannel`.
    /// - Parameters:
    ///   - id: Unique identifier for the DM channel.
    ///   - active: Indicates if the DM channel is active.
    ///   - recipients: List of user identifiers who are part of the DM channel.
    ///   - last_message_id: Optional identifier for the last message in the channel.
    public init(id: String, active: Bool, recipients: [String], last_message_id: String? = nil) {
        self.id = id
        self.active = active
        self.recipients = recipients
        self.last_message_id = last_message_id
    }
    
    public var id: String // Unique identifier for the DM channel.
    public var active: Bool // Indicates if the DM channel is active.
    public var recipients: [String] // List of user identifiers in the DM channel.
    public var last_message_id: String? // Identifier of the last message sent in the channel.
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case active, recipients, last_message_id
    }
}

// MARK: - GroupDMChannel Structure

/// Represents a group direct message channel.
public struct GroupDMChannel: Codable, Equatable, Identifiable {
    /// Initializes a new instance of `GroupDMChannel`.
    /// - Parameters:
    ///   - id: Unique identifier for the group DM channel.
    ///   - recipients: List of user identifiers in the group DM channel.
    ///   - name: Name of the group DM channel.
    ///   - owner: Identifier of the user who created the group DM channel.
    ///   - icon: Optional icon file associated with the group DM channel.
    ///   - permissions: Optional permissions associated with the group DM channel.
    ///   - description: Optional description of the group DM channel.
    ///   - nsfw: Optional flag indicating if the channel is NSFW (Not Safe For Work).
    ///   - last_message_id: Optional identifier for the last message in the channel.
    public init(id: String, recipients: [String], name: String, owner: String, icon: File? = nil, permissions: Permissions? = nil, description: String? = nil, nsfw: Bool? = nil, last_message_id: String? = nil) {
        self.id = id
        self.recipients = recipients
        self.name = name
        self.owner = owner
        self.icon = icon
        self.permissions = permissions
        self.description = description
        self.nsfw = nsfw
        self.last_message_id = last_message_id
    }
    
    public var id: String // Unique identifier for the group DM channel.
    public var recipients: [String] // List of user identifiers in the group DM channel.
    public var name: String // Name of the group DM channel.
    public var owner: String // Identifier of the channel owner.
    public var icon: File? // Icon associated with the group DM channel.
    public var permissions: Permissions? // Permissions associated with the channel.
    public var description: String? // Description of the group DM channel.
    public var nsfw: Bool? // Indicates if the channel is NSFW.
    public var last_message_id: String? // Identifier of the last message in the channel.
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case recipients, name, owner, icon, permissions, description, nsfw, last_message_id
    }
}

// MARK: - TextChannel Structure

/// Represents a text channel within a server.
public struct TextChannel: Codable, Equatable, Identifiable {
    /// Initializes a new instance of `TextChannel`.
    /// - Parameters:
    ///   - id: Unique identifier for the text channel.
    ///   - server: Identifier of the server to which the text channel belongs.
    ///   - name: Name of the text channel.
    ///   - description: Optional description of the text channel.
    ///   - icon: Optional icon file associated with the text channel.
    ///   - default_permissions: Optional default permissions for the text channel.
    ///   - role_permissions: Optional role-specific permissions for the text channel.
    ///   - nsfw: Optional flag indicating if the channel is NSFW.
    ///   - last_message_id: Optional identifier for the last message in the channel.
    ///   - voice: Optional voice information associated with the text channel.
    public init(id: String, server: String, name: String, description: String? = nil, icon: File? = nil, default_permissions: Overwrite? = nil, role_permissions: [String : Overwrite]? = nil, nsfw: Bool? = nil, last_message_id: String? = nil, voice: VoiceInformation? = nil) {
        self.id = id
        self.server = server
        self.name = name
        self.description = description
        self.icon = icon
        self.default_permissions = default_permissions
        self.role_permissions = role_permissions
        self.nsfw = nsfw
        self.last_message_id = last_message_id
        self.voice = voice
    }
    
    public var id: String // Unique identifier for the text channel.
    public var server: String // Identifier of the server to which the text channel belongs.
    public var name: String // Name of the text channel.
    public var description: String? // Optional description of the text channel.
    public var icon: File? // Icon associated with the text channel.
    public var default_permissions: Overwrite? // Default permissions for the text channel.
    public var role_permissions: [String: Overwrite]? // Role-specific permissions for the text channel.
    public var nsfw: Bool? // Indicates if the channel is NSFW.
    public var last_message_id: String? // Identifier of the last message in the channel.
    public var voice: VoiceInformation? // Voice information associated with the text channel.
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case server, name, description, icon, default_permissions, role_permissions, nsfw, last_message_id, voice
    }
}

// MARK: - VoiceChannel Structure

/// Represents a voice channel within a server.
public struct VoiceChannel: Codable, Equatable, Identifiable {
    /// Initializes a new instance of `VoiceChannel`.
    /// - Parameters:
    ///   - id: Unique identifier for the voice channel.
    ///   - server: Identifier of the server to which the voice channel belongs.
    ///   - name: Name of the voice channel.
    ///   - description: Optional description of the voice channel.
    ///   - icon: Optional icon file associated with the voice channel.
    ///   - default_permissions: Optional default permissions for the voice channel.
    ///   - role_permissions: Optional role-specific permissions for the voice channel.
    ///   - nsfw: Optional flag indicating if the channel is NSFW.
    public init(id: String, server: String, name: String, description: String? = nil, icon: File? = nil, default_permissions: Overwrite? = nil, role_permissions: [String : Overwrite]? = nil, nsfw: Bool? = nil) {
        self.id = id
        self.server = server
        self.name = name
        self.description = description
        self.icon = icon
        self.default_permissions = default_permissions
        self.role_permissions = role_permissions
        self.nsfw = nsfw
    }
    
    public var id: String // Unique identifier for the voice channel.
    public var server: String // Identifier of the server to which the voice channel belongs.
    public var name: String // Name of the voice channel.
    public var description: String? // Optional description of the voice channel.
    public var icon: File? // Icon associated with the voice channel.
    public var default_permissions: Overwrite? // Default permissions for the voice channel.
    public var role_permissions: [String: Overwrite]? // Role-specific permissions for the voice channel.
    public var nsfw: Bool? // Indicates if the channel is NSFW.
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case server, name, description, icon, default_permissions, role_permissions, nsfw
    }
}

// MARK: - VoiceInformation Structure

/// Represents information about a voice channel.
public struct VoiceInformation: Codable, Equatable {
    /// Initializes a new instance of `VoiceInformation`.
    /// - Parameter max_users: Optional maximum number of users allowed in the voice channel.
    public init(max_users: Int? = nil) {
        self.max_users = max_users
    }
    
    public var max_users: Int? // Maximum number of users allowed in the voice channel.
}

// MARK: - Channel Enum

/// Enum representing different types of channels in the application.
@frozen
public enum Channel: Identifiable, Equatable {
    case saved_messages(SavedMessages) // Case for saved messages channel.
    case dm_channel(DMChannel) // Case for direct message channel.
    case group_dm_channel(GroupDMChannel) // Case for group direct message channel.
    case text_channel(TextChannel) // Case for text channel.
    case voice_channel(VoiceChannel) // Case for voice channel.
    
    /// Unique identifier for the channel.
    public var id: String {
        switch self {
            case .saved_messages(let c):
                return c.id
            case .dm_channel(let c):
                return c.id
            case .group_dm_channel(let c):
                return c.id
            case .text_channel(let c):
                return c.id
            case .voice_channel(let c):
                return c.id
        }
    }
    
    public var isDM: Bool {
        switch self {
        case .dm_channel(let c):
            return true
        default:
            return false
        }
    }
    
    public var isTextChannel: Bool {
        switch self {
        case .text_channel(let c):
            return true
        default:
            return false
        }
    }
    
    /// Optional icon file associated with the channel.
    public var icon: File? {
        switch self {
            case .saved_messages(_):
                return nil
            case .dm_channel(_):
                return nil
            case .group_dm_channel(let c):
                return c.icon
            case .text_channel(let c):
                return c.icon
            case .voice_channel(let c):
                return c.icon
        }
    }
    
    /// Optional description of the channel.
    public var name: String? {
        switch self {
            case .saved_messages(_):
                return nil
            case .dm_channel(_):
                return nil
            case .group_dm_channel(let c):
                return c.name
            case .text_channel(let c):
                return c.name
            case .voice_channel(let c):
                return c.name
        }
    }

    /// Optional description of the channel.
    public var description: String? {
        switch self {
            case .saved_messages(_):
                return nil
            case .dm_channel(_):
                return nil
            case .group_dm_channel(let c):
                return c.description
            case .text_channel(let c):
                return c.description
            case .voice_channel(let c):
                return c.description
        }
    }
    
    /// Optional identifier for the last message sent in the channel.
    public var last_message_id: String? {
        switch self {
            case .dm_channel(let c):
                return c.last_message_id
            case .group_dm_channel(let c):
                return c.last_message_id
            case .text_channel(let c):
                return c.last_message_id
            default:
                return nil
        }
    }
    
    public  func setLastMessageId(id : String?) {
        switch self {
        case .dm_channel(var c):
            c.last_message_id = id
        case .group_dm_channel(var c):
            c.last_message_id = id
        case .text_channel(var c):
            c.last_message_id = id
        default:
            debugPrint("invalid channel")
        }
    }
    
    /// Indicates if the channel is NSFW (Not Safe For Work).
    public var nsfw: Bool {
        switch self {
            case .saved_messages(_):
                return false
            case .dm_channel(_):
                return false
            case .group_dm_channel(let c):
                return c.nsfw ?? false
            case .text_channel(let c):
                return c.nsfw ?? false
            case .voice_channel(let c):
                return c.nsfw ?? false
        }
    }
    
    /// Optional identifier of the server to which the channel belongs.
    public var server: String? {
        switch self {
            case .saved_messages(_):
                return nil
            case .dm_channel(_):
                return nil
            case .group_dm_channel(_):
                return nil
            case .text_channel(let textChannel):
                return textChannel.server
            case .voice_channel(let voiceChannel):
                return voiceChannel.server
        }
    }
    
    /// Optional role-specific permissions associated with the channel.
    public var role_permissions: [String: Overwrite]? {
        switch self {
            case .saved_messages(let savedMessages):
                return nil
            case .dm_channel(let dMChannel):
                return nil
            case .group_dm_channel(let groupDMChannel):
                return nil
            case .text_channel(let textChannel):
                return textChannel.role_permissions
            case .voice_channel(let voiceChannel):
                return voiceChannel.role_permissions
        }
    }
    
    /// Optional default permissions associated with the channel.
    public var default_permissions: Overwrite? {
        switch self {
            case .saved_messages(let savedMessages):
                return nil
            case .dm_channel(let dMChannel):
                return nil
            case .group_dm_channel(let groupDMChannel):
                return nil
            case .text_channel(let textChannel):
                return textChannel.default_permissions
            case .voice_channel(let voiceChannel):
                return voiceChannel.default_permissions
        }
    }
    
    /// Recipients list for DM and Group DM channels.
    public var recipients: [String] {
        switch self {
            case .dm_channel(let dmChannel):
                return dmChannel.recipients
            case .group_dm_channel(let groupDMChannel):
                return groupDMChannel.recipients
            default:
                return []
        }
    }
}

// MARK: - Channel Extensions for Encoding and Decoding

extension Channel: Decodable {
    enum CodingKeys: String, CodingKey { case channel_type } // Coding keys for the `Channel` enum.
    enum Tag: String, Codable { case SavedMessages, DirectMessage, Group, TextChannel, VoiceChannel } // Tags representing channel types.
    
    /// Decodes a `Channel` instance from a decoder.
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .channel_type) {
            case .SavedMessages:
                self = .saved_messages(try singleValueContainer.decode(SavedMessages.self))
            case .DirectMessage:
                self = .dm_channel(try singleValueContainer.decode(DMChannel.self))
            case .Group:
                self = .group_dm_channel(try singleValueContainer.decode(GroupDMChannel.self))
            case .TextChannel:
                self = .text_channel(try singleValueContainer.decode(TextChannel.self))
            case .VoiceChannel:
                self = .voice_channel(try singleValueContainer.decode(VoiceChannel.self))
        }
    }
}

extension Channel: Encodable {
    /// Encodes the channel instance to the given encoder.
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: any Encoder) throws {
        var tagContainer = encoder.container(keyedBy: CodingKeys.self)

        switch self {
            case .saved_messages(let c):
                try tagContainer.encode(Tag.SavedMessages, forKey: .channel_type)
                try c.encode(to: encoder)
            case .dm_channel(let c):
                try tagContainer.encode(Tag.DirectMessage, forKey: .channel_type)
                try c.encode(to: encoder)
            case .group_dm_channel(let c):
                try tagContainer.encode(Tag.Group, forKey: .channel_type)
                try c.encode(to: encoder)
            case .text_channel(let c):
                try tagContainer.encode(Tag.TextChannel, forKey: .channel_type)
                try c.encode(to: encoder)
            case .voice_channel(let c):
                try tagContainer.encode(Tag.VoiceChannel, forKey: .channel_type)
                try c.encode(to: encoder)
        }
    }
}



extension Channel {
    /// Checks if the channel is a Group DM, Text, or Voice channel.
    public var isRelevantChannel: Bool {
        switch self {
        case .group_dm_channel, .text_channel, .voice_channel:
            return true
        default:
            return false
        }
    }
    
    public var isNotSavedMessages: Bool {
            switch self {
            case .saved_messages:
                return false
            default:
                return true
            }
        }
    
    
    public var isGroupDmChannel: Bool {
            switch self {
            case .group_dm_channel:
                return true
            default:
                return false
            }
        }

    public var isSavedMessages: Bool {
            switch self {
            case .saved_messages:
                return true
            default:
                return false
            }
        }

    public var isTextOrVoiceChannel: Bool {
            switch self {
            case .text_channel(_):
                return true
            case .voice_channel(_):
                return true
            default:
                return false
            }
        }
}
