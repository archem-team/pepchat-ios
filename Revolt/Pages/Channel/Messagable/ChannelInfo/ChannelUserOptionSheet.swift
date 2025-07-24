//
//  ChannelUserOptionSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct ChannelUserOptionSheet: View {
    
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented : Bool
    @State private var sheetHeight: CGFloat = .zero
    
    
    var user: User
    var member: Member?
    
    var channel : Channel
    var server : Server?
    var onTransferOwnershipTap: () -> Void
    var onKickTap: () -> Void
    var onBanTap: () -> Void
    
    var serverPermissions: Permissions{
        if let server = server, let currentUser = viewState.currentUser, let member =  viewState.members[server.id]?[currentUser.id]{
            return resolveServerPermissions(user: currentUser, member: member, server: server)
        }
        
        return .none
    }

    
    var body: some View {
        
        VStack(spacing: .spacing24){
            
            PeptideUserAvatar(user: user,
                              member: member)
            .padding(top: .padding16, bottom: .padding8)
            
            VStack(spacing: .spacing4){
                
                Button {
                    viewState.openUserSheet(user: user, member: member)
                    isPresented.toggle()
                } label: {
                    
                    PeptideActionButton(icon: .peptideProfileIdCard,
                                        title: "View Profile",
                                        hasArrow: false)
                }
                
                
                
                PeptideDivider()
                    .padding(.leading, .padding48)
                
                Button {
                    self.viewState.mentionedUser = self.user.id
                    self.isPresented.toggle()
                    self.viewState.path.removeLast()
                } label: {
                    PeptideActionButton(icon: .peptideAt,
                                        title:  "Mention",
                                        hasArrow: false)
                }
                
                PeptideDivider()
                    .padding(.leading, .padding48)
                
                Button {
                    let id = member?.id.user ?? user.id
                    copyText(text: id)
                    viewState.showAlert(message: "User ID Copied!", icon: .peptideCopy)
                } label: {
                    PeptideActionButton(icon: .peptideCopy,
                                        title: "Copy User ID",
                                        hasArrow: false)
                }
                
                
            }
            .backgroundGray11(verticalPadding: .padding4)
            
            if case .text_channel(let channel) = channel {
            
                let showKick = serverPermissions.contains(.kickMembers)
                let showBan = serverPermissions.contains(.banMembers)
                
                VStack(spacing: .spacing4){
                    
                    if(showKick){
                    
                        Button {
                            self.onKickTap()
                        } label: {
                            
                            PeptideActionButton(
                                icon: .peptideSignOutLeave,
                                iconColor: .iconRed07,
                                title: "Kick",
                                titleColor: .textRed07,
                                hasArrow: false
                            )
                        }
                        
                    }
                    
                    if (showKick && showBan){
                        PeptideDivider()
                            .padding(.leading, .padding48)
                    }
                    
                    if(showBan){
                    
                        Button {
                            self.onBanTap()
                        } label: {
                            PeptideActionButton(
                                icon: .peptideBanGlave,
                                iconColor: .iconRed07,
                                                title:  "Ban",
                                titleColor: .textRed07,
                                                hasArrow: false
                            )
                        }
                        
                    }
                    
                }
                .backgroundGray11(verticalPadding: .padding4)
                    
            }
            
            
            if let currentUser = viewState.currentUser,
               case .group_dm_channel(_) = channel,
               resolveChannelPermissions(from: currentUser,
                                         targettingUser: currentUser,
                                         targettingMember: member,
                                         channel: channel,
                                         server: server).contains(.kickMembers) {
                
                VStack(spacing: .spacing4) {
                    
                    let id = member?.id.user ?? user.id
                    
                    Button {
                        Task {
                            let result = await viewState.http.removeMemberFromGroup(groupId: channel.id, memberId: id)
                            switch result{
                            case .success(_):
                                self.isPresented = false
                                self.viewState.path.removeLast()
                            case .failure(_):
                                self.viewState.showAlert(message: "Somthing went wrong!", icon: .peptideInfo2)
                                
                            }
                            
                            debugPrint("Remove Member Result: \(result)")
                        }
                    } label: {
                        PeptideActionButton(
                            icon: .peptideSignOutLeave,
                            iconColor: .iconRed07,
                            title: "Remove From Group",
                            titleColor: .textRed07,
                            hasArrow: false
                        )
                    }
                    
                    PeptideDivider().padding(.leading, .padding48)
                    
                    Button {
                        self.onTransferOwnershipTap()
                    } label: {
                        PeptideActionButton(
                            icon: .peptideAdminKing,
                            iconColor: .iconRed07,
                            title: "Transfer Group Ownership",
                            titleColor: .textRed07,
                            hasArrow: false
                        )
                    }
                    
                }
                .backgroundGray11(verticalPadding: .padding4)
            }
            
            
            //options for text channel

            
        }
        .padding(top: .padding8,
                 bottom: .padding8,
                 leading: .padding16,
                 trailing: .padding16)
        .overlay {
            GeometryReader { geometry in
                Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
            sheetHeight = newHeight
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.bottom)
    }
    
    
   
}

#Preview {
    
    let viewState = ViewState.preview().applySystemScheme(theme: .dark)
    
    
    
    ChannelUserOptionSheet(isPresented: .constant(false),
                           user: viewState.users["0"]!,
                           member: viewState.members["0"]?["a"],
                           channel: viewState.channels["0"]!,
                           onTransferOwnershipTap: {},
                           onKickTap: {},
                           onBanTap: {})
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)

}
