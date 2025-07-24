//
//  MessageReactions.swift
//  Revolt
//
//  Created by Angelo on 05/12/2023.
//

import Foundation
import SwiftUI
import Flow
import Types

/// A SwiftUI view representing a single message reaction, including the emoji and a count of users who reacted.
///
/// This view handles both visual display and user interaction with a message reaction.
/// The reaction can either be an emoji (represented as a string) or a custom emoji (lazy loaded).
/// When the view is tapped, it toggles the reaction for the current user.
///
/// - Parameters:
///   - channel: The `Channel` object representing the channel where the message was posted.
///   - message: The `Message` object representing the message to which reactions are applied.
///   - emoji: A `String` representing the emoji used for the reaction. Can be a standard or custom emoji.
///   - users: A binding to an optional array of user IDs (`[String]?`) that reacted to the message.
///   - disabled: A `Bool` indicating whether the reaction is disabled (default is false).
struct MessageReaction: View {
    @EnvironmentObject var viewState: ViewState
    
    var channel: Channel
    var message: Message
    
    var emoji: String
    @Binding var users: [String]?
    
    var disabled: Bool = false
    
    // MARK: - Body
    
    /// The body of the `MessageReaction` view.
    ///
    /// Displays an emoji or custom image and the count of users who have reacted to the message.
    /// The reaction can be toggled by tapping on it, adding or removing the user's reaction.
    ///
    /// - Returns: A view containing the emoji or custom emoji and the user count for the reaction.
    var body: some View {
        
        let hasCurrentUserReacted = users?.contains(viewState.currentUser!.id) ?? false
        
        HStack(spacing: .spacing4) {
            if emoji.count == 26 {
                LazyImage(source: .emoji(emoji), height: .size20, width: .size20, clipTo: Rectangle()) // Load custom emoji
            } else {
                Text(verbatim: emoji)
                    .font(.system(size: 20)) // Display standard emoji
            }
            
            let font = PeptideFont.peptideButton.getFontData()
            
            Text(verbatim: "\(users?.count ?? 0)")
                .fontWithLineHeight(font: font.font, lineHeight: font.lineHeight)
                .fontWeight(font.weight)
                .foregroundStyle(.textDefaultGray01)
                .lineLimit(1)
            
            /*Text(verbatim: "\(users?.count ?? 0)")
                .font(PeptideFont.peptideBody1.font)
                .font(.footnote)
                .foregroundStyle(disabled ? viewState.theme.foreground2 : viewState.theme.foreground)*/
        }
        .padding(leading: .padding4,
                 trailing: .padding8)
        .frame(minWidth: .size40)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: .radiusXSmall)
            .foregroundStyle(hasCurrentUserReacted ? .bgPurple11 : .bgGray11)
            .addBorder(
                (hasCurrentUserReacted)
                ? Color.borderPurple07
                : Color.borderGray11,
                cornerRadius: .radiusXSmall
            )
        )
        
        .onTapGesture {
            // Capture message and channel IDs to prevent wrong message targeting
            let messageId = message.id
            let channelId = channel.id
            
            if users?.contains(viewState.currentUser!.id) ?? false {
                Task {
                    await viewState.http.unreactMessage(channel: channelId, message: messageId, emoji: emoji)
                }
            } else {
                Task {
                    await viewState.http.reactMessage(channel: channelId, message: messageId, emoji: emoji)
                }
            }
        }
    }
}

/// A SwiftUI view displaying a collection of reactions for a message.
///
/// The reactions are shown in two sections: required reactions (predefined by the message author) and optional reactions
/// (those added by users). The view handles displaying these reactions and allowing user interaction, enabling them to
/// add or remove reactions based on the restrictions set in `interactions`.
///
/// - Parameters:
///   - channel: The `Channel` object representing the channel where the message was posted.
///   - message: The `Message` object representing the message with reactions.
///   - reactions: A binding to an optional dictionary mapping emoji strings to an array of user IDs (`[String]`) that reacted.
///   - interactions: A binding to an optional `Interactions` object that defines allowed reactions and other interaction restrictions.
struct MessageReactions: View {
    @EnvironmentObject var viewState: ViewState
    
    var channel: Channel
    var server: Server?
    var message: Message
    
    @Binding var reactions: [String: [String]]?
    @Binding var interactions: Interactions?
    
    @State var showingSelectEmoji: Bool = false

    
    // MARK: - Helper Methods
    
    /// Retrieves the reactions for the message, splitting them into required and optional reactions.
    ///
    /// Required reactions are those predefined in the message's interactions, and optional reactions
    /// are those added by users. This function ensures that both types are displayed separately.
    ///
    /// - Returns: A tuple containing two arrays of tuples, where each tuple represents an emoji string and its associated users.
    func getReactions() -> ([(String, Binding<[String]?>)], [(String, Binding<[String]?>)]) {
        var required: [String] = []
        var optional: [String] = []
        
        for emoji in interactions?.reactions ?? [] {
            required.append(emoji) // Reactions predefined by the message's interactions
        }
        
        if let reactions {
            for emoji in reactions.keys {
                if !required.contains(emoji) {
                    optional.append(emoji) // User-added reactions
                }
            }
        }
                
        return (
            required.map { (
                $0,
                Binding($reactions)?[$0] ?? .constant([]) // Binding users to the required reactions
            ) },
            optional.map { (
                $0,
                Binding($reactions)?[$0] ?? .constant([]) // Binding users to the optional reactions
            ) }
        )
    }
    
    // MARK: - Body
    
    /// The body of the `MessageReactions` view.
    ///
    /// Displays both required and optional reactions for the message. Optional reactions can be restricted
    /// by the message's interaction settings.
    ///
    /// - Returns: A view displaying the reactions for the message, split into required and optional sections.
    var body: some View {
        let restrict_reactions = interactions?.restrict_reactions ?? false
        let (required, optional) = getReactions()
        
        if !required.isEmpty || !optional.isEmpty {
            HFlow(spacing: .spacing4) {
                ForEach(required, id: \.0) { (emoji, users) in
                    MessageReaction(channel: channel, message: message, emoji: emoji, users: users) // Required reactions
                }
                
                /*if required.count != 0, optional.count != 0 {
                    Divider()
                        .frame(height: 14)
                        .foregroundStyle(viewState.theme.foreground3)
                        .padding(.horizontal, 2)
                }*/
                
                ForEach(optional, id: \.0) { (emoji, users) in
                    MessageReaction(channel: channel, message: message, emoji: emoji, users: users, disabled: restrict_reactions) // Optional reactions
                }
                
                
                if let currentUser = viewState.currentUser {
                    if  resolveChannelPermissions(from: currentUser, targettingUser: currentUser, targettingMember: server.flatMap { viewState.members[$0.id]?[currentUser.id] }, channel: channel, server: server).contains(.react) {
                        
                        Button {
                            
                            self.showingSelectEmoji = true
                            
                        } label: {
                            HStack(spacing: .spacing4) {
                                
                                
                                PeptideIcon(iconName: .peptideReactionAdd,
                                            color: .iconGray04)
                                
                                
                            }
                            .padding(leading: .padding4,
                                     trailing: .padding4)
                            .frame(height: 28)
                            .frame(minWidth: 32)
                            .background(RoundedRectangle(cornerRadius: .radiusXSmall)
                                .foregroundStyle(.bgGray11)
                                .addBorder(
                                    Color.borderGray11,
                                    cornerRadius: .radiusXSmall
                                )
                            )
                        }
                    }
                }
                
            }
            .sheet(isPresented: $showingSelectEmoji) {
                EmojiPicker(background: AnyView(Color.bgGray12)) { emoji in
                    if let id = emoji.emojiId {
                        //content.append(":\(id):")
                        sendEmojiReaction(emoji: ":\(id):")
                    } else {
                        //content.append(String(String.UnicodeScalarView(emoji.base.compactMap(Unicode.Scalar.init))))
                        sendEmojiReaction(emoji: String(String.UnicodeScalarView(emoji.base.compactMap(Unicode.Scalar.init))))
                    }
                    
                    showingSelectEmoji = false
                }
                .padding([.top, .horizontal], .padding16)
                //.background(viewState.theme.background.ignoresSafeArea(.all))
                //.presentationDetents([.large])
                .presentationDetents([.fraction(0.4), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.bgGray12)
            }
        }
    }
    
    func sendEmojiReaction(emoji : String){
        // Capture message and channel IDs to prevent wrong message targeting
        let messageId = message.id
        let channelId = channel.id
        
        Task {
            await viewState.http.reactMessage(channel: channelId, message: messageId, emoji: emoji)
        }
    }
}
