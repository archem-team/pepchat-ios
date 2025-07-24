//
//  ChannelPermissionsSettings.swift
//  Revolt
//
//  Created by Angelo on 25/09/2024.
//

import Foundation
import SwiftUI
import Types

/// A view that manages the permission settings for a specific channel within a server.
struct ChannelPermissionsSettings: View {
    /// The environment object that holds the current application state.
    @EnvironmentObject var viewState: ViewState
    
    /// A binding to the server where the channel exists.
    @Binding var server: Server?
    
    /// A binding to the channel whose permissions are being managed.
    @Binding var channel: Channel
    
    @State private var permissions : Permissions = .defaultGroupDirectMessages
    
    @State var showSaveButton: Bool = false
    @State var saveBtnState : ComponentState = .default
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                //TODO:
                
                self.saveBtnState = .loading
                
                Task {
                    let response = await viewState.http.setDefaultPermission(target: self.channel.id, permissions: self.permissions)
                    
                    self.saveBtnState = .default
                    
                    switch response {
                    case .success(_):
                        //TODO update channel settin from socket
                        self.viewState.showAlert(message: "Group Permissions Updated!", icon: .peptideDone)
                        self.viewState.path.removeLast()
                    case .failure(let failure):
                        debugPrint("error \(failure)")
                    }
                }
                
                
            } label: {
                
                
                Group {
                    if saveBtnState == .loading {
                        
                        ProgressView()
                        
                    } else {
                        
                        
                        PeptideText(text: "Save",
                                    font: .peptideButton,
                                    textColor: .textYellow07,
                                    alignment: .center)
                        
                    }
                    
                }
                .opacity(showSaveButton ? 1 : 0)
                .disabled(!showSaveButton)
                
            }
            
            
        )
    }
    
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Permissions",
                                                 showBackButton: true,
                                                 customToolbarView: saveBtnView,
                                                 showBottomLine: true)){_,_ in
            
            
            
            switch channel {
            case .saved_messages(_):
                EmptyView()
                
            case .dm_channel(_):
                EmptyView()
                
            case .group_dm_channel(let groupDMChannel):
                // Display permission settings for group direct message channels.
                
                
                
                LazyVStack(spacing: .zero){
                    
                    PeptideText(text: "Set default permissions that apply to all members.",
                                font: .peptideBody3,
                                textColor: .textGray07,
                                alignment: .leading)
                    .padding(.vertical, .padding24)
                    
                    AllPermissionSettings(
                        permissions: .defaultRole(Binding {
                            
                            /*print("******Updated permissions: \(groupDMChannel.permissions ?? .defaultGroupDirectMessages)")
                             return groupDMChannel.permissions ?? .defaultGroupDirectMessages*/
                            
                            permissions
                            
                        } set: {
                            /*groupDMChannel.permissions = $0
                             print("#####Updated permissions: \($0)")*/
                            
                            permissions = $0
                            showSaveButton = true
                            
                        }),
                        filter: [.sendMessages,
                                 .manageMessages,
                                 .inviteOthers,
                                 .sendEmbeds,
                                 .uploadFiles,
                                 .masquerade,
                                 .react,
                                 .manageChannel,
                                 .managePermissions]
                    )
                    .task {
                        self.permissions = groupDMChannel.permissions ?? .defaultGroupDirectMessages
                    }
                }
                .padding(.horizontal, .padding16)
                
                
                
            case .text_channel, .voice_channel:
                // Section for text and voice channels.
                // List each role in the server and allow navigation to their permission settings.
                
                
                Button {
                    
                    self.viewState.path.append(NavigationDestination.role_setting(
                        serverId: self.server!.id,
                        channelId: self.channel.id,
                        roleId: "default",
                        roleTitle: "Everyone's Permissions",
                        value: .overwrite(channel.default_permissions ?? Overwrite(a: .none, d: .none))
                        
                    ))
                    
                } label: {
                    PeptideActionButton(
                        icon: .peptideTeamUsers,
                        title: "@everyone",
                        subTitle: "Default permissions for all channel members",
                        hasArrow: true)
                    .backgroundGray11(verticalPadding: .padding4)
                    .padding(.top, .padding24)
                }
                .padding(.horizontal, .padding16)

                
                
                if server?.roles?.isEmpty == false {
                    
                    
                    HStack(spacing: .zero){
                        
                        let roleCount = server?.roles?.count ?? 0
                        
                        PeptideText(textVerbatim: "Role - \(roleCount)",
                                    font: .peptideHeadline)
                        
                        Spacer(minLength: .zero)
                    }
                    .padding(top: .padding24)
                    .padding(.horizontal, .padding16)
                    
                    
                    
                    let sortedRoles = Array(server?.roles ?? [:]).sorted(by: { a, b in a.value.rank < b.value.rank })
                    
                    let lastRoleId = sortedRoles.last?.key
                    
                    
                    LazyVStack(spacing: .zero){
                        
                        ForEach(sortedRoles, id: \.key) { pair in
                            // Get the role's color or default to the theme's foreground color.
                            let roleColour = pair.value.colour.map { parseCSSColor(currentTheme: viewState.theme, input: $0) } ?? AnyShapeStyle(viewState.theme.foreground)
                            
                            
                            
                            Button {
                                
                                let overwrite = channel.role_permissions?[pair.key] ?? Overwrite(a: .none, d: .none)
                                let value : ChannelRolePermissionsSettings.Value = .overwrite(overwrite)
                                
                                self.viewState.path.append(NavigationDestination.role_setting(serverId: server!.id, channelId : channel.id, roleId: pair.key, roleTitle: pair.value.name,  value: value))
                                
                                
                            } label: {
                                
                                
                                PeptideActionButton(
                                    icon: .peptideShieldUserRole,
                                    iconColor: Color(hex: pair.value.colour ?? "#FFFFFD") ?? .iconDefaultGray01,
                                    iconSize: .size32,
                                    title: pair.value.name,
                                    hasArrow: true
                                )
                                
                                
                            }
                            
                            
                            
                            if pair.key != lastRoleId {
                                PeptideDivider()
                                    .padding(.leading, .padding48)
                            }
                            
                            
                            
                            // Navigation link to role-specific permission settings.
                            /* NavigationLink {
                             let overwrite = channel.role_permissions?[pair.key] ?? Overwrite(a: .none, d: .none)
                             ChannelRolePermissionsSettings(
                             server: Binding($server)!,
                             channel: $channel,
                             roleId: pair.key,
                             permissions: .overwrite(overwrite)
                             )
                             .toolbar {
                             ToolbarItem(placement: .principal) {
                             // Display the role name in the toolbar.
                             Text(verbatim: pair.value.name)
                             .bold()
                             .foregroundStyle(roleColour)
                             }
                             }
                             } label: {
                             // Display the role name.
                             Text(verbatim: pair.value.name)
                             .foregroundStyle(roleColour)
                             }*/
                        }
                        
                    }
                    .backgroundGray11(verticalPadding: .padding4)
                    .padding(.bottom, .padding24)
                    .padding(.horizontal, .padding16)
                    
                    
                }
                
                
                // Navigation link for default permissions.
                /*NavigationLink {
                 ChannelRolePermissionsSettings(
                 server: Binding($server)!,
                 channel: $channel,
                 roleId: "default",
                 permissions: .overwrite(channel.default_permissions ?? Overwrite(a: .none, d: .none))
                 )
                 .navigationTitle("Default") // Set title for default permissions view.
                 } label: {
                 // Label for the default permissions link.
                 Text("Default")
                 }*/
                
            }
            
            
            
            Spacer(minLength: .size40)
        }
        
    }
}


#Preview {
    
    @Previewable @StateObject var viewState = ViewState.preview()
    
    ChannelPermissionsSettings(server: .constant(nil), channel: .constant(viewState.channels["4"]!))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
