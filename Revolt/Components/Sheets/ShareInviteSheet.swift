//
//  ShareInviteSheet.swift
//  Revolt
//
//  Created by Angelo on 09/03/2024.
//

import Foundation
import SwiftUI
import Types

/// A view that provides functionality for sharing an invite link and inviting friends.
struct ShareInviteSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool

    
    //@State var channel: Channel  // Channel to which the invite pertains
    @State var url: URL  // Invite URL to share
    @State var friendSearch: String = ""  // Search string for filtering friends
    @State var copiedToClipboard: Bool = false  // State to track if the URL has been copied to the clipboard
    
    /// Retrieves a list of friends from the user's contacts.
    /// - Returns: An array of User objects representing friends.
    func getFriends() -> [User] {
        var friends: [User] = []  // Array to store friends
        
        // Iterate over users in the view state
        for user in viewState.users.values {
            // Check if the user is a friend
            switch user.relationship ?? .None {
                case .Friend:
                    friends.append(user)  // Append friend to the list
                default:
                    ()
            }
        }
        
        return friends  // Return the list of friends
    }
    
    
    private var headerSection: some View {
        ZStack(alignment: .center) {
            PeptideText(
                text: "Create Invite",
                font: .peptideHeadline,
                textColor: .textDefaultGray01
            )
            HStack {
                PeptideIconButton(icon: .peptideBack, color: .iconDefaultGray01, size: .size24) {
                    self.isPresented.toggle()
                }
                Spacer()
            }
        }
        .padding(.bottom, .padding24)
    }
    
    var body: some View {
        
        PeptideSheet(isPresented: $isPresented, topPadding: .padding16) {
            
            headerSection
            
            Image(.peptideDiscover)
                .resizable()
                .frame(width: .size100, height: .size100)
            
            PeptideText(text: "You can invite people to the server via a link.",
                        font: .peptideSubhead,
                        textColor: .textGray07)
            .padding(.top, .padding4)
            
            HStack(spacing:  .zero) {
                ShareLink(item: url) {
                    
                    
                    PeptideIconWithTitleButton(icon: .peptideShare,
                                               title: "Share Invite",
                                               disabled: true){}
                    
                   
                }
                
                
                PeptideIconWithTitleButton(icon: .peptideLink,
                                           title: "Copy Link"){
                        copyUrl(url: url)
                        withAnimation{
                            viewState.showAlert(message: "Invite Link Copied!", icon: .peptideCopy)
                        }
                }
                
            }
            .padding(.top, .padding24)

 
                /*VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")  // Search icon
                            .resizable()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(viewState.theme.foreground2)
                        
                        // Search field for filtering friends
                        TextField("Invite your friends", text: $friendSearch)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewState.theme.background2)  // Background for the search field
                    .clipShape(RoundedRectangle(cornerRadius: 8))  // Rounded corners
                    .padding(.horizontal, 16)
                    
                    List {
                        // Filter and display friends based on the search term
                        ForEach(getFriends().filter { user in
                            friendSearch.isEmpty || (user.username.contains(friendSearch) || (user.display_name?.contains(friendSearch) ?? false))
                        }) { user in
                            HStack(spacing: 12) {
                                Avatar(user: user)  // Display friend's avatar
                                    .frame(width: 16, height: 16)
                                    .frame(width: 24, height: 24)
                                
                                Text(user.display_name ?? user.username)  // Display friend's name
                                
                                Spacer()  // Spacer to align invite button to the right
                                
                                // Invite button
                                Text("Invite")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(viewState.theme.background3, in: RoundedRectangle(cornerRadius: 50))
                            }
                            .listRowBackground(viewState.theme.background2)  // Background for list row
                        }
                    }
                    .scrollContentBackground(.hidden)  // Hide scroll content background
                    .listRowInsets(.none)  // Remove list row insets
                }*/
            
            //.alertPopup(content: "Copied to clipboard", show: copiedToClipboard)
            
        }
        
        
    }
}

/// Preview provider for ShareInviteSheet to enable SwiftUI previews.
#Preview {
    let viewState = ViewState.preview()  // Create a preview environment

    ShareInviteSheet(isPresented: .constant(true) , url: URL(string: "https://revolt.chat")!)  // Present the ShareInviteSheet
        .applyPreviewModifiers(withState: viewState)  // Apply preview modifiers
        .preferredColorScheme(.dark)
}
