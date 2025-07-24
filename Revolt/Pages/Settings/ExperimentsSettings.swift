//
//  ExperimentsSettings.swift
//  Revolt
//
//  Created by Angelo on 2024-02-10.
//

import SwiftUI

/// View for displaying and managing experimental settings in the application.
struct ExperimentsSettings: View {
    @EnvironmentObject var viewState: ViewState // Shared application state containing user settings.
    
    var body: some View {
        List {
            // Checkbox item for enabling or disabling custom markdown feature.
            CheckboxListItem(
                title: "Enable Custom Markdown",
                isOn: $viewState.userSettingsStore.store.experiments.customMarkdown
            )
            .listRowBackground(viewState.theme.background2) // Background color for the list row.
        }
        .background(viewState.theme.background) // Background color for the entire list.
        .scrollContentBackground(.hidden) // Hides the background of the scroll view.
        .toolbarBackground(viewState.theme.topBar, for: .automatic) // Sets the toolbar background color.
        .navigationTitle("Experiments") // Title for the navigation bar.
    }
}

// Preview for development.
#Preview {
    // Provide a preview of the ExperimentsSettings view.
    ExperimentsSettings()
        .environmentObject(ViewState.preview()) // Provide a preview environment.
}
