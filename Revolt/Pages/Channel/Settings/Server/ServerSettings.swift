//
//  ServerSettings.swift
//  Revolt
//
//  Created by Angelo on 08/11/2023.
//

import Foundation
import SwiftUI
import Types

/// A view that displays the settings for a specific server in the application.
struct ServerSettings: View {
    /// The environment object that holds the current state of the application.
    @EnvironmentObject var viewState: ViewState
    
    /// A binding to the selected server's settings.
    @Binding var server: Server
    
    var body: some View {
        List {
            // Section for general server settings.
            Section("Settings") {
                // Navigation link to the server overview settings.
                NavigationLink {
                    ServerOverviewSettings(server: $server)
                } label: {
                    Image(systemName: "info.circle.fill")
                    Text("Overview")
                }
                
                // Navigation link for server categories (currently a placeholder).
                NavigationLink(destination: Text("Todo")) {
                    Image(systemName: "list.bullet")
                    Text("Categories")
                }

                // Navigation link to manage server roles.
                NavigationLink {
                    ServerRolesSettings(server: $server)
                } label: {
                    Image(systemName: "flag.fill")
                    Text("Roles")
                }
            }
            .listRowBackground(viewState.theme.background2)
            
            // Section for server customizations.
            Section("Customisation") {
                // Navigation link to manage server emojis.
                NavigationLink {
                    ServerEmojiSettings(server: $server)
                } label: {
                    Image(systemName: "face.smiling")
                    Text("Emojis")
                }
            }
            .listRowBackground(viewState.theme.background2)
            
            // Section for user management related settings.
            Section("User Management") {
                // Navigation link to manage server members (currently a placeholder).
                NavigationLink(destination: Text("Todo")) {
                    Image(systemName: "person.2.fill")
                    Text("Members")
                }
                
                // Navigation link to manage server invites (currently a placeholder).
                NavigationLink(destination: Text("Todo")) {
                    Image(systemName: "envelope.fill")
                    Text("Invites")
                }
                
                // Navigation link to manage banned users (currently a placeholder).
                NavigationLink(destination: Text("Todo")) {
                    Image(systemName: "person.fill.xmark")
                    Text("Bans")
                }
            }
            .listRowBackground(viewState.theme.background2)
            
            // Button to delete the server.
            Button {
                // Action to delete the server will be implemented here.
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Delete server")
                }
                .foregroundStyle(.red) // Makes the text red to signify a destructive action.
            }
            .listRowBackground(viewState.theme.background2)
            
        }
        // Set the background color of the list.
        .scrollContentBackground(.hidden)
        .background(viewState.theme.background) // Use the current theme background color.
        
        // Toolbar configuration.
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    // Display the server icon and name in the toolbar.
                    ServerIcon(server: server, height: 24, width: 24, clipTo: Circle())
                    Text(verbatim: server.name)
                }
            }
        }
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic) // Use the theme color for the toolbar.
    }
}

// Preview provider for SwiftUI preview.
#Preview {
    let viewState = ViewState.preview() // Create a preview instance of the ViewState.

    return NavigationStack {
        ServerSettings(server: .constant(viewState.servers["0"]!)) // Pass a sample server for the preview.
            .applyPreviewModifiers(withState: viewState) // Apply modifiers for the preview.
    }
}
