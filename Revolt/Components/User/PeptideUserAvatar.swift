//
//  PeptideUserAvatar.swift
//  Revolt
//
//

import SwiftUI
import Types

struct PeptideUserAvatar: View {
    
    var user: User
    var member: Member?
    
    var nameStyle : PeptideFont = .peptideCallout
    var usernameStyle : PeptideFont = .peptideCaption1
    var spaceBetween : CGFloat = .spacing8
    
    var usernameColor : Color = .textGray07
    
    var body: some View {
        HStack(spacing: spaceBetween){
            
            Avatar(user: user, member: member,
                   width: .size40,
                   height: .size40,
                   withPresence: false)
            
            VStack(alignment: .leading, spacing: .zero){
                
                PeptideText(textVerbatim: member?.nickname ?? user.display_name ?? user.username,
                            font: nameStyle,
                            textColor: .textDefaultGray01)
                
                PeptideText(textVerbatim: user.usernameWithDiscriminator(),
                            font: usernameStyle,
                            textColor: usernameColor)
                
                
            }
            
            Spacer(minLength: .zero)
            
        }
    }
}

#Preview {
    PeptideUserAvatar(user: .init(id: "1",
                                  username: "abcd#1225",
                                  discriminator: ""),
                      member: nil)
    .preferredColorScheme(.dark)
}
