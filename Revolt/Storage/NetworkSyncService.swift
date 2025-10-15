//
//  NetworkSyncService.swift
//  Revolt
//
//  Network synchronization service - fetches from API and saves to Database
//  UI reads from Database only - reactive architecture
//

import Foundation
import OSLog
import SwiftCSV
import Types

/// Service responsible for syncing data from Network to Database
/// UI components should NOT call this directly - they read from Database only
@MainActor
class NetworkSyncService {
    
    // MARK: - Singleton
    static let shared = NetworkSyncService()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "NetworkSyncService")
    private var activeSyncs: Set<String> = [] // Prevent duplicate syncs
    
    private init() {}
    
    // MARK: - Members Sync
    
    /// Syncs server members from API to database
    /// Returns immediately - sync happens in background
    func syncServerMembers(serverId: String, excludeOffline: Bool = false) {
        let syncKey = "members_\(serverId)"
        guard !activeSyncs.contains(syncKey) else {
            logger.debug("⏭️ Members sync for server \(serverId) already active")
            return
        }
        
        activeSyncs.insert(syncKey)
        logger.info("🔄 Starting background sync for server members: \(serverId)")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check if data is stale first
                let isStale = await MemberRepository.shared.isDataStale(forServer: serverId)
                if !isStale {
                    logger.debug("✅ Members data is fresh for server \(serverId), skipping sync")
                    await MainActor.run {
                        self.activeSyncs.remove(syncKey)
                    }
                    return
                }
                
                // Fetch members from API
                let response = try await self.fetchServerMembersFromAPI(serverId: serverId, excludeOffline: excludeOffline)
                
                // Save to database
                await MemberRepository.shared.saveMembersWithUsers(response.members, users: response.users)
                
                logger.info("✅ Members sync completed for server \(serverId): \(response.members.count) members")
                
            } catch {
                logger.error("❌ Members sync failed for server \(serverId): \(error.localizedDescription)")
            }
            
            await MainActor.run {
                self.activeSyncs.remove(syncKey)
            }
        }
    }
    
    /// Fetches server members from API
    private func fetchServerMembersFromAPI(serverId: String, excludeOffline: Bool) async throws -> MembersWithUsers {
        logger.debug("🌐 Fetching members for server \(serverId) from API...")
        
        // Get ViewState reference
        guard let viewState = await MainActor.run(body: { ViewState.shared }) else {
            throw NSError(domain: "NetworkSyncService", code: -1, userInfo: [NSLocalizedDescriptionKey: "ViewState not available"])
        }
        
        // Call API
        let result = await viewState.http.fetchServerMembers(target: serverId, excludeOffline: excludeOffline)
        
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
    
    // MARK: - Friends Sync
    
    /// Syncs friends data from API to database
    /// Returns immediately - sync happens in background
    func syncFriends() {
        guard !activeSyncs.contains("friends") else {
            logger.debug("⏭️ Friends sync already active")
            return
        }
        
        activeSyncs.insert("friends")
        logger.info("🔄 Starting background sync for friends")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check if data is stale first
                let isStale = await FriendsRepository.shared.isDataStale()
                if !isStale {
                    logger.debug("✅ Friends data is fresh, skipping sync")
                    await MainActor.run {
                        self.activeSyncs.remove("friends")
                    }
                    return
                }
                
                // Fetch friends from API
                let friends = try await self.fetchFriendsFromAPI()
                
                // Save to database
                await FriendsRepository.shared.saveFriends(friends)
                
                logger.info("✅ Friends sync completed: \(friends.count) friends")
                
            } catch {
                logger.error("❌ Friends sync failed: \(error.localizedDescription)")
            }
            
            await MainActor.run {
                self.activeSyncs.remove("friends")
            }
        }
    }
    
    /// Fetches friends from API
    private func fetchFriendsFromAPI() async throws -> [Types.User] {
        // This would typically call the actual API endpoint
        // For now, return empty array as placeholder
        logger.debug("🌐 Fetching friends from API...")
        
        // TODO: Implement actual API call
        // let response = try await http.fetchFriends()
        // return response.users
        
        return []
    }
    
    // MARK: - Channels Sync
    
    /// Syncs all channels from API to database
    /// Returns immediately - sync happens in background
    func syncAllChannels() {
        guard !activeSyncs.contains("all_channels") else {
            logger.debug("⏭️ Channels sync already active")
            return
        }
        
        activeSyncs.insert("all_channels")
        logger.info("🔄 Starting background sync for all channels")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                // Channels are synced via WebSocket Ready event
                // This is mainly for triggering a refresh if needed
                logger.debug("✅ Channels sync - data comes from WebSocket Ready event")
                
            } catch {
                logger.error("❌ Channels sync failed: \(error.localizedDescription)")
            }
            
            await MainActor.run {
                self.activeSyncs.remove("all_channels")
            }
        }
    }
    
    // MARK: - Servers Sync
    
    /// Syncs all servers from API to database
    /// Returns immediately - sync happens in background
    func syncAllServers() {
        guard !activeSyncs.contains("all_servers") else {
            logger.debug("⏭️ Servers sync already active")
            return
        }
        
        activeSyncs.insert("all_servers")
        logger.info("🔄 Starting background sync for all servers")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                // Servers are synced via WebSocket Ready event
                // This is mainly for triggering a refresh if needed
                logger.debug("✅ Servers sync - data comes from WebSocket Ready event")
                
            } catch {
                logger.error("❌ Servers sync failed: \(error.localizedDescription)")
            }
            
            await MainActor.run {
                self.activeSyncs.remove("all_servers")
            }
        }
    }
    
    // MARK: - Discover Servers Sync
    
    /// Syncs discover servers from CSV to database
    /// Returns immediately - sync happens in background
    func syncDiscoverServers() {
        guard !activeSyncs.contains("discover_servers") else {
            logger.debug("⏭️ Discover servers sync already active")
            return
        }
        
        activeSyncs.insert("discover_servers")
        logger.info("🔄 Starting background sync for discover servers")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check if data is stale first
                let isStale = await DiscoverRepository.shared.isDataStale()
                if !isStale {
                    logger.debug("✅ Discover data is fresh, skipping sync")
                    await MainActor.run {
                        self.activeSyncs.remove("discover_servers")
                    }
                    return
                }
                
                // Fetch from CSV
                let serverChats = try await self.fetchDiscoverServersFromCSV()
                
                // Save to database
                await DiscoverRepository.shared.saveServerChats(serverChats)
                
                // Convert to DiscoverItems and save
                let discoverItems = serverChats.map { chat in
                    DiscoverItem(
                        id: chat.id,
                        code: chat.inviteCode,
                        title: chat.name,
                        description: chat.description,
                        isNew: chat.isNew,
                        sortOrder: chat.sortOrder,
                        disabled: chat.disabled,
                        color: chat.color
                    )
                }
                await DiscoverRepository.shared.saveDiscoverItems(discoverItems)
                
                logger.info("✅ Discover servers synced: \(serverChats.count) servers")
                
            } catch {
                logger.error("❌ Failed to sync discover servers: \(error.localizedDescription)")
            }
            
            await MainActor.run {
                self.activeSyncs.remove("discover_servers")
            }
        }
    }
    
    /// Fetches discover servers from CSV (moved from ServerChatDataFetcher)
    private func fetchDiscoverServersFromCSV() async throws -> [ServerChat] {
        let csvUrl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRY41D-NgTE6bC3kTN3dRpisI-DoeHG8Eg7n31xb1CdydWjOLaphqYckkTiaG9oIQSWP92h3NE-7cpF/pub?gid=0&single=true&output=csv"
        
        logger.debug("🌐 Fetching CSV from URL: \(csvUrl)")
        
        let (data, _) = try await URLSession.shared.data(from: URL(string: csvUrl)!)
        let csvString = String(data: data, encoding: .utf8)!
        
        let csv = try CSV<Named>(string: csvString)
        logger.debug("📊 Parsing CSV with \(csv.rows.count) rows")
        
        let serverChats = csv.rows.compactMap { row -> ServerChat? in
            guard let id = row["id"],
                  let name = row["name"],
                  let description = row["description"],
                  let inviteCode = row["inviteCode"],
                  let disabled = row["disabled"].map({ $0.lowercased() == "true" }),
                  let isNew = row["new"].map({ $0.lowercased() == "true" }),
                  let sortOrder = row["sortorder"].flatMap(Int.init),
                  let chronological = row["chronological"].flatMap(Int.init) else { return nil }
            
            return ServerChat(
                id: id,
                name: name,
                description: description,
                inviteCode: inviteCode,
                disabled: disabled,
                isNew: isNew,
                sortOrder: sortOrder,
                chronological: chronological,
                dateAdded: row["dateAdded"],
                price1: row[""],
                price2: row[""],
                color: row["showcolor"]
            )
        }
        
        logger.debug("📋 Parsed \(serverChats.count) valid servers from CSV")
        return serverChats
    }

    // MARK: - Channel Messages Sync
    
    /// Syncs messages for a channel from network to database
    /// Returns immediately - sync happens in background
    func syncChannelMessages(channelId: String, viewState: ViewState) {
        guard !activeSyncs.contains(channelId) else {
            logger.debug("⏭️ Sync already active for channel \(channelId)")
            return
        }
        
        activeSyncs.insert(channelId)
        logger.info("🔄 Starting background sync for channel \(channelId)")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                let serverId = await viewState.channels[channelId]?.server
                
                let result = try await viewState.http.fetchHistory(
                    channel: channelId,
                    limit: 100,
                    sort: "Latest",
                    server: serverId,
                    include_users: true
                ).get()
                
                await self.logger.info("✅ Fetched \(result.messages.count) messages from network for channel \(channelId)")
                
                // Save to database (DatabaseObserver will update ViewState)
                await NetworkRepository.shared.saveFetchHistoryResponse(
                    messages: result.messages,
                    users: result.users,
                    members: result.members
                )
                
                await self.logger.info("💾 Saved to database - DatabaseObserver will update UI")
                
            } catch {
                await self.logger.error("❌ Sync failed for channel \(channelId): \(error.localizedDescription)")
            }
            
            await MainActor.run {
                self.activeSyncs.remove(channelId)
            }
        }
    }
    
    // MARK: - Target Message Sync
    
    /// Syncs a specific target message and nearby messages
    func syncTargetMessage(messageId: String, channelId: String, viewState: ViewState) {
        logger.info("🎯 Starting target message sync: \(messageId)")
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            do {
                let result = try await viewState.http.fetchHistory(
                    channel: channelId,
                    limit: 100,
                    nearby: messageId
                ).get()
                
                await self.logger.info("✅ Fetched target message + \(result.messages.count) nearby messages")
                
                // Save to database
                await NetworkRepository.shared.saveFetchHistoryResponse(
                    messages: result.messages,
                    users: result.users,
                    members: result.members
                )
                
                await self.logger.info("💾 Target message saved - DatabaseObserver will update UI")
                
            } catch {
                await self.logger.error("❌ Target message sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Single Message Sync
    
    /// Syncs a single message (for replies, etc)
    func syncSingleMessage(messageId: String, channelId: String, viewState: ViewState) {
        logger.info("📨 Syncing single message: \(messageId)")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                let message = try await viewState.http.fetchMessage(
                    channel: channelId,
                    message: messageId
                ).get()
                
                await self.logger.info("✅ Fetched message \(messageId)")
                
                // Save to database
                await MessageRepository.shared.saveMessage(message)
                
                await self.logger.info("💾 Message saved to database")
                
            } catch {
                await self.logger.error("❌ Message sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - User Sync
    
    /// Syncs user information
    func syncUser(userId: String, viewState: ViewState) {
        logger.info("👤 Syncing user: \(userId)")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                let user = try await viewState.http.fetchUser(user: userId).get()
                
                await self.logger.info("✅ Fetched user \(user.username)")
                
                // Save to database
                await UserRepository.shared.saveUser(user)
                
                await self.logger.info("💾 User saved to database")
                
            } catch {
                await self.logger.error("❌ User sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Load More Messages
    
    /// Syncs older messages (for infinite scroll)
    func syncMoreMessages(channelId: String, before messageId: String, viewState: ViewState) {
        logger.info("📜 Syncing more messages before: \(messageId)")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                let serverId = await viewState.channels[channelId]?.server
                
                let result = try await viewState.http.fetchHistory(
                    channel: channelId,
                    limit: 100,
                    before: messageId,
                    after: nil,
                    nearby: nil,
                    sort: "Latest",
                    server: serverId,
                    messages: [],
                    include_users: true
                ).get()
                
                await self.logger.info("✅ Fetched \(result.messages.count) older messages")
                
                // Save to database
                await NetworkRepository.shared.saveFetchHistoryResponse(
                    messages: result.messages,
                    users: result.users,
                    members: result.members
                )
                
                await self.logger.info("💾 Older messages saved to database")
                
            } catch {
                await self.logger.error("❌ Load more sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Acknowledge Message
    
    /// Acknowledges a message as read
    func acknowledgeMessage(channelId: String, messageId: String, viewState: ViewState) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                _ = try await viewState.http.ackMessage(
                    channel: channelId,
                    message: messageId
                ).get()
                
                await self.logger.info("✅ Acknowledged message \(messageId)")
                
            } catch {
                await self.logger.error("❌ Ack failed: \(error.localizedDescription)")
            }
        }
    }
}

