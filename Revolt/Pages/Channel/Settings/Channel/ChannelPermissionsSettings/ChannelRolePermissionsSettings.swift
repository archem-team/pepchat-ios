//
//  ChannelRolePermissionsSettings.swift
//  Revolt
//
//  Created by Angelo on 25/09/2024.
//

import Foundation
import SwiftUI
import Types

/// A SwiftUI view for managing role-based permissions in a specific channel of a server.
///
/// This view provides an interface to view and edit the permissions associated with a role within a specific
/// channel. The permissions can be customized based on default roles or overwrite settings for specific roles.
///
/// - Parameters:
///   - server: A binding to the `Server` object representing the server where the channel exists.
///   - channel: A binding to the `Channel` object representing the channel in which permissions are being modified.
///   - roleId: A string representing the ID of the role whose permissions are being modified.
///   - initial: The initial set of permissions or overwrite settings for the role within the channel.
///   - currentValue: The current permissions being edited by the user.
struct ChannelRolePermissionsSettings: View {
    
    /// The global application state, injected via environment.
    /// Contains information such as theming and methods for HTTP requests.
    @EnvironmentObject var viewState: ViewState
    
    /// An enum representing either permissions or an overwrite setting for the role in the channel.
    /// This can either be:
    /// - `permission`: A set of general permissions.
    /// - `overwrite`: A specific overwrite of permissions for the role in the channel.
    enum Value: Equatable, Hashable, Codable {
        case permission(Permissions)
        case overwrite(Overwrite)
    }
    
    /// The server to which the channel belongs, passed as a binding.
    @Binding var server: Server
    
    /// The channel in which the role permissions are being edited, passed as a binding.
    @Binding var channel: Channel
    
    /// The ID of the role for which the permissions are being set or modified.
    var roleId: String
    var roleTitle : String
    
    /// The initial permissions or overwrite values for the role.
    @State var initial: Value = .permission(.all)
    
    /// The current permissions or overwrite values being edited by the user.
    @State var currentValue: Value
    
    @State var showSaveButton: Bool = true

    
    /// Initializes the view with the server, channel, role ID, and permissions/overwrite settings.
    /// - Parameters:
    ///   - server: A binding to the `Server` where the channel exists.
    ///   - channel: A binding to the `Channel` in which the role's permissions are being managed.
    ///   - roleId: The ID of the role whose permissions are being edited.
    ///   - permissions: The initial `Value` (either permissions or overwrite) to be set for the role.
    init(server: Binding<Server>, channel: Binding<Channel>, roleId: String, roleTitle:String, permissions: Value) {
        self._server = server
        self._channel = channel
        self.roleId = roleId
        self.roleTitle = roleTitle
        self.initial = permissions
        self.currentValue = permissions
    }
    
    
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                //TODO:
                
                Task {
                    
                    switch currentValue {
                    case .permission(let permissions):
                        Task{
                            let response = await self.viewState.http.setDefaultPermission(target: self.channel.id, permissions: permissions)
                            switch response {
                            case .success(_):
                                self.viewState.path.removeLast()
                            case .failure(let failure):
                                debugPrint("\(failure)")
                            }
                        }
                    case .overwrite(let overwrite):
                        Task {
                            let response = await self.viewState.http.setChannelRolePermissions(target: self.channel.id, role: roleId, permissions: overwrite)
                            switch response {
                            case .success(_):
                                self.viewState.path.removeLast()
                            case .failure(let failure):
                                debugPrint("\(failure)")

                            }
                        }
                    }
                    
                }
                
                
            } label: {
                PeptideText(text: "Save",
                            font: .peptideButton,
                            textColor: .textYellow07,
                            alignment: .center)
            }
                .opacity(showSaveButton ? 1 : 0)
                .disabled(!showSaveButton)
            
            
        )
    }
    
    var body: some View {
        
        
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: roleTitle,
                                                 showBackButton: true,
                                                 backButtonIcon: .peptideCloseLiner,
                                                 customToolbarView: saveBtnView,
                                                 showBottomLine: true)){_,_ in
            
            
            LazyVStack(spacing: .zero) {
                AllPermissionSettings(
                    permissions: {
                        switch currentValue {
                        case .permission(let permissions):
                                .defaultRole(Binding {
                                    permissions
                                } set: {
                                    currentValue = .permission($0)
                                })
                        case .overwrite(let overwrite):
                                .role(Binding {
                                    overwrite
                                } set: {
                                    currentValue = .overwrite($0)
                                })
                        }
                    }(),
                    filter: [
                        .manageChannel,
                        .managePermissions,
                        .viewChannel,
                        .sendMessages,
                        .manageMessages,
                        .inviteOthers,
                        .sendEmbeds,
                        .uploadFiles,
                        .masquerade,
                        .react,
                        
                        /*.viewChannel,
                         .readMessageHistory,
                         .sendMessages,
                         .manageMessages,
                         .inviteOthers,
                         .sendEmbeds,
                         .uploadFiles,
                         .masquerade,
                         .react,
                         .manageChannel,
                         .managePermissions*/
                    ]
                )
            }
            .padding(.horizontal, .padding16)
            .padding(.top, .padding24)

            
            Spacer(minLength: .zero)
            
            
            
            /*.toolbar {
                // Adds a toolbar button to save changes when permissions have been modified
                #if os(iOS)
                let placement = ToolbarItemPlacement.topBarTrailing
                #elseif os(macOS)
                let placement = ToolbarItemPlacement.automatic
                #endif
                ToolbarItem(placement: placement) {
                    // Shows save button only if currentValue differs from initial
                    if initial != currentValue {
                        Button {
                            
                            Task {
                                
                                switch currentValue {
                                case .permission(let permissions):
                                    Task{
                                        let _ = await self.viewState.http.setDefaultPermission(target: self.channel.id, permissions: permissions)
                                    }
                                case .overwrite(let overwrite):
                                    Task {
                                        let _ = await self.viewState.http.setChannelRolePermissions(target: self.channel.id, role: roleId, permissions: overwrite)
                                    }
                                }
                                
                            }
                            
                            
                        } label: {
                            Text("Save")
                                .foregroundStyle(viewState.theme.accent)
                        }
                    }
                }
            }
            .toolbarBackground(viewState.theme.topBar.color, for: .automatic)*/
            
            
        }
        
        
    }
}
