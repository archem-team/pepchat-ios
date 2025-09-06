//
//  UserMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - UserBot Mapper

extension Types.UserBot {
    func toRealm() -> UserBotRealm {
        let realm = UserBotRealm()
        realm.owner = self.owner
        return realm
    }
}

extension UserBotRealm {
    func toOriginal() -> Types.UserBot {
        return Types.UserBot(owner: self.owner)
    }
}

// MARK: - Presence Mapper

extension Types.Presence {
    func toString() -> String {
        return self.rawValue
    }
    
    static func fromString(_ string: String) -> Types.Presence? {
        return Types.Presence(rawValue: string)
    }
}

// MARK: - Relation Mapper

extension Types.Relation {
    func toString() -> String {
        return self.rawValue
    }
    
    static func fromString(_ string: String) -> Types.Relation? {
        return Types.Relation(rawValue: string)
    }
}

// MARK: - Status Mapper

extension Types.Status {
    func toRealm() -> StatusRealm {
        let realm = StatusRealm()
        realm.text = self.text
        realm.presence = self.presence?.toString()
        return realm
    }
}

extension StatusRealm {
    func toOriginal() -> Types.Status {
        return Types.Status(
            text: self.text,
            presence: self.presence != nil ? Types.Presence.fromString(self.presence!) : nil
        )
    }
}

// MARK: - UserRelation Mapper

extension Types.UserRelation {
    func toRealm() -> UserRelationRealm {
        let realm = UserRelationRealm()
        realm.status = self.status
        return realm
    }
}

extension UserRelationRealm {
    func toOriginal() -> Types.UserRelation {
        return Types.UserRelation(status: self.status)
    }
}

// MARK: - Profile Mapper

extension Types.Profile {
    func toRealm() -> ProfileRealm {
        let realm = ProfileRealm()
        realm.content = self.content
        realm.background = self.background?.toRealm()
        return realm
    }
}

extension ProfileRealm {
    func toOriginal() -> Types.Profile {
        return Types.Profile(
            content: self.content,
            background: self.background?.toOriginal()
        )
    }
}

// MARK: - User Mapper

extension Types.User {
    func toRealm() -> UserRealm {
        let realm = UserRealm()
        realm.id = self.id
        realm.username = self.username
        realm.discriminator = self.discriminator
        realm.display_name = self.display_name
        realm.avatar = self.avatar?.toRealm()
        
        if let relations = self.relations {
            realm.relations.removeAll()
            for relation in relations {
                realm.relations.append(relation.toRealm())
            }
        }
        
        realm.badges = self.badges
        realm.status = self.status?.toRealm()
        realm.relationship = self.relationship?.toString()
        realm.online = self.online
        realm.flags = self.flags
        realm.bot = self.bot?.toRealm()
        realm.privileged = self.privileged
        realm.profile = self.profile?.toRealm()
        
        return realm
    }
}

extension UserRealm {
    func toOriginal() -> Types.User {
        let relations = self.relations.isEmpty ? nil : Array(self.relations.map { $0.toOriginal() })
        
        return Types.User(
            id: self.id,
            username: self.username,
            discriminator: self.discriminator,
            display_name: self.display_name,
            avatar: self.avatar?.toOriginal(),
            relations: relations,
            badges: self.badges,
            status: self.status?.toOriginal(),
            relationship: self.relationship != nil ? Types.Relation.fromString(self.relationship!) : nil,
            online: self.online,
            flags: self.flags,
            bot: self.bot?.toOriginal(),
            privileged: self.privileged,
            profile: self.profile?.toOriginal()
        )
    }
}
