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
        await withCheckedContinuation { continuation in
            Task {
                guard let userRealm = await realmManager.fetchItemByPrimaryKey(UserRealm.self, primaryKey: id) else {
                    continuation.resume(returning: nil)
                    return
                }
                if let user = userRealm.toOriginal() as? Types.User {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Fetch all users from Realm
    func fetchAllUsers() async -> [Types.User] {
        await withCheckedContinuation { continuation in
            Task {
                await realmManager.getListOfObjects(type: UserRealm.self) { usersRealm in
                    let users = usersRealm.compactMap { $0.toOriginal() as? Types.User }
                    continuation.resume(returning: users)
                }
            }
        }
    }
}
