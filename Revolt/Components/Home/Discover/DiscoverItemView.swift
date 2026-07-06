//
//  DiscoverItemView.swift
//  Revolt
//
//

import SwiftUI
import Kingfisher

struct DiscoverItemView: View {
    
    var discoverItem: DiscoverItem
    var onClick : () -> Void
    var isMember: Bool = false
    @EnvironmentObject var viewState: ViewState
    
    // Helper function to determine the display color
    private var displayColor: Color {
        if let colorHex = discoverItem.color, !colorHex.isEmpty, colorHex.hasPrefix("#") {
            // Parse custom color from the Discover server API
            return Color(hex: colorHex) ?? (discoverItem.isNew ? .textYellow07 : .textDefaultGray01)
        } else if discoverItem.isNew {
            // Use yellow for new items
            return .textYellow07
        } else {
            // Use default gray for normal items
            return .textDefaultGray01
        }
    }
    
    private var iconColor: Color {
        if let colorHex = discoverItem.color, !colorHex.isEmpty, colorHex.hasPrefix("#") {
            // Parse custom color from the Discover server API
            return Color(hex: colorHex) ?? (discoverItem.isNew ? .iconYellow07 : .iconDefaultGray01)
        } else if discoverItem.isNew {
            // Use yellow for new items
            return .iconYellow07
        } else {
            // Use default gray for normal items
            return .iconDefaultGray01
        }
    }
    
    private var arrowIconColor: Color {
        if isMember {
            return .iconGreen07
        } else if let colorHex = discoverItem.color, !colorHex.isEmpty, colorHex.hasPrefix("#") {
            // Parse custom color from the Discover server API
            return Color(hex: colorHex) ?? (discoverItem.isNew ? .iconYellow07 : .iconGray07)
        } else if discoverItem.isNew {
            return .iconYellow07
        } else {
            return .iconGray07
        }
    }

    private var logoURL: URL? {
        guard let logo = discoverItem.logo, !logo.isEmpty else { return nil }
        let autumnURL = viewState.apiInfo?.features.autumn.url ?? "https://peptide.chat/autumn"
        let autumnBaseURL = autumnURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(autumnBaseURL)/icons/\(logo)?max_side=256")
    }
    
    var body: some View {
        
        Button{
            // print("🔗 [DiscoverItemView] Clicked on server: \(discoverItem.title)")
            // print("   📎 Invite code: \(discoverItem.code)")
            // print("   🔒 Disabled: \(discoverItem.disabled)")
            // print("   👥 Is Member: \(isMember)")
            onClick()
        } label: {
            
            HStack(spacing: .spacing12){
                
                
                DiscoverServerIcon(
                    logoURL: logoURL,
                    isDisabled: discoverItem.disabled,
                    fallbackColor: iconColor
                )
                
                VStack(alignment: .leading, spacing: .spacing2){
                    
                    HStack(spacing: .spacing4) {
                        PeptideText(text: discoverItem.title,
                                    font: .peptideCallout,
                                    textColor: displayColor,
                                    alignment: .leading)
                        
                        // Show member badge if user is a member
                        // if isMember {
                        //     Text("MEMBER")
                        //         .font(.system(size: 10, weight: .bold))
                        //         .foregroundColor(.white)
                        //         .padding(.horizontal, 6)
                        //         .padding(.vertical, 2)
                        //         .background(Color.green)
                        //         .cornerRadius(4)
                        // }
                    }
                    
                    PeptideText(text: discoverItem.description,
                                font: .peptideCaption1,
                                textColor: .textGray07,
                                alignment: .leading,
                                lineLimit: 2)
                    
                }
                
                Spacer(minLength: .zero)
                
                PeptideIcon(iconName: isMember ? .peptideDoneCircle : .peptideArrowRight,
                            size: .size20,
                            color: arrowIconColor)
                
                
            }
            .padding(.padding8)
            .frame(minHeight: .size64)
            .opacity(self.discoverItem.disabled ? 0.5 : 1.0)
            .background{
                RoundedRectangle(cornerRadius: .radius8).fill(Color.bgGray11)
            }
        }
        
    }
}

private struct DiscoverServerIcon: View {
    let logoURL: URL?
    let isDisabled: Bool
    let fallbackColor: Color

    @State private var didLoadLogo = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let logoURL {
                KFImage(logoURL)
                    .cacheOriginalImage()
                    .placeholder { fallbackIcon }
                    .onSuccess { _ in didLoadLogo = true }
                    .onFailure { _ in didLoadLogo = false }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                fallbackIcon
            }

            if isDisabled && didLoadLogo {
                Circle()
                    .fill(Color.bgGray11)
                    .frame(width: 14, height: 14)
                    .overlay {
                        PeptideIcon(
                            iconName: .peptideLock,
                            size: 9,
                            color: fallbackColor
                        )
                    }
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 32, height: 32)
        .onChange(of: logoURL) { _ in
            didLoadLogo = false
        }
    }

    private var fallbackIcon: some View {
        PeptideIcon(
            iconName: isDisabled ? .peptideLock : .peptideTeamUsers,
            size: .size24,
            color: fallbackColor
        )
        .frame(width: 32, height: 32)
    }
}


