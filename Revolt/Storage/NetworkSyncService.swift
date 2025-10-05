//
//  NetworkSyncService.swift
//  Revolt
//
//  Network synchronization service - fetches from API and saves to Database
//  UI reads from Database only - reactive architecture
//

import Foundation
import Types
import OSLog

/// Service responsible for syncing data from Network to Database
/// UI components should NOT call this directly - they read from Database only
@MainActor
class NetworkSyncService {
    
    // MARK: - Singleton
    static let shared = NetworkSyncService()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "NetworkSyncService")
    private var activeSyncs: Set<String> = [] // Prevent duplicate syncs
    
    private init() {}
    
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
                    limit: 50,
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
                    server: serverId,
                    messages: [messageId]
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

