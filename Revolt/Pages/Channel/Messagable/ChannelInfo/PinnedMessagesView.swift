//
//  PinnedMessagesView.swift
//  Revolt
//
//  Created by Akshat Srivastava on 17/03/26.
//
/// Pinned messages list for a channel; reuses the same message cell UI as ChannelSearch.

import SwiftUI
import Foundation
import Types

struct PinnedMessagesView: View {
    @EnvironmentObject var viewState: ViewState
    
    @Binding var channel: Channel
    
    @State private var pinnedMessages: [Types.Message] = []
    @State private var isLoading = true
    @State private var isNavigatingToMessage = false
    
    var body: some View {
        let server: Binding<Server?> = channel.server.map { id in
            Binding(
                get: { viewState.servers[id] },
                set: { viewState.servers[id] = $0 }
            )
        } ?? Binding.constant(nil)
        
        VStack(spacing: .zero) {
            PeptideDivider(backgrounColor: .bgDefaultPurple13)
            
            VStack(spacing: .zero) {
                HStack(spacing: .padding4) {
                    PeptideIconButton(icon: .peptideCloseLiner,
                                      color: .iconGray07,
                                      size: .size24,
                                      disabled: false) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ChannelSearchClosing"),
                            object: ["channelId": channel.id, "isReturning": true]
                        )
                        viewState.path.removeLast()
                    }
                    .padding(.padding8)
                    
                    PeptideText(
                        textVerbatim: "Pinned Messages",
                        font: .peptideTitle3,
                        textColor: .textDefaultGray01
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.padding16)
                
                if isLoading {
                    ProgressView()
                        .tint(.iconDefaultGray01)
                        .padding(.vertical, .padding24)
                        .frame(maxWidth: .infinity)
                } else if pinnedMessages.isEmpty {
                    VStack(spacing: .spacing4) {
                        Image(systemName: "pin.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.textGray07)
                        
                        PeptideText(
                            textVerbatim: "No Pinned Messages",
                            font: .peptideHeadline,
                            textColor: .textDefaultGray01
                        )
                        
                        PeptideText(
                            textVerbatim: "Pin important messages to find them here.",
                            font: .peptideFootnote,
                            textColor: .textGray07
                        )
                    }
                    .padding(.vertical, .padding24)
                    .padding(.horizontal, .padding16)
                    
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Color.bgGray12
                                .frame(height: .padding16)
                            
                            ForEach(pinnedMessages) { message in
                                let author = viewState.users[message.author] ?? User(
                                    id: message.author,
                                    username: "Unknown User",
                                    discriminator: "0000",
                                    relationship: .None
                                )
                                
                                MessageView(viewModel: .init(
                                    viewState: viewState,
                                    message: .constant(message),
                                    author: .constant(author),
                                    member: .constant(channel.server.flatMap{ viewState.members[$0]?[message.author] }),
                                    server: server,
                                    channel: $channel,
                                    replies: .constant([]),
                                    channelScrollPosition: .empty,
                                    editing: .constant(nil)
                                ),
                                isStatic: true
                                            
                                )
                                .padding(.horizontal, .padding16)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    navigateToMessage(message)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .scrollIndicators(.visible)
                    .background(Color.bgGray12)
                }
            }
            Spacer(minLength: .zero)
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: .radiusLarge, topTrailingRadius: .radiusLarge)
                .fill(Color.bgGray12)
        }
        .task {
            await loadPinnedMessages()
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden)
        .fillMaxSize()
    }
    
    private func loadPinnedMessages() async {
        isLoading = true
        pinnedMessages = []
        
        switch await viewState.http.fetchPinnedMessages(channel: channel.id, sort: .latest, limit: 100) {
        case .success(let response):
            for user in response.users {
                viewState.users[user.id] = user
            }
            if let members = response.members {
                for member in members {
                    viewState.members[member.id.server, default: [:]][member.id.user] = member
                }
            }
            pinnedMessages = response.messages
            
        case .failure(let error):
            print("PinnedMessagesView: Failed to load pinned messages: \(error)")
        }
        isLoading = false
    }
    
    private func navigateToMessage(_  message: Types.Message) {
        isNavigatingToMessage = true
        Task {
            let serverId = viewState.channels[message.channel]?.server
            let messageLink = await generateMessageLink(
                serverId: serverId,
                channelId: message.channel,
                messageId: message.id,
                viewState: viewState
            )
            guard let messageURL = URL(string: messageLink) else {
                return
            }
            await MainActor.run {
                handleMessageURL(messageURL)
            }
        }
    }
    
    private func handleMessageURL(_ url: URL) {
        if url.absoluteString.hasPrefix("https://peptide.chat/server/") {
            let components = url.pathComponents
            if components.count >= 6 {
                let serverId = components[2]
                let channelId = components[4]
                let messageId = components[5]
                
                if viewState.servers[serverId] != nil, viewState.channels[channelId] != nil {
                    guard viewState.currentUser != nil else {return}
                    let userMember = viewState.getMember(byServerId: serverId, userId: viewState.currentUser!.id)
                    if userMember !=  nil {
                        isNavigatingToMessage = true
                        viewState.currentTargetMessageId = messageId
                        viewState.path = []
                        viewState.path.append(NavigationDestination.maybeChannelView)
                        return
                    }
                }
            }
        }
        
        if url.absoluteString.hasPrefix("https://peptide.chat/channel/") {
            let components = url.pathComponents
            if components.count >= 4 {
                let channelId = components[2]
                let messageId = components[3]
                if viewState.channels[channelId] != nil {
                    guard viewState.currentUser != nil else {return}
                    isNavigatingToMessage = true
                    viewState.currentTargetMessageId = messageId
                    viewState.path = []
                    viewState.path.append(NavigationDestination.maybeChannelView)
                }
            }
        }
    }
}

private func generateMessageLink(serverId: String?, channelId: String, messageId: String, viewState: ViewState) async -> String {
    let baseURL = await viewState.baseURL ?? viewState.defaultBaseURL
    let webDomain: String
    if baseURL.contains("peptide.chat") {
        webDomain = "https://peptide.chat"
    } else if baseURL.contains("app.revolt.chat") {
        webDomain = "https://app.revolt.chat"
    } else {
        if let url = URL(string: baseURL), let host = url.host {
            webDomain = "https://\(host)"
        } else {
            webDomain = "https://app.revolt.chat"
        }
    }
    if let serverId = serverId, !serverId.isEmpty {
        return "\(webDomain)/server/\(serverId)/channel/\(channelId)/\(messageId)"
    } else {
        return "\(webDomain)/channel/\(channelId)/\(messageId)"
    }
}

//#Preview {
//    PinnedMessagesView()
//}
