//
//  UnreadModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift

// MARK: - Unread Realm Object

class UnreadRealm: Object {
    @Persisted var id: String = ""            // Compound key: "<channel>:<user>"
    @Persisted var channel: String = ""
    @Persisted var user: String = ""
    @Persisted var last_id: String?
    @Persisted var mentions = List<String>()
    
    override static func primaryKey() -> String? {
        return "id"
    }
}


