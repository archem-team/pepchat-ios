//
//  MemberRepository.swift
//  Revolt
//
//  Repository for Member data operations
//

import Foundation
import RealmSwift
import Types
import OSLog

/// Repository for managing Member data between Network and Realm
class MemberRepository {
    
    // MARK: - Singleton
    
    static let shared = MemberRepository()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "MemberRepository")
    private let realmManager = RealmManager.shared
    
    private init() {}
    
    // MARK: - Save Operations
    
    /// Save a single member to Realm (from API or WebSocket)
    func saveMember(_ member: Types.Member) async {
        await realmManager.write(member.toRealm())
        logger.debug("✅ Member saved: \(member.id.user) in server \(member.id.server)")
    }
    
    /// Save multiple members to Realm (from API or WebSocket)
    func saveMembers(_ members: [Types.Member]) async {
        guard !members.isEmpty else { return }
        await realmManager.writeBatch(members.map { $0.toRealm() })
        logger.debug("✅ Saved \(members.count) members")
    }
    
    // MARK: - Delete Operations
    
    /// Delete a member by composite ID (server + user)
    func deleteMember(serverId: String, userId: String) async {
        let compositeKey = "\(serverId)_\(userId)"
        await realmManager.deleteByPrimaryKey(MemberRealm.self, key: compositeKey)
        logger.debug("✅ Member deleted: \(userId) from server \(serverId)")
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch a member from Realm by server and user ID
    func fetchMember(serverId: String, userId: String) async -> Types.Member? {
        let compositeKey = "\(serverId)_\(userId)"
        guard let memberRealm = await realmManager.fetchItemByPrimaryKey(MemberRealm.self, primaryKey: compositeKey) else {
            return nil
        }
        return memberRealm.toOriginal() as? Types.Member
    }
    
    /// Fetch all members for a specific server
    func fetchMembers(forServer serverId: String) async -> [Types.Member] {
        let realms = await realmManager.getListOfObjects(type: MemberRealm.self)
        let filtered = realms.filter { $0.memberIdRealm?.server == serverId }
        return filtered.compactMap { $0.toOriginal() as? Types.Member }
    }
    
    /// Fetch all members from Realm
    func fetchAllMembers() async -> [Types.Member] {
        let realms = await realmManager.getListOfObjects(type: MemberRealm.self)
        return realms.compactMap { $0.toOriginal() as? Types.Member }
    }
    
    /// Search members by query in a specific server
    func searchMembers(forServer serverId: String, query: String, users: [String: Types.User]) async -> [Types.Member] {
        let members = await fetchMembers(forServer: serverId)
        
        guard !query.isEmpty else {
            return members
        }
        
        let lowercaseQuery = query.lowercased()
        
        return members.filter { member in
            if let user = users[member.id.user] {
                return user.username.lowercased().contains(lowercaseQuery) ||
                       (user.display_name?.lowercased().contains(lowercaseQuery) ?? false)
            }
            return false
        }
    }
    
    /// Get members count for a server
    func getMembersCount(forServer serverId: String) async -> Int {
        let members = await fetchMembers(forServer: serverId)
        return members.count
    }
    
    /// Get formatted members count for a server
    func getFormattedMembersCount(forServer serverId: String) async -> String {
        let count = await getMembersCount(forServer: serverId)
        return count.formattedWithSeparator()
    }
    
    /// Save members with users (from API response)
    func saveMembersWithUsers(_ members: [Types.Member], users: [Types.User]) async {
        // Save users first
        await UserRepository.shared.saveUsers(users)
        
        // Then save members
        await saveMembers(members)
        
        logger.debug("✅ Saved \(members.count) members and \(users.count) users")
    }
    
    /// Check if data is stale (older than 5 minutes)
    func isDataStale(forServer serverId: String) async -> Bool {
        // For now, always consider data fresh since we have real-time updates
        // In the future, we could add timestamp checking
        return false
    }
    
    /// Clear all members data for a specific server
    func clearMembersData(forServer serverId: String) async {
        let realms = await realmManager.getListOfObjects(type: MemberRealm.self)
        let serverMembers = realms.filter { $0.memberIdRealm?.server == serverId }
        
        await realmManager.deleteBatch(serverMembers)
        logger.debug("✅ Cleared members data for server \(serverId)")
    }
}
