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
}
