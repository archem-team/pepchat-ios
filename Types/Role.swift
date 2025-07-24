//
//  Role.swift
//  Types
//
//  Created by Angelo on 19/05/2024.
//

import Foundation

/// A structure representing a role in the system, including its name, permissions, color, visibility, and rank.
public struct Role: Codable, Equatable {
    /// The name of the role.
    public var name: String
    
    /// The permissions associated with the role, represented as an `Overwrite`.
    public var permissions: Overwrite
    
    /// The color of the role in hexadecimal format (optional).
    public var colour: String?
    
    /// A boolean value indicating whether the role should be displayed separately in the user list (optional).
    public var hoist: Bool?
    
    /// The rank of the role, used to determine its hierarchy in relation to other roles.
    public var rank: Int
    
    /// Creates a new instance of `Role`.
    /// - Parameters:
    ///   - name: The name of the role.
    ///   - permissions: The permissions associated with the role.
    ///   - colour: The color of the role in hexadecimal format (optional).
    ///   - hoist: A boolean indicating if the role should be displayed separately (optional).
    ///   - rank: The rank of the role, determining its hierarchy.
    public init(name: String, permissions: Overwrite, colour: String? = nil, hoist: Bool? = nil, rank: Int) {
        self.name = name
        self.permissions = permissions
        self.colour = colour
        self.hoist = hoist
        self.rank = rank
    }
}
