//
//  PeptideActionButton.swift
//  Revolt
//
//

import SwiftUI

struct PeptideActionButton: View {
    
    var icon : ImageResource
    var iconColor : Color = .iconDefaultGray01
    var iconSize : CGFloat = .size24
    
    var title : String
    var titleColor : Color = .textDefaultGray01
    var titleAlignment: TextAlignment = .center
    
    var subTitle : String? = nil
    var subTitleColor : Color = .textGray06
    
    var value : String? = nil
    var valueStyle : PeptideFont = .peptideSubhead
    var valueColor : Color = .textDefaultGray01
    
    var iconAction : ImageResource? = nil
    var onClicIconAction : () -> Void = {}
    
    
    var arrowColor : Color = .iconDefaultGray01
    var arrowIcon : ImageResource = .peptideArrowRight
    var hasArrow : Bool = true
    
    var hasToggle : Bool = false
    var toggleChecked : Bool = true
    var onToggle: ((Bool) -> Void)?
    
    var body: some View {
        
        HStack(spacing: .spacing12){
            
            PeptideIcon(iconName: icon,
                        size: iconSize,
                        color: iconColor)
                
            VStack(alignment: .leading, spacing: .zero){
                PeptideText(textVerbatim: title,
                            font: .peptideButton,
                            textColor: titleColor,
                            alignment: titleAlignment)
                
                if let subTitle = subTitle {
                    PeptideText(text: subTitle,
                                font: .peptideCaption1,
                                textColor: subTitleColor,
                                alignment: .leading)
                }
                
            }
            
            
            Spacer(minLength: .zero)
            
            if let iconAction = iconAction {
                PeptideIconButton(icon: iconAction,
                                  color: .iconRed07,
                                  size: .size24,
                                  onClick: onClicIconAction)
            }
            
            if let value = value {
                PeptideText(textVerbatim: value,
                            font: valueStyle,
                            textColor: valueColor,
                            alignment: .center,
                            lineLimit: 1)
            }
            
            if hasToggle {
                Button {
                    if let onToggle {
                        onToggle(!toggleChecked)
                    }
                } label: {
                    Toggle("", isOn: Binding(
                        get: { toggleChecked },
                        set: { newValue in
                            if let onToggle {
                                onToggle(newValue)
                            }
                        }
                    ))
                    .toggleStyle(PeptideSwitchToggleStyle())
                }
            }
            
            if hasArrow {
                PeptideIcon(iconName: arrowIcon,
                            size: .size24,
                            color: arrowColor)
            }
            
            
            
        }
        .padding(.horizontal, .padding12)
        .frame(height: .size48)
        
    }
}


struct BackgroundGray11Modifier: ViewModifier {
    var hasBorder: Bool = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: .radiusMedium)
                    .fill(Color.bgGray11)
                    .stroke(.borderGray10, lineWidth: hasBorder ? .size1 : .zero)
            )
    }
}

struct BackgroundGray12Modifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: .radiusMedium)
                    .fill(Color.bgGray12)
            )
    }
}

extension View {
    func backgroundGray11(verticalPadding  : CGFloat = .zero,
                          horizontalPadding: CGFloat = .zero,
                          hasBorder: Bool = false
    ) -> some View {
        self
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .modifier(BackgroundGray11Modifier(hasBorder: hasBorder))
    }
    
    func backgroundGray12(verticalPadding  : CGFloat = .zero,
                          horizontalPadding: CGFloat = .zero) -> some View {
        self
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .modifier(BackgroundGray12Modifier())
    }
}

#Preview {
    
    VStack(spacing: 32){
        
        PeptideActionButton(icon: .peptideNewGroup,
                            title: "New Group",
                            iconAction: .peptideTrashDelete,
                            onClicIconAction: {
            
        })
        .backgroundGray11(
            verticalPadding: .padding4,
            horizontalPadding: .padding12
        )
        
        
        PeptideActionButton(icon: .peptideNewUser,
                            title: "Add a Friend")
        
        PeptideActionButton(
                            icon: .peptideNewUser,
                            title: "Add a Friend",
                            hasArrow: false,
                            hasToggle: true
            
        )
        
    }
    
    
        .preferredColorScheme(.dark)
}
