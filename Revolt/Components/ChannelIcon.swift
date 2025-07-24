//
//  ChannelIcon.swift
//  Revolt
//
//  Created by Angelo on 18/10/2023.
//

import Foundation
import SwiftUI
import Types

/// A view that displays an icon representing a channel, along with its name.
///
/// The `ChannelIcon` view presents different types of channels (text, voice, group DM, DM, saved messages)
/// with appropriate icons and names. The icon can be a custom image or a system icon, depending on the
/// channel type and its properties.
struct ChannelIcon: View {
    @EnvironmentObject var viewState: ViewState
    
    /// The channel to be represented by the icon.
    var channel: Channel
    
    /// A boolean indicating whether to display the user's presence indicator.
    var withUserPresence: Bool = false
    
    /// The spacing between the icon and the text.
    var spacing: CGFloat = .padding8
    
    /// The initial size of the icon.
    var initialSize: (CGFloat, CGFloat) = (20, 20)
    
    /// The frame size of the icon.
    var frameSize: (CGFloat, CGFloat) = (32, 32)
    
    var font: PeptideFont = .peptideCallout

    /// The body of the `ChannelIcon`.
    ///
    /// The body determines the layout based on the channel type. It uses a horizontal stack (`HStack`)
    /// to display the channel icon and name. Depending on the channel type, it either shows a custom
    /// image, a system icon, or an avatar for direct messages.
    var body: some View {
        HStack(spacing: spacing) {
            switch channel {
            case .text_channel(let c):
                
                if let icon = c.icon {
                    LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.0, clipTo: Circle())
                        .frame(width: frameSize.0, height: frameSize.1)
                } else {
                    
                    PeptideIcon(iconName: c.voice != nil ? .peptideTag : .peptideTag,
                                size: initialSize.0,
                                color: .iconGray07)
                }
                
            
                PeptideText(text: c.name,
                            font: font,
                            textColor: .textDefaultGray01)
                
                Spacer(minLength: .zero)

          
            case .voice_channel(let c):
                
                if let icon = c.icon {
                    LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.0, clipTo: Circle())
                        .frame(width: frameSize.0, height: frameSize.1)
                } else {
                   
                    PeptideIcon(iconName: .peptideTag,
                                size: initialSize.0,
                                color: .iconGray07)
                }
                
                PeptideText(text: c.name,
                            font: font,
                            textColor: .textDefaultGray01)
                
                Spacer(minLength: .zero)

            case .group_dm_channel(let c):
                
                Group {
                    if let icon = c.icon {
                        LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.1, clipTo: Circle())
                            .frame(width: frameSize.0, height: frameSize.1)
                    } else {
                        PeptideIcon(iconName: .peptideUsers,
                                    size: initialSize.0,
                                    color: .iconDefaultGray01)
                        .frame(width: frameSize.0, height: frameSize.1)
                        .background(Circle().fill(Color.bgGreen07))
                    }
                }
                .padding(.leading, .padding16)

                
                
                
                VStack(alignment : .leading, spacing: .zero){
                    PeptideText(text: c.name,
                                font: font,
                                textColor: .textDefaultGray01)
                    
                    PeptideText(text: "\(c.recipients.count) Members",
                                font: .peptideCaption1,
                                textColor: .textGray07)
                }
                
                
                Spacer(minLength: .zero)
                
                PeptideIcon(iconName: .peptideArrowRight,
                            size: .size20,
                            color: .iconGray07)
                .padding(.trailing, .padding16)

                                
            case .dm_channel(let c):
                
                if let recipient = viewState.getDMPartnerName(channel: c){
                    
                    Avatar(user: recipient, withPresence: withUserPresence)
                        .frame(width: frameSize.0, height: frameSize.1)
                        .padding(.leading, .padding16)

                    VStack(alignment: .leading, spacing: .zero){
                        PeptideText(text: recipient.username,
                                    font: font, textColor: .textDefaultGray01)
                        let isOnline = recipient.online == true
                        let presenceText = isOnline ?  (recipient.status?.presence?.rawValue ?? Presence.Online.rawValue) : "Offline"
                        
                        PeptideText(text: recipient.status?.text ?? presenceText	,
                                    font: .peptideCaption1,
                                    textColor: .textGray07)
                    }
                    
                    Spacer(minLength: .zero)
                    
                    PeptideIcon(iconName: .peptideArrowRight,
                                size: .size20,
                                color: .iconGray07)
                    .padding(.trailing, .padding16)

                    
                }
                

                
            case .saved_messages(_):
                
                
                PeptideIcon(iconName: .peptideBookmark,
                            size: initialSize.0,
                            color: .iconDefaultGray01)
                .frame(width: frameSize.0, height: frameSize.1)
                .background(Circle().fill(Color.bgGreen07))
                .padding(.leading, .padding16)

                
                PeptideText(text: "Saved Messages",
                            font: font,
                            textColor: .textDefaultGray01)
                
                Spacer(minLength: .zero)
                
                PeptideIcon(iconName: .peptideArrowRight,
                            size: .size20,
                            color: .iconGray07)
                .padding(.trailing, .padding16)


                
            }
        }
        .padding(top: .padding8, bottom: .padding8)
    }
}

/// A preview provider for the `ChannelIcon` view.
///
/// This provides a preview layout for the `ChannelIcon`, allowing for visualization
/// of how the view will look with sample data.
struct ChannelIcon_Preview: PreviewProvider {
    static var viewState: ViewState = ViewState.preview()
    
    static var previews: some View {
        
        VStack {
            
            ChannelIcon(channel: viewState.channels["2"]!)
                .previewLayout(.sizeThatFits)
                .preferredColorScheme(.dark)
            
        }
        .preferredColorScheme(.dark)
        
        
    }
}



struct ChannelIconDM: View {
    @EnvironmentObject var viewState: ViewState
    
    /// The channel to be represented by the icon.
    var channel: Channel
    
    /// A boolean indicating whether to display the user's presence indicator.
    var withUserPresence: Bool = false
    
    /// The spacing between the icon and the text.
    var spacing: CGFloat = .padding8
    
    /// The initial size of the icon.
    var initialSize: (CGFloat, CGFloat) = (20, 20)
    
    /// The frame size of the icon.
    var frameSize: (CGFloat, CGFloat) = (32, 32)
    
    var font: PeptideFont = .peptideCallout

    /// The body of the `ChannelIcon`.
    ///
    /// The body determines the layout based on the channel type. It uses a horizontal stack (`HStack`)
    /// to display the channel icon and name. Depending on the channel type, it either shows a custom
    /// image, a system icon, or an avatar for direct messages.
    var body: some View {
        HStack(spacing: spacing) {
            switch channel {
            case .text_channel(let c):
                
                if let icon = c.icon {
                    LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.0, clipTo: Circle())
                        .frame(width: frameSize.0, height: frameSize.1)
                } else {
                    
                    PeptideIcon(iconName: c.voice != nil ? .peptideTag : .peptideTag,
                                size: initialSize.0,
                                color: .iconGray07)
                }
                
            
                PeptideText(text: c.name,
                            font: font,
                            textColor: .textDefaultGray01)
                
                Spacer(minLength: .zero)

          
            case .voice_channel(let c):
                
                if let icon = c.icon {
                    LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.0, clipTo: Circle())
                        .frame(width: frameSize.0, height: frameSize.1)
                } else {
                   
                    PeptideIcon(iconName: .peptideTag,
                                size: initialSize.0,
                                color: .iconGray07)
                }
                
                PeptideText(text: c.name,
                            font: font,
                            textColor: .textDefaultGray01)
                
                Spacer(minLength: .zero)

            case .group_dm_channel(let c):
                
                let unread = viewState.getUnreadCountFor(channel: channel)
                

                ZStack(alignment: .leading){
                    
                    Group {
                        if let icon = c.icon {
                            LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.1, clipTo: Circle())
                                .frame(width: frameSize.0, height: frameSize.1)
                        } else {
                            PeptideIcon(iconName: .peptideUsers,
                                        size: initialSize.0,
                                        color: .iconDefaultGray01)
                            .frame(width: frameSize.0, height: frameSize.1)
                            .background(Circle().fill(Color.bgGreen07))
                        }
                    }
                    .padding(.leading, .padding16)
                    
                    if let unread = unread{
                      
                        if case .unread = unread {
                            UnreadView(unreadSize: .size8)
                                .offset(x: -4)
                        } else if case .unreadWithMentions = unread {
                            UnreadView(unreadSize: .size8)
                                .offset(x: -4)
                        } else {
                            UnreadView(unreadSize: .size8)
                                .opacity(0)
                        }
                    }

                    
                }
                
                
                VStack(alignment : .leading, spacing: .zero){
                    PeptideText(text: c.name,
                                font: font,
                                textColor: .textDefaultGray01)
                    
                    PeptideText(text: "\(c.recipients.count) Members",
                                font: .peptideCaption1,
                                textColor: .textGray07)
                }
                
                
                Spacer(minLength: .zero)
                
                if case .mentions(let count) = unread {
                    UnreadMentionsView(count: count, mentionSize: .size20)
                } else if case .unreadWithMentions(let count) = unread {
                    UnreadMentionsView(count: count, mentionSize: .size20)
                }
                
                PeptideIcon(iconName: .peptideArrowRight,
                            size: .size20,
                            color: .iconGray07)
                .padding(.trailing, .padding16)

                                
            case .dm_channel(let c):
                
                // CRITICAL FIX: Always show something, even if recipient is nil
                let recipient = viewState.getDMPartnerName(channel: c)
                let unread = viewState.getUnreadCountFor(channel: channel)
                
                ZStack(alignment: .leading){
                    if let recipient = recipient {
                        Avatar(user: recipient, withPresence: withUserPresence)
                            .frame(width: frameSize.0, height: frameSize.1)
                            .padding(.leading, .padding16)
                    } else {
                        // Fallback icon when recipient is nil
                        PeptideIcon(iconName: .peptideUsers,
                                    size: initialSize.0,
                                    color: .iconDefaultGray01)
                        .frame(width: frameSize.0, height: frameSize.1)
                        .background(Circle().fill(Color.bgGray11))
                        .padding(.leading, .padding16)
                    }
                    
                    if let unread = unread{
                       
                        if case .unread = unread {
                            UnreadView(unreadSize: .size8)
                                .offset(x: -4)
                        } else if case .unreadWithMentions = unread {
                            UnreadView(unreadSize: .size8)
                                .offset(x: -4)
                        } else {
                            UnreadView(unreadSize: .size8)
                                .opacity(0)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: .zero){
                    PeptideText(text: recipient?.username ?? "Unknown User",
                                font: font, textColor: .textDefaultGray01)
                    
                    if let recipient = recipient {
                        let isOnline = recipient.online == true
                        let presenceText = isOnline ?  (recipient.status?.presence?.rawValue ?? Presence.Online.rawValue) : "Offline"
                        
                        PeptideText(text: recipient.status?.text ?? presenceText,
                                    font: .peptideCaption1,
                                    textColor: .textGray07)
                    } else {
                        PeptideText(text: "Loading...",
                                    font: .peptideCaption1,
                                    textColor: .textGray07)
                    }
                }
                
                Spacer(minLength: .zero)
                
                if case .mentions(let count) = unread {
                    UnreadMentionsView(count: count, mentionSize: .size20)
                } else if case .unreadWithMentions(let count) = unread {
                    UnreadMentionsView(count: count, mentionSize: .size20)
                }
                
                PeptideIcon(iconName: .peptideArrowRight,
                            size: .size20,
                            color: .iconGray07)
                .padding(.trailing, .padding16)
                

                
            case .saved_messages(_):
                
                
                PeptideIcon(iconName: .peptideBookmark,
                            size: initialSize.0,
                            color: .iconDefaultGray01)
                .frame(width: frameSize.0, height: frameSize.1)
                .background(Circle().fill(Color.bgGreen07))
                .padding(.leading, .padding16)

                
                PeptideText(text: "Saved Messages",
                            font: font,
                            textColor: .textDefaultGray01)
                
                Spacer(minLength: .zero)
                
                PeptideIcon(iconName: .peptideArrowRight,
                            size: .size20,
                            color: .iconGray07)
                .padding(.trailing, .padding16)


                
            }
        }
        .padding(top: .padding8, bottom: .padding8)
    }
}



struct ChannelOnlyIcon : View {
    @EnvironmentObject var viewState: ViewState
    
    /// The channel to be represented by the icon.
    var channel: Channel
    
    /// A boolean indicating whether to display the user's presence indicator.
    var withUserPresence: Bool = false
    
    
    /// The initial size of the icon.
    var initialSize: (CGFloat, CGFloat) = (24, 24)
    
    /// The frame size of the icon.
    var frameSize: (CGFloat, CGFloat) = (40, 40)
    
    var showPlaceHolder : Bool = false
    
    /// The body of the `ChannelIcon`.
    ///
    /// The body determines the layout based on the channel type. It uses a horizontal stack (`HStack`)
    /// to display the channel icon and name. Depending on the channel type, it either shows a custom
    /// image, a system icon, or an avatar for direct messages.
    var body: some View {
        HStack(spacing: .zero) {
            switch channel {
            case .text_channel(let c):
                if let icon = c.icon, !showPlaceHolder {
                    LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.0, clipTo: Circle())
                        .frame(width: frameSize.0, height: frameSize.1)
                } else {
                    
                    PeptideIcon(iconName: c.voice != nil ? .peptideTag : .peptideTag,
                                size: initialSize.0,
                                color: .iconDefaultGray01)
                    .frame(width: frameSize.0, height: frameSize.1)
                }
                
            
            case .voice_channel(let c):
                if let icon = c.icon, !showPlaceHolder  {
                    LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.0, clipTo: Circle())
                        .frame(width: frameSize.0, height: frameSize.1)
                } else {
                   
                    PeptideIcon(iconName: .peptideTag,
                                size: initialSize.0,
                                color: .iconDefaultGray01)
                    .frame(width: frameSize.0, height: frameSize.1)
                }
                
                
                
            case .group_dm_channel(let c):
                if let icon = c.icon, !showPlaceHolder  {
                    LazyImage(source: .file(icon), height: frameSize.0, width: frameSize.1, clipTo: Circle())
                        .frame(width: frameSize.0, height: frameSize.1)
                } else {
                    PeptideIcon(iconName: .peptideUsers,
                                size: initialSize.0,
                                color: .iconDefaultGray01)
                    .frame(width: frameSize.0, height: frameSize.1)
                    .background(Circle().fill(Color.bgGreen07))
                }
                
              
                                
            case .dm_channel(let c):
                
                // CRITICAL FIX: Always show something, even if recipient is nil
                let recipient = viewState.getDMPartnerName(channel: c)
                
                if let recipient = recipient {
                    Avatar(user: recipient,
                           width: frameSize.0,
                           height: frameSize.1,
                           withPresence: withUserPresence)
                        .frame(width: frameSize.0, height: frameSize.1)
                } else {
                    // Fallback icon when recipient is nil
                    PeptideIcon(iconName: .peptideUsers,
                                size: initialSize.0,
                                color: .iconDefaultGray01)
                    .frame(width: frameSize.0, height: frameSize.1)
                    .background(Circle().fill(Color.bgGray11))
                }
                

                
            case .saved_messages(_):
                
                
                PeptideIcon(iconName: .peptideBookmark,
                            size: initialSize.0,
                            color: .iconDefaultGray01)
                .frame(width: frameSize.0, height: frameSize.1)
                .background(Circle().fill(Color.bgGreen07))
                
                
            }
        }
    }
}



struct HomeChannelOnlyIcon : View {
    @EnvironmentObject var viewState: ViewState
    
    /// The channel to be represented by the icon.
    var channel: Channel
    
    /// A boolean indicating whether to display the user's presence indicator.
    var withUserPresence: Bool = false
    
    
    /// The frame size of the icon.
    var frameSize: CGFloat = .size48
    
    /// The body of the `ChannelIcon`.
    ///
    /// The body determines the layout based on the channel type. It uses a horizontal stack (`HStack`)
    /// to display the channel icon and name. Depending on the channel type, it either shows a custom
    /// image, a system icon, or an avatar for direct messages.
    var body: some View {
        HStack(spacing: .zero) {
            
            switch channel {
            case .text_channel(let c):
                if let icon = c.icon {
                    LazyImage(source: .file(icon),
                              height: frameSize,
                              width: frameSize,
                              clipTo: Circle())
                        .frame(width: frameSize, height: frameSize)
                } else {
                    
                    HomeChannelNameIconView(name: c.name,
                                            frameSize: frameSize)
                    
                }
                
            
            case .voice_channel(let c):
                if let icon = c.icon {
                    LazyImage(source: .file(icon),
                              height: frameSize,
                              width: frameSize,
                              clipTo: Circle())
                        .frame(width: frameSize,
                               height: frameSize)
                } else {
                   
                    HomeChannelNameIconView(name: c.name,
                                            frameSize: frameSize)
                }
                
                
                
            case .group_dm_channel(let c):
                if let icon = c.icon {
                    LazyImage(source: .file(icon),
                              height: frameSize,
                              width: frameSize,
                              clipTo: Circle())
                        .frame(width: frameSize,
                               height: frameSize)
                } else {
                    HomeChannelNameIconView(name: c.name,
                                            frameSize: frameSize)
                }
                
              
                                
            case .dm_channel(let c):
                
                if let recipient = viewState.users[c.recipients.first(where: { $0 != viewState.currentUser?.id }) ?? "-1"] {
                    Avatar(user: recipient,
                           width: frameSize,
                           height: frameSize,
                           withPresence: withUserPresence,
                           showNameIcon: true)
                        .frame(width: frameSize, height: frameSize)
                    
                }
                

                
            case .saved_messages(_):
                HomeChannelNameIconView(name: "Saved",
                                        frameSize: frameSize)
                
                
            }
        }
    }
    
    
    
}


struct HomeChannelNameIconView : View {
    
    let name : String
    let frameSize : CGFloat
    
    var body: some View {
        ZStack(alignment: .center) {
            
            Circle()
                .fill(Color.bgGray11)
                .frame(width: frameSize, height: frameSize)
            
            PeptideText(textVerbatim: processString(name),
                        font: .peptideTitle3,
                        textColor: .textDefaultGray01)
            
        }
    }
    
    func processString(_ input: String?) -> String {
        guard let input = input?.replacingOccurrences(of: " ", with: ""), !input.isEmpty else {
            // If the string is empty or nil, return a random uppercase letter
            return String((65...90).map { Character(UnicodeScalar($0)) }.randomElement() ?? "A")
        }

        if input.count > 2 {
            // If the string length is greater than 2, return the first two characters
            return String(input.prefix(2).uppercased())
        } else {
            // Otherwise, return the string as it is
            return input.uppercased()
        }
    }
}
