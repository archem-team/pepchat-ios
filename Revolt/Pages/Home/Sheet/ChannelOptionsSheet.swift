//
//  ChannelOptionsSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct ChannelOptionsSheet: View {
    
    @EnvironmentObject var viewState: ViewState
    
    @State private var selectedUserForCloseDm: User?
    @State private var selecteCchannelForCloseDm: DMChannel?
    @State private var showCloseDmSheet: Bool = false
    
    @Binding var isPresented: Bool
    var channel: Channel
    var server : Server? = nil
    var onClick: (ChannelOptionsSheetType) -> Void
    
    
    private var channelPermission: Permissions {
        guard let currentUser = viewState.currentUser else {
            return .none
        }
        
        return resolveChannelPermissions(
            from: currentUser,
            targettingUser: currentUser,
            targettingMember: server.flatMap { viewState.members[$0.id]?[currentUser.id] },
            channel: channel,
            server: server
        )
    }
    
    // Single grouped list with sections
    private let dmChannelItems: [(section: String, items: [PeptideSheetItem])] = [
        (
            section: "First Section",
            items: [
                .init(index: 1, title: "View Profile", icon: .peptideProfileIdCard),
                .init(index: 2, title: "Message", icon: .peptideMessage),
                .init(index: 3, title: "Notification Options", icon: .peptideNotificationOn),
                .init(index: 4, title: "Copy Direct Message ID", icon: .peptideCopy, isLastItem: true)
            ]
        ),
        (
            section: "Second Section",
            items: [
                .init(index: 5, title: "Close DM", icon: .peptideRemoveUser),
                .init(index: 6, title: "Report User", icon: .peptideReportFlag, isLastItem: true)
            ]
        )
    ]
    
    var body: some View {
        
        let _ = self.selectedUserForCloseDm;
        let _ = self.selecteCchannelForCloseDm;
        
        PeptideSheet(isPresented: $isPresented, topPadding: .padding24) {
            
            if case .dm_channel(let channel) = channel {
                
                if let recipient = viewState.getDMPartnerName(channel: channel) {
                    
                    PeptideUserAvatar(user: recipient,
                                      member: nil,
                                      usernameStyle: .peptideFootnote)
                    .padding(.bottom, .padding24)
                    
                    // First Section
                    if let firstSection = dmChannelItems.first(where: { $0.section == "First Section" }) {
                        VStack(spacing: .spacing4) {
                            ForEach(firstSection.items, id: \.index) { item in
                                Button {
                                    handleAction(for: item, recipient: recipient, channel: channel)
                                    isPresented.toggle()
                                } label: {
                                    PeptideActionButton(icon: item.icon,
                                                        title: item.title,
                                                        hasArrow: false)
                                }
                                
                                if !item.isLastItem {
                                    PeptideDivider()
                                        .padding(.leading, .padding48)
                                }
                            }
                        }
                        .backgroundGray11(verticalPadding: .padding4)
                        .padding(.bottom, .padding24)
                    }
                    
                    // Second Section
                    if let secondSection = dmChannelItems.first(where: { $0.section == "Second Section" }) {
                        VStack(spacing: .spacing4) {
                            ForEach(secondSection.items, id: \.index) { item in
                                Button {
                                    handleAction(for: item, recipient: recipient, channel: channel)
                                } label: {
                                    PeptideActionButton(
                                        icon: item.icon,
                                        iconColor: .iconRed07,
                                        title: item.title,
                                        titleColor: .textRed07,
                                        hasArrow: false
                                    )
                                }
                                
                                if !item.isLastItem {
                                    PeptideDivider()
                                        .padding(.leading, .padding48)
                                }
                            }
                        }
                        .backgroundGray11(verticalPadding: .padding4)
                    }
                }
            }
            
            else if case .group_dm_channel(let channel) = channel{
                
                HStack(spacing: .spacing8){
                    
                    ChannelOnlyIcon(channel: self.channel)
                    
                    
                    VStack(alignment : .leading, spacing: .zero){
                        PeptideText(text: channel.name,
                                    font: .peptideCallout,
                                    textColor: .textDefaultGray01)
                        
                        PeptideText(text: "\(channel.recipients.count) Members",
                                    font: .peptideCaption1,
                                    textColor: .textGray07)
                    }
                    
                    Spacer(minLength: .zero)
                }
                .padding(.bottom, .padding8)
                
                if let _ = viewState.getUnreadCountFor(channel: self.channel) {
                    Button {
                        
                        Task{
                            
                            if let lastId = viewState.channels[self.channel.id]?.last_message_id {
                                let _ = await viewState.http.ackMessage(channel: self.channel.id, message: lastId)
                                
                                self.isPresented.toggle()
                            }
                        }
                        
                    } label: {
                        
                        PeptideActionButton(icon: .peptideEye,
                                            title: "Mark as Read",
                                            hasArrow: false)
                        .backgroundGray11(verticalPadding: .padding4)
                        
                    }
                    .padding(.top, .padding24)
                }
                
                
                Button {
                    onClick(.copyGroupId(channelId: self.channel.id))
                    self.isPresented.toggle()
                } label: {
                    
                    PeptideActionButton(icon: .peptideCopy,
                                        title: "Copy Group ID",
                                        hasArrow: false)
                    .backgroundGray11(verticalPadding: .padding4)
                    
                }
                .padding(.top, .padding24)
                
                
                VStack(spacing: .spacing4) {
                    Button {
                        onClick(.notificationOptions)
                        isPresented.toggle()
                    } label: {
                        PeptideActionButton(
                            icon: .peptideNotificationOn,
                            title: "Notification Options",
                            hasArrow: false
                        )
                    }
                    
                    
                    if channelPermission.contains(.manageChannel){
                        PeptideDivider()
                            .padding(.leading, .padding48)
                        
                        Button {
                            onClick(.groupSetting(channelId: self.channel.id))
                            isPresented.toggle()
                        } label: {
                            PeptideActionButton(
                                icon: .peptideSetting,
                                title: "Group Setting",
                                hasArrow: false
                            )
                        }
                    }
                
                }
                .backgroundGray11(verticalPadding: .padding4)
                .padding(.top, .padding24)
                
                Button {
                    
                    onClick(.closeDMGroup(channel: channel))
                } label: {
                    
                    PeptideActionButton(icon: .peptideSignOutLeave,
                                        iconColor: .iconRed07,
                                        title: "Leave Group",
                                        titleColor: .textRed07,
                                        hasArrow: false)
                    .backgroundGray11(verticalPadding: .padding4)
                    
                }
                .padding(.top, .padding24)
                
                
            }
            else if case .text_channel(let textChannel) = channel {
                HStack(spacing: .spacing8){
                    
                    ChannelOnlyIcon(channel: self.channel)
                    
                    
                    PeptideText(text: "#\(textChannel.name)",
                                font: .peptideCallout,
                                textColor: .textDefaultGray01)
                    
                    Spacer(minLength: .zero)
                }
                .padding(.bottom, .padding8)
                
                
                if let unreadCount = viewState.getUnreadCountFor(channel: self.channel) {
                    switch unreadCount {
                    case .unread, .unreadWithMentions:
                        
                        
                        VStack(spacing: .spacing4) {
                            Button {
                                Task{
                                    
                                    if let lastId = viewState.channels[self.channel.id]?.last_message_id {
                                        let _ = await viewState.http.ackMessage(channel: self.channel.id, message: lastId)
                                    }
                                }
                            } label: {
                                PeptideActionButton(icon: .peptideEye,
                                                    title: "Mark as Read",
                                                    hasArrow: false)
                            }
                            
                            
                            PeptideDivider()
                                .padding(.leading, .padding48)
                            
                            
                            Button {
                                onClick(.notificationOptions)
                                isPresented.toggle()
                            } label: {
                                PeptideActionButton(
                                    icon: .peptideNotificationOn,
                                    title: "Notification Options",
                                    hasArrow: false)
                            }
                            
                            
                        }
                        .backgroundGray11(verticalPadding: .padding4)
                        .padding(.top, .padding24)
                        
                        
                    default:
                        EmptyView()
                    }
                } else {
                    Button {
                        onClick(.notificationOptions)
                        isPresented.toggle()
                    } label: {
                        
                        PeptideActionButton(
                            icon: .peptideNotificationOn,
                            title: "Notification Options",
                            hasArrow: false)
                        .backgroundGray11(verticalPadding: .padding4)
                        
                    }
                    .padding(.top, .padding24)
                }
                
                
                VStack(spacing: .spacing4) {
                    Button {
                        onClick(.invite)
                        isPresented.toggle()
                    } label: {
                        PeptideActionButton(
                            icon: .peptideNewUser,
                            title: "Invite",
                            hasArrow: false
                        )
                    }
                    
                    PeptideDivider()
                        .padding(.leading, .padding48)
                    
                    
                    Button {
                        onClick(.copyGroupId(channelId: textChannel.name))
                        isPresented.toggle()
                    } label: {
                        PeptideActionButton(
                            icon: .peptideCopy,
                            title: "Copy Channel ID",
                            hasArrow: false
                        )
                    }
                    
                    
                }
                .backgroundGray11(verticalPadding: .padding4)
                .padding(.top, .padding24)
                
                
                
                VStack(spacing: .spacing4) {
                    
                    
                    if channelPermission.contains(.manageChannel){
                        
                        Button {
                            onClick(.channelOverview)
                            isPresented.toggle()
                        } label: {
                            PeptideActionButton(
                                icon: .peptideInfo,
                                title: "Channel Overview",
                                hasArrow: false
                            )
                        }
                        
                     
                    }
                    
                    if channelPermission.contains(.manageChannel) && channelPermission.contains(.managePermissions){
                        PeptideDivider()
                            .padding(.leading, .padding48)
                    }
                    
                    if channelPermission.contains(.managePermissions){
                        
                        Button {
                            
                            if let serverId = self.channel.server{
                                
                                onClick(.groupPermissionsSetting(channelId: self.channel.id, serverId: serverId))
                                isPresented.toggle()
                                
                            }
                            
                        } label: {
                            PeptideActionButton(
                                icon: .peptideSetting,
                                title: "Permissions",
                                hasArrow: false
                            )
                        }
                        
                    }
                    
                }
                .backgroundGray11(verticalPadding: .padding4)
                .padding(.top, .padding24)
                
                let isOwner = viewState.isCurrentUserOwner(of: server?.id ?? "")
                
                if(isOwner){
                    
                    
                    Button {
                        
                        onClick(.closeDM(channelId: channel.id))
                        
                    } label: {
                        
                        PeptideActionButton(icon: .peptideTrashDelete,
                                            iconColor: .iconRed07,
                                            title: "Delete Channel",
                                            titleColor: .textRed07,
                                            hasArrow: false)
                        .backgroundGray11(verticalPadding: .padding4)
                        
                    }
                    .padding(.top, .padding24)
                    
                }
                
            }
        }
        .popup(
            isPresented: $showCloseDmSheet,
            view: {
                
                ConfirmationSheet(
                    isPresented: $showCloseDmSheet,
                    isLoading: .constant(false),
                    title: "Close Conversation with \(self.selectedUserForCloseDm?.displayName() ?? "")?",
                    subTitle: "You can re-open it later but it will disappear on both sides.",
                    confirmText: "Close DM",
                    dismissText: "Cancel",
                    showCloseButton: true
                ){
                    onClick(.closeDM(channelId: channel.id))
                    isPresented.toggle()
                }
                
            },
            customize: {
                $0.type(.default)
                    .isOpaque(true)
                    .appearFrom(.bottomSlide)
                    .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                    .closeOnTap(false)
                    .closeOnTapOutside(false)
            })
    }
    
    private func showCloseDmSheet (user: User, channel: DMChannel){
        self.selectedUserForCloseDm = user
        self.selecteCchannelForCloseDm = channel
        self.showCloseDmSheet.toggle()
        
    }
    
    private func handleAction(for item: PeptideSheetItem, recipient: User, channel: DMChannel) {
        
        if(item.index != 5){
            isPresented.toggle()
        }
        
        switch item.index {
        case 1:
            onClick(.viewProfile(user: recipient, member: nil))
        case 2:
            onClick(.message(user: recipient))
        case 3:
            onClick(.notificationOptions)
        case 4:
            onClick(.copyDirectMessageId(channelId: channel.id))
        case 5:
            self.showCloseDmSheet(user: recipient, channel: channel)
        case 6:
            onClick(.reportUser(user: recipient))
        default:
            break
        }
    }
}



enum ChannelOptionsSheetType{
    case viewProfile(user: User, member : Member?)
    case message(user: User)
    case notificationOptions
    case copyDirectMessageId(channelId : String)
    case closeDM(channelId : String)
    case closeDMGroup(channel : GroupDMChannel)
    case reportUser(user: User)
    
    case copyGroupId(channelId : String)
    case groupSetting(channelId : String)
    case groupPermissionsSetting(channelId : String, serverId : String)
    case invite
    case channelOverview
    
}

#Preview {
    
    @Previewable @StateObject var viewState  = ViewState.preview()
    
    ChannelOptionsSheet(isPresented: .constant(false), channel: viewState.channels["0"]!, onClick: { _ in
    })
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
