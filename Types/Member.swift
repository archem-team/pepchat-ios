//
//  Member.swift
//  Revolt
//
//  Created by Angelo on 12/10/2023.
//

import Foundation

// MARK: - MemberId Structure

/// Represents a unique identifier for a member in a server.
public struct MemberId: Codable, Equatable, Hashable {
    /// Initializes a new instance of `MemberId`.
    /// - Parameters:
    ///   - server: The identifier of the server.
    ///   - user: The identifier of the user.
    public init(server: String, user: String) {
        self.server = server // Initialize the server ID.
        self.user = user // Initialize the user ID.
    }
    
    public var server: String // Identifier of the server.
    public var user: String // Identifier of the user.
}

// MARK: - Member Structure

/// Represents a member of a server.
public struct Member: Codable, Equatable, Hashable {
    /// Initializes a new instance of `Member`.
    /// - Parameters:
    ///   - id: A unique identifier for the member, comprising the server and user IDs.
    ///   - nickname: The nickname of the member (optional).
    ///   - avatar: The avatar associated with the member (optional).
    ///   - roles: A list of roles assigned to the member (optional).
    ///   - joined_at: The timestamp when the member joined the server.
    ///   - timeout: The timeout duration for the member (optional).
    public init(id: MemberId, nickname: String? = nil, avatar: File? = nil, roles: [String]? = nil, joined_at: String, timeout: String? = nil) {
        self.id = id // Set the member's ID.
        self.nickname = nickname // Set the member's nickname (if any).
        self.avatar = avatar // Set the member's avatar (if any).
        self.roles = roles // Set the roles assigned to the member (if any).
        self.joined_at = joined_at // Set the joining timestamp.
        self.timeout = timeout // Set the timeout duration (if any).
    }
    
    public var id: MemberId // Unique identifier for the member.
    public var nickname: String? // Nickname of the member (optional).
    public var avatar: File? // Avatar associated with the member (optional).
    public var roles: [String]? // Roles assigned to the member (optional).
    public var joined_at: String // Timestamp of when the member joined.
    public var timeout: String? // Timeout duration for the member (optional).
    
    enum CodingKeys: String, CodingKey {
        case id = "_id" // Mapping the ID to the JSON key "_id".
        case nickname, avatar, roles, joined_at, timeout // Other properties mapped directly.
    }
    
    public func copyWithAvatar(newAvatar: File) -> Member {
        return Member(id: id, nickname: nickname, avatar: newAvatar, roles: roles, joined_at: joined_at, timeout: timeout)
    }
}
