//
//  AlertPopup.swift
//  Revolt
//
//  Created by Angelo on 13/10/2024.
//

import Foundation
import SwiftUI

struct AlertPopup<C: View, P: View>: View {
    @EnvironmentObject var viewState: ViewState

    var show: Bool
    var inner: C
    var popup: () -> P

    var body: some View {
        inner.overlay(alignment: .top) {
            if show {
                popup()
                    .padding()
                    .padding(.top, .padding8)
                    .transition(.move(edge: .top))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}


struct AlertMessagePopup : View {
    
    var message : String
    var icon : ImageResource? = nil
    var iconColor : Color = .iconDefaultGray01
    
    var body: some View {
        HStack(spacing: .spacing4){
            
            if let icon = icon {
                PeptideIcon(iconName: icon, color: iconColor)
            }
            
            PeptideText(text: message,
                        font: .peptideCallout,
                        textColor: .textDefaultGray01)
        }
        .padding(.padding8)
        .frame(minHeight: .size32)
        .background{
            RoundedRectangle(cornerRadius: .radiusLarge).fill(Color.bgGray11)
                .overlay{
                    RoundedRectangle(cornerRadius: .radiusLarge)
                        .stroke(Color.borderGray10, lineWidth: .size1)
                }
        }
    }
}


#Preview{
    AlertMessagePopup(message: "Direct Message ID Copied!")
        .preferredColorScheme(.dark)
}
