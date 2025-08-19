//
//  BadgeView.swift
//  Revolt
//
//

import SwiftUI
import Types

/// A view that displays a single badge
struct BadgeView: View {
    let badge: Badges
    let size: CGFloat
    
    init(badge: Badges, size: CGFloat = 20) {
        self.badge = badge
        self.size = size
    }
    
    var body: some View {
        Image(badge.getImage())
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// A view that displays multiple badges horizontally
struct UserBadgesView: View {
    let badges: [Badges]
    let badgeSize: CGFloat
    let spacing: CGFloat
    
    init(badges: [Badges], badgeSize: CGFloat = 20, spacing: CGFloat = 4) {
        self.badges = badges
        self.badgeSize = badgeSize
        self.spacing = spacing
    }
    
    var body: some View {
        if !badges.isEmpty {
            HStack(spacing: spacing) {
                ForEach(badges, id: \.self) { badge in
                    BadgeView(badge: badge, size: badgeSize)
                }
            }
        }
    }
}



#Preview {
    VStack(spacing: 16) {
        // Single badge preview
        BadgeView(badge: .developer)
        
        // Multiple badges preview
        UserBadgesView(badges: [.developer, .founder, .supporter])
        
        // Empty badges preview
        UserBadgesView(badges: [])
    }
    .padding()
    .preferredColorScheme(.dark)
}
