//
//  Member.swift
//  Revolt
//
//  Created by Angelo on 2024-07-18.
//

import Foundation
import Types
import SwiftUI

// Extension to add functionality to the Member type.
extension Member {
    
    /// Returns the display color for a member based on their roles and the server's theme.
    /// - Parameters:
    ///   - theme: The current theme to use for parsing colors.
    ///   - server: The server containing role information.
    /// - Returns: An optional AnyShapeStyle representing the member's display color.
    public func displayColour(theme: Theme, server: Server) -> AnyShapeStyle? {
        roles? // Safely unwraps the roles property of the member.
            .compactMap { server.roles?[$0] } // Fetches the roles from the server, filtering out nil values.
            .sorted(by: { $0.rank > $1.rank }) // Sorts the roles by rank in descending order.
            .compactMap(\.colour) // Extracts the color property of each role, filtering out nil values.
            .last // Gets the last color in the sorted list, which corresponds to the lowest rank.
            .map {
                return parseCSSColor(currentTheme: theme, input: $0) // Parses the CSS color using the current theme.
            }
    }
}
