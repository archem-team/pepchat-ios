//
//  ChannelMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - VoiceInformation Mapper

extension VoiceInformation {
    func toRealm() -> VoiceInformationRealm {
        let realm = VoiceInformationRealm()
        realm.max_users = self.max_users
        return realm
    }
}

extension VoiceInformationRealm {
    func toOriginal() -> VoiceInformation {
        return VoiceInformation(max_users: self.max_users)
    }
}

// MARK: - SavedMessages Mapper

extension SavedMessages {
    func toRealm() -> SavedMessagesRealm {
        let realm = SavedMessagesRealm()
        realm.id = self.id
        realm.user = self.user
        return realm
    }
}

extension SavedMessagesRealm {
    func toOriginal() -> SavedMessages {
        return SavedMessages(id: self.id, user: self.user)
    }
}

// MARK: - DMChannel Mapper

extension DMChannel {
    func toRealm() -> DMChannelRealm {
        let realm = DMChannelRealm()
        realm.id = self.id
        realm.active = self.active
        realm.recipients.removeAll()
        realm.recipients.append(objectsIn: self.recipients)
        realm.last_message_id = self.last_message_id
        return realm
    }
}

extension DMChannelRealm {
    func toOriginal() -> DMChannel {
        return DMChannel(
            id: self.id,
            active: self.active,
            recipients: Array(self.recipients),
            last_message_id: self.last_message_id
        )
    }
}

// MARK: - GroupDMChannel Mapper

extension GroupDMChannel {
    func toRealm() -> GroupDMChannelRealm {
        let realm = GroupDMChannelRealm()
        realm.id = self.id
        realm.recipients.removeAll()
        realm.recipients.append(objectsIn: self.recipients)
        realm.name = self.name
        realm.owner = self.owner
        realm.icon = self.icon?.toRealm()
        realm.permissions = self.permissions?.toRealm()
        realm.channelDescription = self.description
        realm.nsfw = self.nsfw
        realm.last_message_id = self.last_message_id
        return realm
    }
}

extension GroupDMChannelRealm {
    func toOriginal() -> GroupDMChannel {
        return GroupDMChannel(
            id: self.id,
            recipients: Array(self.recipients),
            name: self.name,
            owner: self.owner,
            icon: self.icon?.toOriginal(),
            permissions: self.permissions?.toOriginal(),
            description: self.channelDescription,
            nsfw: self.nsfw,
            last_message_id: self.last_message_id
        )
    }
}

// MARK: - TextChannel Mapper

extension TextChannel {
    func toRealm() -> TextChannelRealm {
        let realm = TextChannelRealm()
        realm.id = self.id
        realm.server = self.server
        realm.name = self.name
        realm.channelDescription = self.description
        realm.icon = self.icon?.toRealm()
        realm.default_permissions = self.default_permissions?.toRealm()
        
        // Convert role permissions
        if let rolePerms = self.role_permissions {
            realm.role_permissions.removeAll()
            for (key, value) in rolePerms {
                realm.role_permissions[key] = value.toRealm()
            }
        }
        
        realm.nsfw = self.nsfw
        realm.last_message_id = self.last_message_id
        realm.voice = self.voice?.toRealm()
        return realm
    }
}

extension TextChannelRealm {
    func toOriginal() -> TextChannel {
        // Convert role permissions back
        var rolePermissions: [String: Overwrite]? = nil
        if self.role_permissions.count > 0 {
            rolePermissions = [:]
            for key in self.role_permissions.keys {
                if let value = self.role_permissions[key] {
                    rolePermissions![key] = value.toOriginal()
                }
            }
        }
        
        return TextChannel(
            id: self.id,
            server: self.server,
            name: self.name,
            description: self.channelDescription,
            icon: self.icon?.toOriginal(),
            default_permissions: self.default_permissions?.toOriginal(),
            role_permissions: rolePermissions,
            nsfw: self.nsfw,
            last_message_id: self.last_message_id,
            voice: self.voice?.toOriginal()
        )
    }
}

// MARK: - VoiceChannel Mapper

extension VoiceChannel {
    func toRealm() -> VoiceChannelRealm {
        let realm = VoiceChannelRealm()
        realm.id = self.id
        realm.server = self.server
        realm.name = self.name
        realm.channelDescription = self.description
        realm.icon = self.icon?.toRealm()
        realm.default_permissions = self.default_permissions?.toRealm()
        
        // Convert role permissions
        if let rolePerms = self.role_permissions {
            realm.role_permissions.removeAll()
            for (key, value) in rolePerms {
                realm.role_permissions[key] = value.toRealm()
            }
        }
        
        realm.nsfw = self.nsfw
        return realm
    }
}

extension VoiceChannelRealm {
    func toOriginal() -> VoiceChannel {
        // Convert role permissions back
        var rolePermissions: [String: Overwrite]? = nil
        if self.role_permissions.count > 0 {
            rolePermissions = [:]
            for key in self.role_permissions.keys {
                if let value = self.role_permissions[key] {
                    rolePermissions![key] = value.toOriginal()
                }
            }
        }
        
        return VoiceChannel(
            id: self.id,
            server: self.server,
            name: self.name,
            description: self.channelDescription,
            icon: self.icon?.toOriginal(),
            default_permissions: self.default_permissions?.toOriginal(),
            role_permissions: rolePermissions,
            nsfw: self.nsfw
        )
    }
}

// MARK: - Channel Mapper

extension Channel {
    func toRealm() -> ChannelRealm {
        let realm = ChannelRealm()
        realm.id = self.id
        
        switch self {
        case .saved_messages(let savedMessages):
            realm.channel_type = "saved_messages"
            realm.savedMessages = savedMessages.toRealm()
        case .dm_channel(let dmChannel):
            realm.channel_type = "dm_channel"
            realm.dmChannel = dmChannel.toRealm()
        case .group_dm_channel(let groupDMChannel):
            realm.channel_type = "group_dm_channel"
            realm.groupDMChannel = groupDMChannel.toRealm()
        case .text_channel(let textChannel):
            realm.channel_type = "text_channel"
            realm.textChannel = textChannel.toRealm()
        case .voice_channel(let voiceChannel):
            realm.channel_type = "voice_channel"
            realm.voiceChannel = voiceChannel.toRealm()
        }
        
        return realm
    }
}

extension ChannelRealm {
    func toOriginal() -> Channel {
        switch self.channel_type {
        case "saved_messages":
            return .saved_messages(self.savedMessages!.toOriginal())
        case "dm_channel":
            return .dm_channel(self.dmChannel!.toOriginal())
        case "group_dm_channel":
            return .group_dm_channel(self.groupDMChannel!.toOriginal())
        case "text_channel":
            return .text_channel(self.textChannel!.toOriginal())
        case "voice_channel":
            return .voice_channel(self.voiceChannel!.toOriginal())
        default:
            fatalError("Unknown channel type: \(self.channel_type)")
        }
    }
}
