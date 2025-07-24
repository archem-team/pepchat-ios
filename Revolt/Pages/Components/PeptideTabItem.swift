//
//  PeptideTabItem.swift
//  Revolt
//
//

import SwiftUI


struct PeptideTabItemIndicator: View {
    
    var isSelected: Bool = false
    var label : String
    var onClick : () -> Void
    
    var body: some View {
        
        
        Button {
            
            withAnimation{
                onClick()
            }
            
        } label: {
            
            ZStack(alignment: .bottom) {
                VStack(spacing: .zero){
                    
              
                    
                    PeptideText(text: label,
                                font: .peptideButton,
                                textColor:.textDefaultGray01)
                    
                }
                .frame(height: .size36)
                
                if isSelected {
                    
                    UnevenRoundedRectangle(topLeadingRadius: .radiusXSmall, topTrailingRadius: .radiusXSmall)
                        .fill(Color.bgYellow07)
                        .frame(height: 2)
             
                } else {
                    PeptideDivider(size: 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        
        
        

    }
}


struct PeptideTabItem: View {
    
    var isSelected: Bool = false
    var icon : ImageResource
    var label : String
    var onClick : () -> Void
    
    var body: some View {
        
        
        Button {
            
            withAnimation{
                onClick()
            }
            
        } label: {
            
            VStack(spacing: .zero){
                
                PeptideIcon(iconName: icon,
                            size: .size24,
                            color: isSelected ? .iconDefaultGray01 : .iconGray07)
                
                PeptideText(text: label,
                            font: .peptideButton,
                            textColor: isSelected ? .textDefaultGray01 : .textGray07)
                
            }
            .frame(maxWidth: .infinity)
        }
        
        
        

    }
}

#Preview {
    /*PeptideTabItem(icon: .peptideHome, label: "Home", onClick: {
        
    })*/
    
    HStack(spacing: .zero) {
        PeptideTabItemIndicator(isSelected: true,
                                label: "Latest"){
            
        }
        
        PeptideTabItemIndicator(label: "New"){
            
        }
    }
    
    
   
        .preferredColorScheme(.dark)
}
