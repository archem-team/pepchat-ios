import Foundation
import SQLite3
import Types
import OSLog

/// Helper function to extract creation date from message ID
func createdAt(id: String) -> Date {
    // Revolt message IDs are ULIDs (Universally Unique Lexicographically Sortable Identifiers)
    // The first 48 bits represent the timestamp in milliseconds since Unix epoch
    
    guard id.count == 26 else {
        return Date() // Return current date for invalid IDs
    }
    
    // ULID uses Crockford's Base32 encoding
    let base32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    let timestampPortion = String(id.prefix(10)) // First 10 characters represent timestamp
    
    var timestamp: UInt64 = 0
    for char in timestampPortion {
        timestamp = timestamp * 32
        if let index = base32.firstIndex(of: char.uppercased().first!) {
            timestamp += UInt64(base32.distance(from: base32.startIndex, to: index))
        }
    }
    
    // Convert from milliseconds to seconds
    let timeInterval = TimeInterval(timestamp) / 1000.0
    return Date(timeIntervalSince1970: timeInterval)
}

/// A high-performance message cache manager using SQLite for local storage
/// This provides instant message loading similar to Telegram's approach
class MessageCacheManager {
    static let shared = MessageCacheManager()
    
    private var db: OpaquePointer?
    private let logger = Logger(subsystem: "Revolt", category: "MessageCache")
    private let dbQueue = DispatchQueue(label: "com.revolt.messagecache", qos: .userInitiated)
    
    // MARK: - Database Schema
    private let createMessagesTable = """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            channel_id TEXT NOT NULL,
            author_id TEXT NOT NULL,
            content TEXT,
            created_at INTEGER NOT NULL,
            edited_at INTEGER,
            message_data BLOB NOT NULL,
            INDEX(channel_id, created_at)
        )
    """
    
    private let createUsersTable = """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL,
            display_name TEXT,
            avatar_url TEXT,
            user_data BLOB NOT NULL
        )
    """
    
    private let createChannelInfoTable = """
        CREATE TABLE IF NOT EXISTS channel_info (
            channel_id TEXT PRIMARY KEY,
            last_message_id TEXT,
            message_count INTEGER DEFAULT 0,
            last_updated INTEGER NOT NULL
        )
    """
    
    // MARK: - Initialization
    private init() {
        openDatabase()
        createTables()
    }
    
    deinit {
        closeDatabase()
    }
    
    private func openDatabase() {
        guard let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("Failed to get documents directory")
            return
        }
        
        let revoltDir = documentsPath.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
        
        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: revoltDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Revolt directory: \(error.localizedDescription)")
            return
        }
        
        let dbPath = revoltDir.appendingPathComponent("messages.sqlite").path
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            logger.error("Unable to open database at path: \(dbPath)")
            db = nil
        } else {
            logger.info("Successfully opened message cache database")
            
            // Enable WAL mode for better performance
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA journal_mode=WAL", -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        
        let tables = [createMessagesTable, createUsersTable, createChannelInfoTable]
        
        for tableSQL in tables {
            if sqlite3_exec(db, tableSQL, nil, nil, nil) != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db))
                logger.error("Error creating table: \(errmsg)")
            }
        }
    }
    
    private func closeDatabase() {
        if sqlite3_close(db) != SQLITE_OK {
            logger.error("Error closing database")
        }
        db = nil
    }
    
    // MARK: - Message Operations
    
    /// Cache messages locally for instant loading
    func cacheMessages(_ messages: [Message], for channelId: String) {
        dbQueue.async { [weak self] in
            self?._cacheMessages(messages, for: channelId)
        }
    }
    
    private func _cacheMessages(_ messages: [Message], for channelId: String) {
        guard let db = db else { return }
        
        let insertSQL = """
            INSERT OR REPLACE INTO messages 
            (id, channel_id, author_id, content, created_at, edited_at, message_data) 
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            
            for message in messages {
                // Extract basic info
                let content = extractMessageContent(from: message)
                let createdAt = Int64(createdAt(id: message.id).timeIntervalSince1970)
                let editedAt = message.edited?.map { Int64($0.timeIntervalSince1970) }
                
                // Serialize entire message
                guard let messageData = try? JSONEncoder().encode(message) else {
                    continue
                }
                
                // Bind parameters
                sqlite3_bind_text(statement, 1, message.id, -1, nil)
                sqlite3_bind_text(statement, 2, channelId, -1, nil)
                sqlite3_bind_text(statement, 3, message.author, -1, nil)
                sqlite3_bind_text(statement, 4, content, -1, nil)
                sqlite3_bind_int64(statement, 5, createdAt)
                
                if let editedAt = editedAt {
                    sqlite3_bind_int64(statement, 6, editedAt)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                
                sqlite3_bind_blob(statement, 7, messageData.withUnsafeBytes { $0.baseAddress }, Int32(messageData.count), nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    let errmsg = String(cString: sqlite3_errmsg(db))
                    logger.error("Error inserting message: \(errmsg)")
                }
                
                sqlite3_reset(statement)
            }
            
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
        
        sqlite3_finalize(statement)
        
        // Update channel info
        updateChannelInfo(channelId: channelId, messages: messages)
    }
    
    /// Load cached messages instantly from local storage
    func loadCachedMessages(for channelId: String, limit: Int = 50) async -> [Message] {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let messages = self?._loadCachedMessages(for: channelId, limit: limit) ?? []
                continuation.resume(returning: messages)
            }
        }
    }
    
    private func _loadCachedMessages(for channelId: String, limit: Int) -> [Message] {
        guard let db = db else { return [] }
        
        let selectSQL = """
            SELECT message_data FROM messages 
            WHERE channel_id = ? 
            ORDER BY created_at DESC 
            LIMIT ?
        """
        
        var statement: OpaquePointer?
        var messages: [Message] = []
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, channelId, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let blob = sqlite3_column_blob(statement, 0) {
                    let size = sqlite3_column_bytes(statement, 0)
                    let data = Data(bytes: blob, count: Int(size))
                    
                    if let message = try? JSONDecoder().decode(Message.self, from: data) {
                        messages.append(message)
                    }
                }
            }
        }
        
        sqlite3_finalize(statement)
        
        // Return in chronological order (oldest first)
        return messages.reversed()
    }
    
    /// Check if channel has cached messages
    func hasCachedMessages(for channelId: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let hasMessages = self?._hasCachedMessages(for: channelId) ?? false
                continuation.resume(returning: hasMessages)
            }
        }
    }
    
    private func _hasCachedMessages(for channelId: String) -> Bool {
        guard let db = db else { return false }
        
        let selectSQL = "SELECT COUNT(*) FROM messages WHERE channel_id = ?"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, channelId, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        
        sqlite3_finalize(statement)
        return count > 0
    }
    
    /// Cache user data for message authors
    func cacheUsers(_ users: [User]) {
        dbQueue.async { [weak self] in
            self?._cacheUsers(users)
        }
    }
    
    private func _cacheUsers(_ users: [User]) {
        guard let db = db else { return }
        
        let insertSQL = """
            INSERT OR REPLACE INTO users 
            (id, username, display_name, avatar_url, user_data) 
            VALUES (?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            
            for user in users {
                guard let userData = try? JSONEncoder().encode(user) else { continue }
                
                sqlite3_bind_text(statement, 1, user.id, -1, nil)
                sqlite3_bind_text(statement, 2, user.username, -1, nil)
                sqlite3_bind_text(statement, 3, user.display_name, -1, nil)
                
                if let avatar = user.avatar {
                    sqlite3_bind_text(statement, 4, avatar.id, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                
                sqlite3_bind_blob(statement, 5, userData.withUnsafeBytes { $0.baseAddress }, Int32(userData.count), nil)
                
                sqlite3_step(statement)
                sqlite3_reset(statement)
            }
            
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
        
        sqlite3_finalize(statement)
    }
    
    /// Load cached user data
    func loadCachedUsers(for userIds: [String]) async -> [String: User] {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let users = self?._loadCachedUsers(for: userIds) ?? [:]
                continuation.resume(returning: users)
            }
        }
    }
    
    private func _loadCachedUsers(for userIds: [String]) -> [String: User] {
        guard let db = db else { return [:] }
        
        var users: [String: User] = [:]
        
        for userId in userIds {
            let selectSQL = "SELECT user_data FROM users WHERE id = ?"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, userId, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let blob = sqlite3_column_blob(statement, 0) {
                        let size = sqlite3_column_bytes(statement, 0)
                        let data = Data(bytes: blob, count: Int(size))
                        
                        if let user = try? JSONDecoder().decode(User.self, from: data) {
                            users[userId] = user
                        }
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        return users
    }
    
    // MARK: - Helper Methods
    
    private func updateChannelInfo(channelId: String, messages: [Message]) {
        guard let db = db, !messages.isEmpty else { return }
        
        let lastMessage = messages.max { createdAt(id: $0.id) < createdAt(id: $1.id) }
        let now = Int64(Date().timeIntervalSince1970)
        
        let updateSQL = """
            INSERT OR REPLACE INTO channel_info 
            (channel_id, last_message_id, message_count, last_updated) 
            VALUES (?, ?, (SELECT COUNT(*) FROM messages WHERE channel_id = ?), ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, channelId, -1, nil)
            sqlite3_bind_text(statement, 2, lastMessage?.id, -1, nil)
            sqlite3_bind_text(statement, 3, channelId, -1, nil)
            sqlite3_bind_int64(statement, 4, now)
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    private func extractMessageContent(from message: Message) -> String {
        if let system = message.system {
            switch system {
            case .text(let content):
                return content
            case .user_added(let userData):
                return "User \(userData.by ?? "") added \(userData.id)"
            case .user_remove(let userData):
                return "User \(userData.by ?? "") removed \(userData.id)"
            case .user_joined:
                return "User joined"
            case .user_left:
                return "User left"
            case .user_kicked:
                return "User was kicked"
            case .user_banned:
                return "User was banned"
            case .channel_renamed(let renameData):
                return "Channel renamed to \(renameData.name)"
            case .channel_description_changed:
                return "Channel description changed"
            case .channel_icon_changed:
                return "Channel icon changed"
            case .channel_ownership_changed:
                return "Channel ownership changed"
            }
        } else if let content = message.content {
            return content
        }
        
        return ""
    }
    
    // MARK: - Smart Preloading
    
    /// Preload messages for frequently accessed channels
    func preloadFrequentChannels(channelIds: [String]) {
        Task.detached(priority: .background) { [weak self] in
            for channelId in channelIds {
                // Check if channel already has recent cache
                let hasCached = await self?.hasCachedMessages(for: channelId) ?? false
                if !hasCached {
                    print("📦 PRELOAD: Channel \(channelId) has no cache, skipping preload")
                    continue
                }
                
                // Only preload if cache is older than 1 hour
                let needsRefresh = await self?._needsCacheRefresh(for: channelId) ?? false
                if needsRefresh {
                    print("📦 PRELOAD: Refreshing cache for channel \(channelId)")
                    // This would trigger a background API call to refresh messages
                    // Implementation depends on having access to HTTP client
                }
            }
        }
    }
    
    private func _needsCacheRefresh(for channelId: String) -> Bool {
        guard let db = db else { return true }
        
        let selectSQL = "SELECT last_updated FROM channel_info WHERE channel_id = ?"
        var statement: OpaquePointer?
        var needsRefresh = true
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, channelId, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let lastUpdated = sqlite3_column_int64(statement, 0)
                let lastUpdateDate = Date(timeIntervalSince1970: TimeInterval(lastUpdated))
                let hourAgo = Date().addingTimeInterval(-3600) // 1 hour ago
                
                needsRefresh = lastUpdateDate < hourAgo
            }
        }
        
        sqlite3_finalize(statement)
        return needsRefresh
    }
    
    // MARK: - Cleanup Operations
    
    /// Clean old messages to manage storage size
    func cleanupOldMessages(olderThan days: Int = 30) {
        dbQueue.async { [weak self] in
            self?._cleanupOldMessages(olderThan: days)
        }
    }
    
    private func _cleanupOldMessages(olderThan days: Int) {
        guard let db = db else { return }
        
        let cutoffDate = Int64(Date().addingTimeInterval(-Double(days * 24 * 60 * 60)).timeIntervalSince1970)
        let deleteSQL = "DELETE FROM messages WHERE created_at < ?"
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, cutoffDate)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                let deletedCount = sqlite3_changes(db)
                logger.info("Cleaned up \(deletedCount) old messages")
            }
        }
        
        sqlite3_finalize(statement)
        
        // Clean orphaned users
        let cleanUsersSQL = """
            DELETE FROM users WHERE id NOT IN (
                SELECT DISTINCT author_id FROM messages
            )
        """
        
        sqlite3_exec(db, cleanUsersSQL, nil, nil, nil)
        
        // Vacuum database to reclaim space
        sqlite3_exec(db, "VACUUM", nil, nil, nil)
    }
    
    /// Get cache statistics
    func getCacheStats() async -> (messageCount: Int, userCount: Int, sizeInMB: Double) {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let stats = self?._getCacheStats() ?? (0, 0, 0.0)
                continuation.resume(returning: stats)
            }
        }
    }
    
    private func _getCacheStats() -> (messageCount: Int, userCount: Int, sizeInMB: Double) {
        guard let db = db else { return (0, 0, 0.0) }
        
        var messageCount = 0
        var userCount = 0
        var sizeInMB = 0.0
        
        // Get message count
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM messages", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                messageCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Get user count
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM users", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                userCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Get database size
        if sqlite3_prepare_v2(db, "PRAGMA page_count", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let pageCount = sqlite3_column_int(statement, 0)
                sqlite3_finalize(statement)
                
                if sqlite3_prepare_v2(db, "PRAGMA page_size", -1, &statement, nil) == SQLITE_OK {
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let pageSize = sqlite3_column_int(statement, 0)
                        sizeInMB = Double(pageCount * pageSize) / (1024 * 1024)
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        
        return (messageCount, userCount, sizeInMB)
    }
} 