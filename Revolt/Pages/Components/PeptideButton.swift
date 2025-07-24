//
//  PeptideButton.swift
//  Revolt
//
//

import Foundation
import SwiftUI

struct PeptideButton: View {
    var buttonType : PeptideButtonType = .medium()
    var title: String
    var bgColor: Color = .bgYellow07
    var contentColor: Color = .textInversePurple13
    var buttonState : ComponentState = .default
    var isFullWidth: Bool = true
    
    var leadingIcon : ImageResource? = nil
    
    var onButtonClick : () -> Void
    
    var body: some View {
        
        let (height, _, cornerRadius, _) = buttonType.values
        
        Button(action: {
            withAnimation{
                onButtonClick()
            }
        }) {
            
            HStack(spacing: .zero) {
                
                
                ZStack {
                    
                    if buttonState == .loading {
                        
                        PeptideLoading(activeColor: contentColor)
                    } else {
                        
                        HStack(spacing: .padding4){
                            
                            if let leadingIcon {
                                PeptideIcon(iconName: leadingIcon,
                                            color: contentColor)

                            }
                            
                            PeptideText(text: title,
                                        font: .peptideButton,
                                        textColor: contentColor,
                                        alignment: .center)
                            .padding(.horizontal, .padding4)
                        }
                        
                        
                    }
                    
                }
                
                
            }
            .padding(.horizontal, .size8)
            .`if`(isFullWidth){
                $0.frame(maxWidth: .infinity , minHeight: height)
            }
            
        }
        .frame(minHeight: height)
        .background(bgColor.opacity(buttonState.bgColorOpacity))
        .cornerRadius(cornerRadius.rawValue)
        .disabled(buttonState.isDisabled)
        
        
    }
}


enum PeptideButtonType  {
    case large(height: CGFloat = .size48,
               iconsSize : CGFloat = .size24,
               cornerRadius: PeptideButtonCornerType = .deafult,
               spaceBetweenIconsAndText: CGFloat = .size8)
    
    case medium(height: CGFloat = .size40,
                iconsSize : CGFloat = .size24,
                cornerRadius: PeptideButtonCornerType = .deafult,
                spaceBetweenIconsAndText: CGFloat = .size8)
    
    case small(height: CGFloat = .size32,
               iconsSize : CGFloat = .size20,
               cornerRadius: PeptideButtonCornerType = .deafult,
               spaceBetweenIconsAndText: CGFloat = .size4)
    
    case custom (height: CGFloat = .size48,
                 iconsSize : CGFloat = .size24,
                 cornerRadius: PeptideButtonCornerType = .deafult,
                 spaceBetweenIconsAndText: CGFloat = .size8)
    
    
    var values: (height: CGFloat, iconsSize: CGFloat, cornerRadius: PeptideButtonCornerType, spaceBetweenIconsAndText: CGFloat) {
        switch self {
        case .large(let height, let iconsSize, let cornerRadius, let spaceBetweenIconsAndText),
                .medium(let height, let iconsSize, let cornerRadius, let spaceBetweenIconsAndText),
                .small(let height, let iconsSize, let cornerRadius, let spaceBetweenIconsAndText),
                .custom(let height, let iconsSize, let cornerRadius, let spaceBetweenIconsAndText):
            return (height, iconsSize, cornerRadius, spaceBetweenIconsAndText)
        }
    }
    
}


enum PeptideButtonCornerType : CGFloat {
    case `deafult` = 4
    case large = 24
}


#Preview{
    
    VStack {
        
        PeptideButton(title: "Register", onButtonClick: {
            
        })
        
        PeptideButton(title: "Register", buttonState: .loading, onButtonClick: {
            
        })
        
        
        PeptideButton(buttonType: .small(),
                      title: "New Conversation",
                      bgColor: .bgPurple10,
                      contentColor: .textDefaultGray01,
                      buttonState: .default,
                      isFullWidth: false){
        }
        
    }
    
}
