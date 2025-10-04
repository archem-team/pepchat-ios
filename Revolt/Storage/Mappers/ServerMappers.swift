//
//  ServerMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - ServerFlags Mapper

extension ServerFlags {
    func toRealm() -> ServerFlagsRealm {
        let realm = ServerFlagsRealm()
        realm.rawValue = self.rawValue
        return realm
    }
}

extension ServerFlagsRealm {
    func toOriginal() -> ServerFlags {
        return ServerFlags(rawValue: self.rawValue)
    }
}

// MARK: - SystemMessages Mapper

extension SystemMessages {
    func toRealm() -> SystemMessagesRealm {
        let realm = SystemMessagesRealm()
        realm.user_joined = self.user_joined
        realm.user_left = self.user_left
        realm.user_kicked = self.user_kicked
        realm.user_banned = self.user_banned
        return realm
    }
}

extension SystemMessagesRealm {
    func toOriginal() -> SystemMessages {
        return SystemMessages(
            user_joined: self.user_joined,
            user_left: self.user_left,
            user_kicked: self.user_kicked,
            user_banned: self.user_banned
        )
    }
}

// MARK: - Category Mapper

extension Types.Category {
    func toRealm() -> CategoryRealm {
        let realm = CategoryRealm()
        realm.id = self.id
        realm.title = self.title
        realm.channels.removeAll()
        realm.channels.append(objectsIn: self.channels)
        return realm
    }
}

extension CategoryRealm {
	func toOriginal() -> Types.Category {
        return Category(
            id: self.id,
            title: self.title,
            channels: Array(self.channels)
        )
    }
}

// MARK: - Role Mapper

extension Role {
    func toRealm() -> RoleRealm {
        let realm = RoleRealm()
        realm.name = self.name
        realm.permissions = self.permissions.toRealm()
        realm.colour = self.colour
        realm.hoist = self.hoist
        realm.rank = self.rank
        return realm
    }
}

extension RoleRealm {
    func toOriginal() -> Role {
        return Role(
            name: self.name,
            permissions: self.permissions!.toOriginal(),
            colour: self.colour,
            hoist: self.hoist,
            rank: self.rank
        )
    }
}

// MARK: - Server Mapper

extension Server {
    func toRealm() -> ServerRealm {
        let realm = ServerRealm()
        realm.id = self.id
        realm.owner = self.owner
        realm.name = self.name
        realm.channels.removeAll()
        realm.channels.append(objectsIn: self.channels)
        realm.default_permissions = self.default_permissions.toRealm()
        realm.serverDescription = self.description
        
        if let categories = self.categories {
            realm.categories.removeAll()
            for category in categories {
                realm.categories.append(category.toRealm())
            }
        }
        
        realm.system_messages = self.system_messages?.toRealm()
        
        if let roles = self.roles {
            realm.roles.removeAll()
            for (key, value) in roles {
                realm.roles[key] = value.toRealm()
            }
        }
        
        realm.icon = self.icon?.toRealm()
        realm.banner = self.banner?.toRealm()
        realm.nsfw = self.nsfw
        realm.flags = self.flags?.toRealm()
        
        return realm
    }
}

extension ServerRealm {
    func toOriginal() -> Server {
        let categories = self.categories.isEmpty ? nil : Array(self.categories.map { $0.toOriginal() })
        
        var roles: [String: Role]? = nil
        if self.roles.count > 0 {
            roles = [:]
            for key in self.roles.keys {
                if let value = self.roles[key] {
                    roles![key] = value?.toOriginal()
                }
            }
        }
        
        return Server(
            id: self.id,
            owner: self.owner,
            name: self.name,
            channels: Array(self.channels),
            default_permissions: self.default_permissions!.toOriginal(),
            description: self.serverDescription,
            categories: categories,
            system_messages: self.system_messages?.toOriginal(),
            roles: roles,
            icon: self.icon?.toOriginal(),
            banner: self.banner?.toOriginal(),
            nsfw: self.nsfw,
            flags: self.flags?.toOriginal()
        )
    }
}

// MARK: - MemberId Mapper

extension MemberId {
    func toRealm() -> MemberIdRealm {
        let realm = MemberIdRealm()
        realm.server = self.server
        realm.user = self.user
        return realm
    }
}

extension MemberIdRealm {
    func toOriginal() -> MemberId {
        return MemberId(server: self.server, user: self.user)
    }
}

// MARK: - Member Mapper

extension Member {
    func toRealm() -> MemberRealm {
        let realm = MemberRealm()
        // Ensure stable primary key based on composite id
        realm.id = "\(self.id.server)_\(self.id.user)"
        realm.memberIdRealm = self.id.toRealm()
        realm.nickname = self.nickname
        realm.avatar = self.avatar?.toRealm()
        
        if let roles = self.roles {
            realm.roles.removeAll()
            realm.roles.append(objectsIn: roles)
        }
        
        realm.joined_at = self.joined_at
        realm.timeout = self.timeout
        return realm
    }
}

extension MemberRealm {
    func toOriginal() -> Member {
        let roles = self.roles.isEmpty ? nil : Array(self.roles)
        
        return Member(
            id: self.memberIdRealm!.toOriginal(),
            nickname: self.nickname,
            avatar: self.avatar?.toOriginal(),
            roles: roles,
            joined_at: self.joined_at,
            timeout: self.timeout
        )
    }
}
