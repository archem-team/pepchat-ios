//
//  FriendsRepository.swift
//  Revolt
//
//  Repository for Friends data operations
//

import Foundation
import RealmSwift
import Types
import OSLog

/// Repository for managing Friends data between Network and Realm
class FriendsRepository {
    
    // MARK: - Singleton
    
    static let shared = FriendsRepository()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "FriendsRepository")
    private let realmManager = RealmManager.shared
    
    private init() {}
    
    // MARK: - Save Operations
    
    /// Save friends data to Realm (from API or WebSocket)
    func saveFriends(_ friends: [Types.User]) async {
        guard !friends.isEmpty else { return }
        await realmManager.writeBatch(friends.map { $0.toRealm() })
        logger.debug("✅ Saved \(friends.count) friends")
    }
    
    /// Save a single friend to Realm
    func saveFriend(_ friend: Types.User) async {
        await realmManager.write(friend.toRealm())
        logger.debug("✅ Friend saved: \(friend.id)")
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all friends from Realm
    func fetchAllFriends() async -> [Types.User] {
        let realms = await realmManager.getListOfObjects(type: UserRealm.self)
        return realms.compactMap { realm in
            let user = realm.toOriginal() as? Types.User
            return user?.relationship == .Friend ? user : nil
        }
    }
    
    /// Fetch friends by relationship type
    func fetchFriendsByRelationship(_ relationship: Relation) async -> [Types.User] {
        let realms = await realmManager.getListOfObjects(type: UserRealm.self)
        return realms.compactMap { realm in
            let user = realm.toOriginal() as? Types.User
            return user?.relationship == relationship ? user : nil
        }
    }
    
    /// Fetch incoming friend requests
    func fetchIncomingRequests() async -> [Types.User] {
        return await fetchFriendsByRelationship(.Incoming)
    }
    
    /// Fetch outgoing friend requests
    func fetchOutgoingRequests() async -> [Types.User] {
        return await fetchFriendsByRelationship(.Outgoing)
    }
    
    /// Fetch blocked users
    func fetchBlockedUsers() async -> [Types.User] {
        return await fetchFriendsByRelationship(.Blocked)
    }
    
    /// Fetch users who blocked current user
    func fetchBlockedByUsers() async -> [Types.User] {
        return await fetchFriendsByRelationship(.BlockedOther)
    }
    
    /// Search friends by query
    func searchFriends(query: String) async -> [Types.User] {
        let friends = await fetchAllFriends()
        let lowercaseQuery = query.lowercased()
        
        return friends.filter { friend in
            let username = friend.username.lowercased()
            let displayName = friend.display_name?.lowercased()
            
            return query.isEmpty ||
                   username.contains(lowercaseQuery) ||
                   (displayName?.contains(lowercaseQuery) ?? false)
        }
    }
    
    /// Get friends grouped by first letter (for alphabetical sorting)
    func getFriendsGroupedAlphabetically(query: String = "") async -> [String: [Types.User]] {
        let friends = await searchFriends(query: query)
        
        return Dictionary(grouping: friends) { String($0.username.prefix(1)).uppercased() }
            .sorted { $0.key < $1.key }
            .reduce(into: [:]) { result, group in
                result[group.key] = group.value
            }
    }
    
    /// Get friends grouped by status (for status sorting)
    func getFriendsGroupedByStatus(query: String = "") async -> [String: [Types.User]] {
        let friends = await searchFriends(query: query)
        
        let groupedUsers = Dictionary(grouping: friends) { user in
            user.status?.presence?.rawValue ?? "offline"
        }
        
        let sortedGroups = groupedUsers.sorted { $0.key < $1.key }
        
        return sortedGroups.reduce(into: [:]) { result, group in
            result[group.key] = group.value
        }
    }
    
    /// Check if data is stale (older than 5 minutes)
    func isDataStale() async -> Bool {
        // For now, always consider data fresh since we have real-time updates
        // In the future, we could add timestamp checking
        return false
    }
    
    /// Clear all friends data
    func clearFriendsData() async {
        let realms = await realmManager.getListOfObjects(type: UserRealm.self)
        let friendRealms = realms.filter { realm in
            let user = realm.toOriginal() as? Types.User
            return user?.relationship == .Friend || 
                   user?.relationship == .Incoming || 
                   user?.relationship == .Outgoing ||
                   user?.relationship == .Blocked ||
                   user?.relationship == .BlockedOther
        }
        
        await realmManager.deleteBatch(friendRealms)
        logger.debug("✅ Cleared friends data")
    }
}
