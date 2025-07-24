//
//  PeptideIconButton.swift
//  Revolt
//
//

import SwiftUI

struct PeptideIconButton: View {
    
    var icon: ImageResource
    var color : Color = .iconDefaultGray01
    var size : CGFloat = .size24
    var disabled : Bool = false
    
    var onClick : () -> Void
    
    var body: some View {
        
        
        Button{
            onClick()
        } label: {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .foregroundColor(color)
                .frame(width: size, height: size)
        }
        .disabled(disabled)

        
    }
}


struct PeptideIconWithTitleButton: View {
    var icon: ImageResource
    var title: String
    var iconColor: Color = .iconGray04
    var iconSize: CGFloat = .size24
    var backgroundColor: Color = .bgGray11
    var backgroundSize: CGFloat = .size40
    var titleColor: Color = .textGray06
    var disabled: Bool = false
    var spacing: CGFloat = .spacing4
    var titleFont : PeptideFont = .peptideFootnote
    var onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: spacing) {
                
                PeptideIcon(iconName: icon,
                            size: iconSize,
                            color: iconColor)
                .frame(width: backgroundSize, height: backgroundSize)
                .background(
                    Circle()
                        .fill(backgroundColor)
                )
                
                PeptideText(
                    text: title,
                    font: titleFont,
                    textColor: titleColor,
                    alignment: .center
                )
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(disabled)
    }
}


#Preview {
    
    HStack(spacing: .zero) {
        /*PeptideIconButton(icon: .peptideClose){
            
        }*/
        
        PeptideIconWithTitleButton(icon: .peptideNewUser,
                                   title: "Add Friend"){
            
        }
        
        PeptideIconWithTitleButton(icon: .peptideReportFlag,
                                   title: "Report",
                                   iconColor: .iconRed07,
                                   titleColor: .textRed07){
            
        }
    }
    .preferredColorScheme(.dark)
    
   
}
