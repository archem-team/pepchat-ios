//
//  AttachmentsSheet.swift
//  Revolt
//
//

import SwiftUI

struct AttachmentsSheet: View {
    @Binding var isPresented : Bool
    var onClick : (Attachments) -> Void
    
    var body: some View {
        HStack(spacing: 24) {
            ForEach(Attachments.allCases, id: \.self){ item in
                PeptideIconWithTitleButton(icon: item.icon,
                                           title: item.title,
                                           iconColor: .iconDefaultGray01,
                                           backgroundSize: .size48,
                                           titleColor: .textDefaultGray01,
                                           spacing: .spacing4,
                                           titleFont: .peptideCallout,
                                           onClick: {
                    onClick(item)
                    isPresented.toggle()
                })
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .presentationDetents([.height(100)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
    }
}

enum Attachments : CaseIterable {
    case gallery
    case camera
    case file
    
    var title : String {
        switch self {
        case .gallery:
            "Gallery"
        case .camera:
            "Camera"
        case .file:
            "File"
        }
    }
    
    var icon : ImageResource {
        switch self {
        case .gallery:
                .peptideGallery
        case .camera:
                .peptideCamera
        case .file:
                .peptideAttachment
        }
    }
}

#Preview {
    AttachmentsSheet(isPresented: .constant(true), onClick: { _ in
    })
        .preferredColorScheme(.dark)
}
