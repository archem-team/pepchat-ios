//
//  NetworkRepository.swift
//  Revolt
//
//  Repository for bulk network data operations (Ready Event, etc.)
//

import Foundation
import RealmSwift
import Types
import OSLog

/// Repository for managing bulk network data operations
class NetworkRepository {
    
    // MARK: - Singleton
    
    static let shared = NetworkRepository()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "NetworkRepository")
    private let realmManager = RealmManager.shared
    
    private init() {}
    
    // MARK: - Ready Event (WebSocket)
    
    /// Save all data from WebSocket ready event to Realm
    func saveReadyEvent(
        users: [Types.User],
        servers: [Types.Server],
        channels: [Types.Channel],
        members: [Types.Member],
        emojis: [Types.Emoji]
    ) async {
        logger.info("🌐 Saving ready event: users=\(users.count), servers=\(servers.count), channels=\(channels.count), members=\(members.count), emojis=\(emojis.count)")
        
        // Convert to Realm objects
        let usersRealm = users.map { $0.toRealm() }
        let serversRealm = servers.map { $0.toRealm() }
        let channelsRealm = channels.map { $0.toRealm() }
        let membersRealm = members.map { $0.toRealm() }
        let emojisRealm = emojis.map { $0.toRealm() }
        
        // Save all in batches
        await realmManager.writeBatch(usersRealm)
        await realmManager.writeBatch(serversRealm)
        await realmManager.writeBatch(channelsRealm)
        await realmManager.writeBatch(membersRealm)
        await realmManager.writeBatch(emojisRealm)
        
        logger.info("✅ Ready event saved successfully")
    }
    
    // MARK: - Fetch History Response
    
    /// Save fetch history response to Realm
    func saveFetchHistoryResponse(
        messages: [Types.Message],
        users: [Types.User],
        members: [Types.Member]?
    ) async {
        logger.debug("💾 Saving fetch history: messages=\(messages.count), users=\(users.count), members=\(members?.count ?? 0)")
        
        // Save users
        await UserRepository.shared.saveUsers(users)
        
        // Save members
        if let members = members {
            await MemberRepository.shared.saveMembers(members)
        }
        
        // Save messages
        await MessageRepository.shared.saveMessages(messages)
        
        logger.debug("✅ Fetch history saved successfully")
    }
}
