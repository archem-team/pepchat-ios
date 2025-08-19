//
//  ChannelSettings.swift
//  Revolt
//
//  Created by Angelo on 08/01/2024.
//

import Foundation
import SwiftUI
import Types

/// A view that allows users to manage settings for a specific channel within a server.
struct ChannelSettings: View {
    /// The environment object that holds the current state of the application.
    @EnvironmentObject var viewState: ViewState
    
    /// A binding to the server to which the channel belongs.
    @Binding var server: Server?
    
    /// A binding to the channel whose settings are being managed.
    @Binding var channel: Channel
    
    
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
    
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Group Settings",
                                                 showBottomLine: true)){_,_ in
            VStack(spacing: .zero) {
                
                
                ChannelOnlyIcon(channel: self.channel,
                                initialSize: (24,24),
                                frameSize: (48,48))
                .padding(.top, .padding24)
                
                
                PeptideText(textVerbatim: "\(self.channel.getName(self.viewState))",
                            font: .peptideTitle3,
                            textColor: .textDefaultGray01)
                .padding(.top, .padding16)
                
                if case .group_dm_channel(let group) = channel {
                    
                    PeptideText(text: "\(group.recipients.count) Members",
                                font: .peptideSubhead,
                                textColor: .textGray07)
                    .padding(.top, .padding4)
                }
                
                Spacer()
                    .frame(height: .padding16)
                
                if channelPermission.contains(.manageChannel){
                    // Navigation link to the overview settings of the channel.
                    Button {
                        self.viewState.path.append(NavigationDestination.channel_overview_setting(channel.id, nil))
                    } label: {
                        PeptideActionButton(icon: .peptideEdit,
                                            title: "Customize Group")
                        .frame(minHeight: .size56)
                        .background{
                            RoundedRectangle(cornerRadius: .radiusMedium).fill(Color.bgGray11)
                                .overlay{
                                    RoundedRectangle(cornerRadius: .radiusMedium)
                                        .stroke(.borderGray10, lineWidth: .size1)
                                }
                        }
                    }
                    .padding(.top, .padding16)
                }
                   
                
                // Members button for group channels
                if case .group_dm_channel(_) = channel {
                    Button {
                        self.viewState.path.append(NavigationDestination.channel_info(channel.id, server?.id))
                    } label: {
                        PeptideActionButton(icon: .peptideUsers,
                                            title: "Members")
                        .frame(minHeight: .size56)
                        .background{
                            RoundedRectangle(cornerRadius: .radiusMedium).fill(Color.bgGray11)
                                .overlay{
                                    RoundedRectangle(cornerRadius: .radiusMedium)
                                        .stroke(.borderGray10, lineWidth: .size1)
                                }
                        }
                    }
                    .padding(.top, .padding16)
                }
                
                if channelPermission.contains(.managePermissions){
                    Button{
                        self.viewState.path.append(NavigationDestination.channel_permissions_settings(serverId: server?.id, channelId: channel.id))
                    } label: {
                        PeptideActionButton(icon: .peptidePermissionsRoles,
                                            title: "Permissions")
                        .frame(minHeight: .size56)
                        .background{
                            RoundedRectangle(cornerRadius: .radiusMedium).fill(Color.bgGray11)
                                .overlay{
                                    RoundedRectangle(cornerRadius: .radiusMedium)
                                        .stroke(.borderGray10, lineWidth: .size1)
                                }
                        }
                    }
                    .padding(.top, .padding16)
                }
                
                // Button to delete the channel.
                /*Button {
                 // Action to delete the channel (to be implemented).
                 } label: {
                 HStack {
                 Image(systemName: "trash.fill") // Trash icon.
                 Text("Delete channel") // Text label for deletion.
                 }
                 }*/
                
                Spacer(minLength: .zero)
            }
            .padding(.horizontal, .padding16)
            
        }
        
        
        
    }
}

#Preview {
    // Preview setup for the ChannelSettings view.
    @Previewable @StateObject var viewState = ViewState.preview().applySystemScheme(theme: .dark)
    let channel = Binding($viewState.channels["0"])! // Binding for the channel.
    let server = $viewState.servers["0"] // Binding for the server.
    
    return NavigationStack {
        // Return the ChannelSettings view within a navigation stack.
        ChannelSettings(server: server, channel: channel)
        
    }.applyPreviewModifiers(withState: viewState)
}
