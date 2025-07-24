//
//  Image.swift
//  Revolt
//
//  Created by Angelo Manca on 2024-07-18.
//

import Foundation
import SwiftUI
import Types

// Extension to add functionality to the Image type.
extension Image {
    
    /// Inverts the image depending on the lightness of the color.
    /// This is specifically designed for use in the session's settings menu.
    /// - Parameters:
    ///   - color: The theme color used to determine the lightness.
    ///   - isDefaultImage: A flag indicating if the image is a default image.
    ///   - defaultIsLight: A flag indicating if the default image is light (default is true).
    /// - Returns: A view that may be color inverted based on the parameters.
    @ViewBuilder
    public func maybeColorInvert(color: ThemeColor, isDefaultImage: Bool, defaultIsLight: Bool = true) -> some View {
        if isDefaultImage {
            self // If it's a default image, return it without modification.
        } else {
            let isLight = Theme.isLightOrDark(color) // Determine if the provided color is light or dark.
            
            // Invert color based on the lightness of the color and whether the default is light or dark.
            if isLight && defaultIsLight {
                self.colorInvert() // Invert the color for a light image with a light default.
            } else if !isLight && !defaultIsLight {
                self.colorInvert() // Invert the color for a dark image with a dark default.
            } else {
                self // Return the original image if none of the conditions match.
            }
        }
    }
}
