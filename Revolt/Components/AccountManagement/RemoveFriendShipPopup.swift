//
//  RemoveFriendShipPopup.swift
//  Revolt
//
//  Created by Mehdi on 2/8/25.
//

import SwiftUI
import Types

enum RemoveFriendShipType{
    case withdrawal;
    case unfriend;
}

struct RemoveFriendShipPopup: View {

    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented : Bool
    let user: User
    let removeFriendShipType: RemoveFriendShipType
    
    var body: some View{
        
        ZStack(alignment: .topTrailing){

            
            
            VStack(alignment: .leading, spacing: .spacing4){
                
                Group {
                    PeptideText(textVerbatim: removeFriendShipType == .unfriend ? "Unfriend \(user.username)?" : "Cancel Friend Request",
                                font: .peptideTitle3,
                                textColor: .textDefaultGray01)
                    .padding(.bottom, .size16)
                    
                    let subtitle = removeFriendShipType == .unfriend ? "Are you sure you want to unfriend \(user.usernameWithDiscriminator()) from your friends?": "Are you sure you want to cancel your friend request to \(user.usernameWithDiscriminator())?"
                    
                    PeptideText(text: subtitle,
                                font: .peptideCallout,
                                textColor: .textGray06,
                                alignment: .leading
                    )
                    
                }
                .padding(.horizontal, .padding24)
                
                
                PeptideDivider(backgrounColor: .borderGray10)
                    .padding(top: .padding28, bottom: .padding20)
                
                HStack(spacing: .padding12){
                    Spacer(minLength: .zero)
                    
                    PeptideButton(buttonType: .medium(),
                                  title: "Dismiss",
                                  bgColor: .clear,
                                  contentColor: .textDefaultGray01,
                                  buttonState: .default,
                                  isFullWidth: false){
                        self.isPresented.toggle()
                    }
                    
                    PeptideButton(buttonType: .medium(),
                                  title: removeFriendShipType == .unfriend ? "Unfriend" : "Cancel Friend Request",
                                  bgColor: .bgRed07,
                                  contentColor: .textDefaultGray01,
                                  buttonState: .default,
                                  isFullWidth: false){
                        
                        
 
                                    Task{

                                        let res = await self.viewState.http.removeFriend(user: user.id)

                                        switch res {
                                            case .success(_):
                                                viewState.users[user.id]?.relationship = .None
                                                viewState.closeUserOptionsSheet()
                                                self.isPresented.toggle()
                                            case .failure(_):
                                                self.viewState.showAlert(message: "Something went wronge!", icon: .peptideCloseLiner)
                                        }

                                    }
                            
                    
                        
                    }
                    
                }
                .padding(.horizontal, .padding24)
                
            }
            .padding(top: .padding24, bottom: .padding24)
            .background{
                RoundedRectangle(cornerRadius: .radiusMedium)
                    .fill(Color.bgGray11)
            }
            
            PeptideIconButton(icon: .peptideCloseLiner){
                self.isPresented.toggle()
            }
            .padding(.all, .size16)
            
        }
        .padding(.padding16)
        
    }
    
    
}

struct RemoveFriendShipPopupPreview: PreviewProvider {
    @StateObject static var viewState: ViewState = ViewState.preview().applySystemScheme(theme: .dark)
    
    static var previews: some View {
        Text("foo")
            .popup(isPresented: .constant(true)) {
                RemoveFriendShipPopup(
                    isPresented: .constant(true),
                    user: viewState.users["0"]!,
                    removeFriendShipType: .unfriend
                )
            }
            .applyPreviewModifiers(withState: viewState)
    }
}
