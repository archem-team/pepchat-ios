//
//  Payloads.swift
//  Revolt
//
//  Created by Tom on 2023-11-13.
//

import Foundation
import Types

/// Payload structure for creating a new account.
struct AccountCreatePayload: Encodable {
    var email: String        // User's email address
    var password: String     // User's password
    var invite: String?      // Optional invite code
    var captcha: String?     // Optional captcha response
}

/// An empty response structure for scenarios where no content is returned.
struct EmptyResponse {
    
}

/// Payload structure for fetching message history.
struct FetchHistory: Decodable {
    var messages: [Message]  // Array of messages in the history
    var users: [User]        // Array of users involved in the messages
    var members: [Member]?    // Optional array of channel members
}

/// Payload structure for replying to a message.
struct ApiReply: Encodable {
    var id: String           // ID of the message being replied to
    var mention: Bool        // Indicates if the reply mentions the user
}

/// Payload structure for sending a message.
struct SendMessage: Encodable {
    var replies: [ApiReply]  // Array of replies to the message
    var content: String       // Content of the message
    var attachments: [String] // Array of attachment IDs
}

/// Payload structure for reporting content.
/// Payload structure for reporting content.
struct ContentReportPayload: Encodable {
    
    /// Reasons for reporting content.
    /// Reason for reporting content.
    enum ContentReportReason: String, Encodable, CaseIterable {
        case NoneSpecified = "NoneSpecified"
        case Illegal = "Illegal"
        case IllegalGoods = "IllegalGoods"
        case IllegalExtortion = "IllegalExtortion"
        case IllegalPornography = "IllegalPornography"
        case IllegalHacking = "IllegalHacking"
        case ExtremeViolence = "ExtremeViolence"
        case PromotesHarm = "PromotesHarm"
        case UnsolicitedSpam = "UnsolicitedSpam"
        case Raid = "Raid"
        case SpamAbuse = "SpamAbuse"
        case ScamsFraud = "ScamsFraud"
        case Malware = "Malware"
        case Harassment = "Harassment"
        case InappropriateProfile = "InappropriateProfile"
        case Impersonation = "Impersonation"
        case BanEvasion = "BanEvasion"
        case Underage = "Underage"
        
        /// Returns the title for the reason based on the report type.
        func title(for type: ContentReportType) -> String {
            switch (self, type) {
                // MARK: - General Cases
            case (.NoneSpecified, _):
                return "No reason specified / other reason"
                
                // MARK: - Message Report Titles
            case (.Illegal, .Message):
                return "Content breaks one or more laws"
            case (.SpamAbuse, .Message):
                return "This is spam or platform abuse"
            case (.Harassment, .Message):
                return "This is harassment or abuse targeted at another user"
            case (.ExtremeViolence, .Message):
                return "Violent or Harmful Message"
            case (.PromotesHarm, .Message):
                return "Content promotes harm to others or self"
            case (.Malware, .Message):
                return "This is malware"
                
                // MARK: - Server Report Titles
            case (.Illegal, .Server):
                return "Content breaks one or more laws"
            case (.Raid, .Server):
                return "Server Raid Activity"
            case (.PromotesHarm, .Server):
                return "Content promotes harm to others or self"
            case (.SpamAbuse, .Server):
                return "This is spam or platform abuse"
            case (.Malware, .Server):
                return "This is malware"
            case (.Harassment, .Server):
                return "This is harassment or abuse targeted at another user"
                
                // MARK: - User Report Titles
            case (.SpamAbuse, .User):
                return "User is sending spam or otherwise abusing the platform"
            case (.InappropriateProfile, .User):
                return "User's profile is inappropriate for a general audience"
            case (.Impersonation, .User):
                return "This user is impersonating someone else"
            case (.BanEvasion, .User):
                return "This user is evading a ban"
            case (.Underage, .User):
                return "This user is not old enough to have an account"
                /*case (.UnsolicitedSpam, .User):
                 return "Harassment by User"*/
                
                
                // Default case for other combinations
            default:
                return "General Report Reason"
            }
        }
        
        /// Returns the list of reasons specific to the given report type.
        static func reasons(for type: ContentReportPayload.ContentReportType) -> [ContentReportReason] {
            switch type {
            case .Message:
                return [
                    .NoneSpecified, .Illegal, .PromotesHarm, .SpamAbuse, .Malware, .Harassment, /*.IllegalGoods, .IllegalExtortion, .IllegalPornography,
                    .IllegalHacking, .ExtremeViolence,  .UnsolicitedSpam,
                    .Raid,  .ScamsFraud,*/
                ]
            case .Server:
                return [
                    .NoneSpecified, .Illegal, .PromotesHarm, .SpamAbuse, .Malware, .Harassment
                ]
            case .User:
                return [
                    .NoneSpecified, .SpamAbuse, .InappropriateProfile, .Impersonation, .BanEvasion,
                    .Underage, /*.UnsolicitedSpam,*/
                    
                ]
            }
        }
    }
    
    
    /// Types of content that can be reported.
    enum ContentReportType: String, Encodable {
        case Message = "Message" // Report a message
        case Server = "Server"   // Report a server
        case User = "User"       // Report a user
    }
    
    /// Nested structure for the content details being reported.
    struct NestedContentReportPayload: Encodable {
        var type: ContentReportType // The type of content being reported
        var id: String              // The ID of the content
        var report_reason: ContentReportReason // The reason for reporting the content
        var message_id: String? = nil          // Optional message ID for user reports
        
        /// Initializes a new nested payload for content reporting.
        init(type: ContentReportType, id: String, report_reason: ContentReportReason, message_id: String? = nil) {
            self.type = type
            self.id = id
            self.report_reason = report_reason
            self.message_id = message_id
        }
    }
    
    var content: NestedContentReportPayload // The content details being reported
    var additional_context: String          // Additional context or information
    
    /// Initializes a new content report payload.
    init(type: ContentReportType, contentId: String, reason: ContentReportReason, userContext: String, messageId: String? = nil) {
        self.content = NestedContentReportPayload(type: type, id: contentId, report_reason: reason, message_id: messageId)
        self.additional_context = userContext
    }
}

/// Payload structure for uploading an autumn file.
struct AutumnPayload: Encodable {
    var file: Data // Data of the file being uploaded
}

/// Payload structure for resetting a password.
struct PasswordResetPayload: Encodable {
    var token: String   // Token for resetting the password
    var password: String // New password
}

/// Payload structure for creating a group channel.
struct GroupChannelCreate: Encodable {
    var name: String            // Name of the group channel
    var users: [String]        // Array of user IDs to add to the group
}

/// Payload structure for editing server settings.
import Foundation

import Foundation

struct ServerEdit: Codable {
    enum Remove: String, Codable {
        case description = "Description"
        case categories = "Categories"
        case system_messages = "SystemMessages"
        case icon = "Icon"
        case banner = "Banner"
    }
    
    var name: String?
    var description: String?
    var icon: String?
    var banner: String?
    var categories: [Types.Category]?
    var system_messages: SystemMessages?
    var flags: Int?
    var discoverable: Bool?
    var analytics: Bool?
    var remove: [Remove]?
    
    enum CodingKeys: String, CodingKey {
        case name, description, icon, banner, categories, system_messages, flags, discoverable, analytics, remove
    }
    
    /// ✅ **Custom Initializer**
    init(
        name: String? = nil,
        description: String? = nil,
        icon: String? = nil,
        banner: String? = nil,
        categories: [Types.Category]? = nil,
        system_messages: SystemMessages? = nil,
        flags: Int? = nil,
        discoverable: Bool? = nil,
        analytics: Bool? = nil,
        remove: [Remove]? = nil
    ) {
        self.name = name
        self.description = description
        self.icon = icon
        self.banner = banner
        self.categories = categories
        self.system_messages = system_messages
        self.flags = flags
        self.discoverable = discoverable
        self.analytics = analytics
        self.remove = remove
    }

    /// ✅ **Encoding Logic (Unchanged)**
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        if let name = name {
            try container.encode(name, forKey: .name)
        }
        if let description = description {
            try container.encode(description, forKey: .description)
        }
        if let icon = icon {
            try container.encode(icon, forKey: .icon)
        }
        if let banner = banner {
            try container.encode(banner, forKey: .banner)
        }
        if let categories = categories {
            try container.encode(categories, forKey: .categories)
        }
        if let system_messages = system_messages {
            try container.encode(system_messages, forKey: .system_messages)
        }
        if let flags = flags {
            try container.encode(flags, forKey: .flags)
        }
        if let discoverable = discoverable {
            try container.encode(discoverable, forKey: .discoverable)
        }
        if let analytics = analytics {
            try container.encode(analytics, forKey: .analytics)
        }
        if let remove = remove {
            try container.encode(remove, forKey: .remove)
        }
    }

    /// ✅ **Decoding Logic**
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        banner = try container.decodeIfPresent(String.self, forKey: .banner)
        categories = try container.decodeIfPresent([Types.Category].self, forKey: .categories)
        system_messages = try container.decodeIfPresent(SystemMessages.self, forKey: .system_messages)
        flags = try container.decodeIfPresent(Int.self, forKey: .flags)
        discoverable = try container.decodeIfPresent(Bool.self, forKey: .discoverable)
        analytics = try container.decodeIfPresent(Bool.self, forKey: .analytics)
        remove = try container.decodeIfPresent([Remove].self, forKey: .remove)
    }
}



/// Payload structure for editing a message.
struct MessageEdit: Encodable {
    var content: String? // Optional new content for the message
}

/// Payload structure for searching channels.
struct ChannelSearchPayload: Encodable {
    enum MessageSort: String, Encodable, CaseIterable {
        case latest = "Latest"       // Sort by latest messages
        case oldest = "Oldest"       // Sort by oldest messages
        case relevance = "Relevance" // Sort by relevance
    }
    
    var query: String            // Search query
    var limit: Int?             // Optional limit on the number of results
    var before: String?         // Optional ID to fetch results before a certain message
    var after: String?          // Optional ID to fetch results after a certain message
    var sort: MessageSort?      // Optional sort order for the results
    var include_users: Bool?    // Optional flag to include users in the search results
}

/// Payload structure for editing a role.
struct RoleEditPayload: Encodable {
    enum Remove: String, Encodable {
        case colour = "Colour" // Option to remove the role color
    }
    
    var name: String?       // Optional new name for the role
    var colour: String?     // Optional new color for the role
    var hoist: Bool?        // Optional hoist setting for the role
    var rank: Int?          // Optional rank for the role
    var remove: [Remove]?   // Optional fields to remove from the role
}

/// Payload structure for creating a new emoji.
struct CreateEmojiPayload: Encodable {
    var id: String               // ID for the emoji
    var name: String             // Name of the emoji
    var parent: EmojiParent      // Parent category for the emoji
    var nsfw: Bool?              // Optional flag indicating if the emoji is NSFW
}

struct EditBotPayload: Encodable {
    enum Remove: String, Encodable {
        case token = "Token"
    }
    
    var name: String?
    var isPublic: Bool?
    var analytics: Bool?
    var interactions_url: String?
    var remove: [Remove]?
    
    enum CodingKeys: String, CodingKey {
        case name, analytics, interactions_url, remove
        case isPublic = "public"
    }
}


struct ChannelEditPayload: Encodable {
    var name: String?
    var description: String?
    var icon: String?
    var nsfw: Bool?
    var owner : String?
    var remove: [RemoveField]?

    enum RemoveField: String, Encodable {
        case description = "Description"
        case icon = "Icon"
        case defaultPermissions = "DefaultPermissions"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let name = name, !name.isEmpty { try container.encode(name, forKey: .name) }
        if let description = description, !description.isEmpty { try container.encode(description, forKey: .description) }
        if let icon = icon, !icon.isEmpty { try container.encode(icon, forKey: .icon) }
        if let nsfw = nsfw { try container.encode(nsfw, forKey: .nsfw) }
        if let remove = remove, !remove.isEmpty { try container.encode(remove, forKey: .remove) }
        if let owner = owner { try container.encode(owner, forKey: .owner) }
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, icon, nsfw, remove, owner
    }
}



struct SetDefaultPermissionPayload: Codable {
    var permissions: Permissions
    
    enum CodingKeys: String, CodingKey {
        case permissions
    }
}


enum RemoveMemberField: String, Codable, CaseIterable {
    case nickname = "Nickname"
    case avatar = "Avatar"
    case roles = "Roles"
    case timeout = "Timeout"
}

struct EditMember: Codable {
    var nickname: String?
    var avatar: String?
    var remove: [RemoveMemberField]?
    var roles: [String]?
    //var timeout: String?
    
    
    init(nickname: String? = nil, avatar: String? = nil, remove: [RemoveMemberField]? = nil, roles: [String]? = nil) {
        self.nickname = nickname
        self.avatar = avatar
        self.remove = remove
        self.roles = roles
    }
    
    enum CodingKeys: String, CodingKey {
        case nickname, avatar, remove, roles
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode nickname if it's not nil or empty
        if let nickname = nickname, !nickname.isEmpty {
            try container.encode(nickname, forKey: .nickname)
        }
        
        // Encode avatar if it's not nil or empty
        if let avatar = avatar, !avatar.isEmpty {
            try container.encode(avatar, forKey: .avatar)
        }
        
        // Encode remove only if it's not nil and not empty
        if let remove = remove, !remove.isEmpty {
            try container.encode(remove, forKey: .remove)
        }
        
        // Encode remove only if it's not nil and not empty
        if let roles = roles{
            try container.encode(roles, forKey: .roles)
        }
    }
    
}


/// Payload structure for creating a new channel.
struct CreateChannel: Codable {
    var type: String // Type of the channel
    var name: String // Name of the channel
}



struct ProfilePayload: Codable {
    var status: Status?
    var remove: [ProfileRemoveField]?
    var displayName: String?
    var profile: ProfileContent?
    var avatar: String?

    
    init(status: Status? = nil, remove: [ProfileRemoveField]? = nil, displayName: String? = nil, profile: ProfileContent? = nil, avatar : String? = nil) {
        self.status = status
        self.remove = remove
        self.displayName = displayName
        self.profile = profile
        self.avatar = avatar
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        if let status = status {
            try container.encode(status, forKey: .status)
        }
        
        if let remove = remove {
            try container.encode(remove, forKey: .remove)
        }
        
        if let displayName = displayName {
            try container.encode(displayName, forKey: .displayName)
        }
        
        if let profile = profile{
            try container.encode(profile, forKey: .profile)
        }
        
        if let avatar {
            try container.encode(avatar, forKey: .avatar)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case status, remove
        case displayName = "display_name"
        case profile
        case avatar
    }
}


struct ProfileContent: Codable {
    var content: String?
    var background : String?
    
    init(content: String? = nil, background : String? = nil) {
        self.content = content
        self.background = background
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        if let content = content {
            try container.encode(content, forKey: .content)
        }
        
        if let background = background {
            try container.encode(background, forKey: .background)
        }
        
        
    }
    
    private enum CodingKeys: String, CodingKey {
        case content
        case background
       
    }
}

enum ProfileRemoveField: String, Codable {
    case statusText = "StatusText"
}


struct UpdateEmail: Codable {
    var email: String
    var currentPassword: String

    enum CodingKeys: String, CodingKey {
        case email
        case currentPassword = "current_password"
    }
    
    init(email: String = "", currentPassword: String = "") {
        self.email = email
        self.currentPassword = currentPassword
    }
}


struct CreateServer : Codable {
    let name: String
}

