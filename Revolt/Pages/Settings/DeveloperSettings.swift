//
//  DeveloperSettings.swift
//  Revolt
//
//  Created by Angelo Manca on 2024-07-12.
//

import SwiftUI

/// View for managing developer settings in the application.
struct DeveloperSettings: View {
    @EnvironmentObject var viewState: ViewState

    var body: some View {
        List {
            // Button to force the upload of remote notifications.
            Button {
                Task {
                    await viewState.promptForNotifications() // Asynchronously prompts the user for notifications.
                }
            } label: {
                Text("Force remote notification upload") // Button label.
            }
            .listRowBackground(viewState.theme.background2) // Background color for the list row.
        }
        .background(viewState.theme.background) // Background color for the entire list.
        .scrollContentBackground(.hidden) // Hides the background of the scroll view.
        .toolbarBackground(viewState.theme.topBar, for: .automatic) // Sets the toolbar background color.
        .navigationTitle("Developer") // Title for the navigation bar.
    }
}

// Preview for development.
#Preview {
    // Provide a preview of the DeveloperSettings view.
    DeveloperSettings()
        .environmentObject(ViewState.preview()) // Provide a preview environment with dummy data.
}
