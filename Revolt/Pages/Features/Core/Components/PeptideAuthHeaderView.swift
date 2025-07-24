//
//  PeptideAuthHeaderView.swift
//  Revolt
//
//

import SwiftUI

struct PeptideAuthHeaderView: View {
    var imageResourceName: ImageResource
    var title: String
    var subtitle: String
    
    var body: some View {
        VStack(spacing: .zero) {
            Image(imageResourceName)
                .padding(.top, .padding16)
                .padding(.bottom, .padding4)
            
            PeptideText(text: title, font: .peptideTitle1)
                .padding(.bottom, .padding4)
            
            PeptideText(text: subtitle,
                        font: .peptideBody3,
                        textColor: .textGray06)
                .offset(y: -1 * .size4)
        }
    }
}


#Preview {
    PeptideAuthHeaderView(
        imageResourceName : .peptideLogin,
        title: "welcome-back",
        subtitle : "great-to-see-you-again"
    )
}

