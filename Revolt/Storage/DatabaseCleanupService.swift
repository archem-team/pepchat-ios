//
//  DatabaseCleanupService.swift
//  Revolt
//
//  Service to manage database size through TTL-based cleanup
//  Prevents unbounded database growth
//

import Foundation
import RealmSwift
import Types
import OSLog

/// Manages database cleanup to prevent unbounded growth
class DatabaseCleanupService {
    
    // MARK: - Singleton
    
    static let shared = DatabaseCleanupService()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "DatabaseCleanup")
    
    // MARK: - Configuration
    
    /// Keep messages for 30 days
    private let messageTTLDays: Int = 30
    
    /// Maximum messages per channel to keep
    private let maxMessagesPerChannel: Int = 500
    
    /// How often to run cleanup (in seconds)
    private let cleanupInterval: TimeInterval = 3600 // 1 hour
    
    private var cleanupTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Cleanup Operations
    
    /// Start periodic cleanup
    func startPeriodicCleanup() {
        logger.info("🧹 Starting periodic database cleanup (interval: \(self.cleanupInterval)s)")
        
        // Run initial cleanup after a delay
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60) { [weak self] in
            Task {
                //await self?.performCleanup()
            }
        }
        
        // Schedule periodic cleanup
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task {
                //await self?.performCleanup()
            }
        }
    }
    
    /// Stop periodic cleanup
    func stopPeriodicCleanup() {
        logger.info("🛑 Stopping periodic database cleanup")
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    /// Perform full database cleanup
    func performCleanup() async {
        logger.info("🧹 Starting database cleanup")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Run cleanup operations
        await cleanupOldMessages()
        await cleanupExcessMessagesPerChannel()
        await cleanupOrphanedUsers()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        logger.info("✅ Database cleanup completed in \(String(format: "%.2f", duration))ms")
    }
    
    /// Remove messages older than TTL
    private func cleanupOldMessages() async {
        let cutoffDate = Date().addingTimeInterval(-Double(messageTTLDays) * 24 * 60 * 60)
        logger.debug("🗑️ Removing messages older than \(self.messageTTLDays) days (before \(cutoffDate))")
        
        do {
            let realm = try await Realm()
            let allMessages = realm.objects(MessageRealm.self)
            
            // ULID contains timestamp in first 10 characters
            // Convert cutoff date to ULID timestamp
            let cutoffTimestamp = Int64(cutoffDate.timeIntervalSince1970 * 1000)
            
            var deletedCount = 0
            try realm.write {
                // Delete messages older than cutoff
                for message in allMessages {
                    // Parse ULID timestamp (first 10 chars represent milliseconds since epoch)
                    if let timestamp = extractTimestamp(from: message.id), timestamp < cutoffTimestamp {
                        realm.delete(message)
                        deletedCount += 1
                    }
                }
            }
            
            if deletedCount > 0 {
                logger.info("🗑️ Deleted \(deletedCount) old messages")
            }
        } catch {
            logger.error("❌ Failed to cleanup old messages: \(error.localizedDescription)")
        }
    }
    
    /// Keep only the most recent messages per channel
    private func cleanupExcessMessagesPerChannel() async {
        logger.debug("🗑️ Removing excess messages per channel (max: \(self.maxMessagesPerChannel))")
        
        do {
            let realm = try await Realm()
            let allMessages = realm.objects(MessageRealm.self)
            
            // Group messages by channel
            var messagesByChannel: [String: [MessageRealm]] = [:]
            for message in allMessages {
                if messagesByChannel[message.channel] == nil {
                    messagesByChannel[message.channel] = []
                }
                messagesByChannel[message.channel]?.append(message)
            }
            
            var totalDeleted = 0
            try realm.write {
                for (channelId, messages) in messagesByChannel {
                    if messages.count > maxMessagesPerChannel {
                        // Sort by ID descending (newest first)
                        let sorted = messages.sorted { $0.id > $1.id }
                        
                        // Keep only the newest messages
                        let toDelete = sorted.dropFirst(maxMessagesPerChannel)
                        
                        for message in toDelete {
                            realm.delete(message)
                            totalDeleted += 1
                        }
                        
                        logger.debug("🗑️ Channel \(channelId): Deleted \(toDelete.count) excess messages")
                    }
                }
            }
            
            if totalDeleted > 0 {
                logger.info("🗑️ Deleted \(totalDeleted) excess messages across all channels")
            }
        } catch {
            logger.error("❌ Failed to cleanup excess messages: \(error.localizedDescription)")
        }
    }
    
    /// Remove users that aren't referenced by any message
    private func cleanupOrphanedUsers() async {
        logger.debug("🗑️ Removing orphaned users")
        
        do {
            let realm = try await Realm()
            let allMessages = realm.objects(MessageRealm.self)
            let allUsers = realm.objects(UserRealm.self)
            
            // Collect all user IDs referenced by messages
            var referencedUserIds = Set<String>()
            for message in allMessages {
                referencedUserIds.insert(message.author)
                // Note: mentions would need to be parsed from message content or stored separately
            }
            
            var deletedCount = 0
            try realm.write {
                for user in allUsers {
                    // Don't delete if user is referenced
                    if !referencedUserIds.contains(user.id) {
                        // Keep users with relationships (friends, blocked, etc.)
                        if user.relationship == nil || user.relationship == "None" {
                            realm.delete(user)
                            deletedCount += 1
                        }
                    }
                }
            }
            
            if deletedCount > 0 {
                logger.info("🗑️ Deleted \(deletedCount) orphaned users")
            }
        } catch {
            logger.error("❌ Failed to cleanup orphaned users: \(error.localizedDescription)")
        }
    }
    
    /// Force cleanup (called on app terminate/background)
    func forceCleanup() async {
        logger.info("⚡ Force cleanup triggered")
        //await performCleanup()
    }
    
    // MARK: - Helper Methods
    
    /// Extract timestamp from ULID (first 10 characters represent milliseconds)
    private func extractTimestamp(from ulid: String) -> Int64? {
        guard ulid.count >= 10 else { return nil }
        let timestampPart = String(ulid.prefix(10))
        
        // ULID uses Crockford's Base32 encoding
        // For simplicity, we'll use a heuristic: newer messages have larger IDs
        // This works because ULID's timestamp part is lexicographically sortable
        return nil // For now, we'll rely on ID sorting rather than timestamp extraction
    }
    
    /// Get database statistics
    func getDatabaseStats() async -> (messages: Int, users: Int, channels: Int, servers: Int) {
        do {
            let realm = try await Realm()
            let messageCount = realm.objects(MessageRealm.self).count
            let userCount = realm.objects(UserRealm.self).count
            let channelCount = realm.objects(ChannelRealm.self).count
            let serverCount = realm.objects(ServerRealm.self).count
            
            return (messages: messageCount, users: userCount, channels: channelCount, servers: serverCount)
        } catch {
            logger.error("❌ Failed to get database stats: \(error.localizedDescription)")
            return (0, 0, 0, 0)
        }
    }
}

