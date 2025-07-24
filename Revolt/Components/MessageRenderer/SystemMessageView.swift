//
//  SystemMessageView.swift
//  Revolt
//
//  Created by Angelo on 12/12/2023.
//

import Foundation
import SwiftUI
import Types

struct SystemMessageView: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: .zero) {
            
            
            switch message.system {
            case .channel_icon_changed(let content):
                
                let user = viewState.users[content.by]!
                let member = viewState.channels[message.channel]?.server.flatMap { viewState.members[$0]?[user.id] }
                
                SystemMessageAvatar(user: user,
                                    member: member,
                                    masquerade: message.masquerade,
                                    actionIcon: .peptideEdit,
                                    actionIconColor: .iconDefaultGray01)
                
                VStack(alignment: .leading, spacing: .zero){
                    
                    Text(verbatim: member?.nickname ?? user.display_name ?? user.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: " changed the group icon.")
                        .font(.peptideBody1Font)
                        .foregroundStyle(.textGray04)
                    
                    SystemMessageDate(id: message.id)
                }
                
                
                
                Spacer(minLength: .zero)
                
                
            case .user_joined(let content):
                
                let user = viewState.users[content.id]!
                let member = viewState.channels[message.channel]?.server.flatMap { viewState.members[$0]?[user.id] }
                
                SystemMessageAvatar(user: user,
                                    member: member,
                                    masquerade: message.masquerade,
                                    actionIcon: .peptideSignInJoin,
                                    actionIconColor: .iconGreen07)
                
                VStack(alignment: .leading, spacing: .zero){
                    
                    Text(verbatim: member?.nickname ?? user.display_name ?? user.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: " joined the group.")
                        .font(.peptideBody1Font)
                        .foregroundStyle(.textGray04)
                    
                    SystemMessageDate(id: message.id)
                }
                
                Spacer(minLength: .zero)
                
                
                
            case .user_left(let content):
                
                let user = viewState.users[content.id]!
                let member = viewState.channels[message.channel]?.server.flatMap { viewState.members[$0]?[user.id] }
                
                SystemMessageAvatar(user: user,
                                    member: member,
                                    masquerade: message.masquerade,
                                    actionIcon: .peptideSignOutLeave,
                                    actionIconColor: .iconRed07)
                
                VStack(alignment: .leading, spacing: .zero){
                    
                    Text(verbatim: member?.nickname ?? user.display_name ?? user.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: " left the group.")
                        .font(.peptideBody1Font)
                        .foregroundStyle(.textGray04)
                    
                    SystemMessageDate(id: message.id)
                }
                
                Spacer(minLength: .zero)
            
                
            case .channel_renamed(let content):
                
                let user = viewState.users[content.by]!
                let member = viewState.channels[message.channel]?.server.flatMap { viewState.members[$0]?[user.id] }
                
                SystemMessageAvatar(user: user,
                                    member: member,
                                    masquerade: message.masquerade,
                                    actionIcon: .peptideEdit,
                                    actionIconColor: .iconDefaultGray01)
                
                VStack(alignment: .leading, spacing: .zero){
                    
                    Text(verbatim: member?.nickname ?? user.display_name ?? user.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: " renamed the channel to: ")
                        .font(.peptideBody1Font)
                        .foregroundStyle(.textGray04) +  Text(verbatim: content.name)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01)
                    
                    SystemMessageDate(id: message.id)
                }
                
                
                
                Spacer(minLength: .zero)
                
                
            case .channel_description_changed(let content):
                
                
                let user = viewState.users[content.by]!
                let member = viewState.channels[message.channel]?.server.flatMap { viewState.members[$0]?[user.id] }
                
                SystemMessageAvatar(user: user,
                                    member: member,
                                    masquerade: message.masquerade,
                                    actionIcon: .peptideEdit,
                                    actionIconColor: .iconDefaultGray01)
                
                VStack(alignment: .leading, spacing: .zero){
                    
                    Text(verbatim: member?.nickname ?? user.display_name ?? user.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: " changed the group description.")
                        .font(.peptideBody1Font)
                        .foregroundStyle(.textGray04)
                    
                    SystemMessageDate(id: message.id)
                }
                
                Spacer(minLength: .zero)
                
            case .user_added(let content):
                
                //public var id: String // The ID of the user who was added.
                //public var by: String // The ID of the user who added them.
                
                //todo user and member
                
                let addedUser = viewState.users[content.id]!
                let byAddedUser = viewState.users[content.by]!
                
                SystemMessageTwoAvatar(user0: addedUser,
                                       user1: byAddedUser,
                                       actionIcon: .peptideNewUser,
                                       actionIconColor: .iconGreen07)
                
                //Frank was added by Wallace
                
                
                VStack(alignment: .leading, spacing: .zero){
                    
                    Text(verbatim:  addedUser.display_name ?? addedUser.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: " was added by ")
                        .font(.peptideBody1Font)
                        .foregroundStyle(.textGray04) + Text(verbatim:  byAddedUser.display_name ?? byAddedUser.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01)
                    
                    SystemMessageDate(id: message.id)
                }
                
                Spacer(minLength: .zero)
                
            case .user_removed(let content):
                
                
                //public var id: String // The ID of the user who was added.
                //public var by: String // The ID of the user who added them.
                
                //todo user and member
                
                let addedUser = viewState.users[content.id]!
                let byAddedUser = viewState.users[content.by]!
                
                SystemMessageTwoAvatar(user0: addedUser,
                                       user1: byAddedUser,
                                       actionIcon: .peptideRemoveUser,
                                       actionIconColor: .iconRed07)
                
                //Frank was added by Wallace
                
                
                VStack(alignment: .leading, spacing: .zero){
                    
                    Text(verbatim:  addedUser.display_name ?? addedUser.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: " was removed by ")
                        .font(.peptideBody1Font)
                        .foregroundStyle(.textGray04) + Text(verbatim:  byAddedUser.display_name ?? byAddedUser.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01)
                    
                    SystemMessageDate(id: message.id)
                }
                
                Spacer(minLength: .zero)
                
            case .channel_ownership_changed(let content):
                
                //public var id: String // The ID of the user who was added.
                //public var by: String // The ID of the user who added them.
                
                //todo user and member
                
                let fromUser = viewState.users[content.from]!
                let toUser = viewState.users[content.to]!
                
                SystemMessageTwoAvatar(user0: toUser,
                                       user1: fromUser,
                                       actionIcon: .peptideKey,
                                       actionIconColor: .iconDefaultGray01)
                                
                
                VStack(alignment: .leading, spacing: .zero){
                    
                    Text(verbatim:  fromUser.display_name ?? fromUser.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: " gave ")
                        .font(.peptideBody1Font)
                        .foregroundStyle(.textGray04) + Text(verbatim:  toUser.display_name ?? toUser.username)
                        .font(.peptideTitle4Font)
                        .foregroundStyle(.textDefaultGray01) +  Text(verbatim: "  group ownership")
                        .font(.peptideBody1Font)
                    
                    SystemMessageDate(id: message.id)
                }
                
                Spacer(minLength: .zero)
                
            case .message_pinned(let content):
                
                HStack(spacing: .spacing4){
                    
                    
                    Spacer(minLength: .zero)
                    
                    Text(verbatim: "Message pinned by ")
                    .font(.peptideBody1Font)
                    .foregroundStyle(.textGray04) + Text(verbatim:  content.by_username)
                    .font(.peptideTitle4Font)
                    .foregroundStyle(.textDefaultGray01)
                    
                    Spacer(minLength: .zero)
                    
                }
                
            case .message_unpinned(let content) :
                HStack(spacing: .spacing4){
                    
                    
                    Spacer(minLength: .zero)
                    
                    Text(verbatim: "Message unpinned by ")
                    .font(.peptideBody1Font)
                    .foregroundStyle(.textGray04) + Text(verbatim:  content.by_username)
                    .font(.peptideTitle4Font)
                    .foregroundStyle(.textDefaultGray01)
                    
                    Spacer(minLength: .zero)
                    
                }
                                
            default:
                Text("unknown")
            }
        }
    }
}


struct SystemMessageAvatar : View {
    
    @EnvironmentObject var viewState: ViewState
    
    var user: User
    var member: Member? = nil
    var masquerade: Masquerade? = nil
    
    var actionIcon : ImageResource
    var actionIconColor : Color
    
    var body: some View {
        
        Button {
            self.viewState.openUserSheet(user: user, member: member)
        } label: {
            ZStack(alignment: .trailing){
                Avatar(user: user, member: member, masquerade: masquerade, width: 40, height: 40)
                PeptideIcon(iconName: actionIcon,
                            size: .size16,
                            color: actionIconColor)
                .frame(width: .size24, height: .size24)
                .background(
                    Circle()
                        .stroke(Color.bgDefaultPurple13, lineWidth: 2)
                        .background(Circle().fill(Color.bgGray11))
                )
                .offset(x: 12)
            }
            .padding(.trailing, .padding12 + .padding16)

      }
        
        
    }
    
}



struct SystemMessageTwoAvatar : View {
    
    @EnvironmentObject var viewState: ViewState
    
    var user0: User
    var member0: Member? = nil
    var masquerade0: Masquerade? = nil
    
    
    var user1: User
    var member1: Member? = nil
    var masquerade1: Masquerade? = nil
    
    var actionIcon : ImageResource
    var actionIconColor : Color
    
    var body: some View {
        
        Button {
            self.viewState.openUserSheet(user: user0, member: member0)
        } label: {
            ZStack(alignment: .trailing){
                Avatar(user: user0, member: member0, masquerade: masquerade0, width: 40, height: 40)
                
                
                ZStack(alignment: .top){
                    
                    Avatar(user: user1, member: member1, masquerade: masquerade1, width: 24, height: 24)
                        .overlay{
                            
                            Circle()
                                .stroke(Color.bgDefaultPurple13, lineWidth: 2)
                            
                        }
                        .offset(y: -8)

                    
                    PeptideIcon(iconName: actionIcon,
                                size: .size16,
                                color: actionIconColor)
                    .frame(width: .size24, height: .size24)
                    .background(
                        Circle()
                            .stroke(Color.bgDefaultPurple13, lineWidth: 2)
                            .background(Circle().fill(Color.bgGray11))
                    )
                    .offset(y: 12)
                    
                }
                .offset(x: 12)

                /*.offset(x: 12)*/
            }
            .padding(.trailing, .padding12 + .padding16)

        }
        
    }
}


struct SystemMessageDate : View {
    var id : String
    var body: some View {
        Text(formattedMessageDate(from: createdAt(id: id)))
            .font(.peptideFootnoteFont)
            .foregroundStyle(.textGray06)
            .lineLimit(1)
    }
}


#Preview {
    
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    
    let user0 = viewState.users["0"]!
    let user1 = viewState.users["0"]!
    
    SystemMessageTwoAvatar(user0: user0, user1: user1, actionIcon: .peptideNewUser, actionIconColor: .iconGreen07)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.light)
    
}



