//
//  AddFriend.swift
//  Revolt
//
//  Created by Angelo on 09/03/2024.
//

import Foundation
import SwiftUI
import Types


struct AddFriend: View {
    
    @EnvironmentObject var viewState: ViewState
    @State var username = ""
    @State var usernameTextFieldStatus : PeptideTextFieldState = .default
    @State var sendFriendRequestBtnState : ComponentState = .disabled
    let toolbarConfig: ToolbarConfig = .init(isVisible: true,
                                             title: "Add a Friend",
                                             showBottomLine: true)
    
    func sendFriendRequest() {
        
        Task {
            
            usernameTextFieldStatus = .disabled
            sendFriendRequestBtnState = .loading
            
            do {
                let _ = try await viewState.http.sendFriendRequest(username: username).get()
            } catch {
                
                withAnimation{
                    usernameTextFieldStatus = .error(message: "Entered username is invalid. Double check and try.")
                    sendFriendRequestBtnState = .default
                }
                
                return
                
            }
            
            usernameTextFieldStatus = .default
            sendFriendRequestBtnState = .default
            
            self.viewState.showAlert(message: "Friend Request Sent", icon: .peptideHandWave, color: .iconGreen07)
            self.username = ""
                        
        }
        
    }

    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: toolbarConfig){scrollViewProxy, keyboardVisibility in
            
            VStack(alignment: .leading, spacing: .zero) {
                
                
                PeptideText(text: "Add by Username",
                            font: .peptideTitle3,
                            textColor: .textDefaultGray01)
                            .padding(.top, .padding32)
                
                
                PeptideText(text: "Enter a username to send a friend request.",
                            font: .peptideBody3,
                            textColor: .textGray07)
                .padding(.top, .padding8)
                
               
                PeptideTextField(
                    text: $username,
                    state: $usernameTextFieldStatus,
                    placeholder : "Enter a username",
                    keyboardType: .default)
                .onChange(of: username){_, newUsername in
                    
                    usernameTextFieldStatus = .default
                    
                    if newUsername.isEmpty {
                        sendFriendRequestBtnState = .disabled
                    } else {
                        sendFriendRequestBtnState = .default
                    }
                    
                }
                .onChange(of: keyboardVisibility.wrappedValue) { oldState,  newState in
                    if newState  {
                        withAnimation{
                            scrollViewProxy.scrollTo("username-keyboard-spacer", anchor: .top)
                        }
                        
                    }
                }
                .padding(.top, .padding24)
                
                Spacer()
                
                
                PeptideButton(title: "Send Friend Request",
                              buttonState: sendFriendRequestBtnState){
                  
                    sendFriendRequest()
                }
                .padding(.top, .padding32)
                
             
                
                Spacer()
                    .frame(height: .size8)
                    .id("username-keyboard-spacer")
                
                
                Spacer()
                    .frame(height: .size24)

                
            }
            .padding(.horizontal, .padding16)
            
            
        }

    }
}


#Preview {
    AddFriend()
        .applyPreviewModifiers(withState: ViewState.preview())
}
