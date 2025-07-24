//
//  MessageBadge.swift
//  Revolt
//
//  Created by Angelo on 18/11/2023.
//

import Foundation
import SwiftUI
import Types

/// A SwiftUI view that displays a small badge with text and a customizable background color.
///
/// This component can be used to display labels such as "Masquerade", "Bot", or any other status in a badge format.
struct MessageBadge: View {
    // MARK: - Properties
    
    /// The text that appears inside the badge.
    var text: String
    
    /// The background color of the badge.
    var color: Color

    // MARK: - Body
    
    /// The content and layout of the `MessageBadge` view.
    ///
    /// This view consists of a `Text` element that displays the provided `text` with some padding and is
    /// enclosed in a rounded rectangle of the provided `color`.
    ///
    /// - Returns: A `View` representing a styled badge with a text and background color.
    var body: some View {
        

        PeptideText(textVerbatim: text,
                    font: .peptideFootnote,
                    textColor: .textDefaultGray01)
        .padding(.horizontal, .padding4)
        .background(color, in: RoundedRectangle(cornerRadius: .radiusXSmall))
        .padding(.horizontal, .padding4)

        
    
    }
}

#Preview {
    /// A preview of the `MessageBadge` showing a teal badge labeled "Masquerade".
    MessageBadge(text: "Masquerade", color: .red)
}

#Preview {
    /// A preview of the `MessageBadge` showing a purple badge labeled "Bot".
    MessageBadge(text: "Bot", color: .red)
}
