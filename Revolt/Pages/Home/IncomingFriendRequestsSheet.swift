//
//  IncomingFriendRequestsSheet.swift
//  Revolt
//
//  Created by Mehdi on 2/17/25.
//

import SwiftUI
import Types

struct IncomingFriendRequestsSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool
    
    var users: [User] {
        let usersWithRequest = viewState.users.values
            .filter { user in
                user.relationship == .Incoming
            }
        
        return usersWithRequest
    }
    
    var body: some View {
        PeptideSheet(isPresented: $isPresented) {
            
            PeptideText(
                text: "Incoming Friend Requests",
                font: .peptideHeadline
            )
            .padding(.bottom, .size24)
            
            VStack(spacing: .padding8) {
                ForEach(users, id: \.id) { user in
                    HStack {
                        Avatar(user: user, width: .size40, height: .size40)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2)) // Optional: Add a border
                        
                        VStack(alignment: .leading, spacing: .zero) {
                            
                            PeptideText(
                                text: user.username
                            )
                            
                            PeptideText(
                                text: "Waiting",
                                font: .peptideCaption1,
                                textColor: .textGray07
                            )
                            
                        }
                        
                        Spacer()
                        
                        HStack {
                            
                            Button(action: {
                                Task {
                                    let response = await viewState.http.removeFriend(user: user.id)
                                    switch response {
                                    case .success(_):
                                        viewState.users[user.id]?.relationship = .None
                                        if(users.isEmpty){
                                            self.isPresented.toggle()
                                        }
                                    case .failure(_):
                                        viewState.showAlert(message: "Something went wronge!", icon: .peptideClose)
                                    }
                                    
                                }
                            }) {
                                PeptideIcon(iconName: .peptideClose, size: .size24, color: .iconRed07)
                            }
                            
                            Button(action: {
                                Task {
                                    let response = await viewState.http.acceptFriendRequest(user: user.id)
                                    switch response {
                                    case .success(_):
                                        viewState.users[user.id]?.relationship = .Friend
                                        if(users.isEmpty){
                                            self.isPresented.toggle()
                                        }
                                    case .failure(_):
                                        viewState.showAlert(message: "Something went wronge!", icon: .peptideClose)
                                    }
                                    
                                }
                            }) {
                                PeptideIcon(iconName: .peptideDoneCircle, size: .size24, color: .iconGreen07)
                            }
                        }
                    }
                    .padding(.all, .size8)
                    .background(Color.bgGray11)
                    .cornerRadius(.radius8)
                }
            }
            
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    let users = [viewState.users["0"]!, viewState.users["1"]!]
    
    VStack{
        
        
    }
    .sheet(isPresented: .constant(true)){
        
        IncomingFriendRequestsSheet(isPresented: .constant(true))
        
        
    }
    .background(Color.black)
    .frame(width: .infinity, height: .infinity)
    .applyPreviewModifiers(withState:viewState)
    .preferredColorScheme(.dark)
    
    
}
