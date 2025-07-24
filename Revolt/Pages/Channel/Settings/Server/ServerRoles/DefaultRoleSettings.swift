//
//  DefaultRoleSettings.swift
//  Revolt
//
//  Created by Angelo on 25/09/2024.
//

import Foundation
import SwiftUI
import Types

/// A SwiftUI view for editing the default role permissions of a server.
///
/// This view allows users to modify and save the default permissions associated with a server's default role.
/// It provides an interface for adjusting permissions and includes functionality to save any changes
/// via the toolbar. The view updates the server's role settings when permissions are modified.
///
/// - Parameters:
///   - server: A binding to a `Server` object representing the server for which the permissions are being modified.
///   - initial: The initial permissions of the server's default role, provided as a `Permissions` object.
///   - currentValue: The current permissions being edited by the user. This is updated when the user makes changes in the view.
/// - Environment:
///   - viewState: The app's global state, which includes theme information and HTTP functions for making server requests.
struct DefaultRoleSettings: View {
    /// The shared application state, provided by the environment.
    /// This contains information such as the app's theme and HTTP client.
    @EnvironmentObject var viewState: ViewState
    
    /// A binding to the server for which the default role permissions are being modified.
    @Binding var server: Server
    
    /// The initial set of permissions for the server's default role.
    @State var initial: Permissions = .all
    
    /// The current permissions being edited by the user. This starts as the initial permissions and can be modified.
    @State var currentValue: Permissions
    
    @State var showSaveButton: Bool = false
    @State var saveButtonIsLoading: Bool = false

    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                //TODO:
                
                Task {
                    saveButtonIsLoading = true
                    let result = await viewState.http.setDefaultRolePermissions(server: server.id, permissions: currentValue)
                    saveButtonIsLoading = false
                    switch result {
                    case .success(let server):
                        initial = server.default_permissions // Update the initial permissions
                        currentValue = initial // Reset the current value to reflect the saved permissions
                        showSaveButton = false
                        self.viewState.showAlert(message: "Saved changes", icon: .peptideDoneCircle, color: .iconGreen07)
                    case .failure(_):
                        self.viewState.showAlert(message: "Something went wrong!", icon: .peptideInfo)
                    }
                    		
                }
                
                
            } label: {
                
                if saveButtonIsLoading {
                    
                    ProgressView()
                    
                }else{
                
                    PeptideText(text: "Save",
                                font: .peptideButton,
                                textColor: .textYellow07,
                                alignment: .center)
                    
                }
                
            }
                .opacity(showSaveButton ? 1 : 0)
                .disabled(!showSaveButton)
            
            
        )
    }
    
    /// Initializes the view with the server and its associated permissions.
    /// - Parameters:
    ///   - s: A binding to the `Server` object representing the server.
    ///   - permissions: The initial permissions of the server's default role.
    init(server s: Binding<Server>, permissions: Permissions) {
        self._server = s
        self.initial = permissions
        self.currentValue = permissions
    }
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Everyone's Role",
                                                 showBackButton: true,
                                                 backButtonIcon: .peptideCloseLiner,
                                                 customToolbarView: saveBtnView,
                                                 showBottomLine: true)){_,_ in
            
            LazyVStack(spacing: .zero){
                
                PeptideText(text: "Set default permissions that apply to all members.",
                            font: .peptideBody3,
                            textColor: .textGray07,
                            alignment: .leading)
                            .padding(.vertical, .padding24)
                
                AllPermissionSettings(permissions: .defaultRole($currentValue),
                                      filter: [
                                        .manageChannel,
                                        .manageServer,
                                        .managePermissions,
                                        .manageRole,
                                        .manageCustomisation,
                                        .kickMembers,
                                        .banMembers,
                                        .timeoutMembers,
                                        .assignRoles,
                                        .changeNicknames,
                                        .manageNickname,
                                        .changeAvatars,
                                        .removeAvatars,
                                        .viewChannel,
                                        .sendMessages,
                                        .manageMessages,
                                        .inviteOthers,
                                        .sendEmbeds,
                                        .uploadFiles,
                                        .masquerade,
                                        .react,
                                        .connect
                                      ])
                
            }
            .padding(.horizontal, .padding16)

            
        }
                                                 .onChange(of: currentValue){ _, _ in
                                                     self.showSaveButton = true
                                                     
                                                 }
        
    }
}


#Preview {
    
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    DefaultRoleSettings(server: .constant(viewState.servers["0"]!), permissions: .all)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
    
    
}
