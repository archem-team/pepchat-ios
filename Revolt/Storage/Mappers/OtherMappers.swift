//
//  OtherMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - EmojiParent Mappers

extension EmojiParentServer {
    func toRealm() -> EmojiParentServerRealm {
        let realm = EmojiParentServerRealm()
        realm.id = self.id
        return realm
    }
}

extension EmojiParentServerRealm {
    func toOriginal() -> EmojiParentServer {
        return EmojiParentServer(id: self.id)
    }
}

extension EmojiParentDetached {
    func toRealm() -> EmojiParentDetachedRealm {
        return EmojiParentDetachedRealm()
    }
}

extension EmojiParentDetachedRealm {
    func toOriginal() -> EmojiParentDetached {
        return EmojiParentDetached()
    }
}

extension EmojiParent {
    func toRealm() -> EmojiParentRealm {
        let realm = EmojiParentRealm()
        
        switch self {
        case .server(let server):
            realm.type = "server"
            realm.serverParent = server.toRealm()
        case .detached(let detached):
            realm.type = "detached"
            realm.detachedParent = detached.toRealm()
        }
        
        return realm
    }
}

extension EmojiParentRealm {
    func toOriginal() -> EmojiParent {
        switch self.type {
        case "server":
            return .server(self.serverParent!.toOriginal())
        case "detached":
            return .detached(self.detachedParent!.toOriginal())
        default:
            fatalError("Unknown emoji parent type: \(self.type)")
        }
    }
}

// MARK: - Emoji Mapper

extension Emoji {
    func toRealm() -> EmojiRealm {
        let realm = EmojiRealm()
        realm.id = self.id
        realm.parent = self.parent.toRealm()
        realm.creator_id = self.creator_id
        realm.name = self.name
        realm.animated = self.animated
        realm.nsfw = self.nsfw
        return realm
    }
}

extension EmojiRealm {
    func toOriginal() -> Emoji {
        return Emoji(
            id: self.id,
            parent: self.parent!.toOriginal(),
            creator_id: self.creator_id,
            name: self.name,
            animated: self.animated,
            nsfw: self.nsfw
        )
    }
}

// MARK: - Bot Mapper

extension Bot {
    func toRealm() -> BotRealm {
        let realm = BotRealm()
        realm.id = self.id
        realm.owner = self.owner
        realm.token = self.token
        realm.isPublic = self.isPublic
        realm.analytics = self.analytics
        realm.discoverable = self.discoverable
        realm.interactions_url = self.interactions_url
        realm.terms_of_service_url = self.terms_of_service_url
        realm.privacy_policy_url = self.privacy_policy_url
        realm.flags = self.flags
        realm.user = self.user?.toRealm()
        return realm
    }
}

extension BotRealm {
    func toOriginal() -> Bot {
        return Bot(
            id: self.id,
            owner: self.owner,
            token: self.token,
            isPublic: self.isPublic,
            analytics: self.analytics,
            discoverable: self.discoverable,
            interactions_url: self.interactions_url,
            terms_of_service_url: self.terms_of_service_url,
            privacy_policy_url: self.privacy_policy_url,
            flags: self.flags,
            user: self.user?.toOriginal()
        )
    }
}

// MARK: - Invite Mappers

extension ServerInvite {
    func toRealm() -> ServerInviteRealm {
        let realm = ServerInviteRealm()
        realm.id = self.id
        realm.server = self.server
        realm.creator = self.creator
        realm.channel = self.channel
        return realm
    }
}

extension ServerInviteRealm {
    func toOriginal() -> ServerInvite {
        return ServerInvite(id: self.id, server: self.server, creator: self.creator, channel: self.channel)
    }
}

extension GroupInvite {
    func toRealm() -> GroupInviteRealm {
        let realm = GroupInviteRealm()
        realm.id = self.id
        realm.creator = self.creator
        realm.channel = self.channel
        return realm
    }
}

extension GroupInviteRealm {
    func toOriginal() -> GroupInvite {
        return GroupInvite(id: self.id, creator: self.creator, channel: self.channel)
    }
}

extension Invite {
    func toRealm() -> InviteRealm {
        let realm = InviteRealm()
        realm.id = self.id
        
        switch self {
        case .server(let serverInvite):
            realm.type = "server"
            realm.serverInvite = serverInvite.toRealm()
        case .group(let groupInvite):
            realm.type = "group"
            realm.groupInvite = groupInvite.toRealm()
        }
        
        return realm
    }
}

extension InviteRealm {
    func toOriginal() -> Invite {
        switch self.type {
        case "server":
            return .server(self.serverInvite!.toOriginal())
        case "group":
            return .group(self.groupInvite!.toOriginal())
        default:
            fatalError("Unknown invite type: \(self.type)")
        }
    }
}

// MARK: - ServerChannel Mapper

extension ServerChannel {
    func toRealm() -> ServerChannelRealm {
        let realm = ServerChannelRealm()
        realm.server = self.server.toRealm()
        realm.channels.removeAll()
        for channel in self.channels {
            realm.channels.append(channel.toRealm())
        }
        return realm
    }
}

extension ServerChannelRealm {
    func toOriginal() -> ServerChannel {
        return ServerChannel(
            server: self.server!.toOriginal(),
            channels: Array(self.channels.map { $0.toOriginal() })
        )
    }
}
