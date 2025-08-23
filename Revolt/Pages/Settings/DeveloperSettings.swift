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
    @State private var showingUnreadCounts = false
    @State private var unreadCountsText = ""

    var body: some View {
        List {
            // Section for notifications
            Section("Notifications") {
                Button {
                    Task {
                        await viewState.promptForNotifications() // Asynchronously prompts the user for notifications.
                    }
                } label: {
                    Text("Force remote notification upload") // Button label.
                }
                .listRowBackground(viewState.theme.background2) // Background color for the list row.
            }
            
            // Section for badge debugging
            Section("Badge Debugging") {
                Button {
                    viewState.debugBadgeCount() // Print detailed badge analysis to console
                } label: {
                    Text("Debug Badge Count") // Button label.
                }
                .listRowBackground(viewState.theme.background2)
                
                Button {
                    viewState.cleanupStaleUnreads() // Remove stale unread entries
                } label: {
                    Text("Cleanup Stale Unreads") // Button label.
                }
                .listRowBackground(viewState.theme.background2)
                
                Button {
                    viewState.forceMarkAllAsRead() // Force mark all as read and clear badge
                } label: {
                    Text("Force Mark All Read") // Button label.
                }
                .listRowBackground(viewState.theme.background2)
                
                Button {
                    viewState.refreshAppBadge() // Manually refresh badge count
                } label: {
                    Text("Refresh Badge Count") // Button label.
                }
                .listRowBackground(viewState.theme.background2)
                
                Button {
                    viewState.showUnreadCounts() // Also log to console
                    unreadCountsText = viewState.getUnreadCountsString()
                    showingUnreadCounts = true
                } label: {
                    Text("Show Unread Counts") // Button label.
                }
                .listRowBackground(viewState.theme.background2)
            }
        }
        .background(viewState.theme.background) // Background color for the entire list.
        .scrollContentBackground(.hidden) // Hides the background of the scroll view.
        .toolbarBackground(viewState.theme.topBar, for: .automatic) // Sets the toolbar background color.
        .navigationTitle("Developer") // Title for the navigation bar.
        .alert("Unread Message Counts", isPresented: $showingUnreadCounts) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(unreadCountsText)
        }
    }
}

// Preview for development.
#Preview {
    // Provide a preview of the DeveloperSettings view.
    DeveloperSettings()
        .environmentObject(ViewState.preview()) // Provide a preview environment with dummy data.
}
