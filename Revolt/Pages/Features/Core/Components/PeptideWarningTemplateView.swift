//
//  PeptideWarningTemplateView.swift
//  Revolt
//
//

import SwiftUI

struct PeptideWarningTemplateView: View {
    
    @EnvironmentObject private var viewState : ViewState
    
    var body: some View {
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "")){_,_ in
            
            Image(.peptideWelcome)
                .padding(.padding8)
            
            PeptideText(text: "The selected item has been removed or is no longer available.",
                        font: .peptideTitle4)
            .padding(.padding16)
            
            
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    PeptideWarningTemplateView()
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
