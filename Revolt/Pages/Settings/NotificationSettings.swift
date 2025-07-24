//
//  NotificationSettings.swift
//  Revolt
//
//  Created by Angelo on 2024-02-10.
//

import SwiftUI
import Sentry // Import Sentry for error tracking.

/// View for managing notification settings in the application.
struct NotificationSettings: View {
    @EnvironmentObject var viewState: ViewState // Access to shared application state.
    @State var pushNotificationsEnabled = false // State variable to track push notifications status.
    @State var notificationsWhileAppRunningEnabled = false // State variable for notifications while app is running.

    var body: some View {
        List {
            Section("Push Notifications") {
                // Checkbox for enabling/disabling push notifications.
                VStack {
                    CheckboxListItem(
                        title: "Enable push notifications",
                        isOn: $pushNotificationsEnabled,
                        onChange: { enabled in
                            if enabled {
                                Task {
                                    await viewState.promptForNotifications() // Prompt for notification permissions when enabling.
                                }
                            } else {
                                Task {
                                    do {
                                        // Revoke the notification token when disabling push notifications.
                                        let _ = try await viewState.http.revokeNotificationToken().get()
                                    } catch {
                                        // Capture error if revoking fails using Sentry.
                                        SentrySDK.capture(error: error as! RevoltError)
                                        viewState.userSettingsStore.store.notifications.rejectedRemoteNotifications = false
                                        return
                                    }
                                    // Update settings upon successful revocation.
                                    viewState.userSettingsStore.store.notifications.rejectedRemoteNotifications = true
                                    viewState.userSettingsStore.store.notifications.wantsNotificationsWhileAppRunning = false
                                    notificationsWhileAppRunningEnabled = false // Disable notifications while app running.
                                }
                            }
                        })
                }
                // Checkbox for notifications while the app is running.
                VStack {
                    CheckboxListItem(
                        title: "Enable notifications while app running",
                        isOn: $notificationsWhileAppRunningEnabled,
                        onChange: { enabled in
                            viewState.userSettingsStore.store.notifications.wantsNotificationsWhileAppRunning = enabled // Update state based on user preference.
                        })
                    // Disable the checkbox if push notifications are not enabled.
                    .disabled(true)
                }
            }
            .listRowBackground(viewState.theme.background2) // Set row background color.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Expand the list to fill the available space.
        .toolbarBackground(viewState.theme.topBar, for: .automatic) // Set the toolbar background color.
        .scrollContentBackground(.hidden) // Hide the scroll view background.
        .background(viewState.theme.background) // Set the background color for the view.
        .navigationTitle("Notifications") // Set the navigation title.
        .onAppear {
            // Load the initial state for notification settings when the view appears.
            pushNotificationsEnabled = !viewState.userSettingsStore.store.notifications.rejectedRemoteNotifications
            notificationsWhileAppRunningEnabled = viewState.userSettingsStore.store.notifications.wantsNotificationsWhileAppRunning
        }
    }
}

// Preview for development.
#Preview {
    NotificationSettings()
        .environmentObject(ViewState.preview()) // Provide a preview environment with dummy data.
}
