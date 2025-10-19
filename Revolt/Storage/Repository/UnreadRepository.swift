//
//  UnreadRepository.swift
//  Revolt
//
//  Repository for Unread data operations
//

import Foundation
import RealmSwift
import Types
import OSLog

class UnreadRepository {
    static let shared = UnreadRepository()
    private init() {}
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "UnreadRepository")
    private let realmManager = RealmManager.shared
    
    // MARK: - Save
    func saveAll(_ unreads: [Unread]) async {
        guard !unreads.isEmpty else { return }
        await realmManager.writeBatch(unreads.map { $0.toRealm() })
        logger.debug("✅ Saved \(unreads.count) unreads")
    }
    
    func save(_ unread: Unread) async {
        await realmManager.write(unread.toRealm())
        logger.debug("✅ Unread saved for channel=\(unread.id.channel)")
    }
    
    // MARK: - Fetch
    func fetchAll(forUser userId: String? = nil) async -> [Unread] {
        let results = await realmManager.getListOfObjects(type: UnreadRealm.self)
        let filtered: [UnreadRealm]
        if let userId {
            filtered = results.filter { $0.user == userId }
        } else {
            filtered = results
        }
        return filtered.map { $0.toOriginal() }
    }
    
    func fetch(forChannel channelId: String, userId: String? = nil) async -> Unread? {
        let key: String
        if let userId { key = "\(channelId):\(userId)" } else { key = channelId }
        if let realmObj = await realmManager.fetchItemByPrimaryKey(UnreadRealm.self, primaryKey: key) {
            return realmObj.toOriginal()
        }
        return nil
    }
    
    // MARK: - Update
    func updateAck(channelId: String, lastId: String, userId: String) async {
        // Upsert by primary key
        let realmObj = UnreadRealm()
        realmObj.id = "\(channelId):\(userId)"
        realmObj.channel = channelId
        realmObj.user = userId
        realmObj.last_id = lastId
        await realmManager.write(realmObj)
        logger.debug("✅ Ack persisted for channel=\(channelId) -> last_id=\(lastId)")
    }
    
    func clearMentions(channelId: String, userId: String) async {
        if let realmObj = await realmManager.fetchItemByPrimaryKey(UnreadRealm.self, primaryKey: "\(channelId):\(userId)") {
            let updated = UnreadRealm()
            updated.id = realmObj.id
            updated.channel = realmObj.channel
            updated.user = realmObj.user
            updated.last_id = realmObj.last_id
            updated.mentions.removeAll()
            await realmManager.write(updated)
            logger.debug("✅ Cleared mentions for channel=\(channelId)")
        }
    }
}


