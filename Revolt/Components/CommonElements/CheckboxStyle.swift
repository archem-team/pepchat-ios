//
//  CheckboxStyle.swift
//  Revolt
//
//  Created by Angelo on 19/06/2024.
//

import SwiftUI

/// A custom toggle style for a checkbox in the Revolt app.
struct CheckboxStyle: ToggleStyle {
    @EnvironmentObject var viewState: ViewState  // Access the global application state

    /// Creates the body of the toggle style.
    /// - Parameter configuration: The configuration object that holds the state and label for the toggle.
    /// - Returns: A view representing the toggle style.
    func makeBody(configuration: Self.Configuration) -> some View {
        return HStack {
            // Label of the toggle
            configuration.label
            
            Spacer()  // Spacer to push the checkmark to the right
            
            // Checkmark icon, displayed when the toggle is in the "on" state
            if configuration.isOn {
                Image(systemName: "checkmark")  // System checkmark icon
                    .resizable()  // Make the icon resizable
                    .frame(width: 16, height: 16)  // Set the size of the icon
                    .foregroundColor(viewState.theme.accent.color)  // Color from the current theme
            }
        }
        .onTapGesture {
            configuration.isOn.toggle()  // Toggle the state when tapped
        }
    }
}
