//
//  PeptideImage.swift
//  Revolt
//
//

import SwiftUI

struct PeptideImage: View {
    
    let imageName: ImageResource
    let width: CGFloat
    let height: CGFloat
    let contentMode: ContentMode = .fill

    
    var body: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .frame(width: width, height: height)
            .clipped()
    }
}

#Preview {
    
    VStack {
        
        PeptideImage(imageName: .peptideLogo, width: .size100, height: .size90)
        
        PeptideImage(imageName: .peptideBack, width: .size24, height: .size24)
        
    }
    .fillMaxSize()
    
    
}


