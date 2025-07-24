//
//  ServerRolesSettings.swift
//  Revolt
//
//  Created by Angelo on 25/09/2024.
//

import Foundation
import Types
import SwiftUI

/// A view that displays the settings for managing roles within a server.
struct ServerRolesSettings: View {
    /// The environment object that holds the current state of the application.
    @EnvironmentObject var viewState: ViewState
    
    /// A binding to the server whose roles are being managed.
    @Binding var server: Server
    
    /// State variable to control the presentation of the role creation alert.
    @State var showCreateRole: Bool = false
    @State private var isPresentedRoleDelete : Bool = false
    
    
    @State private var selectedRole : (roleId: String, role: Role)? = nil
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Roles"),
                            fixBottomView: AnyView(
                                HStack(spacing: .zero) {
                                    
                                    Button {
                                        self.viewState.path.append(NavigationDestination.create_server_role(serverId: server.id))
                                    } label: {
                                        
                                        HStack(spacing: .spacing4){
                                            
                                            PeptideIcon(iconName: .peptideAdd,
                                                        color: .iconInverseGray13)
                                            
                                            PeptideText(text: "Create",
                                                        textColor: .textInversePurple13)
                                            .padding(.trailing, .padding4)
                                            
                                        }
                                        .padding(.horizontal, .padding8)
                                        .frame(height: .size40)
                                        .background{
                                            RoundedRectangle(cornerRadius: .radiusLarge)
                                                .fill(Color.bgYellow07)
                                        }
                                        
                                    }
                                    
                                }
                                    .padding(.horizontal, .padding16)
                                    .padding(top: .padding8, bottom: .padding24)
                                    .background(Color.bgDefaultPurple13)
                            )){_,_ in
                                
                                let _ = selectedRole
                                
                                VStack(alignment: .leading, spacing: .zero){
                                    
                                    
                                    PeptideText(text: "Organize members and customize their permissions with roles.",
                                                font: .peptideBody4,
                                                textColor: .textGray06,
                                                alignment: .center)
                                    .padding(top: .padding24,
                                             leading: .padding16,
                                             trailing: .padding16)
                                    
                                    Button{
                                        self.viewState.path.append(NavigationDestination.default_role_settings(serverId: server.id))
                                    } label: {
                                        PeptideActionButton(
                                            icon: .peptideTeamUsers,
                                            title: "@everyone",
                                            subTitle: "Default permissions for all server members",
                                            hasArrow: true)
                                        .backgroundGray11(verticalPadding: .padding4)
                                        .padding(.top, .padding24)
                                    }
                                    
                                    /*
                                     
                                     PeptideActionButton(icon: .peptideNewGroup,
                                     title: "New Group",
                                     )
                                     
                                     */
                                    
                                    if server.roles?.isEmpty == false {
                                        
                                        let roleCount = server.roles?.count ?? 0
                                        
                                        PeptideText(textVerbatim: "Role - \(roleCount)",
                                                    font: .peptideHeadline)
                                        .padding(top: .padding24, bottom: .padding8)
                                        
                                        
                                        LazyVStack(alignment: .leading, spacing: .spacing4) {
                                            let sortedRoles = Array(server.roles ?? [:]).sorted(by: { a, b in a.value.rank < b.value.rank })
                                            
                                            let lastRoleId = sortedRoles.last?.key
                                            
                                            ForEach(sortedRoles, id: \.key) { pair in
                                                
                                                
                                                Button {
                                                    self.viewState.path.append(NavigationDestination.role_settings(serverId: server.id, roleId: pair.key))
                                                } label: {
                                                    PeptideActionButton(
                                                        icon: .peptideShieldUserRole,
                                                        iconColor: Color(hex: pair.value.colour ?? "#FFFFFD") ?? .iconDefaultGray01,
                                                        iconSize: .size32,
                                                        title: pair.value.name,
                                                        iconAction: .peptideTrashDelete,
                                                        onClicIconAction: {
                                                            // Action for icon click
                                                            self.selectedRole = (pair.key, pair.value)
                                                            self.isPresentedRoleDelete.toggle()
                                                            
                                                        },
                                                        hasArrow: true
                                                    )
                                                }
                                                
//                                                // ?????????????
//                                                NavigationLink {
//                                                    RoleSettings(server: $server, roleId: pair.key, role: pair.value)
//                                                } label: {
//                                                    
//                                                }
                                                
                                                
                                                /*Text(verbatim: pair.value.name)
                                                 .foregroundStyle(pair.value.colour.map { parseCSSColor(currentTheme: viewState.theme, input: $0) } ?? AnyShapeStyle(viewState.theme.foreground))*/
                                                
                                                if pair.key != lastRoleId {
                                                    PeptideDivider()
                                                        .padding(.leading, .padding48)
                                                }
                                            }
                                        }
                                        .backgroundGray11(verticalPadding: .padding4)
                                        .padding(.bottom, .padding24)
                                        
                                    }
                                }
                                .padding(.horizontal, .padding16)
                                
                                Spacer(minLength: .zero)
                                
                            }
                            .popup(isPresented: $isPresentedRoleDelete, view: {
                                
                                if let selectedRole = selectedRole {
                                    RoleDeleteSheet(isPresented: $isPresentedRoleDelete,
                                                    serverId: self.server.id,
                                                    roleId: selectedRole.roleId , role: selectedRole.role)
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


#Preview{
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    ServerRolesSettings(server: .constant(viewState.servers["0"]!))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
