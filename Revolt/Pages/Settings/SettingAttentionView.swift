//
//  SettingAttentionView.swift
//  Revolt
//
//

import SwiftUI

struct SettingAttentionView: View {
    
    var items : [String]
    
    var body: some View {
        HStack(spacing: .padding4){
            PeptideIcon(iconName: .peptideInfo,
                        color: .iconYellow07)
            
            PeptideText(text: "Attention",
                        font: .peptideHeadline)
            
            Spacer(minLength: .zero)
        }
        .padding(top: .padding24, bottom: .padding8)
        
        ForEach(items, id: \.self){ item in
            
            HStack(spacing: .zero){
                
                
                
                Circle()
                    .fill(Color.textGray06)
                    .frame(width: .size4, height: .size4)
                    .padding(.horizontal, .padding12)
                
                PeptideText(text: item,
                            font: .peptideBody4,
                            textColor: .textGray06,
                            alignment: .leading)
                
                Spacer(minLength: .zero)
            }
            
            
        }
    }
}

#Preview {
    SettingAttentionView(items: ["Changing your username may change your number tag.",
                                 "You can freely change the case of your username.",
                                 "Your number tag may change at most once a day."])
    .preferredColorScheme(.dark)
}
