//
//  MessageReactionsSheet.swift
//  Revolt
//
//  Created by Angelo on 11/09/2024.
//

import Foundation
import SwiftUI
import Types

/// A SwiftUI view that displays a sheet for viewing and selecting message reactions.
///
/// This view allows users to see all reactions to a specific message, select a reaction to view the users who reacted with it,
/// and open a user sheet for each user who reacted.
///
/// - Parameters:
///   - viewModel: An instance of `MessageContentsViewModel` that holds the message data and related information.
struct MessageReactionsSheet: View {
    @EnvironmentObject var viewState: ViewState
    
    @ObservedObject var viewModel: MessageContentsViewModel
    @State var selection: String
    
    /// Initializes a new instance of `MessageReactionsSheet`.
    ///
    /// - Parameter viewModel: The `MessageContentsViewModel` that contains the message and its reactions.
    init(viewModel: MessageContentsViewModel) {
        self.viewModel = viewModel
        selection = viewModel.message.reactions!.keys.first!
    }
    
    /// The body of the `MessageReactionsSheet`.
    ///
    /// This view consists of a horizontal scrollable list of emoji reactions and a list of users who reacted with the selected emoji.
    var body: some View {
        VStack {
            // Horizontal scroll view for emoji reactions
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(viewModel.message.reactions!.keys), id: \.self) { emoji in
                        Button {
                            // Update the selected emoji when tapped
                            selection = emoji
                        } label: {
                            HStack(spacing: 8) {
                                // Display the emoji or text representation
                                if emoji.count == 26 {
                                    LazyImage(source: .emoji(emoji), height: 16, width: 16, clipTo: Rectangle())
                                } else {
                                    Text(verbatim: emoji)
                                        .font(.system(size: 16))
                                }
                                
                                // Display the count of users who reacted with the selected emoji
                                Text(verbatim: String(viewModel.message.reactions![emoji]!.count))
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .foregroundStyle(selection == emoji ? viewState.theme.background3 : viewState.theme.background2))
                    }
                }
                .padding(16)
            }
            
            // List of users who reacted with the selected emoji
            HStack {
                let users = viewModel.message.reactions![selection]!
                
                List {
                    ForEach(users.compactMap({ viewState.users[$0] }), id: \.self) { user in
                        let member = viewModel.server.flatMap { viewState.members[$0.id]![user.id] }
                        
                        Button {
                            // Open the user sheet when a user is tapped
                            viewState.openUserSheet(user: user, member: member)
                        } label: {
                            HStack(spacing: 8) {
                                Avatar(user: user, member: member)
                                
                                Text(verbatim: member?.nickname ?? user.display_name ?? user.username)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(viewState.theme.background)
                }
            }
        }
        .padding(.top, 16)
        .presentationDragIndicator(.visible)
        .presentationBackground(viewState.theme.background)
    }
}
