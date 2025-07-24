//
//  MfaItem.swift
//  Revolt
//
//

import SwiftUI

struct MfaItem: View {
    
    var icon : ImageResource
    var title : String
    var onClick : () -> Void
    
    var body: some View {
        
        
        Button(action: onClick){
            HStack(spacing: .spacing12){
                PeptideIcon(iconName: icon,
                            size: .size24,
                            color: .iconDefaultGray01)
                
                PeptideText(text: title,
                            font: .peptideButton,
                            textColor: .textDefaultGray01)
                
                Spacer(minLength: .zero)
                
                
                PeptideIcon(iconName: .peptideArrowRight,
                            size: .size24,
                            color: .iconDefaultGray01)
            }
            .frame(minHeight: .size48)
        }
        .padding(top: .padding4,
                 bottom: .padding4,
                 leading: .padding12,
                 trailing: .padding12)

    }
}



#Preview {
    
    VStack(spacing: .spacing24){
        
        MfaItem(icon: .peptideKey, title: "Authenticator App"){
            
        }
            .preferredColorScheme(.dark)
        
        MfaItem(icon: .peptideRefresh, title: "Recovery Code"){
            
        }
            .preferredColorScheme(.dark)
        
    }
 
   
}

