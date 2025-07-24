//
//  ChannelInfo.swift
//  Revolt
//
//  Created by Angelo on 06/12/2023.
//

import Foundation
import SwiftUI
import Types

/// Represents a URL for an invite, conforming to Identifiable.
struct InviteUrl: Identifiable {
    var url: URL
    var id: String {
        url.path() // Unique identifier derived from the URL path.
    }
}

struct UserDisplay: View {
    @EnvironmentObject var viewState: ViewState
    @State private var isPresentedUserOpitonSheet : Bool = false
    @State private var isPresentedTransferOwnershipSheet: Bool = false
    @State private var isLoadingTransferOwnership: Bool = false
    @State private var isPresentedKickMemberSheet: Bool = false
    @State private var isPresentedBanMemberSheet: Bool = false

    var server: Server?
    var user: User
    var member: Member?
    var channel : Channel
    var withPresence : Bool = true
    var removeUser: () -> Void
    
    
    
    var body: some View {
        Button {
            //viewState.openUserSheet(user: user, member: member)
            isPresentedUserOpitonSheet.toggle()
        } label: {
            HStack(spacing: .spacing12) {
                
                Avatar(user: user, member: member, withPresence: withPresence)
                
                PeptideText(textVerbatim: member?.nickname ?? user.display_name ?? user.username,
                            font: .peptideButton,
                            textColor: .textDefaultGray01)
                
                
                Spacer(minLength: .zero)
                
                
                /*VStack(alignment: .leading) {
                 
                 Text(verbatim: member?.nickname ?? user.display_name ?? user.username)
                 .fontWeight(.bold)
                 .foregroundStyle(member?.displayColour(theme: viewState.theme, server: server!) ?? AnyShapeStyle(viewState.theme.foreground.color))
                 
                 if let statusText = user.status?.text {
                 Text(verbatim: statusText)
                 .font(.caption)
                 .foregroundStyle(viewState.theme.foreground2.color)
                 .lineLimit(1)
                 .truncationMode(.tail)
                 } else {
                 switch user.status?.presence {
                 case .Busy:
                 Text("Busy")
                 .font(.caption)
                 .foregroundStyle(viewState.theme.foreground2.color)
                 
                 case .Idle:
                 Text("Idle")
                 .font(.caption)
                 .foregroundStyle(viewState.theme.foreground2.color)
                 
                 case .Invisible:
                 Text("Invisible")
                 .font(.caption)
                 .foregroundStyle(viewState.theme.foreground2.color)
                 
                 case .Online:
                 Text("Online")
                 .font(.caption)
                 .foregroundStyle(viewState.theme.foreground2.color)
                 
                 case .Focus:
                 Text("Focus")
                 .font(.caption)
                 .foregroundStyle(viewState.theme.foreground2.color)
                 
                 default :
                 Text("Offline")
                 .font(.caption)
                 .foregroundStyle(viewState.theme.foreground2.color)
                 }
                 }
                 }*/
                
                if case .group_dm_channel(let groupDMChannel) = channel {
                    
                    
                    if groupDMChannel.owner == user.id {
                        HStack(spacing: .spacing2){
                            PeptideIcon(iconName: .peptideAdminKing,
                                        size: .size16,
                                        color: .iconGray07)
                            
                            PeptideText(textVerbatim: "Owner",
                                        font: .peptideSubhead,
                                        textColor: .textGray07)
                        }
                        .padding(.horizontal, .padding8)
                        .frame(height: 26)
                        .background{
                            RoundedRectangle(cornerRadius: .radiusMedium)
                                .fill(Color.bgGray11)
                        }
                    }
                    
                }
                
            }
            .padding(.padding12)
        }
        .sheet(isPresented: $isPresentedUserOpitonSheet){
            ChannelUserOptionSheet(isPresented: $isPresentedUserOpitonSheet,
                                   user: user,
                                   member: member,
                                   channel: channel,
                                   server: server,
                                   onTransferOwnershipTap:{
                isPresentedUserOpitonSheet.toggle()
                isPresentedTransferOwnershipSheet.toggle()
            },
                                   onKickTap: {
                isPresentedUserOpitonSheet.toggle()
                isPresentedKickMemberSheet.toggle()
            },
                                   onBanTap: {
                isPresentedUserOpitonSheet.toggle()
                isPresentedBanMemberSheet.toggle()
            })
        }
        .popup(isPresented: $isPresentedTransferOwnershipSheet, view: {
            
            ConfirmationSheet(isPresented: $isPresentedTransferOwnershipSheet, isLoading: $isLoadingTransferOwnership, title: "Transfer Group Ownership?", subTitle: "You’re about to assign ownership to \(user.displayName()). This action cannot be undone.", confirmText: "Transfer Ownership", buttonAlignment: .center){
                
                Task {
                    
                    self.isLoadingTransferOwnership = true
                    
                    let result = await viewState.http.editChannel(id: channel.id, owner: user.id)
                    
                    self.isLoadingTransferOwnership = false
                    
                    switch result{
                    case .success(_):
                        self.isPresentedTransferOwnershipSheet = false
                        self.viewState.path.removeLast()
                    case .failure(_):
                        self.viewState.showAlert(message: "Something Wronge!", icon: .peptideInfo)
                    }
                    
                }
                
            }
            
        }, customize: {
            $0.type(.default)
                .isOpaque(true)
                .appearFrom(.bottomSlide)
                .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                .closeOnTap(false)
                .closeOnTapOutside(false)
        }).popup(isPresented: $isPresentedKickMemberSheet, view: {
            KickMemberSheet(
                isPresented: $isPresentedKickMemberSheet,
                user: user,
                member: member,
                serverId: server?.id ?? ""
            ){
                removeUser()
            }
        }, customize: {
            $0.type(.default)
                .isOpaque(true)
                .appearFrom(.bottomSlide)
                .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                .closeOnTap(false)
                .closeOnTapOutside(false)
        })
        .popup(isPresented: $isPresentedBanMemberSheet, view: {
            BanMemberSheet(
                isPresented: $isPresentedBanMemberSheet,
                user: user,
                member: member,
                serverId: server?.id ?? ""
            ){
                removeUser()
            }
        }, customize: {
            $0.type(.default)
                .isOpaque(true)
                .appearFrom(.bottomSlide)
                .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                .closeOnTap(false)
                .closeOnTapOutside(false)
        })
    }
}

struct ChannelInfo: View {
    @EnvironmentObject var viewState: ViewState
    
    @Binding var channel: Channel
    @Binding var server : Server?
    @State var showInviteSheet: InviteUrl? = nil
    
    @State private var search: String = ""
    @State private var searchTextFieldState : PeptideTextFieldState = .default
    
    @State private var isPresentedMoreSheet : Bool = false
    @State private var isPresentedNotificationSetting : Bool = false
    @State private var isPresentedLeaveChannel : Bool = false
    @State private var isFocused : Bool = false
    @State private var members: [Member] = []
    @State private var textChannelMembers: [UserMaybeMember] = []
    
    
    func getRoleSectionHeaders() -> [(String, Role)] {
        switch channel {
        case .text_channel, .voice_channel:
            let server = viewState.servers[channel.server!]!
            
            return (server.roles ?? [:])
                .filter { $0.value.hoist ?? false }
                .sorted(by: { (r1, r2) in r1.value.rank < r2.value.rank })
            
        default:
            return []
        }
    }
    
    func getRoleSectionContents(users: [UserMaybeMember], role: String) -> [UserMaybeMember] {
        var role_members: [UserMaybeMember] = []
        let other_hoisted_roles = getRoleSectionHeaders().filter { $0.0 != role }
        let server = viewState.servers[channel.server!]!
        
        for u in users {
            let sorted_member_roles = u.member!.roles?.sorted(by: { (a, b) in server.roles![a]!.rank < server.roles![b]!.rank }) ?? []
            
            if let current_role_pos = sorted_member_roles.firstIndex(of: role),
               other_hoisted_roles.allSatisfy({ other_role in (sorted_member_roles.firstIndex(of: other_role.0) ?? Int.max ) > current_role_pos })
            {
                role_members.append(u)
            }
        }
        
        return role_members
    }
    
    func getNoRoleSectionContents(users: [UserMaybeMember]) -> [UserMaybeMember] {
        switch channel {
        case .text_channel, .voice_channel:
            var no_role_members: [UserMaybeMember] = []
            let section_headers = getRoleSectionHeaders().map { $0.0 }
            
            for u in users {
                if (u.member?.roles ?? []).allSatisfy({ !section_headers.contains($0) }) {
                    no_role_members.append(u)
                }
            }
            
            return no_role_members
            
        default:
            return users
        }
        
    }
    
    var users: [UserMaybeMember] {
        let users: [UserMaybeMember]
        
        switch channel {
        case .saved_messages(_):
            users = [UserMaybeMember(user: viewState.currentUser!)]
            
        case .dm_channel(let dMChannel):
            users =  dMChannel.recipients.map { UserMaybeMember(user: viewState.users[$0]!) }
            
        case .group_dm_channel(let groupDMChannel):
            users =  groupDMChannel.recipients.map { UserMaybeMember(user: viewState.users[$0]!) }
            
        case .text_channel(_), .voice_channel(_):
            users =  textChannelMembers
        }
        
        if !search.isEmpty {
            return users.filter { userMaybeMember in
                let name = userMaybeMember.user.display_name ?? userMaybeMember.user.username
                return name.localizedCaseInsensitiveContains(search)
            }
        }
        
        return users
    }
    
    
    /*private func groupedUsers (users : [UserMaybeMember]) -> [Presence: [UserMaybeMember]] {
     Dictionary(grouping: users) { userMaybeMember in
     userMaybeMember.user.status?.presence ?? .Invisible
     }
     }*/
    
    private func groupedUsers(from users: [UserMaybeMember]) -> [String: [UserMaybeMember]] {
        Dictionary(grouping: users) { userMaybeMember in
            userMaybeMember.user.online == true ? "Online" : "Offline"
        }
    }
    
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: !self.isFocused,
                                                 title: self.channel.isTextOrVoiceChannel ? self.channel.name : nil,
                                                 customToolbarView: !self.channel.isTextOrVoiceChannel ? AnyView(
                                                   
                                                   PeptideIconButton(icon: .peptideMore,
                                                                     color: .iconDefaultGray01,
                                                                     size: .size24){
                                                                         
                                                                         isPresentedMoreSheet.toggle()
                                                                     }
                                                 ) : nil )){_,_ in
            
            VStack(alignment: .leading, spacing: .zero) {
                
                                
                let sections = getRoleSectionHeaders()
                
                let server = channel.server.map { viewState.servers[$0]! }
                let no_role = getNoRoleSectionContents(users: users)
                
                
                /*VStack {
                 
                 
                 if let description = channel.description {
                 Text(verbatim: description)
                 .font(.footnote)
                 .foregroundStyle(viewState.theme.foreground2.color)
                 }
                 
                 HStack {
                 NavigationLink(value: NavigationDestination.channel_search(channel.id)) {
                 VStack(alignment: .center) {
                 Image(systemName: "magnifyingglass.circle.fill")
                 .resizable()
                 .frame(width: 32, height: 32)
                 
                 Text("Search")
                 }
                 }
                 
                 Spacer()
                 
                 Button {
                 
                 } label: {
                 VStack(alignment: .center) {
                 Image(systemName: "bell.circle.fill")
                 .resizable()
                 .frame(width: 32, height: 32)
                 
                 Text("Mute")
                 }
                 }
                 
                 Spacer()
                 
                 NavigationLink(value: NavigationDestination.channel_settings(channel.id)) {
                 VStack(alignment: .center) {
                 Image(systemName: "gearshape.circle.fill")
                 .resizable()
                 .frame(width: 32, height: 32)
                 
                 Text("Settings")
                 }
                 }
                 }
                 .padding(.horizontal, 32)
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 32)*/
                
                if(!self.isFocused && !self.channel.isTextOrVoiceChannel){
                
                    VStack(spacing: .zero){
                        
                        ChannelOnlyIcon(channel: channel,
                                        initialSize: (28,28),
                                        frameSize: (48,48))
                        .padding(.bottom, .padding16)
                        
                        PeptideText(textVerbatim: channel.getName(viewState),
                                    font: .peptideTitle3,
                                    textColor: .textDefaultGray01,
                                    lineLimit: 1
                        )
                        .padding(.bottom, .padding4)
                        
                        PeptideText(textVerbatim: "\(no_role.count) Members",
                                    font: .peptideSubhead,
                                    textColor: .textGray07)
                        
                        if let description = channel.description {
                            
                            PeptideDivider(backgrounColor: .borderGray11)
                                .padding(.vertical, .padding16)
                            
                            PeptideText(textVerbatim: description,
                                        font: .peptideBody3,
                                        textColor: .textDefaultGray01,
                                        alignment: .center)
                            
                        }
                        
                        
                    }
                    .padding(.vertical, .padding24)
                    .padding(.horizontal, .padding16)
                    .frame(maxWidth: .infinity)
                    .background{
                        RoundedRectangle(cornerRadius: .radius8)
                            .fill(Color.bgGray12)
                    }
                    .padding(.top, .padding16)
                    
                    
                    if let currentUser = viewState.currentUser {
                        if channel.isGroupDmChannel && resolveChannelPermissions(from: currentUser, targettingUser: currentUser, targettingMember: server.flatMap { viewState.members[$0.id]?[currentUser.id] }, channel: channel, server: server).contains(.inviteOthers) {
                            
                            Button {
                                viewState.path.append(NavigationDestination.add_members_to_channel(channel.id))
                            } label : {
                                
                                
                                PeptideActionButton(icon: .peptideNewUser,
                                                    title: "Add Members")
                                .frame(minHeight: .size56)
                                .background{
                                    RoundedRectangle(cornerRadius: .radiusMedium).fill(Color.bgGray11)
                                        .overlay{
                                            RoundedRectangle(cornerRadius: .radiusMedium)
                                                .stroke(.borderGray10, lineWidth: .size1)
                                        }
                                }
                                
                            }
                            .padding(top: .padding24)
                        }
                    }
                   
                    
                }
                
                Spacer()
                    .frame(height: .size16)
                
                
                LazyVStack(spacing: .zero, pinnedViews: .sectionHeaders){
                    /*if case .dm_channel(let dm) = channel {
                     let recipient = dm.recipients.first { $0 != viewState.currentUser!.id }!
                     
                     NavigationLink(value: NavigationDestination.create_group([recipient])) {
                     HStack(spacing: 12) {
                     Image(systemName: "plus.message.fill")
                     .resizable()
                     .aspectRatio(contentMode: .fit)
                     .frame(width: 32, height: 32)
                     
                     Text("New Group")
                     }
                     }
                     .listRowBackground(viewState.theme.background2.color)
                     
                     } else if case .text_channel = channel {
                     Button {
                     Task {
                     let res = await viewState.http.createInvite(channel: channel.id)
                     
                     if case .success(let invite) = res {
                     showInviteSheet = InviteUrl(url: URL(string: "https://rvlt.gg/\(invite.id)")!)
                     }
                     }
                     } label: {
                     HStack(spacing: 12) {
                     Image(systemName: "person.crop.circle.fill.badge.plus")
                     .resizable()
                     .aspectRatio(contentMode: .fit)
                     .frame(width: 32, height: 32)
                     
                     Text("Invite Users")
                     }
                     }
                     .listRowBackground(viewState.theme.background2.color)
                     }*/
                    
                    
                    /*Section {
                     ForEach(sections, id: \.0) { (roleId, role) in
                     let role_users = getRoleSectionContents(users: users, role: roleId)
                     
                     if !role_users.isEmpty {
                     Section("\(role.name) - \(role_users.count)") {
                     ForEach(role_users) { u in
                     UserDisplay(server: server,
                     user: u.user,
                     member: u.member,
                     channel: channel)
                     }
                     }
                     .listRowBackground(viewState.theme.background2)
                     } else {
                     EmptyView()
                     }
                     }
                     
                     }*/
                    
                    
                    Section {
                        
                        if self.isFocused, self.search.isEmpty{
                            
                            PeptideText(
                                text: "Search members by name or username.",
                                font: .peptideSubhead,
                                textColor: .textGray07
                            )
                            .padding(.top, .size24)
                            
                        }else if self.isFocused, users.isEmpty {
                            
                            Image(.peptideNotFound)
                                .resizable()
                                .frame(width: .size200, height: .size200)
                                .padding(.top, .size24)
                            
                            PeptideText(text: "Nothing Matches Your Search",
                                        font: .peptideHeadline,
                                        textColor: .textDefaultGray01)
                            .padding(.horizontal, .padding24)
                            
                            PeptideText(text: "Make sure the text is correct or try other terms.",
                                        font: .peptideSubhead,
                                        textColor: .textGray07,
                                        alignment: .center)
                            .padding(.horizontal, .padding24)
                            
                        } else if !no_role.isEmpty {
                            
                            let grouped = groupedUsers(from: no_role)
                            
                            ForEach(["Online", "Offline"], id: \.self) { status in
                                if let usersInGroup = grouped[status], !usersInGroup.isEmpty {
                                    
                                    
                                    HStack(spacing: .zero){
                                        
                                        PeptideText(textVerbatim: "\(status) - \(usersInGroup.count)",
                                                    font: .peptideHeadline,
                                                    textColor: .textDefaultGray01)
                                        
                                        Spacer(minLength: .zero)
                                        
                                    }
                                    .padding(top: .padding16)
                                    .padding(.bottom, .padding8)
                                    
                                    //Section(header: Text(status))
                                    
                                    let firstUserId = usersInGroup.first?.user.id
                                    let lastUserId = usersInGroup.last?.user.id
                                    
                                    
                                    ForEach(usersInGroup) { userMaybeMember in
                                        
                                        let userId = userMaybeMember.user.id
                                        
                                        UserDisplay(server: server,
                                                    user: userMaybeMember.user,
                                                    member: userMaybeMember.member,
                                                    channel: channel,
                                                    withPresence: false
                                        ){
                                            Task {
                                                if(self.channel.isTextChannel){
                                                    await fetchMembers()
                                                }
                                            }
                                        }
                                        .padding(.top, userId == firstUserId ? .padding4 : .zero)
                                        .padding(.bottom, userId == lastUserId ? .padding4 : .zero)
                                        .background{
                                            
                                            UnevenRoundedRectangle(topLeadingRadius: userId == firstUserId ? .radiusMedium : .zero,
                                                                   bottomLeadingRadius: userId == lastUserId ? .radiusMedium : .zero,
                                                                   bottomTrailingRadius: userId == lastUserId ? .radiusMedium : .zero,
                                                                   topTrailingRadius: userId == firstUserId ? .radiusMedium : .zero)
                                            .fill(Color.bgGray12)
                                            
                                        }
                                        
                                        
                                        if userId != lastUserId {
                                            PeptideDivider(backgrounColor: .borderGray11)
                                                .padding(.leading, .size48)
                                                .padding(.vertical, .padding4)
                                                .background(Color.bgGray12)
                                            
                                        }
                                        
                                    }
                                    /*.listRowBackground{
                                     /*RoundedRectangle(cornerRadius: .radiusMedium)
                                      .fill(Color.bgGray12)*/
                                     Color.bgGray12
                                     }*/
                                    
                                    
                                }
                            }
                            
                            /*Section("Members - \(no_role.count)") {
                             ForEach(no_role) { u in
                             UserDisplay(server: server, user: u.user, member: u.member)
                             }
                             }
                             .listRowBackground(viewState.theme.background2)*/
                        }
                        
                    } header: {
                        
                        HStack(spacing: 8){
                            
                            if(self.isFocused){
                                PeptideIconButton(icon: .peptideCloseLiner){
//                                    self.isFocused.toggle()
                                    self.search = ""
                                    self.hideKeyboard()
                                }
                            }
                            
                            PeptideTextField(text: $search,
                                             state: $searchTextFieldState,
                                             placeholder: "Search in \(self.channel.isTextOrVoiceChannel ? "channel" : "group") members",
                                             icon: .peptideSearch,
                                             cornerRadius: .radiusLarge,
                                             height: .size40,
                                             keyboardType: .default){ isFocused in
                                self.isFocused = isFocused
                            }
                            .onChange(of: search){_, newQuery in
                                
                            }
                            .padding(.vertical, .padding8)
                            .background(Color.bgDefaultPurple13)
                        }
                        
                    }
                    
                }
                
                Spacer(minLength: .padding32)
                
            }
            .padding(.horizontal, .padding16)
                                                     
                                                 }
                                                 .task {
                                                     if(self.channel.isTextChannel){
                                                         await fetchMembers()
                                                     }
                                                 }
        
        
        /*.toolbar {
         ToolbarItem(placement: .principal) {
         ChannelIcon(channel: channel)
         }
         }*/
        //.toolbarBackground(viewState.theme.topBar.color, for: .automatic)
        //.background(viewState.theme.background.color)
        .sheet(isPresented: $isPresentedMoreSheet){
            ChannelInfoMoreSheet(isPresented: $isPresentedMoreSheet,
                                 channel: channel,
                                 server: server,
                                 isPresentedNotificationSetting: $isPresentedNotificationSetting,
                                 isPresentedLeaveChannel: $isPresentedLeaveChannel)
        }
        .sheet(isPresented: self.$isPresentedNotificationSetting){
            NotificationSettingSheet(isPresented: $isPresentedNotificationSetting,
                                     channel: self.channel,
                                     server: nil)
        }
        .popup(isPresented: $isPresentedLeaveChannel, view: {
            
            DeleteChannelSheet(isPresented: $isPresentedLeaveChannel, channel: self.channel)
            
        }, customize: {
            $0.type(.default)
                .isOpaque(true)
                .appearFrom(.bottomSlide)
                .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                .closeOnTap(false)
                .closeOnTapOutside(false)
        })
        
        /*.sheet(item: $showInviteSheet) { url in
            ShareInviteSheet(channel: channel, url: url.url)
                .presentationBackground(viewState.theme.background)
        }*/
    }
    
    private func fetchMembers() async {
        
        let response = await viewState.http.fetchServerMembers(target: self.channel.server ?? "", excludeOffline: false)
        
        switch response {
        case .success(let fetchedMembers):
            members = fetchedMembers.members
            
            textChannelMembers = fetchedMembers.users.compactMap{ user in
                let member = fetchedMembers.members.first{ member in member.id.user == user.id}
                return UserMaybeMember(user: user, member: member)
            }
        case .failure(_):
            viewState.showAlert(message: "Failed to load members", icon: .peptideInfo)
        }
    }
}


#Preview {
    
    @Previewable @StateObject var viewState : ViewState = .preview()
    
    ChannelInfo(channel: .constant(viewState.channels["0"]!),
                server: .constant(viewState.servers["0"]))
        .applyPreviewModifiers(withState: viewState)
}


struct KickMemberSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool
    @State private var isLoading: Bool = false

    var user: User
    var member: Member?
    var serverId: String
    var removeUser: () -> Void

    var body: some View {
        VStack(spacing: .size8) {

            Group{

                HStack(spacing: .zero) {
                    Avatar(
                        user: user,
                        member: member,
                        width: 40,
                        height: 40
                    )

                    PeptideIcon(
                        iconName: .peptideSignOutLeave,
                               size: .size24,
                               color: .iconRed07
                    )
                    .padding(.size8)
                    .background(Circle().fill(Color.bgRed07.opacity(0.2)))
                    .offset(x: -8)
                }
                .padding(.bottom, .size16)

                PeptideText(
                    text: "Kick Member?",
                    font: .peptideTitle3,
                    textColor: .textDefaultGray01,
                    alignment: .center
                )
                .padding(.bottom, .size4)

                PeptideText(
                    text: "Are you sure you want to kick \(member?.nickname ?? user.username)?",
                    font: .peptideBody3,
                    textColor: .textGray06,
                    alignment: .center
                )
                .padding(.bottom, .size32)

            }
            .padding(.horizontal, .size24)

            PeptideDivider()
                .padding(.bottom, .size24)

            HStack{

                PeptideButton(
                    title: "Cancel",
                    bgColor: .clear,
                    contentColor: .textDefaultGray01,
                    isFullWidth: false
                ){

                        isPresented.toggle()

                }

                PeptideButton(
                    title: "Kick Member",
                    bgColor: .bgRed07,
                    contentColor: .textDefaultGray01,
                    buttonState: isLoading ? .loading : .default,
                    isFullWidth: false
                ){

                    Task {
                        isLoading = true
                        let result = await viewState.http.kickMember(server: serverId, memberId: user.id)
                        isLoading = false

                        switch result {
                        case .success:
                            viewState.showAlert(message: "\(member?.nickname ?? user.username) has been kicked from the server", icon: .peptideInfo)
                            self.removeUser()
                            isPresented.toggle()
                        case .failure:
                            viewState.showAlert(message: "Failed to kick member", icon: .peptideInfo)
                        }
                    }

                }

            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, .size24)

        }
        .padding(.vertical, .size24)
        .frame(maxWidth: .infinity)
        .background(Color.bgGray11)
        .cornerRadius(.size16)
        .padding(.horizontal, .size16)
    }
}


struct KickMemberSheet_Preview: PreviewProvider {
    @StateObject static var viewState = ViewState.preview()  // Create a preview instance of ViewState

    static var previews: some View {
        VStack{


        }
        .popup(isPresented: .constant(true), view: {
            KickMemberSheet(
                isPresented: .constant(true),
                user: viewState.users["0"]!,
                serverId: ""
            ){
                
            }
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
        .frame(width: .infinity, height: .infinity)
        .applyPreviewModifiers(withState: viewState)  // Apply preview modifiers

    }
}

struct BanMemberSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool
    @State private var isLoading: Bool = false
    @State private var banReason: String = ""

    var user: User
    var member: Member?
    var serverId: String
    var removeUser: () -> Void

    var body: some View {
        VStack(spacing: .size8) {

            Group{
                HStack(spacing: .zero) {
                    Avatar(
                        user: user,
                        member: member,
                        width: 40,
                        height: 40
                    )

                    PeptideIcon(
                        iconName: .peptideBanGlave,
                        size: .size24,
                        color: .iconRed07
                    )
                    .padding(.size8)
                    .background(Circle().fill(Color.bgRed07.opacity(0.2)))
                    .offset(x: -8)
                }
                .padding(.bottom, .size16)

                PeptideText(
                    text: "Ban Member?",
                    font: .peptideTitle3,
                    textColor: .textDefaultGray01,
                    alignment: .center
                )
                .padding(.bottom, .size4)

                PeptideText(
                    text: "Are you sure you want to ban \(member?.nickname ?? user.username)?",
                    font: .peptideBody3,
                    textColor: .textGray06,
                    alignment: .center
                )
                .padding(.bottom, .size32)

                PeptideTextField(
                    text: $banReason,
                    state: .constant(.default),
                    placeholder: "Enter ban reason",
                    forceBackgroundColor: .bgGray12
                )
                .padding(.bottom, .size32)

            }
            .padding(.horizontal, .size24)

            PeptideDivider()
                .padding(.bottom, .size24)

            HStack{
                PeptideButton(
                    title: "Cancel",
                    bgColor: .clear,
                    contentColor: .textDefaultGray01,
                    isFullWidth: false
                ){
                    isPresented.toggle()
                }

                PeptideButton(
                    title: "Ban Member",
                    bgColor: .bgRed07,
                    contentColor: .textDefaultGray01,
                    buttonState: isLoading ? .loading : .default,
                    isFullWidth: false
                ){
                    Task {
                        isLoading = true
                        let result = await viewState.http.banMember(server: serverId, member: user.id, reason: banReason)
                        isLoading = false

                        switch result {
                        case .success:
                            viewState.showAlert(message: "\(member?.nickname ?? user.username) has been banned from the server", icon: .peptideInfo)
                            self.removeUser()
                            isPresented.toggle()
                        case .failure:
                            viewState.showAlert(message: "Failed to ban member", icon: .peptideInfo)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, .size24)
        }
        .padding(.vertical, .size24)
        .frame(maxWidth: .infinity)
        .background(Color.bgGray11)
        .cornerRadius(.size16)
        .padding(.horizontal, .size16)
    }
}

struct BanMemberSheet_Preview: PreviewProvider {
    @StateObject static var viewState = ViewState.preview()

    static var previews: some View {
        VStack{
        }
        .popup(isPresented: .constant(true), view: {
            BanMemberSheet(
                isPresented: .constant(true),
                user: viewState.users["0"]!,
                serverId: ""
            ){
                
            }
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
        .frame(width: .infinity, height: .infinity)
        .applyPreviewModifiers(withState: viewState)
    }
}
