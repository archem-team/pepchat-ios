//
//  MessageMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - Interactions Mapper

extension Interactions {
    func toRealm() -> InteractionsRealm {
        let realm = InteractionsRealm()
        if let reactions = self.reactions {
            realm.reactions.removeAll()
            realm.reactions.append(objectsIn: reactions)
        }
        realm.restrict_reactions = self.restrict_reactions
        return realm
    }
}

extension InteractionsRealm {
    func toOriginal() -> Interactions {
        let reactions = self.reactions.isEmpty ? nil : Array(self.reactions)
        return Interactions(reactions: reactions, restrict_reactions: self.restrict_reactions)
    }
}

// MARK: - Masquerade Mapper

extension Masquerade {
    func toRealm() -> MasqueradeRealm {
        let realm = MasqueradeRealm()
        realm.name = self.name
        realm.avatar = self.avatar
        realm.colour = self.colour
        return realm
    }
}

extension MasqueradeRealm {
    func toOriginal() -> Masquerade {
        return Masquerade(name: self.name, avatar: self.avatar, colour: self.colour)
    }
}

// MARK: - System Message Content Mappers

extension TextSystemMessageContent {
    func toRealm() -> TextSystemMessageContentRealm {
        let realm = TextSystemMessageContentRealm()
        realm.content = self.content
        return realm
    }
}

extension TextSystemMessageContentRealm {
    func toOriginal() -> TextSystemMessageContent {
        return TextSystemMessageContent(content: self.content)
    }
}

extension UserAddedSystemContent {
    func toRealm() -> UserAddedSystemContentRealm {
        let realm = UserAddedSystemContentRealm()
        realm.id = self.id
        realm.by = self.by
        return realm
    }
}

extension UserAddedSystemContentRealm {
    func toOriginal() -> UserAddedSystemContent {
        return UserAddedSystemContent(id: self.id, by: self.by)
    }
}

extension UserRemovedSystemContent {
    func toRealm() -> UserRemovedSystemContentRealm {
        let realm = UserRemovedSystemContentRealm()
        realm.id = self.id
        realm.by = self.by
        return realm
    }
}

extension UserRemovedSystemContentRealm {
    func toOriginal() -> UserRemovedSystemContent {
        return UserRemovedSystemContent(id: self.id, by: self.by)
    }
}

extension UserJoinedSystemContent {
    func toRealm() -> UserJoinedSystemContentRealm {
        let realm = UserJoinedSystemContentRealm()
        realm.id = self.id
        return realm
    }
}

extension UserJoinedSystemContentRealm {
    func toOriginal() -> UserJoinedSystemContent {
        return UserJoinedSystemContent(id: self.id)
    }
}

extension UserLeftSystemContent {
    func toRealm() -> UserLeftSystemContentRealm {
        let realm = UserLeftSystemContentRealm()
        realm.id = self.id
        return realm
    }
}

extension UserLeftSystemContentRealm {
    func toOriginal() -> UserLeftSystemContent {
        return UserLeftSystemContent(id: self.id)
    }
}

extension UserKickedSystemContent {
    func toRealm() -> UserKickedSystemContentRealm {
        let realm = UserKickedSystemContentRealm()
        realm.id = self.id
        return realm
    }
}

extension UserKickedSystemContentRealm {
    func toOriginal() -> UserKickedSystemContent {
        return UserKickedSystemContent(id: self.id)
    }
}

extension UserBannedSystemContent {
    func toRealm() -> UserBannedSystemContentRealm {
        let realm = UserBannedSystemContentRealm()
        realm.id = self.id
        return realm
    }
}

extension UserBannedSystemContentRealm {
    func toOriginal() -> UserBannedSystemContent {
        return UserBannedSystemContent(id: self.id)
    }
}

extension ChannelRenamedSystemContent {
    func toRealm() -> ChannelRenamedSystemContentRealm {
        let realm = ChannelRenamedSystemContentRealm()
        realm.name = self.name
        realm.by = self.by
        return realm
    }
}

extension ChannelRenamedSystemContentRealm {
    func toOriginal() -> ChannelRenamedSystemContent {
        return ChannelRenamedSystemContent(name: self.name, by: self.by)
    }
}

extension ChannelDescriptionChangedSystemContent {
    func toRealm() -> ChannelDescriptionChangedSystemContentRealm {
        let realm = ChannelDescriptionChangedSystemContentRealm()
        realm.by = self.by
        return realm
    }
}

extension ChannelDescriptionChangedSystemContentRealm {
    func toOriginal() -> ChannelDescriptionChangedSystemContent {
        return ChannelDescriptionChangedSystemContent(by: self.by)
    }
}

extension ChannelIconChangedSystemContent {
    func toRealm() -> ChannelIconChangedSystemContentRealm {
        let realm = ChannelIconChangedSystemContentRealm()
        realm.by = self.by
        return realm
    }
}

extension ChannelIconChangedSystemContentRealm {
    func toOriginal() -> ChannelIconChangedSystemContent {
        return ChannelIconChangedSystemContent(by: self.by)
    }
}

extension ChannelOwnershipChangedSystemContent {
    func toRealm() -> ChannelOwnershipChangedSystemContentRealm {
        let realm = ChannelOwnershipChangedSystemContentRealm()
        realm.from = self.from
        realm.to = self.to
        return realm
    }
}

extension ChannelOwnershipChangedSystemContentRealm {
    func toOriginal() -> ChannelOwnershipChangedSystemContent {
        return ChannelOwnershipChangedSystemContent(from: self.from, to: self.to)
    }
}

extension MessagePinnedSystemContent {
    func toRealm() -> MessagePinnedSystemContentRealm {
        let realm = MessagePinnedSystemContentRealm()
        realm.id = self.id
        realm.by = self.by
        realm.by_username = self.by_username
        return realm
    }
}

extension MessagePinnedSystemContentRealm {
    func toOriginal() -> MessagePinnedSystemContent {
        return MessagePinnedSystemContent(id: self.id, by: self.by, by_username: self.by_username)
    }
}

// MARK: - SystemMessageContent Mapper

extension SystemMessageContent {
    func toRealm() -> SystemMessageContentRealm {
        let realm = SystemMessageContentRealm()
        
        switch self {
        case .text(let content):
            realm.type = "text"
            realm.textSystemMessage = content.toRealm()
        case .user_added(let content):
            realm.type = "user_added"
            realm.userAddedSystem = content.toRealm()
        case .user_removed(let content):
            realm.type = "user_removed"
            realm.userRemovedSystem = content.toRealm()
        case .user_joined(let content):
            realm.type = "user_joined"
            realm.userJoinedSystem = content.toRealm()
        case .user_left(let content):
            realm.type = "user_left"
            realm.userLeftSystem = content.toRealm()
        case .user_kicked(let content):
            realm.type = "user_kicked"
            realm.userKickedSystem = content.toRealm()
        case .user_banned(let content):
            realm.type = "user_banned"
            realm.userBannedSystem = content.toRealm()
        case .channel_renamed(let content):
            realm.type = "channel_renamed"
            realm.channelRenamedSystem = content.toRealm()
        case .channel_description_changed(let content):
            realm.type = "channel_description_changed"
            realm.channelDescriptionChangedSystem = content.toRealm()
        case .channel_icon_changed(let content):
            realm.type = "channel_icon_changed"
            realm.channelIconChangedSystem = content.toRealm()
        case .channel_ownership_changed(let content):
            realm.type = "channel_ownership_changed"
            realm.channelOwnershipChangedSystem = content.toRealm()
        case .message_pinned(let content):
            realm.type = "message_pinned"
            realm.messagePinnedSystem = content.toRealm()
        case .message_unpinned(let content):
            realm.type = "message_unpinned"
            realm.messageUnpinnedSystem = content.toRealm()
        }
        
        return realm
    }
}

extension SystemMessageContentRealm {
    func toOriginal() -> SystemMessageContent {
        switch self.type {
        case "text":
            return .text(self.textSystemMessage!.toOriginal())
        case "user_added":
            return .user_added(self.userAddedSystem!.toOriginal())
        case "user_removed":
            return .user_removed(self.userRemovedSystem!.toOriginal())
        case "user_joined":
            return .user_joined(self.userJoinedSystem!.toOriginal())
        case "user_left":
            return .user_left(self.userLeftSystem!.toOriginal())
        case "user_kicked":
            return .user_kicked(self.userKickedSystem!.toOriginal())
        case "user_banned":
            return .user_banned(self.userBannedSystem!.toOriginal())
        case "channel_renamed":
            return .channel_renamed(self.channelRenamedSystem!.toOriginal())
        case "channel_description_changed":
            return .channel_description_changed(self.channelDescriptionChangedSystem!.toOriginal())
        case "channel_icon_changed":
            return .channel_icon_changed(self.channelIconChangedSystem!.toOriginal())
        case "channel_ownership_changed":
            return .channel_ownership_changed(self.channelOwnershipChangedSystem!.toOriginal())
        case "message_pinned":
            return .message_pinned(self.messagePinnedSystem!.toOriginal())
        case "message_unpinned":
            return .message_unpinned(self.messageUnpinnedSystem!.toOriginal())
        default:
            fatalError("Unknown system message content type: \(self.type)")
        }
    }
}

// MARK: - MessageWebhook Mapper

extension MessageWebhook {
    func toRealm() -> MessageWebhookRealm {
        let realm = MessageWebhookRealm()
        realm.name = self.name
        realm.avatar = self.avatar
        return realm
    }
}

extension MessageWebhookRealm {
    func toOriginal() -> MessageWebhook {
        return MessageWebhook(name: self.name, avatar: self.avatar)
    }
}

// MARK: - Message Mapper

extension Message {
    func toRealm() -> MessageRealm {
        let realm = MessageRealm()
        realm.id = self.id
        realm.content = self.content
        realm.author = self.author
        realm.channel = self.channel
        realm.system = self.system?.toRealm()
        
        if let attachments = self.attachments {
            realm.attachments.removeAll()
            for attachment in attachments {
                realm.attachments.append(attachment.toRealm())
            }
        }
        
        if let mentions = self.mentions {
            realm.mentions.removeAll()
            realm.mentions.append(objectsIn: mentions)
        }
        
        if let replies = self.replies {
            realm.replies.removeAll()
            realm.replies.append(objectsIn: replies)
        }
        
        realm.edited = self.edited
        realm.masquerade = self.masquerade?.toRealm()
        realm.interactions = self.interactions?.toRealm()
        
        if let reactions = self.reactions {
            realm.reactions.removeAll()
            for (key, value) in reactions {
                let reactionUsers = ReactionUsersRealm()
                reactionUsers.users.append(objectsIn: value)
                realm.reactions[key] = reactionUsers
            }
        }
        
        realm.user = self.user?.toRealm()
        realm.member = self.member?.toRealm()
        
        if let embeds = self.embeds {
            realm.embeds.removeAll()
            for embed in embeds {
                realm.embeds.append(embed.toRealm())
            }
        }
        
        realm.webhook = self.webhook?.toRealm()
        
        return realm
    }
}

extension MessageRealm {
    func toOriginal() -> Message {
        let attachments = self.attachments.isEmpty ? nil : Array(self.attachments.map { $0.toOriginal() })
        let mentions = self.mentions.isEmpty ? nil : Array(self.mentions)
        let replies = self.replies.isEmpty ? nil : Array(self.replies)
        
        var reactions: [String: [String]]? = nil
        if self.reactions.count > 0 {
            reactions = [:]
            for key in self.reactions.keys {
                if let reactionUsersOpt = self.reactions[key], let reactionUsers = reactionUsersOpt {
                    reactions![key] = Array(reactionUsers.users)
                }
            }
        }
        
        let embeds = self.embeds.isEmpty ? nil : Array(self.embeds.map { $0.toOriginal() })
        
        return Message(
            id: self.id,
            content: self.content,
            author: self.author,
            channel: self.channel,
            system: self.system?.toOriginal(),
            attachments: attachments,
            mentions: mentions,
            replies: replies,
            edited: self.edited,
            masquerade: self.masquerade?.toOriginal(),
            interactions: self.interactions?.toOriginal(),
            reactions: reactions,
            user: self.user?.toOriginal(),
            member: self.member?.toOriginal(),
            embeds: embeds,
            webhook: self.webhook?.toOriginal()
        )
    }
}
