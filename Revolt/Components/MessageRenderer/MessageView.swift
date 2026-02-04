//
//  Message.swift
//  Revolt
//
//  Created by Zomatree on 21/04/2023.
//

import Foundation
import SwiftUI
import Types

struct MessageView: View {
    
    private enum AvatarSize {
        case regular
        case compact
        
        var sizes: (CGFloat, CGFloat, CGFloat) {
            switch self {
                case .regular:
                    return (40, 16, 4)
                case .compact:
                    return (16, 8, 2)
            }
        }
    }
    
    @StateObject var viewModel: MessageContentsViewModel
    @EnvironmentObject var viewState: ViewState
    @State var showReportSheet: Bool = false
    @State var isStatic: Bool = false
    @State var onlyShowContent: Bool = false
    
    
    var isCompactMode: (Bool, Bool) {
        return TEMP_IS_COMPACT_MODE
    }
    
    private func pfpView(size: AvatarSize) -> some View {
        
        Button {
            if !isStatic || viewModel.message.webhook != nil {
                viewState.openUserSheet(withId: viewModel.author.id, server: viewModel.server?.id)
            }			    
        } label: {
            ZStack(alignment: .topLeading) {
                /*Avatar(user: viewModel.author, member: viewModel.member, masquerade: viewModel.message.masquerade, webhook: viewModel.message.webhook, width: size.sizes.0, height: size.sizes.0)
                    .onTapGesture {
                        if !isStatic || viewModel.message.webhook != nil {
                            viewState.openUserSheet(withId: viewModel.author.id, server: viewModel.server?.id)
                        }
                    }*/
                

                //if viewModel.message.masquerade != nil {
                    Avatar(user: viewModel.author,
                           member: viewModel.member,
                           masquerade: viewModel.message.masquerade,
                           webhook: viewModel.message.webhook,
                           width: size.sizes.0,
                           height: size.sizes.0)
                            
                        //.padding(.leading, -size.sizes.2)
                        //.padding(.top, -size.sizes.2)
                //}
            }
        }
        
    }
    
    private var nameView: some View {
        let name = viewModel.message.webhook?.name
            ?? viewModel.message.masquerade?.name
            ?? viewModel.member?.nickname
            ?? viewModel.author.display_name
            ?? viewModel.author.username
        
        return Text(verbatim: name)
            .font(.peptideTitle4Font)
            .foregroundStyle(.textDefaultGray01)
            .lineLimit(1)
            .onTapGesture {
                if !isStatic || viewModel.message.webhook != nil {
                    viewState.openUserSheet(withId: viewModel.author.id, server: viewModel.server?.id)
                }
            }
            /*.foregroundStyle(viewModel.member?.displayColour(theme: viewState.theme, server: viewModel.server!) ?? AnyShapeStyle(viewState.theme.foreground.color))*/
    }
    
    @State private var replayParentSize : CGSize = .zero
    
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
    
    var enableSwipe : Bool {
        return canSendMessages
    }
    
    var body: some View {
        // When isStatic (e.g. search results), disable swipe so the parent list scroll receives vertical drags. See Scrolling.md.
        SwipeToReplyView(enableSwipe: enableSwipe && !isStatic, onReply: viewModel.reply){
            VStack(alignment: .leading, spacing: .zero) {
                
                if let replies = viewModel.message.replies {
                               
                               
                               ZStack(alignment: .leading){
                                   
                                   
                                   RoundedRectangle(cornerRadius: .zero)
                                       .fill(Color.borderDefaultGray09)
                                       .frame(width: 2, height: replayParentSize.height)
                                       .offset(x:-1, y: (24 / 2) + 5)
                                       .padding(.leading, 16)
                                   
                                   
                                   VStack(alignment: .leading, spacing: .spacing4) {
                                       ForEach(replies, id: \.self) { id in
                                           
                                           
                                           
                                           HStack(alignment: .top, spacing:.zero){
                                               
                                               Path{ path in
                                                   path.move(to: CGPoint(x: 35,y: 0))
                                                   path.addLine(to: CGPoint(x: 5, y: 0))
                                                   
                                                   path.addCurve(to: CGPoint(x: 0, y: 5), control1: CGPoint(x: 1, y: 1), control2: CGPoint(x: 1, y: 1))
                                                   
                                                   path.addLine(to: CGPoint(x: 0, y: 24 / 2))
                                                   
                                                   //path.closeSubpath()
                                               }
                                               .stroke(Color.borderDefaultGray09, lineWidth: 2)
                                               .frame(width: 35, height: 24 / 2)
                                               .background(Color.clear)
                                               .padding(.leading, .padding16)
                                               .padding(.top, .padding12)

                                               MessageReplyView(
                                                   mentions: viewModel.$message.mentions,
                                                   channelScrollPosition: viewModel.channelScrollPosition,
                                                   id: id,
                                                   server: viewModel.server,
                                                   channel: viewModel.channel
                                               )
                                               .padding(.leading, .size1)
                                               
                                           }
                                           
                                       }
                                   }
                                   .onGeometryChange(for: CGSize.self) { proxy in
                                       proxy.size
                                   } action: {
                                       replayParentSize = $0
                                   }
                                   
                               }
                               
                              
                           }

                
                if viewModel.message.system != nil {
                    SystemMessageView(message: $viewModel.message)
                } else {
                    //TODO:
                    if isCompactMode.0 {
                        HStack(alignment: .top, spacing: 4) {
                            HStack(alignment: .center, spacing: 4) {
                                Text(formattedMessageDate(from: createdAt(id: viewModel.message.id)))
                                    .font(.caption)
                                    .foregroundStyle(viewState.theme.foreground2)
                                
                                if isCompactMode.1 {
                                    pfpView(size: .compact)
                                }
                                
                                nameView
                                
                                if viewModel.author.bot != nil {
                                    MessageBadge(text: String(localized: "BOT"), color: .bgPurple10)
                                }
                            }
                            
                            MessageContentsView(viewModel: viewModel,
                                                isStatic: isStatic,
                                                onlyShowContent: onlyShowContent)
                            
                            if viewModel.message.edited != nil {
                                Text("(edited)")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        }
                    } else {
                        HStack(alignment: .top, spacing: .padding16) {
                            pfpView(size: .regular)
                            
                            VStack(alignment: .leading, spacing: .zero) {
                                HStack(spacing: .zero) {
                                    
                                    HStack(spacing: .spacing4){
                                        nameView
                                        
                                        Text(formattedMessageDate(from: createdAt(id: viewModel.message.id)))
                                            .font(.peptideFootnoteFont)
                                            .foregroundStyle(.textGray06)
                                            .lineLimit(1)
                                    }
                                    
                                    //TODO:
                                    if viewModel.author.bot != nil {
                                        MessageBadge(text: String(localized: "BOT"), color: .bgPurple10)
                                    }
                                    
                                    //TODO:
                                    if viewModel.message.webhook != nil {
                                        MessageBadge(text: String(localized: "Webhook"), color: .bgPurple10)
                                        
                                    }
                                    
                                   
                                   
                                }
                                
                                MessageContentsView(viewModel: viewModel,
                                                    isStatic: isStatic,
                                                    onlyShowContent: onlyShowContent)

                            }
                            Spacer(minLength: .zero)
                        }
                    }
                }
            }
            //.padding(.vertical, .padding4)
        }
        .environment(\.currentMessage, viewModel)
    }
}

//struct GhostMessageView: View {
//    @EnvironmentObject var viewState: ViewState
//
//    var message: QueuedMessage
//
//    var body: some View {
//        HStack(alignment: .top) {
//            Avatar(user: viewState.currentUser!, width: 16, height: 16)
//            VStack(alignment: .leading) {
//                HStack {
//                    Text(viewState.currentUser!.username)
//                        .fontWeight(.heavy)
//                    Text(createdAt(id: message.nonce).formatted())
//                }
//                Contents(text: message.content)
//                //.frame(maxWidth: .infinity, alignment: .leading)
//            }
//            //.frame(maxWidth: .infinity, alignment: .leading)
//        }
//        .listRowSeparator(.hidden)
//    }
//}

struct MessageView_Previews: PreviewProvider {
    static var viewState: ViewState = ViewState.preview().applySystemScheme(theme: .dark)
    @State static var message = viewState.messages["01HDEX6M2E3SHY8AC2S6B9SEAW"]!
    @State static var author = viewState.users[message.author]!
    @State static var member = viewState.members["0"]!["0"]
    @State static var channel = viewState.channels["0"]!
    @State static var server = viewState.servers["0"]
    @State static var replies: [Reply] = []
    @State static var highlighted: String? = nil
    
    static var previews: some View {
        ScrollViewReader { p in
            List {
                MessageView(viewModel: MessageContentsViewModel(viewState: viewState, message: $message, author: $author, member: $member, server: $server, channel: $channel, replies: $replies, channelScrollPosition: ChannelScrollController(proxy: p, highlighted: $highlighted), editing: .constant(nil)), isStatic: false)
            }
            .environment(\.defaultMinListRowHeight, 0)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            
        }
            .applyPreviewModifiers(withState: viewState)
    }
}
