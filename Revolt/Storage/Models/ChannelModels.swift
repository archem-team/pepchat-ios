//
//  ChannelModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - VoiceInformation Realm Object

class VoiceInformationRealm: Object {
    @Persisted var max_users: Int?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - SavedMessages Realm Object

class SavedMessagesRealm: Object {
    @Persisted var id: String = ""
    @Persisted var user: String = ""
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - DMChannel Realm Object

class DMChannelRealm: Object {
    @Persisted var id: String = ""
    @Persisted var active: Bool = false
    @Persisted var recipients = List<String>()
    @Persisted var last_message_id: String?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - GroupDMChannel Realm Object

class GroupDMChannelRealm: Object {
    @Persisted var id: String = ""
    @Persisted var recipients = List<String>()
    @Persisted var name: String = ""
    @Persisted var owner: String = ""
    @Persisted var icon: FileRealm?
    @Persisted var permissions: PermissionsRealm?
    @Persisted var channelDescription: String?
    @Persisted var nsfw: Bool?
    @Persisted var last_message_id: String?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - TextChannel Realm Object

class TextChannelRealm: Object {
    @Persisted var id: String = ""
    @Persisted var server: String = ""
    @Persisted var name: String = ""
    @Persisted var channelDescription: String?
    @Persisted var icon: FileRealm?
    @Persisted var default_permissions: OverwriteRealm?
    @Persisted var role_permissions = RealmSwift.Map<String, OverwriteRealm?>()
    @Persisted var nsfw: Bool?
    @Persisted var last_message_id: String?
    @Persisted var voice: VoiceInformationRealm?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - VoiceChannel Realm Object

class VoiceChannelRealm: Object {
    @Persisted var id: String = ""
    @Persisted var server: String = ""
    @Persisted var name: String = ""
    @Persisted var channelDescription: String?
    @Persisted var icon: FileRealm?
    @Persisted var default_permissions: OverwriteRealm?
    @Persisted var role_permissions = RealmSwift.Map<String, OverwriteRealm?>()
    @Persisted var nsfw: Bool?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - Channel Realm Object (Union Type)

class ChannelRealm: Object {
    @Persisted var id: String = ""
    @Persisted var channel_type: String = ""
    
    @Persisted var savedMessages: SavedMessagesRealm?
    @Persisted var dmChannel: DMChannelRealm?
    @Persisted var groupDMChannel: GroupDMChannelRealm?
    @Persisted var textChannel: TextChannelRealm?
    @Persisted var voiceChannel: VoiceChannelRealm?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}
