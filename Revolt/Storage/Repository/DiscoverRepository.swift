//
//  DiscoverRepository.swift
//  Revolt
//
//  Repository for Discover servers data operations
//

import Foundation
import RealmSwift
import OSLog

/// Repository for managing Discover servers data between Network and Realm
class DiscoverRepository {
    
    // MARK: - Singleton
    
    static let shared = DiscoverRepository()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "DiscoverRepository")
    private let realmManager = RealmManager.shared
    
    private init() {}
    
    // MARK: - Save Operations
    
    /// Save discover items to Realm (from CSV or API)
    func saveDiscoverItems(_ items: [DiscoverItem]) async {
        guard !items.isEmpty else { return }
        
        let realmItems = items.map { $0.toRealm() }
        await realmManager.writeBatch(realmItems)
        logger.debug("✅ Saved \(items.count) discover items")
    }
    
    /// Save server chat data to Realm (from CSV)
    func saveServerChats(_ serverChats: [ServerChat]) async {
        guard !serverChats.isEmpty else { return }
        
        let realmChats = serverChats.map { $0.toRealm() }
        await realmManager.writeBatch(realmChats)
        logger.debug("✅ Saved \(serverChats.count) server chats")
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all discover items from Realm
    func fetchDiscoverItems() async -> [DiscoverItem] {
        let realmItems = await realmManager.getListOfObjects(type: DiscoverItemRealm.self)
        return realmItems.map { $0.toOriginal() }
    }
    
    /// Fetch all server chats from Realm
    func fetchServerChats() async -> [ServerChat] {
        let realmChats = await realmManager.getListOfObjects(type: ServerChatRealm.self)
        return realmChats.map { $0.toOriginal() }
    }
    
    /// Check if discover data is stale (older than 1 hour)
    func isDataStale() async -> Bool {
        let realmItems = await realmManager.getListOfObjects(type: DiscoverItemRealm.self)
        guard let firstItem = realmItems.first else { return true }
        
        let oneHourAgo = Date().addingTimeInterval(-3600) // 1 hour
        return firstItem.lastUpdated < oneHourAgo
    }
    
    /// Clear all discover data
    func clearDiscoverData() async {
        await realmManager.deleteAll(DiscoverItemRealm.self)
        await realmManager.deleteAll(ServerChatRealm.self)
        logger.debug("✅ Cleared all discover data")
    }
}
