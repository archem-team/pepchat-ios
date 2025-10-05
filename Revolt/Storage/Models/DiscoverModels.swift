//
//  DiscoverModels.swift
//  Revolt
//
//  Realm models for Discover servers
//

import Foundation
import RealmSwift
import Types

// MARK: - DiscoverItem Realm Object

class DiscoverItemRealm: Object {
	@Persisted var id: String = ""
	@Persisted var code: String = ""
	@Persisted var title: String = ""
	@Persisted var serverDescription: String = "" // Changed from 'description' to avoid NSObject conflict
	@Persisted var isNew: Bool = false
	@Persisted var sortOrder: Int = 0
	@Persisted var disabled: Bool = false
	@Persisted var color: String?
	@Persisted var lastUpdated: Date = Date()
	
	override static func primaryKey() -> String? {
		return "id"
	}
}

// MARK: - ServerChat Realm Object (for CSV data)

class ServerChatRealm: Object {
	@Persisted var id: String = ""
	@Persisted var name: String = ""
	@Persisted var serverDescription: String = "" // Changed from 'description' to avoid NSObject conflict
	@Persisted var inviteCode: String = ""
	@Persisted var disabled: Bool = false
	@Persisted var isNew: Bool = false
	@Persisted var sortOrder: Int = 0
	@Persisted var chronological: Int = 0
	@Persisted var dateAdded: String?
	@Persisted var price1: String?
	@Persisted var price2: String?
	@Persisted var color: String?
	@Persisted var lastUpdated: Date = Date()
	
	override static func primaryKey() -> String? {
		return "id"
	}
}
