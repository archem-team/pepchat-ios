//
//  MessageContentsView.swift
//  Revolt
//
//  Created by Angelo on 12/12/2023.
//

import Foundation
import SwiftUI
import Types
import SwiftUIMasonry
/// The view model for managing the content and actions related to a message.
///
/// This view model handles the state and functionality of the message, such as deleting, replying, and managing
/// message-related interactions. It also ensures reactivity with the view using `@Binding` properties.
///
/// - Parameters:
///   - viewState: The global state of the view, which provides access to various user and theme settings.
///   - message: A binding to the `Message` object that is displayed or interacted with.
///   - author: A binding to the `User` object representing the author of the message.
///   - member: A binding to an optional `Member` object, representing the member of the server, if applicable.
///   - server: A binding to an optional `Server` object, representing the server in which the message was posted.
///   - channel: A binding to the `Channel` where the message was posted.
///   - channelReplies: A binding to an array of `Reply` objects, representing replies to the message.
///   - editing: A binding to an optional `Message` that is currently being edited.
///   - channelScrollPosition: The scroll position controller for the channel's message list.

@MainActor
class MessageContentsViewModel: ObservableObject, Equatable {
    var viewState: ViewState
    
    @Binding var message: Message
    @Binding var author: User
    @Binding var member: Member?
    @Binding var server: Server?
    @Binding var channel: Channel
    @Binding var channelReplies: [Reply]
    @Binding var editing: Message?
    
    var channelScrollPosition: ChannelScrollController
    
    var isFirstInGroup: Bool
    var isLastInGroup: Bool
    
    init(viewState: ViewState, message: Binding<Message>, author: Binding<User>, member: Binding<Member?>, server: Binding<Server?>, channel: Binding<Channel>, replies: Binding<[Reply]>, channelScrollPosition: ChannelScrollController, editing: Binding<Message?>, isFirstInGroup: Bool = false, isLastInGroup: Bool = false ) {
        self.viewState = viewState
        self._message = message
        self._author = author
        self._member = member
        self._server = server
        self._channel = channel
        self._channelReplies = replies
        self.channelScrollPosition = channelScrollPosition
        self._editing = editing
        self.isFirstInGroup = isFirstInGroup
        self.isLastInGroup = isLastInGroup
        
        // CRITICAL FIX: Ensure message author exists before displaying
        Task { @MainActor in
            let _ = viewState.ensureMessageAuthorExists(messageId: message.wrappedValue.id)
        }
    }
    
    /// Equates two `MessageContentsViewModel` instances by comparing their message IDs.
    static func == (lhs: MessageContentsViewModel, rhs: MessageContentsViewModel) -> Bool {
        lhs.message.id == rhs.message.id
    }
    
    /// Deletes the current message asynchronously.
    func delete() async -> Result<EmptyResponse, RevoltError> {
        let result = await viewState.http.deleteMessage(channel: channel.id, message: message.id)
        
        // If the request was successful, immediately update local state
        if case .success = result {
            await MainActor.run {
                viewState.deletedMessageIds[channel.id, default: Set()].insert(message.id)
                if let userId = viewState.currentUser?.id, let baseURL = viewState.baseURL {
                    MessageCacheWriter.shared.enqueueDeleteMessage(id: message.id, channelId: channel.id, userId: userId, baseURL: baseURL)
                }
                // Remove from messages dictionary
                viewState.messages.removeValue(forKey: message.id)
                
                // Remove from channel messages array
                if var channelMessages = viewState.channelMessages[channel.id] {
                    channelMessages.removeAll { $0 == message.id }
                    viewState.channelMessages[channel.id] = channelMessages
                }
            }
        }
        
        return result
    }
    
    /// Adds the current message as a reply in the channel, limited to 5 replies.
    func reply() {
        if !channelReplies.contains(where: { $0.message.id == message.id }) && channelReplies.count < 5 {
            withAnimation {
                channelReplies.append(Reply(message: message))
            }
        }
    }
}

/// A SwiftUI view that displays the content of a message and provides interaction options such as replying, reacting, and managing the message.
///
/// The view displays the message content, embeds, attachments, and reactions. It also offers context menu actions like editing,
/// deleting, copying, or reporting the message based on user permissions and whether the user is the author of the message.
///
/// - Parameters:
///   - viewState: The current global view state, providing necessary data for rendering and interactions.
///   - viewModel: The `MessageContentsViewModel` object that manages the message's content and actions.
///   - isStatic: A Boolean indicating whether the message is static (non-interactive) or dynamic.
struct MessageContentsView: View {
    @EnvironmentObject var viewState: ViewState
    @ObservedObject var viewModel: MessageContentsViewModel
    
    @State var showMemberSheet: Bool = false
    @State var showReportSheet: Bool = false
    @State var showReactSheet: Bool = false
    @State var showReactionsSheet: Bool = false
    @State var isStatic: Bool = false
    @State var onlyShowContent: Bool = false
    @State var showingSelectEmoji : Bool = false
    
    @State var isPresentedMessageOption : Bool = false
    

    
    
    /// Checks if the current user has permission to manage messages in the channel.
    ///
    /// - Returns: `true` if the user has manage messages permission, `false` otherwise.
    private var canManageMessages: Bool {
        let member = viewModel.server.flatMap {
            viewState.members[$0.id]?[viewState.currentUser!.id]
        }
        
        let permissions = resolveChannelPermissions(from: viewState.currentUser!, targettingUser: viewState.currentUser!, targettingMember: member, channel: viewModel.channel, server: viewModel.server)
        
        return permissions.contains(.manageMessages)
    }
    
    /// Checks if the current user is the author of the message.
    ///
    /// - Returns: `true` if the current user is the author, `false` otherwise.
    private var isMessageAuthor: Bool {
        viewModel.message.author == viewState.currentUser?.id
    }
    
    /// Checks if the current user can delete the message.
    ///
    /// - Returns: `true` if the user can delete the message, either as the author or with manage messages permissions.
    private var canDeleteMessage: Bool {
        return isMessageAuthor || canManageMessages
    }
    
    /// Checks if the current user has permission to send messages (reply to messages).
    ///
    /// - Returns: `true` if the user has send messages permission, `false` otherwise.
    private var canSendMessages: Bool {
        guard let currentUser = viewState.currentUser else {
            return false
        }
        
        // Check if this is a DM channel
        if case .dm_channel(let dmChannel) = viewModel.channel {
            if let otherUser = dmChannel.recipients.filter({ $0 != currentUser.id }).first {
                let relationship = viewState.users.first(where: { $0.value.id == otherUser })?.value.relationship
                return relationship != .Blocked && relationship != .BlockedOther
            }
        } else {
            // For server channels, check send messages permission
            let member = viewModel.server.flatMap {
                viewState.members[$0.id]?[currentUser.id]
            }
            
            let permissions = resolveChannelPermissions(
                from: currentUser,
                targettingUser: currentUser,
                targettingMember: member,
                channel: viewModel.channel,
                server: viewModel.server
            )
            
            return permissions.contains(Types.Permissions.sendMessages)
        }
        
        return true
    }
    
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var enableToSwipe : Bool {
        return canSendMessages
    }
    
    /// When isStatic (e.g. search results), disable swipe so the parent list scroll receives vertical drags. See Scrolling.md.
    private var effectiveEnableSwipe: Bool {
        enableToSwipe && !isStatic
    }
    
    /// The body of the `MessageContentsView`.
    ///
    /// Displays the message content, reactions, and embeds, and provides context menu actions such as reply, react, copy, edit, and delete.
    var body: some View {
        
        
        SwipeToReplyView(enableSwipe: effectiveEnableSwipe, onReply: viewModel.reply){
            HStack(spacing: .zero){
                
                VStack(alignment: .leading, spacing: .zero) {
                    
                    // Display message content if available
                    if let content = Binding(viewModel.$message.content), !content.wrappedValue.isEmpty {
                        
                        Contents(text: content,
                                 fontSize: 18,
                                 font: PeptideFont.peptideBody1.getFontData().font,
                                 foregroundColor: .textGray04,
                                 isEdited: viewModel.message.edited != nil)
                        .offset(y: -8)

                    }
                    
                    
                    // Display embeds if available
                    if !onlyShowContent {
                        if let embeds = viewModel.message.embeds {
                            let filtered = Array(embeds.enumerated())
                                .filter { $0.element != .none }

                            ForEach(filtered, id: \.offset) { index, _ in
                                if let embedsBinding = Binding(viewModel.$message.embeds) {
                                    MessageEmbed(embed: embedsBinding[index])
                                        .padding(.top, .padding4)
                                }
                            }
                        }
                    }


                    
                    // Display attachments if available
                    if !onlyShowContent {
                        /*if let attachments = viewModel.message.attachments {
                         VStack(alignment: .leading) {
                         ForEach(attachments) { attachment in
                         MessageAttachment(attachment: attachment)
                         .padding(.top, .padding4)
                         }
                         }
                         }*/
                        
                        if let attachments = viewModel.message.attachments {
                            let mediaAttachments = attachments.filter {
                                if case .image = $0.metadata { return true }
                                if case .video = $0.metadata { return true }
                                return false
                            }
                            let otherAttachments = attachments.filter { !mediaAttachments.contains($0) }
                            
                            VStack(alignment: .center, spacing: .zero) {
                                if !mediaAttachments.isEmpty {
                                    
                                    if mediaAttachments.count == 2 {
                                        
                                        HStack(spacing: .spacing4){
                                            
                                            MessageAttachment(attachment: mediaAttachments[0], height: 295)
                                            MessageAttachment(attachment: mediaAttachments[1], height: 295)
                                            
                                        }
                                        .clipped()
                                        .padding(.top, .padding4)
                                        
                                    } else if mediaAttachments.count == 3 {
                                        
                                        HStack(spacing: .spacing4){
                                            
                                            MessageAttachment(attachment: mediaAttachments[0], height: 295)
                                            
                                            
                                            VStack(spacing: .spacing4){
                                                MessageAttachment(attachment: mediaAttachments[1], height: 145.5)
                                                MessageAttachment(attachment: mediaAttachments[2], height: 145.5)
                                            }
                                            
                                        }
                                        
                                    } else if mediaAttachments.count == 4 {
                                        
                                        HStack(spacing: .spacing4){
                                            
                                            VStack(spacing: .spacing4){
                                                MessageAttachment(attachment: mediaAttachments[0], height: 145.5)
                                                MessageAttachment(attachment: mediaAttachments[1], height: 145.5)
                                            }
                                            
                                            VStack(spacing: .spacing4){
                                                MessageAttachment(attachment: mediaAttachments[2], height: 145.5)
                                                MessageAttachment(attachment: mediaAttachments[3], height: 145.5)
                                                
                                            }
                                            
                                        }
                                        
                                    } else if mediaAttachments.count == 5 {
                                        
                                        VStack(spacing: .spacing4){
                                            
                                            HStack(spacing: .spacing4){
                                                MessageAttachment(attachment: mediaAttachments[0], height: 145.5)
                                                MessageAttachment(attachment: mediaAttachments[1], height: 145.5)
                                            }
                                            
                                            HStack(spacing: .spacing4){
                                                MessageAttachment(attachment: mediaAttachments[2], height: 145.5)
                                                MessageAttachment(attachment: mediaAttachments[3], height: 145.5)
                                                MessageAttachment(attachment: mediaAttachments[4], height: 145.5)
                                            }
                                            
                                        }
                                        
                                    } else {
                                        
                                    }
                                    
                                }
                                
                                if !otherAttachments.isEmpty {
                                    ForEach(otherAttachments) {
                                        MessageAttachment(attachment: $0).padding(.top, .padding4)
                                    }
                                }
                            }
                        }
                        
                    }
                    
                    // Display message reactions
                    MessageReactions(
                        channel: viewModel.channel,
                        server: viewModel.server,
                        message: viewModel.message,
                        reactions: viewModel.$message.reactions,
                        interactions: viewModel.$message.interactions
                    )
                    .padding(.top, .padding8)
                    
                    if viewModel.message.isInviteLink(), 
                       let content = viewModel.message.content,
                       let inviteCode = content.components(separatedBy: "/").last {
                        // Fetch and display invite
                        InviteFetcher(inviteCode: inviteCode) { invite in
                            return AnyView(
                                InviteView(
                                    inviteCode: inviteCode,
                                    invite: invite
                                )
                                    .padding(.top, .padding4)
                            )
                        }
                    }
                }
                
                Spacer(minLength: .zero)
                
            }

        }
        //.listRowInsets(.init())
        //.listRowSeparator(.hidden)
        //.listRowSpacing(0)
        //.listRowBackground(Color.clear)
        .environment(\.currentMessage, viewModel)
        .onLongPressGesture {
            if !isStatic {
                isPresentedMessageOption.toggle()
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportMessageSheetView(showSheet: $showReportSheet, messageView: viewModel)
                .presentationBackground(viewState.theme.background)
        }
        .sheet(isPresented: $showReactSheet) {
            EmojiPicker(background: AnyView(viewState.theme.background)) { emoji in
                Task {
                    showReactSheet = false
                    let _ = await viewState.http.reactMessage(channel: viewModel.message.channel, message: viewModel.message.id, emoji: emoji.id)
                }
            }
            .padding([.top, .horizontal])
            .background(viewState.theme.background.ignoresSafeArea(.all))
        }
        .sheet(isPresented: $showReactionsSheet) {
            MessageReactionsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSelectEmoji) {
            // Capture message and channel IDs to prevent wrong message targeting
            let messageId = viewModel.message.id
            let channelId = viewModel.message.channel
            
            EmojiPicker(background: AnyView(Color.bgGray12)) { emoji in
                
                Task {
                    let _ = await viewState.http.reactMessage(channel: channelId, message: messageId, emoji: emoji.id)
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
        .sheet(isPresented: $isPresentedMessageOption){
            MessageOptionSheet(viewModel: viewModel,
                               isPresented: $isPresentedMessageOption,
                               isMessageAuthor: isMessageAuthor,
                               canDeleteMessage: self.canDeleteMessage){ messageOptionType in
                
                // Close the sheet first
                isPresentedMessageOption = false
                
                switch messageOptionType {
                case .edit:
                    Task {
                        var replies: [Reply] = []
                        
                        for reply in viewModel.message.replies ?? [] {
                            var message: Message? = viewState.messages[reply]
                            
                            if message == nil {
                                message = try? await viewState.http.fetchMessage(channel: viewModel.channel.id, message: reply).get()
                            }
                            
                            if let message {
                                replies.append(Reply(message: message, mention: viewModel.message.mentions?.contains(message.author) ?? false))
                            }
                        }
                        
                        viewModel.channelReplies = replies
                        viewModel.editing = viewModel.message
                    }
                case .reply:
                    viewModel.reply()
                case .mention:
                    self.viewState.mentionedUser = viewModel.message.author
                case .markUnread:
                    Task {
                        do {
                            _ = try await viewState.http.ackMessage(channel: viewModel.channel.id, message: viewModel.message.id).get()
                        } catch {
                            print("Unexpected send ack: \(error)")
                        }
                    }
                case .copyText:
                    copyText(text: viewModel.message.content ?? "")
                    self.viewState.showAlert(message: "Copied Message Text!", icon: .peptideCopy)
                case .copyLink:
                    Task {
                        let link = await generateMessageLink(
                            serverId: viewModel.server?.id,
                            channelId: viewModel.channel.id,
                            messageId: viewModel.message.id,
                            viewState: viewState
                        )
                        
                        await MainActor.run {
                            copyUrl(url: URL(string: link)!)
                            self.viewState.showAlert(message: "Message Link Copied!", icon: .peptideCopy)
                        }
                    }
                case .copyId:
                    copyText(text: viewModel.message.id)
                    self.viewState.showAlert(message: "Message ID Copied!", icon: .peptideCopy)
                case .report:
                    //showReportSheet.toggle()
                    viewState.path.append(NavigationDestination.report(nil, nil, viewModel.message.id))
                case .deleteMessage:
                    Task {
                        let result = await self.viewModel.delete()
                        await MainActor.run {
                            switch result {
                            case .success:
                                print("Deleted")

                            case .failure(let error):
                                print("Not Deleted")

                            }
                        }
                    }
                    
                case .sendReact(let code):
                    // Capture message and channel IDs to prevent wrong message targeting
                    let messageId = viewModel.message.id
                    let channelId = viewModel.message.channel
                    
                    if code == "-1" {
                        showingSelectEmoji.toggle()
                    } else {
                        Task {
                            let _ = await viewState.http.reactMessage(channel: channelId, message: messageId, emoji: code)
                        }
                    }
                    
                }
            }
        }
        
        /*.contextMenu {
         if !isStatic {
         if isMessageAuthor {
         Button {
         Task {
         var replies: [Reply] = []
         
         for reply in viewModel.message.replies ?? [] {
         var message: Message? = viewState.messages[reply]
         
         if message == nil {
         message = try? await viewState.http.fetchMessage(channel: viewModel.channel.id, message: reply).get()
         }
         
         if let message {
         replies.append(Reply(message: message, mention: viewModel.message.mentions?.contains(message.author) ?? false))
         }
         }
         
         viewModel.channelReplies = replies
         viewModel.editing = viewModel.message
         }
         } label: {
         Label("Edit Message", systemImage: "pencil")
         }
         }
         
         Button(action: viewModel.reply, label: {
         Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
         })
         
         Button {
         showReactSheet = true
         } label: {
         Label("React", systemImage: "face.smiling.inverse")
         }
         
         if !(viewModel.message.reactions?.isEmpty ?? true) {
         Button {
         showReactionsSheet = true
         } label: {
         Label("Reactions", systemImage: "face.smiling.inverse")
         }
         }
         
         Button {
         copyText(text: viewModel.message.content ?? "")
         } label: {
         Label("Copy text", systemImage: "doc.on.clipboard")
         }
         
         if canDeleteMessage {
         Button(role: .destructive, action: {
         Task {
         await viewModel.delete()
         }
         }, label: {
         Label("Delete", systemImage: "trash")
         })
         }
         
         if !isMessageAuthor {
         Button(role: .destructive, action: { showReportSheet.toggle() }, label: {
         Label("Report", systemImage: "exclamationmark.triangle")
         })
         } else {
         Button {
         viewModel.editing = viewModel.message
         } label: {
         Label("Edit", systemImage: "pencil")
         }
         }
         
         Button {
         if let server = viewModel.server {
         copyUrl(url: URL(string: "https://revolt.chat/app/server/\(server.id)/channel/\(viewModel.channel.id)/\(viewModel.message.id)")!)
         } else {
         copyUrl(url: URL(string: "https://revolt.chat/app/channel/\(viewModel.channel.id)/\(viewModel.message.id)")!)
         
         }
         } label: {
         Label("Copy Message Link", systemImage: "link")
         }
         
         Button {
         copyText(text: viewModel.message.id)
         } label: {
         Label("Copy Message ID", systemImage: "doc.on.clipboard")
         }
         
         if canDeleteMessage {
         Button(role: .destructive, action: {
         Task {
         await viewModel.delete()
         }
         }, label: {
         Label("Delete Message", systemImage: "trash")
         })
         }
         
         if !isMessageAuthor {
         Button(role: .destructive, action: { showReportSheet.toggle() }, label: {
         Label("Report Message", systemImage: "exclamationmark.triangle")
         })
         }
         }
         }*/
        .swipeActions(edge: .trailing) {
            isStatic ? nil :
            Button(action: viewModel.reply, label: {
                
                
                ZStack {
                    Circle().fill(Color.bgYellow07)
                    PeptideIcon(iconName: .peptideReply,
                                size: .size20,
                                color: .iconInverseGray13)
                }
                .frame(width: .size32, height: .size32)
                
                
            })
            .background(Color.bgDefaultPurple13)
            .tint(.bgDefaultPurple13)
        }
    }
}


import SwiftUI
import Flow

struct CustomTextView: UIViewRepresentable {
    var text: String
    var font: UIFont
    var lineHeight: CGFloat
    
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.adjustsFontSizeToFitWidth = false
        label.lineBreakMode = .byTruncatingTail
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.alignment = .center
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        label.attributedText = attributedString
        return label
    }
    
    func updateUIView(_ uiView: UILabel, context: Context) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.alignment = .center
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        uiView.attributedText = attributedString
    }
}

// Add this helper view to handle invite fetching
struct InviteFetcher: View {
    @EnvironmentObject var viewState: ViewState
    let inviteCode: String
    let content: (InviteInfoResponse?) -> AnyView
    
    @State private var invite: InviteInfoResponse?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                content(invite)
            }
        }
        .task {
            let response = await viewState.http.fetchInvite(code: inviteCode)
            switch response {
            case .success(let fetchedInvite):
                invite = fetchedInvite
            case .failure(_):
                break
            }
            isLoading = false
        }
    }
}

// MARK: - Helper Functions
/// Generates a dynamic message link based on the current domain
private func generateMessageLink(serverId: String?, channelId: String, messageId: String, viewState: ViewState) async -> String {
    // Get the current base URL and determine the web domain
    let baseURL = await viewState.baseURL ?? viewState.defaultBaseURL
    let webDomain: String
    
    if baseURL.contains("peptide.chat") {
        webDomain = "https://peptide.chat"
    } else if baseURL.contains("app.revolt.chat") {
        webDomain = "https://app.revolt.chat"
    } else {
        // Fallback for other instances - extract domain from API URL
        if let url = URL(string: baseURL),
           let host = url.host {
            webDomain = "https://\(host)"
        } else {
            webDomain = "https://app.revolt.chat" // Ultimate fallback
        }
    }
    
    // Generate proper URL based on channel type
    if let serverId = serverId, !serverId.isEmpty {
        // Server channel
        return "\(webDomain)/server/\(serverId)/channel/\(channelId)/\(messageId)"
    } else {
        // DM channel
        return "\(webDomain)/channel/\(channelId)/\(messageId)"
    }
}
