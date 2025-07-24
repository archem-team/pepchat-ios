//
//  Responses.swift
//  Revolt
//
//  Created by Tom on 2023-11-13.
//

import Foundation
import Types
import AnyCodable


/// Response structure for verifying account creation.
struct AccountCreateVerifyResponse: Decodable {
    struct Inner: Decodable {
        var _id: String             // Unique identifier for the verification ticket
        var account_id: String      // ID of the account being verified
        var token: String           // Verification token
        var validated: Bool         // Indicates if the account is validated
        var authorised: Bool        // Indicates if the account is authorized
        var last_totp_code: String? // Optional last TOTP code used
    }
    
    var ticket: Inner             // The inner ticket details
}

/// Response structure for onboarding status.
struct OnboardingStatusResponse: Decodable {
    var onboarding: Bool          // Indicates if the user is in onboarding
}

/// Response structure for autumn-related requests.
struct AutumnResponse: Decodable {
    var id: String                // ID of the autumn upload
}

/// Response structure for joining a server or group.
struct JoinResponse: Decodable {
    var type: String              // Type of the join response
    var channels: [Channel]       // Array of channels available in the server
    var server: Server            // Server details
}

/// Response structure for unread messages in channels.
struct Unread: Decodable, Identifiable {
    struct Id: Decodable, Hashable {
        var channel: String       // Channel ID
        var user: String          // User ID
    }
    
    var id: Id                    // Unique identifier for the unread messages
    var last_id: String?          // Optional last message ID
    var mentions: [String]?       // Optional array of mentions in unread messages
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"           // Coding key for the ID
        case last_id, mentions     // Other properties
    }
}

/// Response structure for authenticated account details.
struct AuthAccount: Decodable {
    var _id: String              // Unique identifier for the account
    var email: String            // Email associated with the account
}

/// Response structure for TOTP secret.
struct TOTPSecretResponse: Decodable {
    var secret: String           // TOTP secret string
}

/// Response structure for MFA ticket.
struct MFATicketResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case id = "_id"          // Coding key for the ID
        case account_id, token, validated, authorised, last_totp_code
    }
    
    var id: String               // Unique identifier for the MFA ticket
    var account_id: String       // ID of the associated account
    var token: String            // MFA token
    var validated: Bool          // Indicates if the MFA is validated
    var authorised: Bool         // Indicates if the MFA is authorized
    var last_totp_code: String?  // Optional last TOTP code used
}

/// Response structure for search results.
struct SearchResponse: Decodable {
    var messages: [Message]      // Array of messages matching the search criteria
    var users: [User]            // Array of users matching the search criteria
    var members: [Member]?        // Array of members matching the search criteria
}

/// Response structure for mutual connections.
struct MutualsResponse: Decodable {
    var servers: [String]        // Array of server IDs the user is mutual in
    var users: [String]          // Array of user IDs the user is mutual with
}

/// Enum representing information about an invite, which can be a server or a group.
enum InviteInfoResponse {
    case server(ServerInfoResponse)
    case group(GroupInfoResponse)
    
    func getServerID() -> String? {
        switch self{
        case .server(let res): return res.server_id
        case .group(_): return nil
        }    
    }
    
    func getChannelID() -> String? {
        switch self{
        case .server(let res): return res.channel_id
        case .group(let res): return res.channel_id
        }
    }
}

extension InviteInfoResponse: Decodable {
    enum CodingKeys: String, CodingKey { case type }
    enum Tag: String, Codable { case Server, Group }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .type) {
            case .Server:
                self = .server(try singleValueContainer.decode(ServerInfoResponse.self))
            case .Group:
                self = .group(try singleValueContainer.decode(GroupInfoResponse.self))
        }
    }
}

/// Response structure for server invite information.
struct ServerInfoResponse: Decodable {
    var code: String              // Invitation code for the server
    var server_id: String         // Unique identifier for the server
    var server_name: String       // Name of the server
    var server_icon: File?        // Optional server icon file
    var server_banner: File?      // Optional server banner file
    var server_flags: ServerFlags? // Optional server flags
    var channel_id: String        // ID of the channel related to the invite
    var channel_name: String      // Name of the channel related to the invite
    var channel_description: String? // Optional description of the channel
    var user_name: String         // Name of the user who sent the invite
    var user_avatar: File?        // Optional avatar file of the user
    var member_count: Int         // Number of members in the server
}

/// Response structure for group invite information.
struct GroupInfoResponse: Decodable {
    var code: String              // Invitation code for the group
    var channel_id: String        // ID of the channel related to the group
    var channel_name: String      // Name of the channel related to the group
    var channel_description: String? // Optional description of the channel
    var user_name: String         // Name of the user who sent the invite
    var user_avatar: File?        // Optional avatar file of the user
}

/// Response structure for a role that includes an ID.
struct RoleWithId: Decodable {
    var id: String                // Unique identifier for the role
    var role: Role                // The role details
}


struct MembersWithUsers: Decodable {
    var members: [Member]
    var users: [User]
}

struct BotsResponse: Decodable {
    var bots: [Bot]
    var users: [User]
}

struct Ban: Decodable, Identifiable {
    var id: MemberId
    var reason: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case reason
    }
}
struct BansResponse: Decodable {
    var users: [User]
    var bans: [Ban]
}

struct Tuple2<A, B> {
    var a: A
    var b: B
}

extension Tuple2: Codable where A: Codable, B: Codable {
    func encode(to encoder: any Encoder) throws {
        try [AnyCodable(a), AnyCodable(b)].encode(to: encoder)
    }

    init(from decoder: any Decoder) throws {
        let cont = try decoder.singleValueContainer()

        let list = try cont.decode([AnyCodable].self)

        self.a = list[0].value as! A
        self.b = list[1].value as! B
    }
}

typealias SettingsResponse = [String: Tuple2<Int, String>]



enum MFAMethod: String, Codable {
    case password = "Password"
    case recovery = "Recovery"
    case totp = "Totp"
}
