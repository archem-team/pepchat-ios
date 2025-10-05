//
//  ServerRepository.swift
//  Revolt
//
//  Repository for Server data operations
//

import Foundation
import RealmSwift
import Types
import OSLog

/// Repository for managing Server data between Network and Realm
class ServerRepository {
    
    // MARK: - Singleton
    
    static let shared = ServerRepository()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "ServerRepository")
    private let realmManager = RealmManager.shared
    
    private init() {}
    
    // MARK: - Save Operations
    
    /// Save a single server to Realm (from API or WebSocket)
    func saveServer(_ server: Types.Server) async {
        await realmManager.write(server.toRealm())
        logger.debug("✅ Server saved: \(server.id)")
    }
    
    /// Save multiple servers to Realm (from API or WebSocket)
    func saveServers(_ servers: [Types.Server]) async {
        guard !servers.isEmpty else { return }
        await realmManager.writeBatch(servers.map { $0.toRealm() })
        logger.debug("✅ Saved \(servers.count) servers")
    }
    
    // MARK: - Delete Operations
    
    /// Delete a server by ID
    func deleteServer(id: String) async {
        await realmManager.deleteByPrimaryKey(ServerRealm.self, key: id)
        logger.debug("✅ Server deleted: \(id)")
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch a server from Realm by ID
    func fetchServer(id: String) async -> Types.Server? {
        guard let serverRealm = await realmManager.fetchItemByPrimaryKey(ServerRealm.self, primaryKey: id) else {
            return nil
        }
        return serverRealm.toOriginal() as? Types.Server
    }
    
    /// Fetch all servers from Realm
    func fetchAllServers() async -> [Types.Server] {
        let realms = await realmManager.getListOfObjects(type: ServerRealm.self)
        return realms.compactMap { $0.toOriginal() as? Types.Server }
    }
}
