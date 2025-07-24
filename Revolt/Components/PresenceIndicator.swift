//
//  PresenceIndicator.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI
import Types

/// A view that represents the presence status of a user.
///
/// The `PresenceIndicator` displays a circular indicator with different colors
/// representing the user's current presence status (e.g., online, busy, idle).
/// The color and size of the indicator can be customized.
struct PresenceIndicator: View {
    /// The presence status of the user.
    var presence: Presence?
    
    /// The optional width of the indicator.
    var width: CGFloat? = nil
    
    /// The optional height of the indicator.
    var height: CGFloat? = nil
    
    /// The body of the `PresenceIndicator`.
    ///
    /// This view constructs a circular shape filled with a color that corresponds
    /// to the user's presence status. If the presence is nil, it defaults to gray.
    var body: some View {
        let colour = colours[presence]!
        
        Circle()
            .fill(colour)
            .frame(width: width ?? .size12, height: height ?? .size12)
//            .frame(width: .size12, height: .size12)
            .overlay(
                Circle()
                    .stroke(Color.borderGray11, lineWidth: .size2)
            )
        
    }
}

/// A dictionary mapping presence statuses to their corresponding colors.
let colours: [Presence?: Color] = [
    .Online: Color(.bgGreen07),
    .Busy: Color(.bgRed07),
    .Idle: Color(.bgOrane07),
    .Focus: Color(.bgBlue07),
    .Invisible: Color(.bgGray07),
    nil: Color(.bgGray07) // Default color for unknown presence
]


#Preview {
    
    VStack(spacing: 12){
        
        PresenceIndicator(presence: .Online, width: 12, height: 12)
        PresenceIndicator(presence: .Busy, width: 12, height: 12)
        PresenceIndicator(presence: .Idle, width: 12, height: 12)
        PresenceIndicator(presence: .Focus, width: 12, height: 12)
        PresenceIndicator(presence: .Invisible, width: 12, height: 12)
        PresenceIndicator(presence: nil, width: 12, height: 12)
        
        
    }
    
}
