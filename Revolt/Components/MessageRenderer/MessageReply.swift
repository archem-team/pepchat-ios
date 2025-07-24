//
//  MessageReply.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI
import Types

/// `MessageReplyView` is a SwiftUI view that displays a reply to a message.
/// It dynamically loads the message if it's not already present in the app's state.
struct MessageReplyView: View {
    @EnvironmentObject var viewState: ViewState // The global view state managing the app's data
    @State var dead: Bool = false // State to track if the message failed to load or is not available
    @Binding var mentions: [String]? // Binding to track user mentions in the message
    
    var channelScrollPosition: ChannelScrollController // Scroll controller for managing chat scrolling
    var id: String // ID of the message being replied to
    var server: Server? // The server the message belongs to
    var channel: Channel // The channel where the message was sent
    
    var body: some View {
        // Retrieve the message from the viewState using its ID
        let message = viewState.messages[id]
        
        // If the message is available or the message failed to load (`dead`), show the reply
        if message != nil || dead {
            InnerMessageReplyView(mentions: $mentions, channelScrollPosition: channelScrollPosition, server: server, message: message)
        } else {
            // If the message isn't loaded yet, check if it's currently being fetched
            if !viewState.loadingMessages.contains(id) {
                // If it's not being fetched, start fetching it asynchronously
                let _ = Task {
                    do {
                        // Attempt to fetch the message from the server
                        let message = try await viewState.http.fetchMessage(channel: channel.id, message: id).get()
                        // Cache the fetched message in the viewState
                        viewState.messages[id] = message
                        
                        // If the server and member data are available, fetch the member data if it's missing
                        if let server, viewState.members[server.id]?[message.author] == nil {
                            if let member = try? await viewState.http.fetchMember(server: server.id, member: message.author).get() {
                                viewState.members[server.id]?[message.author] = member
                            }
                        }
                    } catch {
                        // If the fetch fails, mark the message as "dead" to stop retrying
                        dead = true
                    }
                }
            }
            
            // Message is loading silently
            EmptyView()
            
        }
    }
}

/// `InnerMessageReplyView` is a sub-view that handles rendering the message reply's content.
/// It displays the author's avatar, name, message content, and allows users to scroll to the original message.
struct InnerMessageReplyView: View {
    @EnvironmentObject var viewState: ViewState // Global view state managing the app's data
    @Binding var mentions: [String]? // Binding to track user mentions in the message
    var channelScrollPosition: ChannelScrollController // Controller for handling scroll-to-message functionality
    var server: Server? // Server object, if applicable
    var message: Message? // The message being displayed
    
    /// Function to format the author's display name for the reply.
    /// It checks for masquerade names, nicknames, or default to the author's username.
    /// If the user is mentioned in the message, an "@" is prepended.
    func formatName(message: Message, author: User, member: Member?) -> String {
        (mentions?.contains(message.author) == true ? "@" : "") + (message.masquerade?.name ?? member?.nickname ?? author.display_name ?? author.username)
    }
    
    var body: some View {
        if let message = message {
            // Fetch the user and member data for the author of the message
            let author = viewState.users[message.author] ?? User(id: "0", username: "", discriminator: "0000")
            let member = server.flatMap { viewState.members[$0.id] }.flatMap { $0[message.author] }
            
            
            HStack(alignment: .top,spacing: .spacing4) {
                // Display the author's avatar (or masquerade avatar if applicable)
                Avatar(user: author, member: member, masquerade: message.masquerade, width: .size24, height: .size24)
                
                VStack(alignment: .leading, spacing: .zero){
                    // Display the author's name (masquerade, nickname, or default username)
                    
                    
                    let attachmentsIsEmpty = message.attachments?.isEmpty ?? true
                    let messageContent = message.content
                    
                    HStack(spacing: .padding4){
                        
                        PeptideText(text: formatName(message: message, author: author, member: member),
                                    font: .peptideHeadline,
                                    textColor: .textDefaultGray01,
                                    lineLimit: 1)
                        .truncationMode(.tail)
                        
                        //.foregroundStyle(member?.displayColour(theme: viewState.theme, server: server!) ?? AnyShapeStyle(viewState.theme.foreground.color))
                        //.font(.caption)
                        
                        if !attachmentsIsEmpty {
                            
                            HStack(spacing: .spacing2){
                                
                                PeptideText(text: "Tap to see  attachment",
                                            font: .peptideFootnote,
                                            textColor: .textGray06,
                                            lineLimit: 1)
                                
                                
                                PeptideIcon(iconName: .peptidePhotoPicture,
                                            size: .size16,
                                            color: .iconGray07)
                                
                            }
                            
                            
                            
                        }
                    }
                    
                    
                    
                    // Display the message content (truncated if it's too long)
                    if let content = messageContent , attachmentsIsEmpty {
                        
                        HStack(spacing: .padding4){
                            
                            PeptideText(text: content,
                                        font: .peptideBody2,
                                        textColor: .textGray07,
                                        lineLimit: 1)
                            .truncationMode(.tail)
                            
                            
                        }
                    }
                }
                
            }
            // When the reply is tapped, scroll to the original message
            .onTapGesture {
                channelScrollPosition.scrollTo(message: message.id)
            }
        } else {
            // If the message data is unavailable, show a placeholder text
            
            HStack(alignment: .center, spacing: .spacing4){
                
                Image(.peptideBadSmile)
                    .resizable()
                    .frame(width: .size24, height: .size24)
                
                PeptideText(text: "Original message was deleted",
                            font: .peptideFootnote,
                            textColor: .textGray06)
                
                PeptideIcon(iconName: .peptideTrashDelete, size: .size16,
                            color: .iconGray07)

                
                
            }
            
        }
    }
}


