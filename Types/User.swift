//
//  User.swift
//  Types
//
//  Created by Angelo on 19/05/2024.
//

import Foundation

/// A structure representing a bot user, containing the owner's ID.
public struct UserBot: Codable, Equatable, Hashable {
    /// The ID of the user who owns this bot.
    public var owner: String
    
    public init(owner: String) {
        self.owner = owner
    }
}

/// An enumeration representing the different presence statuses of a user.
public enum Presence: String, Codable, Equatable, Hashable, CaseIterable {
    case Online     // The user is online.
    case Idle       // The user is idle.
    case Focus      // The user is focused.
    case Busy       // The user is busy.
    case Invisible  // The user is invisible.
    
}

/// An enumeration representing the relationship status between users.
public enum Relation: String, Codable, Equatable, Hashable {
    case Blocked        // The user is blocked.
    case BlockedOther   // The user is blocked by another user.
    case Friend         // The users are friends.
    case Incoming       // An incoming friend request.
    case None           // No relationship status.
    case Outgoing       // An outgoing friend request.
    case User           // The user is a standard user.
}

/// A structure representing the status of a user, including custom text and presence.
public struct Status: Codable, Equatable, Hashable {
    /// Creates a new instance of `Status`.
    /// - Parameters:
    ///   - text: Custom status text (optional).
    ///   - presence: Presence status of the user (optional).
    public init(text: String? = nil, presence: Presence? = nil) {
        self.text = text
        self.presence = presence
    }
    
    /// Custom status text (optional).
    public var text: String?
    
    /// The presence status of the user (optional).
    public var presence: Presence?
}

/// A structure representing the relationship status of a user.
public struct UserRelation: Codable, Equatable, Hashable {
    /// The status of the user relation.
    public var status: String
    
    public init(status: String) {
        self.status = status
    }
}

/// A structure representing a user, including their ID, username, and other attributes.
public struct User: Identifiable, Codable, Equatable, Hashable {
    /// Creates a new instance of `User`.
    /// - Parameters:
    ///   - id: Unique identifier for the user.
    ///   - username: The username of the user.
    ///   - discriminator: The user's discriminator (a unique tag).
    ///   - display_name: The display name of the user (optional).
    ///   - avatar: The user's avatar (optional).
    ///   - relations: A list of user relations (optional).
    ///   - badges: Bitfield of user badges.
    ///   - status: The user's current status (optional).
    ///   - relationship: The relationship status of the user (optional).
    ///   - online: A boolean indicating if the user is online (optional).
    ///   - flags: Flags associated with the user (optional).
    ///   - bot: Information about the user's bot status (optional).
    ///   - privileged: A boolean indicating if the user has privileged status (optional).
    ///   - profile: The user's profile information (optional).
    public init(id: String, username: String, discriminator: String, display_name: String? = nil, avatar: File? = nil, relations: [UserRelation]? = nil, badges: Int? = nil, status: Status? = nil, relationship: Relation? = nil, online: Bool? = nil, flags: Int? = nil, bot: UserBot? = nil, privileged: Bool? = nil, profile: Profile? = nil) {
        self.id = id
        self.username = username
        self.discriminator = discriminator
        self.display_name = display_name
        self.avatar = avatar
        self.relations = relations
        self.badges = badges
        self.status = status
        self.relationship = relationship
        self.online = online
        self.flags = flags
        self.bot = bot
        self.privileged = privileged
        self.profile = profile
    }

    public func usernameWithDiscriminator () -> String{
        return "\(username)#\(discriminator)"
    }

    public func displayName () -> String{
        return display_name ?? usernameWithDiscriminator()
    }
    

    
    /// Unique identifier for the user.
    public var id: String
    
    /// The username of the user.
    public var username: String
    
    /// The user's discriminator (a unique tag).
    public var discriminator: String
    
    /// The display name of the user (optional).
    public var display_name: String?
    
    /// The user's avatar, represented as a `File` object (optional).
    public var avatar: File?
    
    /// A list of user relations (optional).
    public var relations: [UserRelation]?
    
    /// Badges associated with the user (optional).
    public var badges: Int?
    
    /// The user's current status (optional).
    public var status: Status?
    
    /// The relationship status of the user (optional).
    public var relationship: Relation?
    
    /// A boolean indicating if the user is online (optional).
    public var online: Bool?
    
    /// Flags associated with the user (optional).
    public var flags: Int?
    
    /// Information about the user's bot status (optional).
    public var bot: UserBot?
    
    /// A boolean indicating if the user has privileged status (optional).
    public var privileged: Bool?
    
    /// The user's profile information (optional).
    public var profile: Profile?
    
    /// Coding keys for encoding/decoding the `User` structure.
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username, discriminator, display_name, avatar, relations, badges, status, relationship, online, flags, bot, privileged
    }
    
    public func getBadges() -> Badges? {
        return Badges.fromCode(code: badges)
    }
    
    /// Get all badges for this user from the bitfield
    public func getAllBadges() -> [Badges] {
        return Badges.allBadgesFromCode(code: badges)
    }
}

/// A structure representing a user's profile, including content and background.
public struct Profile: Codable, Equatable, Hashable {
    /// Creates a new instance of `Profile`.
    /// - Parameters:
    ///   - content: Content of the profile (optional).
    ///   - background: Background image of the profile (optional).
    public init(content: String? = nil, background: File? = nil) {
        self.content = content
        self.background = background
    }
    
    /// Content of the profile (optional).
    public var content: String?
    
    /// Background image of the profile, represented as a `File` object (optional).
    public var background: File?
}



