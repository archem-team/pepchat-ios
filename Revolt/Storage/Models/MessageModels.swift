//
//  MessageModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - Helper Objects

class ReactionUsersRealm: Object {
    @Persisted var users = List<String>()
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Interactions Realm Object

class InteractionsRealm: Object {
    @Persisted var reactions = List<String>()
    @Persisted var restrict_reactions: Bool?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Masquerade Realm Object

class MasqueradeRealm: Object {
    @Persisted var name: String?
    @Persisted var avatar: String?
    @Persisted var colour: String?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - System Message Content Structures

class TextSystemMessageContentRealm: Object {
    @Persisted var content: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class UserAddedSystemContentRealm: Object {
    @Persisted var id: String = ""
    @Persisted var by: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class UserRemovedSystemContentRealm: Object {
    @Persisted var id: String = ""
    @Persisted var by: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class UserJoinedSystemContentRealm: Object {
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class UserLeftSystemContentRealm: Object {
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class UserKickedSystemContentRealm: Object {
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class UserBannedSystemContentRealm: Object {
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class ChannelRenamedSystemContentRealm: Object {
    @Persisted var name: String = ""
    @Persisted var by: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class ChannelDescriptionChangedSystemContentRealm: Object {
    @Persisted var by: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class ChannelIconChangedSystemContentRealm: Object {
    @Persisted var by: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class ChannelOwnershipChangedSystemContentRealm: Object {
    @Persisted var from: String = ""
    @Persisted var to: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

class MessagePinnedSystemContentRealm: Object {
    @Persisted var id: String = ""
    @Persisted var by: String = ""
    @Persisted var by_username: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - SystemMessageContent Realm Object (Union Type)

class SystemMessageContentRealm: Object {
    @Persisted var type: String = ""
    
    @Persisted var textSystemMessage: TextSystemMessageContentRealm?
    @Persisted var userAddedSystem: UserAddedSystemContentRealm?
    @Persisted var userRemovedSystem: UserRemovedSystemContentRealm?
    @Persisted var userJoinedSystem: UserJoinedSystemContentRealm?
    @Persisted var userLeftSystem: UserLeftSystemContentRealm?
    @Persisted var userKickedSystem: UserKickedSystemContentRealm?
    @Persisted var userBannedSystem: UserBannedSystemContentRealm?
    @Persisted var channelRenamedSystem: ChannelRenamedSystemContentRealm?
    @Persisted var channelDescriptionChangedSystem: ChannelDescriptionChangedSystemContentRealm?
    @Persisted var channelIconChangedSystem: ChannelIconChangedSystemContentRealm?
    @Persisted var channelOwnershipChangedSystem: ChannelOwnershipChangedSystemContentRealm?
    @Persisted var messagePinnedSystem: MessagePinnedSystemContentRealm?
    @Persisted var messageUnpinnedSystem: MessagePinnedSystemContentRealm?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - MessageWebhook Realm Object

class MessageWebhookRealm: Object {
    @Persisted var name: String?
    @Persisted var avatar: String?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Message Realm Object

class MessageRealm: Object {
    @Persisted var id: String = ""
    @Persisted var content: String?
    @Persisted var author: String = ""
    @Persisted var channel: String = ""
    @Persisted var system: SystemMessageContentRealm?
    @Persisted var attachments = List<FileRealm>()
    @Persisted var mentions = List<String>()
    @Persisted var replies = List<String>()
    @Persisted var edited: String?
    @Persisted var masquerade: MasqueradeRealm?
    @Persisted var interactions: InteractionsRealm?
    @Persisted var reactions = RealmSwift.Map<String, ReactionUsersRealm?>()
    @Persisted var user: UserRealm?
    @Persisted var member: MemberRealm?
    @Persisted var embeds = List<EmbedRealm>()
    @Persisted var webhook: MessageWebhookRealm?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}
