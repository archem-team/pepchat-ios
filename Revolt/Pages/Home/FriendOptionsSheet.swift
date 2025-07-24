//
//  FriendOptionsSheet.swift
//  Revolt
//
//  Created by Mehdi on 2/18/25.
//

import SwiftUI
import Types

struct FriendOptionsSheet: View {
    @EnvironmentObject var viewState: ViewState
    var user : User
    @State private var isShowingUnfriendPopup: Bool = false
    @State private var isShowingBlockPopup: Bool = false
    @State private var sheetHeight: CGFloat = .zero
    
    let firstSection : [PeptideSheetItem] = [
        .init(index: 1, title: "View Profile", icon: .peptideProfileIdCard),
        .init(index: 2, title: "Message", icon: .peptideMessage),
        .init(index: 3, title: "Copy User ID", icon: .peptideCopy, isLastItem: true),
    ]
    
    let secondSection : [PeptideSheetItem] = [
        .init(index: 1, title: "Unfriend", icon: .peptideRemoveUser),
        .init(index: 2, title: "Block User", icon: .peptideProhibitNoneBlock),
        .init(index: 3, title: "Report User", icon: .peptideReportFlag, isLastItem: true),
    ]
    
    var body: some View {
        
        VStack{
         
                
                HStack(alignment: .center, spacing: .zero){
                    
                    Avatar(user: user,
                           width: .size40,
                           height: .size40,
                           withPresence: false)
                    .padding(.trailing, .size8)
                    
                    VStack(alignment: .leading, spacing: .zero){
                        
                        PeptideText(text: user.display_name ?? user.username,
                                    font: .peptideCallout,
                                    textColor: .textDefaultGray01)
                        
                                            
                        PeptideText(text: user.username,
                                    font: .peptideCaption1,
                                    textColor: .textGray07)
                        
                        
                    }
                    
                    
                    Spacer(minLength: .zero)
                    
                }
                .padding(.bottom, .size24)
                .padding(.top, .size16)
                
                VStack(spacing: .spacing4) {
                    ForEach(firstSection, id: \.index) { item in
                        Button {

                            if(item.index == 1){
                                
                                self.viewState.closeUserOptionsSheet()
                                self.viewState.openUserSheet(user: self.user)
                                
                            }else if(item.index == 2){
                                
                                self.viewState.closeUserOptionsSheet()
                                self.viewState.navigateToDm(with: user.id)
                                
                            }else if(item.index == 3){
                                
                                copyText(text: user.usernameWithDiscriminator())
                                self.viewState.showAlert(message: "User ID Copied!", icon: .peptideCopy)
                                
                            }
                            
                        } label: {
                            PeptideActionButton(icon: item.icon,
                                                title: item.title,
                                                hasArrow: false)
                        }
                        
                        if !item.isLastItem {
                            PeptideDivider()
                                .padding(.leading, .padding48)
                        }
                    }
                }
                .backgroundGray11(verticalPadding: .padding4)
                .padding(.bottom, .padding24)
                
                VStack(spacing: .spacing4) {
                    ForEach(secondSection, id: \.index) { item in
                        Button {

                            if(item.index == 1){
                                
                                self.isShowingUnfriendPopup.toggle()
                                
                            }else if(item.index == 2){
                                
                                self.isShowingBlockPopup.toggle()
                                
                            }else if(item.index == 3){
                                
                                viewState.closeUserOptionsSheet()
                                viewState.path.append(NavigationDestination.report(user, nil, nil))
                                
                            }
                            
                        } label: {
                            PeptideActionButton(icon: item.icon,
                                                iconColor: .iconRed07,
                                                title: item.title,
                                                titleColor: .textRed07,
                                                hasArrow: false)
                        }
                        
                        if !item.isLastItem {
                            PeptideDivider()
                                .padding(.leading, .padding48)
                        }
                    }
                }
                .backgroundGray11(verticalPadding: .padding4)
                .padding(.bottom, .padding24)
                
                
            
        }
        .padding(.horizontal, .size16)
        .overlay {
            GeometryReader { geometry in
                Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
            sheetHeight = newHeight
        }        
        .popup(isPresented: $isShowingUnfriendPopup, view: {
            RemoveFriendShipPopup(
                isPresented: $isShowingUnfriendPopup,
                user: self.user,
                removeFriendShipType: .unfriend
            )
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.bottom)
        .popup(isPresented: $isShowingBlockPopup, view: {
            BlockUserPopup(isPresented: $isShowingBlockPopup, user: self.user)
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.bottom)
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    let users = [viewState.users["0"]!, viewState.users["1"]!]
    
    VStack{
        
        
    }
    .sheet(isPresented: .constant(true)){
        
        FriendOptionsSheet(user: viewState.users["0"]!)
        
        
    }
    .background(Color.black)
    .frame(width: .infinity, height: .infinity)
    .applyPreviewModifiers(withState:viewState)
    .preferredColorScheme(.dark)
    
    
}
