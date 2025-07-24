//
//  BlockedUsersView.swift
//  Revolt
//
//  Created by Mehdi on 2/1/25.
//

import SwiftUI
import Types

struct BlockedUsersView: View {
    
    @EnvironmentObject var viewState: ViewState
    
    var blockedUsers: [Types.User] {
        return viewState.users.values.filter { $0.relationship == .Blocked }
    }
    @State var delettingUserID: String?
    
    var body: some View {
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Blocked User")){_,_ in
            
            
            if(blockedUsers.isEmpty){
            
                VStack(spacing: .zero){
            
                    PeptideImage(imageName: .emptyListPlaceholder, width: .size100, height: .size100)
                        .padding(.top, .size24)
                    
                    PeptideText(
                        text: "The blocked List is Empty",
                        font: .peptideHeadline,
                        textColor: .textDefaultGray01
                    )
                    .padding(.vertical, .size4)
                    
                    PeptideText(
                        text: "No users have been blocked.",
                        font: .peptideSubhead,
                        textColor: .textGray07
                    ).padding(.bottom, .size4)
                    
                }
                
            }else{
                
                VStack(alignment: .leading, spacing: .zero){
                
                    PeptideText(
                        text: "Blocked Users - \(blockedUsers.count)",
                        font: .peptideHeadline,
                        textColor: .textDefaultGray01
                    )
                        .padding(.top, .size24)
                        .padding(.bottom, .size8)
                        .padding(.leading, .size32)
                    
                    VStack(spacing: .zero){
                        
                        
                        ForEach(blockedUsers, id: \.id){ user in
                            
                            HStack(spacing: .spacing8) {
                                
                                Avatar(user: user,
                                       width: .size40,
                                       height: .size40,
                                       withPresence: false)
                                .padding(.horizontal, .size12)
                                
                                PeptideText(
                                    text: user.username,
                                    font: .peptideButton,
                                    textColor: .textDefaultGray01
                                )
                                
                                Spacer(minLength: .zero)
                                
                                PeptideButton(
                                    title: "Unblock",                                
                                    bgColor: .bgGray11,
                                    contentColor: .textDefaultGray01,
                                    buttonState: delettingUserID == user.id ? .loading : .default,
                                    isFullWidth: false
                                ){
                                
                                    Task {
                                        delettingUserID = user.id
                                        let response = await viewState.http.unblockUser(user: user.id)
                                        delettingUserID = nil
                                        
                                        switch response {
                                        case .success(_):
                                            viewState.updateRelationship(for: user.id, with: .None)
                                        case .failure(_):
                                            viewState.showAlert(message: "Some thing went wronge. Try again a litle later", icon: .peptideClose)
                                        }
                                        
                                    }
                                    
                                }
                                
                            }
                            .padding(.all, .size12)
                            
                            if(user != blockedUsers.last){
                                Divider()
                                    .foregroundColor(.borderGray11)
                                    .padding(.leading, .size48)
                            }
                        
                        }
                        
                    }.backgroundGray12(verticalPadding: .padding4)
                        .padding(.horizontal, .size16)
                        
                    
                }
                
            }
            
            Spacer(minLength: .zero)
            
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    BlockedUsersView()
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}

