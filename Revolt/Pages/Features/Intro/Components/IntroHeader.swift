//
//  IntroHeader.swift
//  Revolt
//
//

import SwiftUI


extension IntroScreen {
    
    private var introHeaderBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [.bgDefaultPurple13, .bgDefaultPurple13.opacity(0.0)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    var introHeader: some View {
        Image(.peptideTextLogo)
            .frame(maxWidth: .infinity, minHeight: .size80)
            .background(introHeaderBackground)
    }
}

