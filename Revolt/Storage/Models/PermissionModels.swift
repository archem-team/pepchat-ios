//
//  PermissionModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - UserPermissions Realm Object

class UserPermissionsRealm: Object {
    @Persisted var rawValue: Int = 0
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Permissions Realm Object

class PermissionsRealm: Object {
    @Persisted var rawValue: Int = 0
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Overwrite Realm Object

class OverwriteRealm: Object {
    @Persisted var a: PermissionsRealm? // Allowed permissions
    @Persisted var d: PermissionsRealm? // Denied permissions
    
    override static func primaryKey() -> String? {
        return nil
    }
}
