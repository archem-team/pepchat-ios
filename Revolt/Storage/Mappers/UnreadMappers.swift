//
//  UnreadMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

extension Unread {
    func toRealm() -> UnreadRealm {
        let realm = UnreadRealm()
        realm.id = "\(id.channel):\(id.user)"
        realm.channel = id.channel
        realm.user = id.user
        realm.last_id = last_id
        realm.mentions.removeAll()
        if let mentions = mentions {
            realm.mentions.append(objectsIn: mentions)
        }
        return realm
    }
}

extension UnreadRealm {
    func toOriginal() -> Unread {
        let inner = Unread.Id(channel: channel, user: user)
        return Unread(id: inner, last_id: last_id, mentions: Array(mentions))
    }
}


