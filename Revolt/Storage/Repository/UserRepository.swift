//
//  UserRepository.swift
//  Revolt
//
//  Repository for User data operations
//

import Foundation
import RealmSwift
import Types
import OSLog

/// Repository for managing User data between Network and Realm
class UserRepository {
    
    // MARK: - Singleton
    
    static let shared = UserRepository()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "UserRepository")
    private let realmManager = RealmManager.shared
    
    private init() {}
    
    // MARK: - Save Operations
    
    /// Save a single user to Realm (from API or WebSocket)
    func saveUser(_ user: Types.User) async {
        await realmManager.write(user.toRealm())
        logger.debug("✅ User saved: \(user.id)")
    }
    
    /// Save multiple users to Realm (from API or WebSocket)
    func saveUsers(_ users: [Types.User]) async {
        guard !users.isEmpty else { return }
        await realmManager.writeBatch(users.map { $0.toRealm() })
        logger.debug("✅ Saved \(users.count) users")
    }
    
    // MARK: - Delete Operations
    
    /// Delete a user by ID
    func deleteUser(id: String) async {
        await realmManager.deleteByPrimaryKey(UserRealm.self, key: id)
        logger.debug("✅ User deleted: \(id)")
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch a user from Realm by ID
    func fetchUser(id: String) async -> Types.User? {
        guard let userRealm = await realmManager.fetchItemByPrimaryKey(UserRealm.self, primaryKey: id) else {
            return nil
        }
        return userRealm.toOriginal() as? Types.User
    }
    
    /// Batch fetch multiple users by their IDs (optimized for message rendering)
    func fetchUsers(ids: [String]) async -> [String: Types.User] {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard !ids.isEmpty else { return [:] }
        
        let realms = await realmManager.getListOfObjects(type: UserRealm.self)
        let idSet = Set(ids)
        let filtered = realms.filter { idSet.contains($0.id) }
        
        var usersDictionary: [String: Types.User] = [:]
        for userRealm in filtered {
            if let user = userRealm.toOriginal() as? Types.User {
                usersDictionary[user.id] = user
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        logger.debug("📊 Batch fetched \(usersDictionary.count) users in \(String(format: "%.2f", duration))ms")
        
        return usersDictionary
    }
    
    /// Fetch all users from Realm
    func fetchAllUsers() async -> [Types.User] {
        let realms = await realmManager.getListOfObjects(type: UserRealm.self)
        return realms.compactMap { $0.toOriginal() as? Types.User }
    }
}
