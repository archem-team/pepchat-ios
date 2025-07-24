//
//  About.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI

/// View displaying information about the app.
struct About: View {
    @EnvironmentObject var viewState: ViewState // Access the application's view state.

    var body: some View {
        VStack {
            // App logo or image at the top.
            appLogo
            
            // App title and version number.
            appInfo
            
            Spacer() // Adds space before the footer message.

            // Footer message.
            footerMessage
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("About") // Toolbar title.
            }
        }
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic) // Set toolbar background.
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Allow flexible sizing.
        .background(viewState.theme.background.color) // Set view background color.
    }
    
    /// View displaying the app logo.
    private var appLogo: some View {
        Image("wide") // Display the app's logo.
            .resizable() // Make the image resizable.
            .scaledToFit() // Maintain aspect ratio.
            .frame(height: 200) // Set a fixed height for the logo.
            .padding() // Add some padding around the logo.
    }

    /// View displaying the app name and version number.
    private var appInfo: some View {
        VStack {
            Text("Revolt iOS") // App name.
                .font(.title) // Set title font.
                .padding(.bottom, 5) // Add spacing below the title.
            
            Text(Bundle.main.releaseVersionNumber) // App version number.
                .font(.caption) // Set caption font.
        }
    }

    /// View displaying the footer message.
    private var footerMessage: some View {
        Text("Brought to you with ❤️ by the Revolt team.") // Footer message.
            .font(.footnote) // Set footnote font.
            .foregroundStyle(.gray) // Set text color to gray.
            .padding(.top, 30) // Add spacing above the footer message.
    }
}

/// Preview provider for the About view.
struct About_Preview: PreviewProvider {
    static var previews: some View {
        About()
            .environmentObject(ViewState.preview()) // Provide a preview environment object.
    }
}
