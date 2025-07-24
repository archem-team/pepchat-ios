//
//  PeptideText.swift
//  Revolt
//
//

import Foundation
import SwiftUI


struct PeptideText: View {
    var text: LocalizedStringKey
    var textVerbatim : String?
    var font: PeptideFont = .peptideBody2
    var textColor: Color = .textDefaultGray01
    var alignment: TextAlignment = .center
    var lineLimit: Int? =  nil
    
    init(text: String? = nil,
         textVerbatim : String? = nil,
         font: PeptideFont = .peptideBody,
         textColor: Color = .textDefaultGray01,
         alignment: TextAlignment = .center,
         lineLimit: Int? =  nil) {
        
        self.text = LocalizedStringKey(text ?? "")
        self.textVerbatim = textVerbatim
        self.font = font
        self.textColor = textColor
        self.alignment = alignment
        self.lineLimit = lineLimit
    }
    
    
    init(text: LocalizedStringKey,
         textVerbatim : String? = nil,
         font: PeptideFont = .peptideBody,
         textColor: Color = .textDefaultGray01,
         alignment: TextAlignment = .center,
         lineLimit: Int? =  nil) {
        self.text = text
        self.textVerbatim = textVerbatim
        self.font = font
        self.textColor = textColor
        self.alignment = alignment
        self.lineLimit = lineLimit
    }
    
    
    var body: some View {
        
        let (fontType, fontWeight, fontLineHeight) = font.getFontData()
        
        HStack {
        
            Group {
                if let textVerbatim = textVerbatim {
                    Text(verbatim: textVerbatim)
                } else {
                    Text(text)
                }
            }
            .fontWithLineHeight(font: fontType, lineHeight: fontLineHeight)
            .fontWeight(fontWeight)
            .foregroundStyle(textColor)
            .multilineTextAlignment(alignment)
            .lineLimit(lineLimit)

        }
        
       
       
    }
}

struct FontWithLineHeight: ViewModifier {
    let font: UIFont
    let lineHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .font(Font(font))
            .lineSpacing(lineHeight - font.lineHeight)
            .padding(.vertical, (lineHeight - font.lineHeight) / 2)
    }
}

extension View {
    func fontWithLineHeight(font: UIFont, lineHeight: CGFloat) -> some View {
        ModifiedContent(content: self, modifier: FontWithLineHeight(font: font, lineHeight: lineHeight))
    }
}


#Preview {
    
    VStack {
        
        PeptideText(text: "Join endless",
                    textColor: .blue)
        
        
        PeptideText(text: "Join endless Join endless Join endless Join endless Join endless Join endless Join endless Join endless",
                    textColor: .blue)
    }
    .background(Color.black)

    
}


