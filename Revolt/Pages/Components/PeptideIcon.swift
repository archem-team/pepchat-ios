//
//  PeptideIcon.swift
//  Revolt
//
//

import SwiftUI

struct PeptideIcon: View {
    
    let iconName: ImageResource
    var size: CGFloat = .size24
    var color : Color = .iconGray04

    
    var body: some View {
        Image(iconName)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .clipped()
    }
}


#Preview {
    
    VStack {
        
        PeptideIcon(iconName: .peptideInfo)
        //PeptideIcon(iconName: .peptideClose, color: .iconRed07)
        
        ZStack {
            Circle().fill(Color.bgYellow07)
            PeptideIcon(iconName: .peptideReply,
                        size: .size20,
                        color: .iconInverseGray13)
        }
        .frame(width: .size32, height: .size32)
        
    }
    
}


