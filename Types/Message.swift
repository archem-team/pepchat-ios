//
//  Message.swift
//  Revolt
//
//  Created by Zomatree on 21/04/2023.
//

import Foundation

// MARK: - Interactions Structure

/// Represents the interactions associated with a message.
public struct Interactions: Codable, Equatable {
    public var reactions: [String]? // List of reactions to the message.
    public var restrict_reactions: Bool? // Indicates if reactions are restricted.
    
    public init(reactions: [String]? = nil, restrict_reactions: Bool? = nil) {
        self.reactions = reactions
        self.restrict_reactions = restrict_reactions
    }
}

// MARK: - Masquerade Structure

/// Represents a masquerade, allowing users to appear with a different name and avatar.
public struct Masquerade: Codable, Equatable {
    public var name: String? // The display name for the masquerade (optional).
    public var avatar: String? // The avatar for the masquerade (optional).
    public var colour: String? // The color associated with the masquerade (optional).
    
    public init(name: String? = nil, avatar: String? = nil, colour: String? = nil) {
        self.name = name
        self.avatar = avatar
        self.colour = colour
    }
}

// MARK: - System Message Content Structures

/// Represents the content of a text system message.
public struct TextSystemMessageContent: Codable, Equatable {
    public var content: String // The content of the system message.
    
    public init(content: String) {
        self.content = content
    }
}

/// Represents the content of a user-added system message.
public struct UserAddedSystemContent: Codable, Equatable {
    public var id: String // The ID of the user who was added.
    public var by: String // The ID of the user who added them.
    
    public init(id: String, by: String) {
        self.id = id
        self.by = by
    }
}

/// Represents the content of a user-removed system message.
public struct UserRemovedSystemContent: Codable, Equatable {
    public var id: String // The ID of the user who was removed.
    public var by: String // The ID of the user who removed them.
    
    public init(id: String, by: String) {
        self.id = id
        self.by = by
    }
}

/// Represents the content of a user-joined system message.
public struct UserJoinedSystemContent: Codable, Equatable {
    public var id: String // The ID of the user who joined.
    
    public init(id: String) {
        self.id = id
    }
}

/// Represents the content of a user-left system message.
public struct UserLeftSystemContent: Codable, Equatable {
    public var id: String // The ID of the user who left.
    
    public init(id: String) {
        self.id = id
    }
}

/// Represents the content of a user-kicked system message.
public struct UserKickedSystemContent: Codable, Equatable {
    public var id: String // The ID of the user who was kicked.
    
    public init(id: String) {
        self.id = id
    }
}

/// Represents the content of a user-banned system message.
public struct UserBannedSystemContent: Codable, Equatable {
    public var id: String // The ID of the banned user.
    
    public init(id: String) {
        self.id = id
    }
}

/// Represents the content of a channel-renamed system message.
public struct ChannelRenamedSystemContent: Codable, Equatable {
    public var name: String // The new name of the channel.
    public var by: String // The ID of the user who renamed the channel.
    
    public init(name: String, by: String) {
        self.name = name
        self.by = by
    }
}

/// Represents the content of a channel-description-changed system message.
public struct ChannelDescriptionChangedSystemContent: Codable, Equatable {
    public var by: String // The ID of the user who changed the description.
    
    public init(by: String) {
        self.by = by
    }
}

/// Represents the content of a channel-icon-changed system message.
public struct ChannelIconChangedSystemContent: Codable, Equatable {
    public var by: String // The ID of the user who changed the icon.
    
    public init(by: String) {
        self.by = by
    }
}

/// Represents the content of a channel-ownership-changed system message.
public struct ChannelOwnershipChangedSystemContent: Codable, Equatable {
    public var from: String // The ID of the previous owner.
    public var to: String // The ID of the new owner.
    
    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}


public struct MessagePinnedSystemContent: Codable, Equatable {
    public var id: String // The ID of the user who was kicked.
    public var by: String // The ID of the user who changed the icon.
    public var by_username: String // The ID of the user who changed the icon.
    
    public init(id: String, by: String, by_username: String) {
        self.id = id
        self.by = by
        self.by_username = by_username
    }
}




// MARK: - System Message Content Enum

/// Enum representing the different types of system message content.
public enum SystemMessageContent: Equatable {
    case text(TextSystemMessageContent)
    case user_added(UserAddedSystemContent)
    case user_removed(UserRemovedSystemContent)
    case user_joined(UserJoinedSystemContent)
    case user_left(UserLeftSystemContent)
    case user_kicked(UserKickedSystemContent)
    case user_banned(UserBannedSystemContent)
    case channel_renamed(ChannelRenamedSystemContent)
    case channel_description_changed(ChannelDescriptionChangedSystemContent)
    case channel_icon_changed(ChannelIconChangedSystemContent)
    case channel_ownership_changed(ChannelOwnershipChangedSystemContent)
    case message_pinned(MessagePinnedSystemContent)
    case message_unpinned(MessagePinnedSystemContent)
}

// MARK: - Codable Conformance for SystemMessageContent

extension SystemMessageContent: Codable {
    enum CodingKeys: String, CodingKey { case type }
    enum Tag: String, Codable {
        case text, user_added, user_remove, user_joined, user_left, user_kicked, user_banned, channel_renamed, channel_description_changed, channel_icon_changed, channel_ownership_changed, message_pinned, message_unpinned
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .type) {
            case .text:
                self = .text(try singleValueContainer.decode(TextSystemMessageContent.self))
            case .user_added:
                self = .user_added(try singleValueContainer.decode(UserAddedSystemContent.self))
            case .user_remove:
                self = .user_removed(try singleValueContainer.decode(UserRemovedSystemContent.self))
            case .user_joined:
                self = .user_joined(try singleValueContainer.decode(UserJoinedSystemContent.self))
            case .user_left:
                self = .user_left(try singleValueContainer.decode(UserLeftSystemContent.self))
            case .user_kicked:
                self = .user_kicked(try singleValueContainer.decode(UserKickedSystemContent.self))
            case .user_banned:
                self = .user_banned(try singleValueContainer.decode(UserBannedSystemContent.self))
            case .channel_renamed:
                self = .channel_renamed(try singleValueContainer.decode(ChannelRenamedSystemContent.self))
            case .channel_description_changed:
                self = .channel_description_changed(try singleValueContainer.decode(ChannelDescriptionChangedSystemContent.self))
            case .channel_icon_changed:
                self = .channel_icon_changed(try singleValueContainer.decode(ChannelIconChangedSystemContent.self))
            case .channel_ownership_changed:
                self = .channel_ownership_changed(try singleValueContainer.decode(ChannelOwnershipChangedSystemContent.self))
            case .message_pinned:
                self = .message_pinned(try singleValueContainer.decode(MessagePinnedSystemContent.self))
            case .message_unpinned:
                self = .message_unpinned(try singleValueContainer.decode(MessagePinnedSystemContent.self))
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var tagContainer = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
            case .text(let content):
                try tagContainer.encode(Tag.text, forKey: .type)
                try content.encode(to: encoder)
            case .user_added(let content):
                try tagContainer.encode(Tag.user_added, forKey: .type)
                try content.encode(to: encoder)
            case .user_removed(let content):
                try tagContainer.encode(Tag.user_remove, forKey: .type)
                try content.encode(to: encoder)
            case .user_joined(let content):
                try tagContainer.encode(Tag.user_joined, forKey: .type)
                try content.encode(to: encoder)
            case .user_left(let content):
                try tagContainer.encode(Tag.user_left, forKey: .type)
                try content.encode(to: encoder)
            case .user_kicked(let content):
                try tagContainer.encode(Tag.user_kicked, forKey: .type)
                try content.encode(to: encoder)
            case .user_banned(let content):
                try tagContainer.encode(Tag.user_banned, forKey: .type)
                try content.encode(to: encoder)
            case .channel_renamed(let content):
                try tagContainer.encode(Tag.channel_renamed, forKey: .type)
                try content.encode(to: encoder)
            case .channel_description_changed(let content):
                try tagContainer.encode(Tag.channel_description_changed, forKey: .type)
                try content.encode(to: encoder)
            case .channel_icon_changed(let content):
                try tagContainer.encode(Tag.channel_icon_changed, forKey: .type)
                try content.encode(to: encoder)
            case .channel_ownership_changed(let content):
                try tagContainer.encode(Tag.channel_ownership_changed, forKey: .type)
                try content.encode(to: encoder)
            case .message_pinned(let content):
                try tagContainer.encode(Tag.message_pinned, forKey: .type)
                try content.encode(to: encoder)
            case .message_unpinned(let content):
                try tagContainer.encode(Tag.message_unpinned, forKey: .type)
                try content.encode(to: encoder)
            
        }
    }
}

// MARK: - MessageWebhook Structure

/// Represents a webhook message, which can have a different name and avatar.
public struct MessageWebhook: Codable, Equatable {
    public var name: String? // The name of the webhook (optional).
    public var avatar: String? // The avatar associated with the webhook (optional).
    
    public init(name: String? = nil, avatar: String? = nil) {
        self.name = name
        self.avatar = avatar
    }
}

// MARK: - Message Structure

/// Represents a message in a channel, containing various attributes.
public struct Message: Identifiable, Codable, Equatable {
    /// Initializes a new instance of `Message`.
    /// - Parameters:
    ///   - id: The unique identifier for the message.
    ///   - content: The content of the message (optional).
    ///   - author: The ID of the message author.
    ///   - channel: The ID of the channel where the message was sent.
    ///   - system: The system message content (optional).
    ///   - attachments: A list of file attachments (optional).
    ///   - mentions: A list of mentioned user IDs (optional).
    ///   - replies: A list of reply message IDs (optional).
    ///   - edited: The timestamp of when the message was edited (optional).
    ///   - masquerade: The masquerade information (optional).
    ///   - interactions: The interactions associated with the message (optional).
    ///   - reactions: A dictionary of reactions (optional).
    ///   - user: The user who sent the message (optional).
    ///   - member: The member associated with the message (optional).
    ///   - embeds: A list of embeds associated with the message (optional).
    ///   - webhook: The webhook information (optional).
    public init(id: String, content: String? = nil, author: String, channel: String, system: SystemMessageContent? = nil, attachments: [File]? = nil, mentions: [String]? = nil, replies: [String]? = nil, edited: String? = nil, masquerade: Masquerade? = nil, interactions: Interactions? = nil, reactions: [String: [String]]? = nil, user: User? = nil, member: Member? = nil, embeds: [Embed]? = nil, webhook: MessageWebhook? = nil) {
        self.id = id // Initialize the message ID.
        self.content = content // Set the message content (if any).
        self.author = author // Set the author ID.
        self.channel = channel // Set the channel ID.
        self.system = system // Set the system message content (if any).
        self.attachments = attachments // Set the attachments (if any).
        self.mentions = mentions // Set the mentions (if any).
        self.replies = replies // Set the replies (if any).
        self.edited = edited // Set the edit timestamp (if any).
        self.masquerade = masquerade // Set the masquerade (if any).
        self.interactions = interactions // Set the interactions (if any).
        self.reactions = reactions // Set the reactions (if any).
        self.user = user // Set the user (if any).
        self.member = member // Set the member (if any).
        self.embeds = embeds // Set the embeds (if any).
        self.webhook = webhook // Set the webhook information (if any).
    }
    
    public var id: String // Unique identifier for the message.
    
    public var content: String? // The content of the message (optional).
    public var author: String // The ID of the message author.
    public var channel: String // The ID of the channel where the message was sent.
    public var system: SystemMessageContent? // The system message content (if any).
    public var attachments: [File]? // List of file attachments (if any).
    public var mentions: [String]? // List of mentioned user IDs (if any).
    public var replies: [String]? // List of reply message IDs (if any).
    public var edited: String? // The timestamp of when the message was edited (if any).
    public var masquerade: Masquerade? // The masquerade information (if any).
    public var interactions: Interactions? // The interactions associated with the message (if any).
    public var reactions: [String: [String]]? // Dictionary of reactions (if any).
    public var user: User? // The user who sent the message (if any).
    public var member: Member? // The member associated with the message (if any).
    public var embeds: [Embed]? // List of embeds associated with the message (if any).
    public var webhook: MessageWebhook? // The webhook information (if any).
    
    enum CodingKeys: String, CodingKey {
        case id = "_id" // Mapping the ID to the JSON key "_id".
        case content, author, channel, system, attachments, mentions, replies, edited, masquerade, interactions, reactions, user, member, embeds, webhook // Other properties mapped directly.
    }
    
    public func isInviteLink() -> Bool {
        guard let content = self.content else { return false }
        
        // Create a pattern that matches "https://peptide.chat/invite/" followed by any characters
        // anywhere in the content
        let pattern = "https://peptide\\.chat/invite/[A-Za-z0-9]+"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(content.startIndex..., in: content)
            return regex.firstMatch(in: content, range: range) != nil
        } catch {
            return false
        }
    }
}
