//
//  TextStyle.swift
//  Revolt
//
//

import Foundation


import SwiftUI


extension Font {
    //"MuktaMahee-Light"
    //"MuktaMahee-Bold"
    static let peptideCustomFontName = "MuktaMahee-Regular" // Update with the correct font name if different
    
    static let peptideLargeTitleFont = Font.custom(peptideCustomFontName, size: 32).weight(.regular)
    static let peptideTitle1Font = Font.custom(peptideCustomFontName, size: 26).weight(.semibold)
    static let peptideTitle2Font = Font.custom(peptideCustomFontName, size: 20).weight(.regular)
    static let peptideTitle3Font = Font.custom(peptideCustomFontName, size: 18).weight(.regular)
    static let peptideTitle4Font = Font.custom(peptideCustomFontName, size: 18).weight(.bold)
    static let peptideHeadlineFont = Font.custom(peptideCustomFontName, size: 15).weight(.semibold)
    static let peptideBodyFont = Font.custom(peptideCustomFontName, size: 15).weight(.regular)
    
    static let peptideBody1Font = Font.custom(peptideCustomFontName, size: 18).weight(.light)
    static let peptideBody2Font = Font.custom(peptideCustomFontName, size: 16).weight(.regular)
    static let peptideBody3Font = Font.custom(peptideCustomFontName, size: 15).weight(.regular)
    static let peptideBody4Font = Font.custom(peptideCustomFontName, size: 14).weight(.light)
    
    
    
    static let peptideButtonFont = Font.custom(peptideCustomFontName, size: 15).weight(.regular)
    static let peptideCalloutFont = Font.custom(peptideCustomFontName, size: 14).weight(.regular)
    static let peptideSubheadFont = Font.custom(peptideCustomFontName, size: 13).weight(.regular)
    static let peptideFootnoteFont = Font.custom(peptideCustomFontName, size: 12).weight(.regular)
    static let peptideCaption1Font = Font.custom(peptideCustomFontName, size: 11).weight(.regular)
    

}

enum PeptideFont {
    case peptideLargeTitle
    case peptideTitle1
    case peptideTitle2
    case peptideTitle3
    case peptideTitle4
    case peptideHeadline
    case peptideBody
    case peptideBody1
    case peptideBody2
    case peptideBody3
    case peptideBody4
    
    case peptideButton
    case peptideCallout
    case peptideSubhead
    case peptideFootnote
    case peptideCaption1
    
    var fontSize : CGFloat {
        switch self {
        case .peptideLargeTitle:
            32
        case .peptideTitle1:
            26
        case .peptideTitle2:
            20
        case .peptideTitle3:
            18
        case .peptideTitle4:
            18
        case .peptideHeadline:
            15
        case .peptideBody:
            15
        case .peptideBody1:
            18
        case .peptideBody2:
            16
        case .peptideBody3:
            15
        case .peptideBody4:
            14
        case .peptideButton:
            15
        case .peptideCallout:
            14
        case .peptideSubhead:
            13
        case .peptideFootnote:
            12
        case .peptideCaption1:
            11
        }
    }
    
    func getFontData() -> (font: UIFont, weight: Font.Weight, lineHeight : CGFloat){
        switch self {
        case .peptideLargeTitle:
            (UIFont(name: Font.peptideCustomFontName, size: 32)!, .regular, 39)
        case .peptideTitle1:
            (UIFont(name: Font.peptideCustomFontName, size: 26)!, .semibold, 32)
        case .peptideTitle2:
            (UIFont(name: Font.peptideCustomFontName, size: 20)!, .regular, 24)
        case .peptideTitle3:
            (UIFont(name: Font.peptideCustomFontName, size: 18)!, .regular, 23)
        case .peptideTitle4:
            (UIFont(name: Font.peptideCustomFontName, size: 18)!, .bold, 23)
        case .peptideHeadline:
            (UIFont(name: Font.peptideCustomFontName, size: 15)!, .semibold, 20)
        case .peptideBody:
            (UIFont(name: Font.peptideCustomFontName, size: 15)!, .regular, 23)
        case .peptideBody1:
            (UIFont(name: Font.peptideCustomFontName, size: 18)!, .light, 23)
        case .peptideBody2:
            (UIFont(name: Font.peptideCustomFontName, size: 16)!, .regular, 21)
        case .peptideBody3:
            (UIFont(name: Font.peptideCustomFontName, size: 15)!, .regular, 20)
        case .peptideBody4:
            (UIFont(name: Font.peptideCustomFontName, size: 14)!, .light, 19)
        case .peptideButton:
            (UIFont(name: Font.peptideCustomFontName, size: 15)!, .regular, 20)
        case .peptideCallout:
            (UIFont(name: Font.peptideCustomFontName, size: 14)!, .regular, 19)
        case .peptideSubhead:
            (UIFont(name: Font.peptideCustomFontName, size: 13)!, .regular, 18)
        case .peptideFootnote:
            (UIFont(name: Font.peptideCustomFontName, size: 12)!, .regular, 16)
        case .peptideCaption1:
            (UIFont(name: Font.peptideCustomFontName, size: 11)!, .regular, 13)
        }
    }
    
    
    var font : UIFont { //(font: UIFont, weight: Font.Weight, lineHeight : CGFloat){
        switch self {
        case .peptideLargeTitle:
            (UIFont(name: Font.peptideCustomFontName, size: 32)!)
        case .peptideTitle1:
            (UIFont(name: Font.peptideCustomFontName, size: 26)!)
        case .peptideTitle2:
            (UIFont(name: Font.peptideCustomFontName, size: 20)!)
        case .peptideTitle3:
            (UIFont(name: Font.peptideCustomFontName, size: 18)!)
        case .peptideTitle4:
            (UIFont(name: Font.peptideCustomFontName, size: 18)!)
        case .peptideHeadline:
            (UIFont(name: Font.peptideCustomFontName, size: 15)!)
        case .peptideBody:
            (UIFont(name: Font.peptideCustomFontName, size: 15)!)
        case .peptideBody1:
            (UIFont(name: Font.peptideCustomFontName, size: 18)!)
        case .peptideBody2:
            (UIFont(name: Font.peptideCustomFontName, size: 16)!)
        case .peptideBody3:
            (UIFont(name: Font.peptideCustomFontName, size: 15)!)
        case .peptideBody4:
            (UIFont(name: Font.peptideCustomFontName, size: 14)!)
        case .peptideButton:
            (UIFont(name: Font.peptideCustomFontName, size: 15)!)
        case .peptideCallout:
            (UIFont(name: Font.peptideCustomFontName, size: 14)!)
        case .peptideSubhead:
            (UIFont(name: Font.peptideCustomFontName, size: 13)!)
        case .peptideFootnote:
            (UIFont(name: Font.peptideCustomFontName, size: 12)!)
        case .peptideCaption1:
            (UIFont(name: Font.peptideCustomFontName, size: 11)!)
        }
    }
    
}
