//
//  PermissionMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - UserPermissions Mapper

extension UserPermissions {
    func toRealm() -> UserPermissionsRealm {
        let realm = UserPermissionsRealm()
        realm.rawValue = self.rawValue
        return realm
    }
}

extension UserPermissionsRealm {
    func toOriginal() -> UserPermissions {
        return UserPermissions(rawValue: self.rawValue)
    }
}

// MARK: - Permissions Mapper

extension Permissions {
    func toRealm() -> PermissionsRealm {
        let realm = PermissionsRealm()
        realm.rawValue = self.rawValue
        return realm
    }
}

extension PermissionsRealm {
    func toOriginal() -> Permissions {
        return Permissions(rawValue: self.rawValue)
    }
}

// MARK: - Overwrite Mapper

extension Overwrite {
    func toRealm() -> OverwriteRealm {
        let realm = OverwriteRealm()
        realm.a = self.a.toRealm()
        realm.d = self.d.toRealm()
        return realm
    }
}

extension OverwriteRealm {
    func toOriginal() -> Overwrite {
        return Overwrite(
            a: self.a!.toOriginal(),
            d: self.d!.toOriginal()
        )
    }
}
