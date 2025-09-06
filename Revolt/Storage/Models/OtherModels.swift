//
//  OtherModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - EmojiParent Realm Objects

class EmojiParentServerRealm: Object {
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class EmojiParentDetachedRealm: Object {
    override static func primaryKey() -> String? {
        return nil
    }
}

class EmojiParentRealm: Object {
    @Persisted var type: String = "" // "server", "detached"
    @Persisted var serverParent: EmojiParentServerRealm?
    @Persisted var detachedParent: EmojiParentDetachedRealm?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Emoji Realm Object

class EmojiRealm: Object {
    @Persisted var id: String = ""
    @Persisted var parent: EmojiParentRealm?
    @Persisted var creator_id: String = ""
    @Persisted var name: String = ""
    @Persisted var animated: Bool?
    @Persisted var nsfw: Bool?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - Bot Realm Object

class BotRealm: Object {
    @Persisted var id: String = ""
    @Persisted var owner: String = ""
    @Persisted var token: String = ""
    @Persisted var isPublic: Bool = false
    @Persisted var analytics: Bool?
    @Persisted var discoverable: Bool?
    @Persisted var interactions_url: String?
    @Persisted var terms_of_service_url: String?
    @Persisted var privacy_policy_url: String?
    @Persisted var flags: Int?
    @Persisted var user: UserRealm?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - Invite Realm Objects

class ServerInviteRealm: Object {
    @Persisted var id: String = ""
    @Persisted var server: String = ""
    @Persisted var creator: String = ""
    @Persisted var channel: String = ""
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

class GroupInviteRealm: Object {
    @Persisted var id: String = ""
    @Persisted var creator: String = ""
    @Persisted var channel: String = ""
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

class InviteRealm: Object {
    @Persisted var id: String = ""
    @Persisted var type: String = "" // "server", "group"
    @Persisted var serverInvite: ServerInviteRealm?
    @Persisted var groupInvite: GroupInviteRealm?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - ServerChannel Realm Object

class ServerChannelRealm: Object {
    @Persisted var server: ServerRealm?
    @Persisted var channels = List<ChannelRealm>()
    
    override static func primaryKey() -> String? {
        return nil
    }
}
