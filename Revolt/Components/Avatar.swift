//
//  Avatar.swift
//  Revolt
//
//  Created by Angelo on 14/10/2023.
//

import Foundation
import SwiftUI
import Kingfisher
import Types

/// A view that displays a user's avatar with optional presence indicators.
///
/// The `Avatar` view can show the avatar of a user, member, or webhook, and it can optionally display a presence indicator based on the user's status.
///
/// - Important: This view requires a `ViewState` environment object to function correctly.
/// - Note: Ensure that the `User`, `Member`, `Masquerade`, and `MessageWebhook` types are defined in your project.
struct Avatar: View {
    
    // MARK: - Properties
    
    /// The environment object that holds the current view state for the application.
    @EnvironmentObject var viewState: ViewState
    
    /// The user whose avatar is being displayed.
    public var user: User
    
    /// The member associated with the user, if available.
    public var member: Member? = nil
    
    /// The masquerade settings for the user, if available.
    public var masquerade: Masquerade? = nil
    
    /// The webhook information for the avatar, if available.
    public var webhook: MessageWebhook? = nil
    
    /// The width of the avatar image.
    public var width: CGFloat = 32
    
    /// The height of the avatar image.
    public var height: CGFloat = 32
    
    public var statusWidth: CGFloat? = nil
    
    public var statusHeight: CGFloat? = nil
    
    public var statusPadding: CGFloat? = nil
    
    /// A Boolean indicating whether to show the presence indicator.
    public var withPresence: Bool = false
    
    public var showNameIcon : Bool = false

    /// A computed property that determines the source for loading the avatar image based on available data.
    var source: LazyImageSource? {
        if let avatar = webhook?.avatar {
            return .id(avatar, "avatars")
        } else if let url = masquerade?.avatar {
            return .url(URL(string: url)!)
        } else if let file = member?.avatar ?? user.avatar {
            return .file(file)
        }
        
        return nil
    }

    // MARK: - Body

    /// The body of the `Avatar` view.
    ///
    /// The body constructs the avatar view. It uses a placeholder image during Xcode previews and loads the avatar image lazily otherwise.
    /// If `withPresence` is set to true, a presence indicator is displayed over the avatar.
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                Image("Image")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .clipShape(Circle())
            } else {
                
                let avatar = viewState.resolveAvatarUrl(user: user, member: member, masquerade: masquerade)
                
                if !avatar.isAvatarSet && showNameIcon {
                    
                    HomeChannelNameIconView(name: avatar.username,
                                            frameSize: width)
                    
                } else {
                    LazyImage(
                        source: .url(avatar.url),
                        height: height,
                        width: width,
                        clipTo: Circle()
                    )
                }
                
                
                
            }
            
            if withPresence {
                PresenceIndicator(presence: user.status?.presence ?? (user.online == true ? .Online : .none), width: statusWidth ?? width / 3, height: statusHeight ?? height / 3)
                    .padding(.trailing, statusPadding ?? -2)
                    .padding(.bottom, statusPadding ?? -2)

            }
        }
        .compositingGroup()
    }
}

/// A preview provider for the `Avatar` view.
class Avatar_Preview: PreviewProvider {
    static var viewState: ViewState = ViewState.preview()
    
    /// Previews of the `Avatar` view in different themes.
    static var previews: some View {
        
        Avatar(user: viewState.currentUser!, width: .size64, height: .size64, statusWidth: .size20, statusHeight: .size20, statusPadding: .zero, withPresence: true)
            .frame(width: .size72, height: .size72)
            .background{
                Circle()
                    .fill(Color.bgGray12)
            }
            .padding(.leading, .padding16)
        
        Avatar(user: viewState.currentUser!, withPresence: true)
            .environmentObject(viewState)
            .previewLayout(.sizeThatFits)
            .background(Theme.light.background.color)
        
        Avatar(user: viewState.currentUser!, withPresence: true)
            .environmentObject(viewState)
            .previewLayout(.sizeThatFits)
            .background(Theme.dark.background.color)
    }
}
