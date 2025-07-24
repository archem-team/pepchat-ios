//
//  ServerBadges.swift
//  Revolt
//
//  Created by Angelo on 12/09/2024.
//

import Foundation
import SwiftUI
import Types

/// A SwiftUI view that displays badges for a server based on its flags.
/// The badges indicate whether the server is official or verified.
struct ServerBadges: View {
    /// The flags associated with the server, determining the badges to display.
    var value: ServerFlags?
    
    /// The body of the view, defining its layout and behavior.
    var body: some View {
        // Check if the server has the official flag and display the corresponding badge.
        if value?.contains(.offical) == true {
            ZStack(alignment: .center) {
                // Display the official badge icon.
                Image(systemName: "seal.fill")
                    .resizable()
                    .frame(width: 12, height: 12) // Set the size of the icon.
                    .foregroundStyle(.white) // Set the icon color to white.
                
                // Display a monochrome image over the badge.
                Image("monochrome")
                    .resizable()
                    .frame(width: 10, height: 10) // Set the size of the monochrome image.
                    .colorInvert() // Invert the colors of the monochrome image.
            }
        // Check if the server has the verified flag and display the corresponding badge.
        } else if value?.contains(.verified) == true {
            // Display the verified badge icon.
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .foregroundStyle(.black, .white) // Set the icon colors.
                .frame(width: 12, height: 12) // Set the size of the icon.
        }
    }
}
