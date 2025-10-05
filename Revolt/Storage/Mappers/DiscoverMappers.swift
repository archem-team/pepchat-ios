//
//  DiscoverMappers.swift
//  Revolt
//
//  Mappers for Discover models
//

import Foundation
import RealmSwift

// MARK: - DiscoverItem Mapper

extension DiscoverItem {
    func toRealm() -> DiscoverItemRealm {
        let realm = DiscoverItemRealm()
        realm.id = self.id
        realm.code = self.code
        realm.title = self.title
        realm.serverDescription = self.description
        realm.isNew = self.isNew
        realm.sortOrder = self.sortOrder
        realm.disabled = self.disabled
        realm.color = self.color
        realm.lastUpdated = Date()
        return realm
    }
}

extension DiscoverItemRealm {
    func toOriginal() -> DiscoverItem {
        return DiscoverItem(
            id: self.id,
            code: self.code,
            title: self.title,
            description: self.serverDescription,
            isNew: self.isNew,
            sortOrder: self.sortOrder,
            disabled: self.disabled,
            color: self.color
        )
    }
}

// MARK: - ServerChat Mapper

extension ServerChat {
    func toRealm() -> ServerChatRealm {
        let realm = ServerChatRealm()
        realm.id = self.id
        realm.name = self.name
        realm.serverDescription = self.description
        realm.inviteCode = self.inviteCode
        realm.disabled = self.disabled
        realm.isNew = self.isNew
        realm.sortOrder = self.sortOrder
        realm.chronological = self.chronological
        realm.dateAdded = self.dateAdded
        realm.price1 = self.price1
        realm.price2 = self.price2
        realm.color = self.color
        realm.lastUpdated = Date()
        return realm
    }
}

extension ServerChatRealm {
    func toOriginal() -> ServerChat {
        return ServerChat(
            id: self.id,
            name: self.name,
            description: self.serverDescription,
            inviteCode: self.inviteCode,
            disabled: self.disabled,
            isNew: self.isNew,
            sortOrder: self.sortOrder,
            chronological: self.chronological,
            dateAdded: self.dateAdded,
            price1: self.price1,
            price2: self.price2,
            color: self.color
        )
    }
}
