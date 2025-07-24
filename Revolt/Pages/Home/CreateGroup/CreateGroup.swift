//
//  CreateGroup.swift
//  Revolt
//
//  Created by Angelo on 09/03/2024.
//

import Foundation
import SwiftUI
import Types

/// The `CreateGroup` view allows users to create a new group by selecting friends from their friend list.
struct CreateGroup: View {
    @EnvironmentObject var viewState: ViewState  // Access to global app state (e.g., theme, users, channels).
    
    @State var searchText: String = ""  // State to manage search input for friends.
    @State var selectedUsers: Set<User> = Set()  // Set of users selected to be part of the group.
    @State var error: String? = nil  // Optional error message to be displayed if group creation fails.
    
    /// Filters the current users to only show those who are friends.
    /// - Returns: A list of users who are marked as friends in the app's state.
    func getFriends() -> [User] {
        var friends: [User] = []
        
        // Iterate over the users in the app's state and add friends to the list.
        for user in viewState.users.values {
            switch user.relationship ?? .None {
                case .Friend:
                    friends.append(user)
                default:
                    ()  // Skip users who are not friends.
            }
        }
        
        return friends
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Display error message if group creation fails.
            if let error = error {
                Text(verbatim: error)
                    .foregroundStyle(viewState.theme.accent)
                    .bold()
            }

            // Search bar to filter friends.
            TextField("Search for friends", text: $searchText)
                .padding(8)
                .background(viewState.theme.background2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding([.horizontal, .top], 16)
            
            // List of friends filtered by the search input, with the ability to select multiple users.
            List(selection: $selectedUsers) {
                ForEach(getFriends().filter { user in
                    // Filter users based on the search text matching the username or display name.
                    searchText.isEmpty || (user.username.contains(searchText) || (user.display_name?.contains(searchText) ?? false))
                }) { user in
                    let binding = Binding(
                        // Determine if the user is selected or not.
                        get: { selectedUsers.contains(user) },
                        // Add or remove the user from the selection set based on the toggle.
                        set: { v in
                            if v {
                                if selectedUsers.count < 99 {  // Ensure the group size is less than 100 members.
                                    selectedUsers.insert(user)
                                }
                            } else {
                                selectedUsers.remove(user)
                            }
                        }
                    )

                    // Each user is displayed as a toggle with their avatar and name.
                    Toggle(isOn: binding) {
                        HStack(spacing: 12) {
                            Avatar(user: user)  // Show user's avatar.
                                .frame(width: 16, height: 16)
                                .frame(width: 24, height: 24)
                            
                            Text(user.display_name ?? user.username)  // Show the user's display name or username.
                        }
                        .padding(.leading, 12)
                    }
                    .toggleStyle(CheckboxStyle())  // Use a checkbox for selection.
                    .listRowBackground(viewState.theme.background2)  // Background color for list rows.
                }
            }
            .scrollContentBackground(.hidden)  // Hide the default background of the list.
            #if os(iOS)
            .environment(\.editMode, .constant(EditMode.active))  // Enable multi-selection on iOS.
            #endif
        }
        .background(viewState.theme.background.color)  // Set background color from theme.
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic)  // Toolbar background matching the theme.
        
        // Toolbar with the title and a counter showing how many members are selected.
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(alignment: .center) {
                    Text("New Group")  // Toolbar title.
                    Text("\(selectedUsers.count + 1) of 100 members")  // Count of selected users.
                        .font(.caption)
                }
            }
        }
        // Additional toolbar with the 'Create' button for group creation.
        .toolbar {
            #if os(iOS)
            let placement = ToolbarItemPlacement.topBarTrailing  // Placement for iOS.
            #elseif os(macOS)
            let placement = ToolbarItemPlacement.automatic  // Placement for macOS.
            #endif
            ToolbarItem(placement: placement) {
                Button {
                    // Attempt to create a new group when the button is pressed.
                    Task {
                        let res = await viewState.http.createGroup(name: "New Group", users: selectedUsers.map(\.id))
                        
                        switch res {
                            case .success(let c):
                                // On success, update the app's state with the new group and navigate to it.
                                //viewState.channels[c.id] = c
                                //viewState.channelMessages[c.id] = []
                                //viewState.currentChannel = .channel(c.id)
                                viewState.path = .init()
                            case .failure(_):
                                // If the group creation fails, show an error message.
                                error = "Failed to create group."
                        }
                    }
                } label: {
                    Text("Create")  // Button label.
                }
            }
        }
    }
}

#Preview {
    // Preview for the `CreateGroup` view with preview state and modifiers.
    NavigationStack {
        CreateGroup()
            .applyPreviewModifiers(withState: ViewState.preview())
            .preferredColorScheme(.dark)
    }
}
