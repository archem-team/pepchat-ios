//
//  ServerModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - ServerFlags Realm Object

class ServerFlagsRealm: Object {
    @Persisted var rawValue: Int = 0
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - SystemMessages Realm Object

class SystemMessagesRealm: Object {
    @Persisted var user_joined: String?
    @Persisted var user_left: String?
    @Persisted var user_kicked: String?
    @Persisted var user_banned: String?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Category Realm Object

class CategoryRealm: Object {
    @Persisted var id: String = ""
    @Persisted var title: String = ""
    @Persisted var channels = List<String>()
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - Role Realm Object

class RoleRealm: Object {
    @Persisted var name: String = ""
    @Persisted var permissions: OverwriteRealm?
    @Persisted var colour: String?
    @Persisted var hoist: Bool?
    @Persisted var rank: Int = 0
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Server Realm Object

class ServerRealm: Object {
    @Persisted var id: String = ""
    @Persisted var owner: String = ""
    @Persisted var name: String = ""
    @Persisted var channels = List<String>()
    @Persisted var default_permissions: PermissionsRealm?
    @Persisted var serverDescription: String? // renamed to avoid keyword conflict
    @Persisted var categories = List<CategoryRealm>()
    @Persisted var system_messages: SystemMessagesRealm?
    @Persisted var roles = RealmSwift.Map<String, RoleRealm>()
    @Persisted var icon: FileRealm?
    @Persisted var banner: FileRealm?
    @Persisted var nsfw: Bool?
    @Persisted var flags: ServerFlagsRealm?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

// MARK: - MemberId Realm Object

class MemberIdRealm: Object {
    @Persisted var server: String = ""
    @Persisted var user: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Member Realm Object

class MemberRealm: Object {
    @Persisted var memberIdRealm: MemberIdRealm?
    @Persisted var nickname: String?
    @Persisted var avatar: FileRealm?
    @Persisted var roles = List<String>()
    @Persisted var joined_at: String = ""
    @Persisted var timeout: String?
    
    // Computed property for unique ID
    var id: String {
        return "\(memberIdRealm?.server ?? "")_\(memberIdRealm?.user ?? "")"
    }
    
    override static func primaryKey() -> String? {
        return nil // We'll use a composite key approach
    }
}
