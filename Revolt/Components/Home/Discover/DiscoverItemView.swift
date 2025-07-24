//
//  DiscoverItemView.swift
//  Revolt
//
//

import SwiftUI

struct DiscoverItemView: View {
    
    var discoverItem: DiscoverItem
    var onClick : () -> Void
    var isMember: Bool = false
    @EnvironmentObject var viewState: ViewState
    
    var body: some View {
        
        Button{
            print("🔗 [DiscoverItemView] Clicked on server: \(discoverItem.title)")
            print("   📎 Invite code: \(discoverItem.code)")
            print("   🔒 Disabled: \(discoverItem.disabled)")
            print("   👥 Is Member: \(isMember)")
            onClick()
        } label: {
            
            HStack(spacing: .spacing12){
                
                
                PeptideIcon(iconName: self.discoverItem.disabled ? .peptideLock : .peptideTeamUsers,
                            size: .size24,
                            color: discoverItem.isNew ? .iconYellow07 : .iconDefaultGray01)
                
                VStack(alignment: .leading, spacing: .spacing2){
                    
                    HStack(spacing: .spacing4) {
                        PeptideText(text: discoverItem.title,
                                    font: .peptideCallout,
                                    textColor: discoverItem.isNew ? .textYellow07 : .textDefaultGray01,
                                    alignment: .leading)
                        
                        // Show member badge if user is a member
                        // if isMember {
                        //     Text("MEMBER")
                        //         .font(.system(size: 10, weight: .bold))
                        //         .foregroundColor(.white)
                        //         .padding(.horizontal, 6)
                        //         .padding(.vertical, 2)
                        //         .background(Color.green)
                        //         .cornerRadius(4)
                        // }
                    }
                    
                    PeptideText(text: discoverItem.description,
                                font: .peptideCaption1,
                                textColor: .textGray07,
                                alignment: .leading,
                                lineLimit: 2)
                    
                }
                
                Spacer(minLength: .zero)
                
                PeptideIcon(iconName: isMember ? .peptideDoneCircle : .peptideArrowRight,
                            size: .size20,
                            color: isMember ? .iconGreen07 : (discoverItem.isNew ? .iconYellow07 : .iconGray07))
                
                
            }
            .padding(.padding8)
            .frame(minHeight: .size64)
            .opacity(self.discoverItem.disabled ? 0.5 : 1.0)
            .background{
                RoundedRectangle(cornerRadius: .radius8).fill(Color.bgGray11)
            }
        }
        
    }
}





