//
//  UserModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - UserBot Realm Object

class UserBotRealm: Object {
    @Persisted var owner: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Status Realm Object

class StatusRealm: Object {
    @Persisted var text: String?
    @Persisted var presence: String? // Stored as string representation of Presence enum
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - UserRelation Realm Object

class UserRelationRealm: Object {
    @Persisted var status: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Profile Realm Object

class ProfileRealm: Object {
    @Persisted var content: String?
    @Persisted var background: FileRealm?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - User Realm Object

class UserRealm: Object {
    @Persisted var id: String = ""
    @Persisted var username: String = ""
    @Persisted var discriminator: String = ""
    @Persisted var display_name: String?
    @Persisted var avatar: FileRealm?
    @Persisted var relations = List<UserRelationRealm>()
    @Persisted var badges: Int?
    @Persisted var status: StatusRealm?
    @Persisted var relationship: String? // Stored as string representation of Relation enum
    @Persisted var online: Bool?
    @Persisted var flags: Int?
    @Persisted var bot: UserBotRealm?
    @Persisted var privileged: Bool?
    @Persisted var profile: ProfileRealm?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}
