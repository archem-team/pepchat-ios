//
//  Invite.swift
//  Revolt
//
//  Created by Angelo on 09/03/2024.
//

import Foundation

// MARK: - ServerInvite Structure

/// Represents an invite to a server.
public struct ServerInvite: Codable, Identifiable {
    public var id: String // Unique identifier for the server invite.
    public var server: String // Identifier for the server being invited to.
    public var creator: String // Identifier of the user who created the invite.
    public var channel: String // Identifier of the channel for the invite.
    
    public init(id: String, server: String, creator: String, channel: String) {
        self.id = id
        self.server = server
        self.creator = creator
        self.channel = channel
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "_id" // Mapping the ID to the JSON key "_id".
        case server, creator, channel // Other properties mapped directly.
    }
}

// MARK: - GroupInvite Structure

/// Represents an invite to a group.
public struct GroupInvite: Codable, Identifiable {
    public var id: String // Unique identifier for the group invite.
    public var creator: String // Identifier of the user who created the invite.
    public var channel: String // Identifier of the channel for the invite.
    
    public init(id: String, creator: String, channel: String) {
        self.id = id
        self.creator = creator
        self.channel = channel
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "_id" // Mapping the ID to the JSON key "_id".
        case creator, channel // Other properties mapped directly.
    }
}

// MARK: - Invite Enum

/// Enum representing either a server invite or a group invite.
public enum Invite: Identifiable {
    case server(ServerInvite) // Case for server invites.
    case group(GroupInvite) // Case for group invites.
    
    /// Unique identifier for the invite.
    public var id: String {
        switch self {
            case .server(let i):
                return i.id // Return the ID of the server invite.
            case .group(let i):
                return i.id // Return the ID of the group invite.
        }
    }
}

// MARK: - Invite Extensions for Encoding and Decoding

extension Invite: Codable {
    enum CodingKeys: String, CodingKey { case type } // Coding key for the invite type.
    enum Tag: String, Codable { case Server, Group } // Tags representing invite types.
    
    /// Decodes an `Invite` instance from a decoder.
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .type) {
            case .Server:
                self = .server(try singleValueContainer.decode(ServerInvite.self)) // Decode as a server invite.
            case .Group:
                self = .group(try singleValueContainer.decode(GroupInvite.self)) // Decode as a group invite.
        }
    }
    
    /// Encodes the `Invite` instance to the given encoder.
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: any Encoder) throws {
        var tagContainer = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
            case .server(let s):
                try tagContainer.encode(Tag.Server, forKey: .type) // Encode as a server invite.
                try s.encode(to: encoder) // Encode the server invite.
            case .group(let g):
                try tagContainer.encode(Tag.Group, forKey: .type) // Encode as a group invite.
                try g.encode(to: encoder) // Encode the group invite.
        }
    }
}
