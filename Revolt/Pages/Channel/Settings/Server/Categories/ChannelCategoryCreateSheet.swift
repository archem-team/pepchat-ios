//
//  ChannelCategoryCreateSheet.swift
//  Revolt
//
//

import SwiftUI

struct ChannelCategoryCreateSheet: View {
    
    @Binding var isPresented: Bool
    var onNavigate : (ChannelCategoryCreateType) -> Void

    
    var body: some View {
        PeptideSheet(isPresented: $isPresented, topPadding: .padding24){
            
            PeptideText(text: "Create",
                        font: .peptideHeadline,
                        textColor: .textDefaultGray01)
            .padding(.bottom, .padding24)
            
            VStack(spacing: .spacing4){
                
                Button {
                    onNavigate(.categories)
                    isPresented.toggle()
                } label: {
                    
                    PeptideActionButton(icon: .peptideFolder,
                                        title: "Categories",
                                        hasArrow: true)
                }
                
                PeptideDivider()
                    .padding(.leading, .padding48)
                
                Button {
                    onNavigate(.channels)
                    isPresented.toggle()
                } label: {
                    
                    PeptideActionButton(icon: .peptideTag,
                                        title: "Channels",
                                        hasArrow: true)
                }
                
            }
            .backgroundGray11(verticalPadding: .padding4)
        }
    }
}


enum ChannelCategoryCreateType : Hashable, Codable{
    case categories
    case channels
}

#Preview {
    ChannelCategoryCreateSheet(isPresented: .constant(true), onNavigate: {type in
    })
}
