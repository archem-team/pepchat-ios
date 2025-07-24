//
//  PeptideSectionHeader.swift
//  Revolt
//
//

import SwiftUI

struct PeptideSectionHeader: View {
    
    var title : String
    
    var body: some View {
        HStack(spacing: .zero){
            
            PeptideText(text: title,
                        font: .peptideHeadline,
                        textColor: .textGray07)
            
            Spacer(minLength: .zero)
            
        }
        .padding(top: .padding24, bottom: .padding8)
    }
}

#Preview {
    PeptideSectionHeader(title: "Users")
        .preferredColorScheme(.dark)
}
