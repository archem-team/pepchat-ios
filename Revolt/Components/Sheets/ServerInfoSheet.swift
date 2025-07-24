//
//  ServerInfoSheet.swift
//  Revolt
//
//  Created by Angelo on 08/07/2024.
//

import SwiftUI
import Types
import PopupView
/// A view that displays information about a server, including settings and options to leave or copy the server ID.


//Task {
//    await self.viewState.getServerMemers(target: elem.value.id)
//}

struct ServerInfoSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Environment(\.dismiss) var dismiss
    
    
    @Binding var isPresentedServerSheet: Bool

    
    @State var showLeaveServerDialog: Bool = false
    
    var server: Server
    
    @State private var isPresentedInviteSheet : Bool = false    
    @State var inviteSheetUrl: InviteUrl? = nil
    
    @State private var isPresentedNotificationSetting : Bool = false
    @State private var isPresentedServerDelete: Bool = false
    @State private var isPresentedIdentitSheet: Bool = false
    @State private var serverMembersCount : String? = nil
    
    var onNavigation : (ServerInfoRouteType, String) -> Void
    
    var serverPermissions: Permissions{
                
        if let currentUser = viewState.currentUser{
            
            if let member =  viewState.members[server.id]?[currentUser.id] {
                return resolveServerPermissions(user: currentUser, member: member, server: server)
            } else if currentUser.id == server.owner {
                return .all
            }
        }
        
        return .none
    }

    var body: some View {
        
        let _ = inviteSheetUrl
        
        ZStack {
            
            VStack(alignment: .leading, spacing: .zero) {
                headerView
                   //ServerBadges(value: server.flags)

                    ScrollView(.vertical) {
                        contentView
                    }
                    .scrollContentBackground(.hidden)
                    .scrollBounceBehavior(.basedOnSize, axes: [.vertical])
                
                
                Spacer(minLength: .zero)
                
            }
            .background(.bgDefaultPurple13)
        }
        .task {
            await getMembersCount()
        }
        .sheet(isPresented: $isPresentedInviteSheet) {
            if let inviteSheetUrl {
                ShareInviteSheet(isPresented: $isPresentedInviteSheet, url: inviteSheetUrl.url)
            }
        }
        .sheet(isPresented: self.$isPresentedNotificationSetting){
                NotificationSettingSheet(isPresented: $isPresentedNotificationSetting,
                                         channel: nil,
                                         server: server)
            
           
        }
        .sheet(isPresented: $isPresentedIdentitSheet){
            if let member = viewState.getMember(byServerId: server.id, userId: viewState.currentUser!.id){
                //let userMaybeMember = UserMaybeMember(user: viewState.currentUser!, member: member)
                
                if(member.avatar == nil && viewState.currentUser!.avatar != nil){
                    
                    IdentitySheet.fromState(isPresented: $isPresentedIdentitSheet, server: server, user: viewState.currentUser!, member: member.copyWithAvatar(newAvatar: viewState.currentUser!.avatar!))
                }else {
                    IdentitySheet.fromState(isPresented: $isPresentedIdentitSheet, server: server, user: viewState.currentUser! , member: member)
                }
            }
            
        }
        .popup(isPresented: $isPresentedServerDelete, view: {
            DeleteServerSheet(isPresented: $isPresentedServerDelete,
                              isPresentedServerSheet: $isPresentedServerSheet,
                              server: self.server,
                              isOwner: viewState.isCurrentUserOwner(of: self.server.id))
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
          
        
    }
    
    private func getMembersCount() async {
        
        Task{
            
            let serverMembers = await self.viewState.http.fetchServerMembers(target: server.id)
            switch serverMembers {
            case .success(let success):
                serverMembersCount = success.members.count.formattedWithSeparator()
            case .failure(_):
                serverMembersCount = nil
            }
            
        }
        
    }

    // MARK: - Header View
    private var headerView: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: .zero) {
                if let banner = server.banner {
                    
                    Color.clear
                        .overlay {
                            LazyImage(source: .file(banner),
                                      height: 130,
                                      clipTo: UnevenRoundedRectangle(topLeadingRadius: .radiusMedium, topTrailingRadius: .radiusMedium))
                        }
                        .frame(height: 130)
                        .clipped()
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: .radiusMedium, topTrailingRadius: .radiusMedium))
                    
                    
                   
                } else {
                    UnevenRoundedRectangle(topLeadingRadius: .radiusMedium, topTrailingRadius: .radiusMedium)
                        .fill(Color.bgGray11)
                        .frame(height: 130)
                }
                RoundedRectangle(cornerRadius: .zero)
                    .fill(Color.bgDefaultPurple13)
                    .frame(height: .size32)
            }
            ServerIcon(server: server, height: 64, width: 64, clipTo: Rectangle())
                .addBorder(.bgDefaultPurple13, width: .size4, cornerRadius: .radiusMedium)
                .padding(.horizontal, .padding16)
        }
    }

    // MARK: - Content View
    private var contentView: some View {
        LazyVStack(alignment: .leading, spacing: .zero) {
            serverInfoSection
            
            identitySection

            PeptideDivider(size: .size4, backgrounColor: .bgGray11)
                .padding(top: .padding20, bottom: .padding24)

            actionsSection
            
            serverSettingsSection
            customizationSection
            userManagementSection
            deleteServerButton
        }
    }

    // MARK: - Sections
    private var serverInfoSection: some View {
        Group {
            HStack(spacing: .zero) {
                PeptideText(textVerbatim: server.name,
                            font: .peptideTitle4,
                            textColor: .textDefaultGray01,
                            lineLimit: 1)
                Spacer(minLength: .zero)
            }
            .padding(.top, .padding16)
            
            HStack(spacing: .spacing2) {
                PeptideIcon(iconName: .peptideTeamUsers,
                            size: .size16,
                            color: .iconGray07)
                PeptideText(textVerbatim: "\(serverMembersCount ?? "---") members",
                            font: .peptideBody4,
                            textColor: .textGray07,
                            lineLimit: 1)
                Spacer(minLength: .zero)
            }
            .padding(top: .spacing2, bottom: .padding16)
        }
        .padding(.horizontal, .padding16)

    }

    private var identitySection: some View {
        

        Group {
            
            let member = viewState.getMember(byServerId: server.id, userId: viewState.currentUser!.id)
            let currentUser = viewState.currentUser

            PeptideText(text: "Your identity on this server",
                        font: .peptideCallout,
                        textColor: .textGray07)
            HStack(spacing: .padding4) {
                Avatar(user: viewState.currentUser!,
                       member: member,
                       width: .size32,
                       height: .size32)
                PeptideText(text: member?.nickname ??  currentUser?.display_name ?? currentUser?.username,
                            font: .peptideTitle4,
                            textColor: .textDefaultGray01,
                            lineLimit: 1)
                
                Spacer(minLength: .zero)
                
                PeptideButton(buttonType: .small(),
                              title: "Edit",
                              bgColor: .bgGray11,
                              contentColor: .textDefaultGray01,
                              isFullWidth: false) {
                    self.isPresentedIdentitSheet.toggle()
                }
            }
            .padding(.padding8)
            .background {
                RoundedRectangle(cornerRadius: .radiusXSmall)
                    .strokeBorder(Color.borderGray11, lineWidth: .size1)
            }
            .padding(.top, .padding8)
        }
        .padding(.horizontal, .padding16)

    }

    private var actionsSection: some View {
        HStack(spacing: .zero) {
            
            let isCurrentUserOwner = self.viewState.isCurrentUserOwner(of: server.id)

            
            PeptideIconWithTitleButton(icon: .peptideNewGroup, title: "Invite") {
                createInvite()
            }
            
            PeptideIconWithTitleButton(icon: .peptideNotificationOn, title: "Notification") {
                self.isPresentedNotificationSetting.toggle()
            }
            
            if !isCurrentUserOwner {
                
                PeptideIconWithTitleButton(icon: .peptideSignOutLeave,
                                           title: "Leave",
                                           iconColor: .iconRed07,
                                           titleColor: .textRed07){
                    
                    self.isPresentedServerDelete.toggle()
                }
                
            }
                
                if !isCurrentUserOwner {
                    PeptideIconWithTitleButton(icon: .peptideReportFlag,
                                               title: "Report",
                                               iconColor: .iconRed07,
                                               titleColor: .textRed07){
                        self.viewState.path.append(NavigationDestination.report(nil, server.id, nil))
                        self.isPresentedServerSheet.toggle()
                    }
                }
            
        }
        .padding(.horizontal, .padding16)
    }

    @ViewBuilder
    private var serverSettingsSection: some View {
        
        if serverPermissions.contains(.manageServer) || serverPermissions.contains(.manageChannel) || serverPermissions.contains(.manageRole) {
            
            section(title: "Server Setting") {
                
                
                if serverPermissions.contains(.manageServer) {
                    Button {
                        dismiss()
                        onNavigation(.overview,server.id)
                    } label: {
                        PeptideActionButton(icon: .peptideInfo2, title: "Overview", hasArrow: true)
                    }
                    
                    if serverPermissions.contains(.manageChannel) || serverPermissions.contains(.manageRole) {
                        PeptideDivider().padding(.leading, .padding48)
                    }
                    
                }
                
                
                

                
                if serverPermissions.contains(.manageChannel){
                    
                    Button {
                        dismiss()
                        onNavigation(.channels,server.id)
                    } label: {
                        PeptideActionButton(icon: .peptideList, title: "Channels", hasArrow: true)
                    }
                    
                    if serverPermissions.contains(.manageRole) {
                        PeptideDivider().padding(.leading, .padding48)
                    }
                    
                }
                

                
                if serverPermissions.contains(.manageRole){
                    
                    Button {
                        viewState.path.append(NavigationDestination.server_role_setting(server.id))
                        dismiss()
                    } label: {
                        PeptideActionButton(icon: .peptideRoleIdCard, title: "Roles", hasArrow: true)
                    }
                }
                
               
            }

        }
        
    }

    @ViewBuilder
    private var customizationSection: some View {
        
        if serverPermissions.contains(.manageCustomisation){
            
            section(title: "Customization") {
                
                Button {
                    dismiss()
                    onNavigation(.emojis, server.id)
                } label: {
                    PeptideActionButton(icon: .peptideSmile, title: "Emojis", hasArrow: true)
                }
            }
        }
        
    }

    private var userManagementSection: some View {
        section(title: "User Management") {
            Button {
                dismiss()
                onNavigation(.members, server.id)
            } label: {
                PeptideActionButton(icon: .peptideTeamUsers, title: "Members", hasArrow: true)
            }
            
            if(serverPermissions.contains(.inviteOthers)){
                
                PeptideDivider().padding(.leading, .padding48)
                
                Button {
                    dismiss()
                    onNavigation(.invite, server.id)
                } label: {
                    PeptideActionButton(icon: .peptideMail, title: "Invites", hasArrow: true)
                }
            }
            
            if serverPermissions.contains(.banMembers){
            
                PeptideDivider().padding(.leading, .padding48)
                
                Button {
                    dismiss()
                    onNavigation(.banned, server.id)
                } label: {
                    PeptideActionButton(icon: .peptideCancelFriendRequest, title: "Banned Users", hasArrow: true)
                }
            }
        }
    }

    @ViewBuilder
    private var deleteServerButton: some View {
        let canDeleteServer = viewState.isCurrentUserOwner(of: server.id) || serverPermissions.contains(.manageServer)
        
        if canDeleteServer {
            Button {
                self.isPresentedServerDelete.toggle()
            } label: {
                PeptideActionButton(icon: .peptideTrashDelete,
                                    iconColor: .iconRed07,
                                    title: "Delete Server",
                                    titleColor: .textRed07,
                                    hasArrow: true)
            }
            .backgroundGray11(verticalPadding: .padding4, hasBorder: false)
            .padding(.top, .padding24)
            .padding(.horizontal, .padding16)
        }
    }

    // MARK: - Helpers
    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        Group {
            PeptideText(text: title, font: .peptideHeadline)
                .padding(top: .padding24, bottom: .padding8)
            VStack(spacing: .spacing4) {
                content()
            }
            .backgroundGray11(verticalPadding: .padding4, hasBorder: false)
        }
        .padding(.horizontal, .padding16)

    }
    
    func createInvite() {
        
        if let channelId = findFirstTextChannelID() {
            Task {
                let res = await viewState.http.createInvite(channel: channelId)
                
                if case .success(let invite) = res {
                    inviteSheetUrl = InviteUrl(url: URL(string: "https://peptide.chat/invite/\(invite.id)")!)
                    isPresentedInviteSheet.toggle()
                }
            }
        }
        
    }
    
    func findFirstTextChannelID() -> String? {
        guard let server = viewState.servers[self.server.id] else {
            return nil
        }
        
        for channelID in server.channels {
            if let channel = viewState.channels[channelID], case .text_channel(_) = channel {
                return channelID
            }
        }
        
        return nil
    }
    
}


enum ServerInfoSheetType {
    case all
    case limited
}

enum ServerInfoRouteType {
    case overview
    case channels
    case roles
    case emojis
    case members
    case invite
    case banned
}


#Preview {
    @Previewable @StateObject var viewState = ViewState.preview()
    ServerInfoSheet(isPresentedServerSheet: .constant(true), server: viewState.servers["0"]!, onNavigation: {route, serverId in
    })
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}


#Preview {
    @Previewable @StateObject var viewState = ViewState.preview()
    ServerInfoSheet(isPresentedServerSheet: .constant(true), server: viewState.servers["0"]!,  onNavigation: {route, serverId in
    })
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
