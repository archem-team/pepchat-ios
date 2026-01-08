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
    
    // Helper function to determine the display color
    private var displayColor: Color {
        if let colorHex = discoverItem.color, !colorHex.isEmpty, colorHex.hasPrefix("#") {
            // Parse custom color from CSV
            return Color(hex: colorHex) ?? (discoverItem.isNew ? .textYellow07 : .textDefaultGray01)
        } else if discoverItem.isNew {
            // Use yellow for new items
            return .textYellow07
        } else {
            // Use default gray for normal items
            return .textDefaultGray01
        }
    }
    
    private var iconColor: Color {
        if let colorHex = discoverItem.color, !colorHex.isEmpty, colorHex.hasPrefix("#") {
            // Parse custom color from CSV
            return Color(hex: colorHex) ?? (discoverItem.isNew ? .iconYellow07 : .iconDefaultGray01)
        } else if discoverItem.isNew {
            // Use yellow for new items
            return .iconYellow07
        } else {
            // Use default gray for normal items
            return .iconDefaultGray01
        }
    }
    
    private var arrowIconColor: Color {
        if isMember {
            return .iconGreen07
        } else if let colorHex = discoverItem.color, !colorHex.isEmpty, colorHex.hasPrefix("#") {
            // Parse custom color from CSV
            return Color(hex: colorHex) ?? (discoverItem.isNew ? .iconYellow07 : .iconGray07)
        } else if discoverItem.isNew {
            return .iconYellow07
        } else {
            return .iconGray07
        }
    }
    
    var body: some View {
        
        Button{
            onClick()
        } label: {
            
            HStack(spacing: .spacing12){
                
                
                PeptideIcon(iconName: self.discoverItem.disabled ? .peptideLock : .peptideTeamUsers,
                            size: .size24,
                            color: iconColor)
                
                VStack(alignment: .leading, spacing: .spacing2){
                    
                    HStack(spacing: .spacing4) {
                        PeptideText(text: discoverItem.title,
                                    font: .peptideCallout,
                                    textColor: displayColor,
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
                            color: arrowIconColor)
                
                
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





