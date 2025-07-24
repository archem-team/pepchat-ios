//
//  AppearanceSettings.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI

/// A view that allows users to pick a theme color for various UI components.
struct ThemeColorPicker: View {
    @Environment(\.self) var environment // Access environment variables.
    @EnvironmentObject var viewState: ViewState // Access the application's view state.

    var title: String // Title for the color picker.
    @Binding var color: ThemeColor // Binding to the selected color.

    var body: some View {
        ColorPicker(selection: Binding {
            color.color // Bind to the current color value.
        } set: { new in
            withAnimation {
                color.set(with: new.resolve(in: environment)) // Update color with animation.
            }
        }, label: {
            Text(title) // Display the title.
        })
    }
}

/// Main view for appearance settings, allowing users to customize themes and colors.
struct AppearanceSettings: View {
    @Environment(\.self) var environment // Access environment variables.
    @Environment(\.colorScheme) var colorScheme // Access the system color scheme.
    @EnvironmentObject var viewState: ViewState // Access the application's view state.

    var body: some View {
        VStack {
            // Theme selection buttons for Light, Dark, and Auto modes.
            themeSelectionButtons

            // List of customizable theme colors.
            List {
                themeSection
                messageSection
            }
            .scrollContentBackground(.hidden) // Hide scroll background.
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Appearance") // Toolbar title.
            }
        }
        .background(viewState.theme.background) // Set background color.
        .toolbarBackground(viewState.theme.topBar, for: .automatic) // Set toolbar background.
        .animation(.easeInOut, value: viewState.theme) // Animate theme changes.
    }

    /// View for theme selection buttons (Light, Dark, Auto).
    private var themeSelectionButtons: some View {
        HStack {
            Spacer()

            Button {
                withAnimation {
                    viewState.theme = .light // Set to Light theme.
                }
            } label: {
                Text("Light")
                    .foregroundStyle(viewState.theme.accent.color)
            }

            Spacer()

            Button {
                withAnimation {
                    viewState.theme = .dark // Set to Dark theme.
                }
            } label: {
                Text("Dark")
                    .foregroundStyle(viewState.theme.accent.color)
            }

            Spacer()

            Button {
                withAnimation {
                    let _ = viewState.applySystemScheme(theme: colorScheme, followSystem: true) // Set to Auto theme.
                }
            } label: {
                Text("Auto")
                    .foregroundStyle(viewState.theme.accent.color)
            }

            Spacer()
        }
        .padding([.horizontal, .top], 16) // Add padding to the button container.
    }

    /// Section containing theme color pickers.
    private var themeSection: some View {
        Section("Theme") {
            ThemeColorPicker(title: "Accent", color: $viewState.theme.accent)
            ThemeColorPicker(title: "Background", color: $viewState.theme.background)
            ThemeColorPicker(title: "Primary Background", color: $viewState.theme.background2)
            ThemeColorPicker(title: "Secondary Background", color: $viewState.theme.background3)
            ThemeColorPicker(title: "Tertiary Background", color: $viewState.theme.background4)
            ThemeColorPicker(title: "Foreground", color: $viewState.theme.foreground)
            ThemeColorPicker(title: "Secondary Foreground", color: $viewState.theme.foreground2)
            ThemeColorPicker(title: "Tertiary Foreground", color: $viewState.theme.foreground3)
            ThemeColorPicker(title: "Message Box", color: $viewState.theme.messageBox)
            ThemeColorPicker(title: "Navigation Bar", color: $viewState.theme.topBar)
            ThemeColorPicker(title: "Error", color: $viewState.theme.error)
            ThemeColorPicker(title: "Mention", color: $viewState.theme.mention)
        }
        .listRowBackground(viewState.theme.background2) // Set the row background color.
        .animation(.easeInOut, value: viewState.theme) // Animate theme changes in this section.
    }

    /// Section containing additional message settings.
    private var messageSection: some View {
        Section("Messages") {
            CheckboxListItem(title: "Compact Mode", isOn: Binding(get: { false }, set: { _ in }))
                .listRowBackground(viewState.theme.background2) // Set the row background color.
                .animation(.easeInOut, value: viewState.theme) // Animate changes in this section.
        }
    }
}

/// Preview provider for AppearanceSettings, showing both Light and Dark themes.
struct AppearanceSettings_Preview: PreviewProvider {
    static var previews: some View {
        let viewState = ViewState.preview()
        
        AppearanceSettings()
            .applyPreviewModifiers(withState: viewState.applySystemScheme(theme: .light)) // Preview Light theme.
        
        AppearanceSettings()
            .applyPreviewModifiers(withState: viewState.applySystemScheme(theme: .dark)) // Preview Dark theme.
    }
}
