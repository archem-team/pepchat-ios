//
//  LanguageSettings.swift
//  Revolt
//
//  Created by Angelo on 29/11/2023.
//

import Foundation
import SwiftUI

struct LanguageSettings: View {
    @Environment(\.locale) var systemLocale: Locale
    @EnvironmentObject var viewState: ViewState

    // Current locale either from the ViewState or the system
    var currentLocale: Locale { viewState.currentLocale ?? systemLocale }
    
    var body: some View {
        List {
            autoButton // Auto language selection button
            
            // Display all available languages
            ForEach(Locale.availableIdentifiers.sorted(), id: \.self) { identifier in
                let locale = Locale(identifier: identifier)
                languageButton(for: locale, identifier: identifier) // Button for each locale
            }
        }
        .scrollContentBackground(.hidden)
        .background(viewState.theme.background) // Background color from theme
        .navigationTitle("Language") // Navigation title
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic) // Toolbar background
    }
    
    // Button for auto language selection
    private var autoButton: some View {
        Button {
            viewState.currentLocale = nil // Reset to auto selection
        } label: {
            Text("Auto")
                .foregroundStyle(viewState.currentLocale == nil ? viewState.theme.accent : viewState.theme.foreground)
        }
        .frame(maxWidth: .infinity, maxHeight: 30)
        .padding(8)
        .listRowBackground(viewState.theme.background2) // Row background color
    }

    // Button for a specific language
    private func languageButton(for locale: Locale, identifier: String) -> some View {
        Button {
            viewState.currentLocale = locale // Set selected locale
        } label: {
            Text(currentLocale.localizedString(forIdentifier: identifier) ?? "Unknown")
                .foregroundStyle(locale == currentLocale ? viewState.theme.accent : viewState.theme.foreground)
        }
        .frame(maxWidth: .infinity, maxHeight: 30)
        .padding(8)
        .listRowBackground(viewState.theme.background2) // Row background color
    }
}

#Preview {
    return NavigationStack {
        LanguageSettings()
    }
    .applyPreviewModifiers(withState: ViewState.preview()) // Preview modifiers
}
