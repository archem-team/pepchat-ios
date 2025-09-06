//
//  Emoji.swift
//  Revolt
//
//  Created by Angelo on 14/10/2023.
//

import Foundation

// MARK: - EmojiParentServer Structure

/// Represents a parent server associated with an emoji.
public struct EmojiParentServer: Codable, Equatable {
    /// Initializes a new instance of `EmojiParentServer`.
    /// - Parameter id: Unique identifier for the emoji's parent server.
    public init(id: String) {
        self.id = id
    }
    
    public var id: String // Unique identifier for the emoji's parent server.
}

// MARK: - EmojiParentDetached Structure

/// Represents a detached parent for an emoji.
public struct EmojiParentDetached: Codable, Equatable {
    // Currently, this structure does not have any properties defined.
    
    public init() {
        // Empty initializer for empty struct
    }
}

// MARK: - EmojiParent Enum

/// Enum representing the parent type of an emoji.
public enum EmojiParent: Equatable {
    case server(EmojiParentServer) // Case for emojis associated with a server.
    case detached(EmojiParentDetached) // Case for detached emojis.
    
    /// Optional identifier for the parent.
    public var id: String? {
        switch self {
            case .server(let p):
                return p.id
            case .detached:
                return nil
        }
    }
}

// MARK: - EmojiParent Extensions for Encoding and Decoding

extension EmojiParent: Codable {
    enum CodingKeys: String, CodingKey { case type } // Coding keys for the `EmojiParent` enum.
    enum Tag: String, Codable { case Server, Detached } // Tags representing parent types.
    
    /// Decodes an `EmojiParent` instance from a decoder.
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .type) {
            case .Server:
                self = .server(try singleValueContainer.decode(EmojiParentServer.self))
            case .Detached:
                self = .detached(try singleValueContainer.decode(EmojiParentDetached.self))
        }
    }
    
    /// Encodes the `EmojiParent` instance to the given encoder.
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: any Encoder) throws {
        var tagContainer = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
            case .server(let e):
                try tagContainer.encode(Tag.Server, forKey: .type)
                try e.encode(to: encoder)
            case .detached(let e):
                try tagContainer.encode(Tag.Detached, forKey: .type)
                try e.encode(to: encoder)
        }
    }
}

// MARK: - Emoji Structure

/// Represents an emoji in the application.
public struct Emoji: Codable, Equatable, Identifiable {
    /// Initializes a new instance of `Emoji`.
    /// - Parameters:
    ///   - id: Unique identifier for the emoji.
    ///   - parent: The parent of the emoji, which can be either a server or detached.
    ///   - creator_id: Identifier of the user who created the emoji.
    ///   - name: Name of the emoji.
    ///   - animated: Optional flag indicating if the emoji is animated.
    ///   - nsfw: Optional flag indicating if the emoji is NSFW (Not Safe For Work).
    public init(id: String, parent: EmojiParent, creator_id: String, name: String, animated: Bool? = nil, nsfw: Bool? = nil) {
        self.id = id
        self.parent = parent
        self.creator_id = creator_id
        self.name = name
        self.animated = animated
        self.nsfw = nsfw
    }
    
    public var id: String // Unique identifier for the emoji.
    public var parent: EmojiParent // The parent of the emoji (server or detached).
    public var creator_id: String // Identifier of the user who created the emoji.
    public var name: String // Name of the emoji.
    public var animated: Bool? // Indicates if the emoji is animated.
    public var nsfw: Bool? // Indicates if the emoji is NSFW.
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case parent, creator_id, name, animated, nsfw
    }
}
