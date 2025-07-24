//
//  permissions.swift
//  Revolt
//
//  Created by Angelo on 14/10/2023.
//

import Foundation

/// A structure representing user-specific permissions using OptionSet.
public struct UserPermissions: OptionSet {
    /// Creates a new instance with the given raw value.
    /// - Parameter rawValue: The raw integer value representing the permissions.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public var rawValue: Int
    
    // Define user permissions
    public static let access = UserPermissions(rawValue: 1 << 0) // Permission to access
    public static let viewProfile = UserPermissions(rawValue: 1 << 1) // Permission to view profile
    public static let sendMessage = UserPermissions(rawValue: 1 << 2) // Permission to send messages
    public static let invite = UserPermissions(rawValue: 1 << 3) // Permission to invite others
    
    // Convenience properties for all or no permissions
    public static let all = UserPermissions(arrayLiteral: [.access, .viewProfile, .sendMessage, .invite])
    public static let none = UserPermissions([])
}

// MARK: - Codable Conformance for UserPermissions
extension UserPermissions: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(Int.self) // Decode the raw value from the decoder
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue) // Encode the raw value to the encoder
    }
}

/// A structure representing various permissions using OptionSet and Hashable.
public struct Permissions: OptionSet, Hashable {
    /// Creates a new instance with the given raw value.
    /// - Parameter rawValue: The raw integer value representing the permissions.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public var rawValue: Int
    
    // Define various permissions
    public static let manageChannel = Permissions(rawValue: 1 << 0) // Permission to manage channels
    public static let manageServer = Permissions(rawValue: 1 << 1) // Permission to manage server settings
    public static let managePermissions = Permissions(rawValue: 1 << 2) // Permission to manage permissions
    public static let manageRole = Permissions(rawValue: 1 << 3) // Permission to manage roles
    public static let manageCustomisation = Permissions(rawValue: 1 << 4) // Permission to manage customisation options
    
    public static let kickMembers = Permissions(rawValue: 1 << 6) // Permission to kick members
    public static let banMembers = Permissions(rawValue: 1 << 7) // Permission to ban members
    public static let timeoutMembers = Permissions(rawValue: 1 << 8) // Permission to timeout members
    public static let assignRoles = Permissions(rawValue: 1 << 9) // Permission to assign roles
    public static let manageNickname = Permissions(rawValue: 1 << 10) // Permission to manage nicknames
    public static let changeNicknames = Permissions(rawValue: 1 << 11) // Permission to change nicknames
    public static let changeAvatars = Permissions(rawValue: 1 << 12) // Permission to change avatars
    public static let removeAvatars = Permissions(rawValue: 1 << 13) // Permission to remove avatars
    
    public static let viewChannel = Permissions(rawValue: 1 << 20) // Permission to view channels
    public static let readMessageHistory = Permissions(rawValue: 1 << 21) // Permission to read message history
    public static let sendMessages = Permissions(rawValue: 1 << 22) // Permission to send messages
    public static let manageMessages = Permissions(rawValue: 1 << 23) // Permission to manage messages
    public static let manageWebhooks = Permissions(rawValue: 1 << 24) // Permission to manage webhooks
    public static let inviteOthers = Permissions(rawValue: 1 << 25) // Permission to invite others
    public static let sendEmbeds = Permissions(rawValue: 1 << 26) // Permission to send embedded messages
    public static let uploadFiles = Permissions(rawValue: 1 << 27) // Permission to upload files
    public static let masquerade = Permissions(rawValue: 1 << 28) // Permission to masquerade as another user
    public static let react = Permissions(rawValue: 1 << 29) // Permission to react to messages
    
    public static let connect = Permissions(rawValue: 1 << 30) // Permission to connect to voice channels
    public static let speak = Permissions(rawValue: 1 << 31) // Permission to speak in voice channels
    public static let video = Permissions(rawValue: 1 << 32) // Permission to share video in voice channels
    public static let muteMembers = Permissions(rawValue: 1 << 33) // Permission to mute members
    public static let deafenMembers = Permissions(rawValue: 1 << 34) // Permission to deafen members
    public static let moveMembers = Permissions(rawValue: 1 << 35) // Permission to move members between channels
    
    // Convenience properties for default permissions
    public static let all = Permissions(arrayLiteral: [
        .manageChannel, .manageServer, .managePermissions, .manageRole, .manageCustomisation, .kickMembers, .banMembers,
        .timeoutMembers, .assignRoles, .manageNickname, .changeNicknames, .changeAvatars, .removeAvatars, .viewChannel,
        .readMessageHistory, .sendMessages, .manageMessages, .manageWebhooks, .inviteOthers, .sendEmbeds,
        .uploadFiles, .masquerade, .react, .connect, .speak, .video, .muteMembers, .deafenMembers, .moveMembers
    ])
    
    public static let defaultViewOnly = Permissions([.viewChannel, .readMessageHistory]) // Default view-only permissions
    public static let `default` = Permissions.defaultViewOnly.intersection(Permissions([
        .sendMessages, .inviteOthers, .sendEmbeds, .uploadFiles, .connect, .speak
    ])) // Default permissions including messaging
    public static let defaultDirectMessages = Permissions.defaultViewOnly.intersection(Permissions([.manageChannel, .react])) // Default permissions for direct messages
    public static let defaultGroupDirectMessages = Permissions([.manageChannel, .sendMessages, .inviteOthers, .sendEmbeds, .uploadFiles, .react])
    public static let defaultAllowInTimeout = Permissions([.viewChannel, .readMessageHistory]) // Permissions allowed in timeout
    public static let none = Permissions([]) // No permissions
    
    /// Applies an overwrite to the current permissions.
    /// - Parameter overwrite: The overwrite containing added and removed permissions.
    /// - Returns: The new permissions after applying the overwrite.
    public func apply(overwrite: Overwrite) -> Permissions {
        return self
            .union(overwrite.a) // Add permissions
            .intersection(Permissions.all.subtracting(overwrite.d)) // Remove permissions
    }
    
    /// Applies an overwrite to the current permissions, modifying the current instance.
    /// - Parameter overwrite: The overwrite containing added and removed permissions.
    public mutating func formApply(overwrite: Overwrite) {        
        self.formUnion(overwrite.a)
        self.formIntersection(Permissions.all.subtracting(overwrite.d))
    }
    
    /// Returns the user-friendly name of the permission.
    public var name: String {
        switch self {
            case .manageChannel: return "Manage Group"
            case .manageServer: return "Manage Server"
            case .managePermissions: return "Manage Permissions"
            case .manageRole: return "Manage Roles"
            case .manageCustomisation: return "Manage Customisations"
            case .kickMembers: return "Kick Members"
            case .banMembers: return "Ban Members"
            case .timeoutMembers: return "Timeout Members"
            case .assignRoles: return "Assign Roles"
            case .manageNickname: return "Manage Nicknames"
            case .changeNicknames: return "Change Nicknames"
            case .changeAvatars: return "Change Avatars"
            case .removeAvatars: return "Remove Avatars"
            case .viewChannel: return "View Channel"
            case .readMessageHistory: return "Read Message History"
            case .sendMessages: return "Send Messages"
            case .manageMessages: return "Manage Messages"
            case .manageWebhooks: return "Manage Webhooks"
            case .inviteOthers: return "Invite Others"
            case .sendEmbeds: return "Send Embeds"
            case .uploadFiles: return "Upload Files"
            case .masquerade: return "Masquerade"
            case .react: return "Use Reactions"
            case .connect: return "Connect"
            case .speak: return "Speak"
            case .video: return "Video"
            case .muteMembers: return "Mute Members"
            case .deafenMembers: return "Deafen Members"
            case .moveMembers: return "Move Members"
            default: return "Unknown"
        }
    }
    
    /// Returns a description of the permission.
    public var description: String {
        switch self {
            case .manageChannel: return "Allows members to edit or delete a group."
            case .manageServer: return "Allows members to change this server's name, description, icon and other related information."
            case .managePermissions: return "Allows members to change permissions for group and roles with a lower ranking."
            case .manageRole: return "Allows members to create, edit and delete roles with a lower rank than theirs, and modify role permissions on channels."
            case .manageCustomisation: return "Allows members to create, edit and delete emojis."
            case .kickMembers: return "Allows members to remove members from this server. Kicked members may rejoin with an invite."
            case .banMembers: return "Allows members to permanently remove members from this server."
            case .timeoutMembers: return "Allows members to temporarily prevent users from interacting with the server."
            case .assignRoles: return "Allows members to assign roles below their own rank to other members."
            case .manageNickname: return "Allows members to change the nicknames of other members."
            case .changeNicknames: return "Allows members to change their nickname on this server."
            case .removeAvatars: return "Allows members to remove the server avatars of other members on this server."
            case .changeAvatars: return "Allows members to change their avatar on this server."
            case .viewChannel: return "Allows members to view any channels they have this permission on."
            case .readMessageHistory: return "Allows members to read the message history of this channel."
            case .sendMessages: return "Allows members to send messages in group."
            case .manageMessages: return "Allows members to delete messages sent by other members."
            case .manageWebhooks: return "Allows members to control webhooks in a channel."
            case .inviteOthers: return "Allows members to invite other users ro a group."
            case .sendEmbeds: return "Allows members to send embedded content, whether from links or custom text embeds."
            case .uploadFiles: return "Allows members to upload files in group."
            case .masquerade: return "Allows members to change their name and avatar per-message."
            case .react: return "Allows members to react to messages."
            case .connect: return "Allows members to connect to a voice channel."
            case .speak: return "Allows members to speak in a voice channel."
            case .video: return "Allows members to stream video in a voice channel."
            case .muteMembers: return "Allows members to mute others in a voice channel."
            case .deafenMembers: return "Allows members to deafen others in a voice channel."
            case .moveMembers: return "Allows members to move others between voice channels."
            default: return "Unknown"
        }
    }
}

// MARK: - Codable Conformance for Permissions
extension Permissions: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(Int.self) // Decode the raw value from the decoder
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue) // Encode the raw value to the encoder
    }
}

/// A structure representing permission overwrites for users or roles.
public struct Overwrite: Codable, Equatable , Hashable{
    /// Creates a new instance with the specified added and removed permissions.
    /// - Parameters:
    ///   - a: The permissions to allow.
    ///   - d: The permissions to deny.
    public init(a: Permissions, d: Permissions) {
        self.a = a
        self.d = d
    }
    
    public var a: Permissions
    public var d: Permissions
}
