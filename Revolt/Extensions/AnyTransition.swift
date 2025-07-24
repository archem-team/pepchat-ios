//
//  AnyTransition.swift
//  Revolt
//
//  Created by Angelo on 2024-07-14.
//

import SwiftUI

// Extension to define custom transitions using SwiftUI's AnyTransition.
extension AnyTransition {
    
    // Custom transition for sliding in from the right and sliding out to the left.
    static var slideNext: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: .trailing), // Slide in from the right.
            removal: .move(edge: .leading)     // Slide out to the left.
        )
    }
    
    // Custom transition for sliding in and out from the top.
    static var slideTop: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: .top),      // Slide in from the top.
            removal: .move(edge: .top)         // Slide out to the top.
        )
    }
}
