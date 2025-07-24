//
//  ServerChannelScrollView.swift
//  Revolt
//
//  Created by Angelo on 2023-11-25.
//

import SwiftUI
import Types


struct ChannelListItem: View {
    @EnvironmentObject var viewState: ViewState
    var server: Server
    var channel: Channel
    
    var toggleSidebar: () -> ()
    
    @State private var isPresentedChannelOption : Bool = false
    @State private var isPresentedNotificationSetting : Bool = false
    @State private var isPresentedInviteSheet : Bool = false
    @State private var selectedChannel : Channel? = nil
    @State private var delletingChannelId : String? = nil
    @State private var isPresentedDelletChannelSheet : Bool = false
    @State private var isLoadingDeleteChannel : Bool = false

    @State var inviteSheetUrl: InviteUrl? = nil
    
    func getValues() -> (Bool, UnreadCount?, ThemeColor, ThemeColor) {
        let isSelected = viewState.currentChannel.id == channel.id
        let unread = viewState.getUnreadCountFor(channel: channel)
        
        let notificationValue = viewState.userSettingsStore.cache.notificationSettings.channel[channel.id]
        let isMuted = notificationValue == .muted || notificationValue == NotificationState.none
        
        let foregroundColor: ThemeColor
        
        if isSelected {
            foregroundColor = viewState.theme.foreground
        } else if isMuted {
            foregroundColor = viewState.theme.foreground3
        } else if unread != nil {
            foregroundColor = viewState.theme.foreground
        } else {
            foregroundColor = viewState.theme.foreground3
        }
        
        let backgroundColor = isSelected ? viewState.theme.background : viewState.theme.background2
        
        return (isMuted, unread, backgroundColor, foregroundColor)
    }
    
    var body: some View {
        let (_, unread, _, _) = getValues()
        let _ = self.selectedChannel
        let _ = self.inviteSheetUrl
        let _ = self.delletingChannelId

        Button {
            toggleSidebar()
            
            // CRITICAL FIX: Clear channel messages before navigating to ensure full message history is loaded
            // This prevents the issue where only new WebSocket messages are shown
            print("🔄 ServerChannelScrollView: Clearing channel messages for channel \(channel.id) to ensure full history loads")
            viewState.channelMessages[channel.id] = []
            viewState.preloadedChannels.remove(channel.id)
            
            viewState.selectChannel(inServer: server.id, withId: channel.id)
            viewState.path.append(NavigationDestination.maybeChannelView)
            
        } label: {
            HStack(spacing: .padding8) {
                
                if case .unread = unread {
                    UnreadView(unreadSize: .size8)
                        .offset(x: -4)
                } else if case .unreadWithMentions = unread {
                    UnreadView(unreadSize: .size8)
                        .offset(x: -4)
                } else {
                    UnreadView(unreadSize: .size8)
                        .opacity(0)
                }
                
                
                ChannelIcon(channel: self.channel,
                            spacing: .padding4,
                            initialSize: (24,24),
                            frameSize: (24,24),
                            font: .peptideBody2)
                            .onLongPressGesture {
                                self.selectedChannel = self.channel
                                self.isPresentedChannelOption.toggle()
                            }
                            //.opacity(isMuted ? 0.4 : 1)
                Spacer()
                
                
                if case .mentions(let count) = unread {
                    UnreadMentionsView(count: count, mentionSize: .size20)
                } else if case .unreadWithMentions(let count) = unread {
                    UnreadMentionsView(count: count, mentionSize: .size20)
                }
                
                
                /*if let unread = unread, !isMuted {
                 UnreadCounter(unread: unread)
                 .padding(.trailing)
                 }*/
            }
            .padding(.trailing, .padding16)
        }
//        .contextMenu {
//            Button("Mark as read") {
//                Task {
//                    if let last_message = viewState.channelMessages[channel.id]?.last {
//                        let _ = try! await viewState.http.ackMessage(channel: channel.id, message: last_message).get()
//                    }
//                }
//            }
//
//            Button("Notification options") {
//                viewState.path.append(NavigationDestination.channel_info(channel.id))
//            }
//
//            /*Button("Create Invite") {
//                Task {
//                    let res = await viewState.http.createInvite(channel: channel.id)
//
//                    if case .success(let invite) = res {
//                        inviteSheetUrl = InviteUrl(url: URL(string: "https://peptide.chat/invite/\(invite.id)")!)
//                        isPresentedInviteSheet.toggle()
//                    }
//                }
//            }*/
//        }
        //.background(backgroundColor)
        //.foregroundStyle(foregroundColor)
        .sheet(isPresented: $isPresentedInviteSheet) {
            ShareInviteSheet(isPresented: $isPresentedInviteSheet, url: inviteSheetUrl!.url)
        }
        .sheet(isPresented: $isPresentedChannelOption){
            
            ChannelOptionsSheet(isPresented: $isPresentedChannelOption,
                                channel: self.selectedChannel!, server: server){ option in
                switch option {
                case .viewProfile(let user, let member):
                    viewState.openUserSheet(user: user, member: member)
                case .message(let user):
                    Task {
                        toggleSidebar()
                        await viewState.openDm(with: user.id)
                        viewState.path.append(NavigationDestination.maybeChannelView)
                    }
                case .notificationOptions:
                    self.isPresentedNotificationSetting.toggle()
                case .copyDirectMessageId(let channelId):
                    copyText(text: channelId)
                    self.viewState.showAlert(message: "Direct Message ID Copied!", icon: .peptideCopy)
                case .closeDM(let channelId):
                    self.delletingChannelId = channelId
                    self.isPresentedDelletChannelSheet.toggle()
                    self.isPresentedChannelOption.toggle()
                case .closeDMGroup(let channel):
                    self.delletingChannelId = channel.id
                    self.isPresentedDelletChannelSheet.toggle()
                    self.isPresentedChannelOption.toggle()
                case .reportUser(let user):
                    viewState.path.append(NavigationDestination.report(user, nil, nil))
                    
                case .copyGroupId(let channelId):
                    copyText(text: channelId)
                    self.viewState.showAlert(message: "Channel ID Copied!", icon: .peptideCopy)
                    
                case .groupSetting(let channelId) :
                    self.viewState.path.append(NavigationDestination.channel_settings(channelId))
                    
                case .invite :
                    Task {
                        let res = await viewState.http.createInvite(channel: channel.id)
                        
                        if case .success(let invite) = res {
                            inviteSheetUrl = InviteUrl(url: URL(string: "https://peptide.chat/invite/\(invite.id)")!)
                            isPresentedInviteSheet.toggle()
                        }
                    }
                    
                case .channelOverview:
                    self.viewState.path.append(NavigationDestination.channel_overview_setting(self.channel.id, self.server.id))
//                case .deleteChannel:
                case .groupPermissionsSetting(let channelId, let serverId):
                    self.viewState.path.append(NavigationDestination.channel_permissions_settings(serverId: serverId, channelId: channelId))


                }
                
            }
        }
        .sheet(isPresented: self.$isPresentedNotificationSetting){
            NotificationSettingSheet(isPresented: $isPresentedNotificationSetting,
                                     channel: self.selectedChannel!,
                                     server: self.server)
        }
        .popup(isPresented: $isPresentedDelletChannelSheet, view: {
            ConfirmationSheet(
                isPresented: $isPresentedDelletChannelSheet,
                isLoading: $isLoadingDeleteChannel,
                title: "Delete Channel?",
                subTitle: "Once it’s deleted, there’s no going back.",
                confirmText: "Delete Channel",
                dismissText: "Cancel",
                popOnConfirm: false
            ){
                if let delletingChannelId = self.delletingChannelId{

                    Task {

                        isLoadingDeleteChannel = true

                        await self.viewState.closeDMGroup(channelId: delletingChannelId)

                        isLoadingDeleteChannel = false
                        isPresentedDelletChannelSheet = false
                    }

                }

            }
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })


    }
}

struct CategoryListItem: View {
    @EnvironmentObject var viewState: ViewState
    
    var server: Server
    var category: Types.Category
    var selectedChannel: String?
    
    var toggleSidebar: () -> ()
    
    var body: some View {
        let isClosed = viewState.userSettingsStore.store.closedCategories[server.id]?.contains(category.id) ?? false
        
        VStack(alignment: .leading, spacing: .zero) {
            Button {
                withAnimation(.easeInOut) {
                    if isClosed {
                        viewState.userSettingsStore.store.closedCategories[server.id]?.remove(category.id)
                    } else {
                        viewState.userSettingsStore.store.closedCategories[server.id, default: Set()].insert(category.id)
                    }
                }
            } label: {
                HStack(spacing: .zero) {
                    
                    PeptideIcon(iconName: .peptideArrowRight,
                                size: .size24,
                                color: .iconGray07)
                    .rotationEffect(Angle(degrees: isClosed ? 0 : 90))
                    
                    PeptideText(textVerbatim: category.title,
                                font: .peptideTitle3,
                                textColor: .textGray06)
                    
                    
                    
                    Spacer(minLength: .zero)
                }
                .padding(top: .padding16,
                         bottom: isClosed ? .zero : .padding4,
                         leading: .padding8,
                         trailing: .padding8)
            }
            
            if !isClosed {
                ForEach(category.channels.compactMap({ viewState.channels[$0] }), id: \.id) { channel in
                    ChannelListItem(server: server, channel: channel, toggleSidebar: toggleSidebar)
                }
            }
        }
    }
}

struct ServerChannelScrollView: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var currentSelection: MainSelection
    @Binding var currentChannel: ChannelSelection
    @State private var isPresentedInviteSheet : Bool = false
    @State var inviteSheetUrl: InviteUrl? = nil
    var toggleSidebar: () -> ()
    
    @State var showServerSheet: Bool = false
    
    private var canOpenServerSettings: Bool {
        if let user = viewState.currentUser, let member = viewState.openServerMember, let server = viewState.openServer {
            let perms = resolveServerPermissions(user: user, member: member, server: server)
            
            return !perms.intersection([.manageChannel, .manageServer, .managePermissions, .manageRole, .manageCustomisation, .kickMembers, .banMembers, .timeoutMembers, .assignRoles, .manageNickname, .manageMessages, .manageWebhooks, .muteMembers, .deafenMembers, .moveMembers]).isEmpty
        } else {
            return false
        }
    }
    
    func createInvite(serverID: String) {
        
        if let channelId = findFirstTextChannelID(serverID: serverID) {
            Task {
                let res = await viewState.http.createInvite(channel: channelId)
                
                if case .success(let invite) = res {
                    inviteSheetUrl = InviteUrl(url: URL(string: "https://peptide.chat/invite/\(invite.id)")!)
                    isPresentedInviteSheet.toggle()
                }
            }
        }
        
    }
    
    func findFirstTextChannelID(serverID: String) -> String? {
        guard let server = viewState.servers[serverID] else {
            return nil
        }
        
        for channelID in server.channels {
            if let channel = viewState.channels[channelID], case .text_channel(_) = channel {
                return channelID
            }
        }
        
        return nil
    }
    
    var body: some View {
        
        let _ = self.inviteSheetUrl
        
        let maybeSelectedServer: Server? = switch currentSelection {
        case .server(let serverId): viewState.servers[serverId]
        default: nil
        }
        
        if let server = maybeSelectedServer {
            let categoryChannels = server.categories?.flatMap(\.channels) ?? []
            let nonCategoryChannels = server.channels.filter({ !categoryChannels.contains($0) })
            
            VStack(spacing: .zero){
                
                Button {
                    showServerSheet = true
                } label: {
                    ZStack(alignment: .bottom) {
                        if let banner = server.banner {
                            
                            
                            Color.clear
                                .overlay {
                                    LazyImage(source: .file(banner),
                                              height: 160,
                                              clipTo: RoundedRectangle(cornerRadius: .zero))
                                }
                                .frame(height: 160)
                                .clipped()
                                .clipShape(
                                    .rect(
                                        topLeadingRadius: 24,
                                        bottomLeadingRadius: 0,
                                        bottomTrailingRadius: 0,
                                        topTrailingRadius: 0
                                    )
                                )
                            
                                
                        }
                        
                        VStack(alignment: .leading, spacing: .zero) {
                            
                            /*ServerBadges(value: server.flags)*/
                            Spacer()
                                .frame(height: server.banner == nil ? .padding12 : .padding40)
                            
                            HStack(spacing: .zero){
                                PeptideText(textVerbatim: server.name,
                                            font: .peptideHeadline,
                                            textColor: .textDefaultGray01,
                                            lineLimit: 1)
                                
                                PeptideIcon(iconName: .peptideArrowRight,
                                            size: .size20,
                                            color: .iconDefaultGray01)
                                
                                Spacer(minLength: .zero)
                                
                                
                            }
                            .padding(.horizontal, .padding16)
                            
                            HStack(spacing: .spacing2){
                                
                                
                                PeptideIcon(iconName: .peptideTeamUsers,
                                            size: .size16,
                                            color: .iconGray07)
                                
                                PeptideText(textVerbatim: "\(self.viewState.serverMembersCount ?? "---") members",
                                            font: .peptideBody4,
                                            textColor: .textGray07,
                                            lineLimit: 1)
                                
                                Spacer(minLength: .zero)
                                
                                if viewState.isCurrentUserOwner(of: server.id){
                                   
                                    Button {
                                        
                                        createInvite(serverID: server.id)
                                        
                                    } label : {
                                        
                                        PeptideIcon(
                                            iconName: .peptideNewGroup,
                                            size: .size20,
                                            color: .iconDefaultGray01
                                        )
                                        .background{
                                            
                                            Circle()
                                                .fill(.bgGray11)
                                                .frame(width: .size32, height: .size32)
                                            
                                        }
                                        
                                    }
                                    
                                }
                                
                            }
                            .padding(top: .padding4, bottom: .padding12, leading: .padding16, trailing: .padding16)
                            
                            /*if canOpenServerSettings {
                             NavigationLink(value: NavigationDestination.server_settings(server.id)) {
                             Image(systemName: "gearshape.fill")
                             .resizable()
                             .bold()
                             .frame(width: 18, height: 18)
                             .foregroundStyle(server.banner != nil ? .white : viewState.theme.foreground.color)
                             }
                             }*/
                        }
                        .frame(alignment: .bottom)
                        .background{
                            
                            
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    Gradient.Stop(color: .clear, location: 0.0),
                                    Gradient.Stop(color: .bgGray12, location: 0.70),
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                }
                
                PeptideDivider(backgrounColor: .borderGray11)
                    .padding(.bottom, .padding4)
                
                if nonCategoryChannels.isEmpty, server.channels.isEmpty {
                
                    VStack(spacing: .spacing4){
                        
                        Image(.peptideDmEmpty)
                            .resizable()
                            .frame(width: .size100, height: .size100)
                            .padding(.top, .size24)
                        
                        PeptideText(text: "Oops, there's nothing here!",
                                    font: .peptideHeadline,
                                    textColor: .textDefaultGray01)
                        .padding(.horizontal, .padding24)
                        
                        PeptideText(text: "This server has no channels, or you don't have access to any.",
                                    font: .peptideSubhead,
                                    textColor: .textGray07,
                                    alignment: .center)
                        .padding(.horizontal, .padding24)

                    }
                    .padding(.horizontal, .padding16)
                    .padding(.bottom, .padding16)
                    
                }
                
                ScrollView {
                    
                    ForEach(nonCategoryChannels.compactMap({ viewState.channels[$0] })) { channel in
                        ChannelListItem(server: server, channel: channel, toggleSidebar: toggleSidebar)
                    }
                    
                    ForEach(server.categories ?? []) { category in
                        CategoryListItem(server: server, category: category, toggleSidebar: toggleSidebar)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .sheet(isPresented: $isPresentedInviteSheet) {
                    if let inviteSheetUrl {
                        ShareInviteSheet(isPresented: $isPresentedInviteSheet, url: inviteSheetUrl.url)
                    }
                }
                .sheet(isPresented: $showServerSheet) {
                    ServerInfoSheet(isPresentedServerSheet: $showServerSheet,
                                    server: server,
                                    onNavigation: {route, serverId in
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                            switch route {
                                                case .overview:
                                                    viewState.path.append(NavigationDestination.server_overview_settings(serverId))
                                                case .channels:
                                                    viewState.path.append(NavigationDestination.server_channels(serverId))
                                                default:
                                                    debugPrint("")
                                            }
                                        }
                                    })
                }
            }
            .background{
                Color.bgGray12
                    .clipShape(
                        .rect(
                            topLeadingRadius: 24,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                    )
                
            }
            
        } else {
            //Text("How did you get here?")
            EmptyView()
        }
    }
}

#Preview {
    let state = ViewState.preview()
    return ServerChannelScrollView(currentSelection: .constant(MainSelection.server("0")), currentChannel: .constant(ChannelSelection.channel("2")), toggleSidebar: {})
        .applyPreviewModifiers(withState: state)
}
