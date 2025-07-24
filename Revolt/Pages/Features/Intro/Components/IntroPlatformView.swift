//
//  IntroPlatformView.swift
//  Revolt
//
//

import SwiftUI

struct IntroPlatformView: View {
    
    var platformName : String
    var platformImage : ImageResource
    var url : String
    var onClick : (String) -> Void
    
    var body: some View {
        
        Button(action: {
            withAnimation{
                onClick(url)
            }
        }) {
            
            VStack(alignment: .center, spacing: .spacing8){
                
                Image(platformImage)
                    .frame(width: .size72, height: .size72)
                    .background{
                        RoundedRectangle(cornerRadius: .radius8)
                            .fill(.bgPurple10)
                    }
                
                PeptideText(text: platformName,
                            font: .peptideBody,
                            textColor: .textGray06,
                            alignment: .center)
                .lineLimit(1)
                
            }
        }
    }
}

#Preview {
    
    HStack(spacing: .spacing24){
        IntroPlatformView(platformName: "PepChat",
                          platformImage: .peptidePlatform,
                          url: "https://peptide.chat/api"){_ in
            
        }
        
        IntroPlatformView(platformName: "Revolt",
                          platformImage: .peptideRevolt,
                          url: "https://app.revolt.chat/api"){_ in
            
        }
        
    }
    
    
}
