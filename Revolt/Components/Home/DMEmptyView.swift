//
//  DMEmptyView.swift
//  Revolt
//
//

import SwiftUI

struct DMEmptyView: View {
    @EnvironmentObject var viewState: ViewState
    
    var body: some View {
        
        HStack {
            
            Spacer(minLength: .zero)

            VStack(spacing: .zero){
                
                Image(.peptideDmEmpty)
                
                PeptideText(text: "It’s Quiet Here...",
                            font: .peptideHeadline,
                            textColor: .textDefaultGray01)
                
                PeptideText(text: "Find friends to chat with or create a group \n conversation.",
                            font: .peptideSubhead,
                            textColor: .textGray07,
                            alignment: .center)
                .padding(.vertical , .padding4)
                
                
                PeptideButton(buttonType: .small(),
                              title: "New Conversation",
                              bgColor: .bgPurple10,
                              contentColor: .textDefaultGray01,
                              buttonState: .default,
                              isFullWidth: false){
                    
//                    toggleSidebar()
                    viewState.currentChannel = .friends
                    viewState.path.append(NavigationDestination.maybeChannelView)
                    
                }
              .padding(.top, .padding16)
                
                
            }

            
            Spacer(minLength: .zero)
            
            
        }
        
        
    }
}

#Preview {
    DMEmptyView()
        .fillMaxSize()
        .preferredColorScheme(.dark)
}
