//
//  HomeBottomNavigation.swift
//  Revolt
//
//

import SwiftUI

struct HomeBottomNavigation: View {
    
    
    @Binding var homeTab: HomeTab
    
    var body: some View {
        
        VStack(spacing: .zero) {
            PeptideDivider()
            
            HStack(spacing: .spacing8){
                
                PeptideTabItem(isSelected: homeTab == .home,
                               icon: .peptideHome,
                               label: "Home",
                               onClick: {
                    homeTab = .home
                })
                
                PeptideTabItem(isSelected: homeTab == .friends,
                               icon: .peptideUsers,
                               label: "Friends",
                               onClick: {
                    homeTab = .friends
                })
                
                
                PeptideTabItem(isSelected: homeTab == .you,
                               icon: .peptideSmile,
                               label: "You",
                               onClick: {
                    homeTab = .you
                })
                
            }
            .padding(top: .padding8, leading: .padding16, trailing: .padding16)
            
            Spacer(minLength: .zero)
            
        }
        .frame(height: .size76)
        .background(Color.bgGray11)
        
    }
}


enum HomeTab : Hashable {
    case home
    case friends
    case you
}




#Preview {
    HomeBottomNavigation(homeTab: .constant(.home))
        .preferredColorScheme(.dark)
}
