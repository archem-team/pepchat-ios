//
//  Settings.swift
//  Revolt
//
//  Created by Angelo on 18/10/2023.
//

import Foundation
import SwiftUI

/// Enum representing the different pages in the settings.
enum CurrentSettingsPage: Hashable {
    case profile
    case sessions
    case appearance
    case language
    case about
}

/// The main view for settings in the application.
struct Settings: View {
    @EnvironmentObject var viewState: ViewState // Access to the application's view state.
    
    @State var presentLogoutDialog = false // State to control the logout confirmation dialog.
    
    @State var isLoadingLogout : Bool = false
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Settings")){_,_ in
            
            
            VStack(spacing: .spacing4){
                
                Button(action:{
                    viewState.path.append(NavigationDestination.user_settings)
                }, label: {
                    PeptideActionButton(icon: .peptideUserProfile,
                                        title: "Account",
                                        hasArrow: true)
                })
                
                PeptideDivider()
                    .padding(.leading, 0)
                
                if let currentUser = viewState.currentUser {
                
                    Button(action:{
                        viewState.path.append(NavigationDestination.profile_setting)
                    }, label: {
                        PeptideActionButton(icon: .peptideRoleIdCard,
                                            title: "Profile",
                                            hasArrow: true)
                    })
                    
                }
                
                
                
                PeptideDivider()
                    .padding(.leading, 0)
                
                Button(action:{
                    viewState.path.append(NavigationDestination.sessions_settings)
                }, label: {
                    PeptideActionButton(icon: .peptideShieldTick,
                                        title: "Sessions",
                                        hasArrow: true)
                })
                
                PeptideDivider()
                    .padding(.leading, 0)
                
                if let url = URL(string: "https://zeko.chat/privacy") {
                    Link(destination: url) {
                        PeptideActionButton(icon: .peptideLock,
                                            title: "Privacy Policy",
                                            hasArrow: true)
                    }
                }
                
                PeptideDivider()
                    .padding(.leading, 0)
                
                if let url = URL(string: "https://zeko.chat/delete-account") {
                    Link(destination: url) {
                        PeptideActionButton(icon: .peptideTrashDelete,
                                            title: "Delete Account",
                                            hasArrow: true)
                    }
                }
                
                
            }
            .backgroundGray11(verticalPadding: .padding4)
            .padding(.horizontal, .padding16)
            .padding(.vertical, .padding24)
            
            // Client Settings Section
            /*Section("Client Settings") {
             NavigationLink(destination: { AppearanceSettings() }) {
             settingsItem(icon: "paintpalette.fill", title: "Appearance")
             }
             NavigationLink(destination: { NotificationSettings() }) {
             settingsItem(icon: "bell.fill", title: "Notifications")
             }
             NavigationLink(destination: { LanguageSettings() }) {
             settingsItem(icon: "globe", title: "Language")
             }
             }
             .listRowBackground(viewState.theme.background2)*/
            
            /*Section("Revolt") {
             NavigationLink {
             BotSettings()
             } label: {
             Image(systemName: "desktopcomputer")
             .resizable()
             .scaledToFit()
             .frame(width: 16, height: 16)
             Text("Bots")
             }
             
             }.listRowBackground(viewState.theme.background2)*/
            
            // Logout Section
            
            Button {
                presentLogoutDialog = true // Show logout confirmation dialog.
            } label: {
                
                PeptideActionButton(icon: .peptideSignOutLeave,
                                    iconColor: .iconRed07,
                                    title: "Log Out",
                                    titleColor: .textRed07,
                                    hasArrow: false)
                .backgroundGray11(verticalPadding: .padding4)
                
            }
            .padding(.horizontal, .padding16)
            
            
            Spacer(minLength: .zero)
            
            
        }
        .popup(isPresented: $presentLogoutDialog, view: {
            
            ConfirmationSheet(
                isPresented: $presentLogoutDialog,
                isLoading: $isLoadingLogout,
                title: "Are you sure?",
                subTitle: "You can login with the same account or another one after logout.",
                confirmText: "Yes",
                dismissText: "Wait!",
                popOnConfirm: false
            ){
                Task {

                    //isLoadingLogout = true
                    //isLoadingLogout = false
                    presentLogoutDialog = false

                    let _ = await self.viewState.signOut()

                    
                }

            }
        }, customize: {
            $0.type(.default)
              .isOpaque(false)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
//        .confirmationDialog("Are you sure?", isPresented: $presentLogoutDialog, titleVisibility: .visible) {
//            Button("Yes", role: .destructive) {
//                Task {
//                    await viewState.signOut() // Sign out the user when confirmed.
//                }
//            }
//            .keyboardShortcut(.defaultAction)
//            Button("Wait!", role: .cancel) {
//                presentLogoutDialog = false // Cancel logout action.
//            }
//            .keyboardShortcut(.cancelAction)
//        }
    }
    
    /// A helper function to create a settings item with an icon and title.
    private func settingsItem(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16) // Set icon size.
            Text(title) // Set item title.
        }
    }
}

#Preview {
    Settings()
        .applyPreviewModifiers(withState: ViewState.preview())
        .preferredColorScheme(.dark)
}
