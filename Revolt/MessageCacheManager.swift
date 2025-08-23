import Foundation
import SQLite3
import Types
import OSLog

/// Helper function to extract creation date from message ID (for cache sorting)
func cacheCreatedAt(id: String) -> Date {
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
            message_data BLOB NOT NULL
        )
    """
    
    private let createMessagesIndex = """
        CREATE INDEX IF NOT EXISTS idx_messages_channel_created 
        ON messages(channel_id, created_at)
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
        print("📦 CACHE_INIT: Initializing MessageCacheManager")
        openDatabase()
        createTables()
        print("📦 CACHE_INIT: MessageCacheManager initialization complete, db = \(db != nil ? "valid" : "nil")")
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
        
        // Check if database file exists before opening
        let fileExists = FileManager.default.fileExists(atPath: dbPath)
        
        if fileExists {
            // Get file size to verify it's not empty
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: dbPath)
                let fileSize = attributes[.size] as? NSNumber ?? 0
            } catch {
            }
        }
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            logger.error("Unable to open database at path: \(dbPath)")
            db = nil
        } else {
            logger.info("Successfully opened message cache database")
            
            // Configure database for iOS persistence
            var statement: OpaquePointer?
            
            // Use DELETE journal mode instead of WAL for better iOS compatibility
            if sqlite3_prepare_v2(db, "PRAGMA journal_mode=DELETE", -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
            
            // Ensure data is synced to disk
            if sqlite3_prepare_v2(db, "PRAGMA synchronous=FULL", -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
            
            // Set a reasonable timeout for database operations
            if sqlite3_prepare_v2(db, "PRAGMA busy_timeout=5000", -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    private func createTables() {
        guard let db = db else { 
            return 
        }
        
        
        // First check if tables already exist and have data
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='messages'", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let tableExists = sqlite3_column_int(statement, 0) > 0
                
                if tableExists {
                    // Check if table has data
                    sqlite3_finalize(statement)
                    if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM messages", -1, &statement, nil) == SQLITE_OK {
                        if sqlite3_step(statement) == SQLITE_ROW {
                            let messageCount = sqlite3_column_int(statement, 0)
                        }
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        
        let tables = [
            ("messages", createMessagesTable),
            ("users", createUsersTable), 
            ("channel_info", createChannelInfoTable),
            ("messages_index", createMessagesIndex)
        ]
        
        for (tableName, tableSQL) in tables {
            if sqlite3_exec(db, tableSQL, nil, nil, nil) != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db))
                logger.error("Error creating \(tableName) table: \(errmsg)")
            } else {
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
    
    /// Simple test method to verify class is working
    func testMethod() {
    }
    
    /// Reset corrupted database by deleting the file and recreating
    func resetDatabase() {
        
        // Close current connection
        closeDatabase()
        
        // Delete the corrupted database file
        let fileManager = FileManager.default
        if let dbPath = getDatabasePath() {
            do {
                if fileManager.fileExists(atPath: dbPath) {
                    try fileManager.removeItem(atPath: dbPath)
                }
            } catch {
            }
        }
        
        // Recreate fresh database
        openDatabase()
        createTables()
    }
    
    private func getDatabasePath() -> String? {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let revoltDir = documentsPath.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
        
        // Create directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: revoltDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        
        return revoltDir.appendingPathComponent("messages.sqlite").path
    }
    
    /// Alternative caching function to test if the issue is with the specific function name
    func storeMessages(_ messages: [Message], channelId: String) {
        
        // Simple test: just log the first message ID
        if let firstMessage = messages.first {
        }
        
        // Call the original function
        self.cacheMessages(messages, for: channelId)
    }
    
    /// Cache messages locally for instant loading
    func cacheMessages(_ messages: [Message], for channelId: String) {
        
        // Check if we have messages to cache
        guard !messages.isEmpty else {
            return
        }
        
        // Check if database is available before queuing
        guard db != nil else {
            return
        }
        
        dbQueue.async { [weak self] in
            
            guard let self = self else {
                return
            }
            
            self._cacheMessages(messages, for: channelId)
        }
        
    }
    
    private func _cacheMessages(_ messages: [Message], for channelId: String) {
        guard let db = db else { 
            return 
        }
        
        
        let insertSQL = """
            INSERT OR REPLACE INTO messages 
            (id, channel_id, author_id, content, created_at, edited_at, message_data) 
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        var successCount = 0
        var failureCount = 0
        
        
        let result = sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil)
        
        if result == SQLITE_OK {
            
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            
            for (index, message) in messages.enumerated() {
                
                // PROPER: Store the complete Message object as JSON
                let content = message.content ?? ""
                let createdAt = Int64(cacheCreatedAt(id: message.id).timeIntervalSince1970)
                
                do {
                    // Store the complete message object
                    let messageData = try JSONEncoder().encode(message)
                    
                    // DEBUG: Verify encoding for first message
                    if index == 0 {
                        if let jsonString = String(data: messageData, encoding: .utf8) {
                            let preview = String(jsonString.prefix(200))
                        }
                    }
                    
                    // DEBUG: Log what we're storing for first message
                    if index == 0 {
                    }
                    
                    // Bind parameters with explicit C string conversion
                    let messageIdCString = message.id.cString(using: .utf8)!
                    let channelIdCString = channelId.cString(using: .utf8)!
                    let authorIdCString = message.author.cString(using: .utf8)!
                    let contentCString = content.cString(using: .utf8)!
                    
                    // DEBUG: Verify channel ID before binding
                    if index == 0 {
                    }
                    
                    sqlite3_bind_text(statement, 1, messageIdCString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    sqlite3_bind_text(statement, 2, channelIdCString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    sqlite3_bind_text(statement, 3, authorIdCString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    sqlite3_bind_text(statement, 4, contentCString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    sqlite3_bind_int64(statement, 5, createdAt)
                    sqlite3_bind_null(statement, 6) // Skip editedAt for now
                    
                        sqlite3_bind_blob(statement, 7, messageData.withUnsafeBytes { $0.baseAddress }, Int32(messageData.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    
                    if sqlite3_step(statement) == SQLITE_DONE {
                        successCount += 1
                        if index < 3 { // Log first few for verification
                            
                            // DEBUG: Immediately verify what was actually stored
                            if index == 0 {
                                sqlite3_reset(statement)
                                var verifyStatement: OpaquePointer?
                                if sqlite3_prepare_v2(db, "SELECT channel_id FROM messages WHERE id = ?", -1, &verifyStatement, nil) == SQLITE_OK {
                                    sqlite3_bind_text(verifyStatement, 1, messageIdCString, -1, nil)
                                    if sqlite3_step(verifyStatement) == SQLITE_ROW {
                                        let storedChannelId = String(cString: sqlite3_column_text(verifyStatement, 0))
                                    }
                                }
                                sqlite3_finalize(verifyStatement)
                            }
                        }
                    } else {
                        let errmsg = String(cString: sqlite3_errmsg(db))
                        failureCount += 1
                    }
                    
                    sqlite3_reset(statement)
                } catch {
                    failureCount += 1
                }
            }
            
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
        }
        
        sqlite3_finalize(statement)
        
        // Update channel info
        updateChannelInfo(channelId: channelId, messages: messages)
        
        // Force synchronization to disk after caching
        sqlite3_exec(db, "PRAGMA synchronous=FULL", nil, nil, nil)
        
    }
    
    /// Load cached messages instantly from local storage
    func loadCachedMessages(for channelId: String, limit: Int = 20) async -> [Message] {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let messages = self?._loadCachedMessages(for: channelId, limit: limit) ?? []
                continuation.resume(returning: messages)
            }
        }
    }
    
    /// Load cached messages with offset for progressive loading
    func loadCachedMessages(for channelId: String, limit: Int, offset: Int) async -> [Message] {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let messages = self?._loadCachedMessages(for: channelId, limit: limit, offset: offset) ?? []
                continuation.resume(returning: messages)
            }
        }
    }
    
    private func _loadCachedMessages(for channelId: String, limit: Int, offset: Int = 0) -> [Message] {
        if let dbPath = getDatabasePath() {
        }
        guard let db = db else { 
            return [] 
        }
        
        // DEBUG: First check what channel IDs are actually in the database
        var debugStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT DISTINCT channel_id, COUNT(*) FROM messages GROUP BY channel_id", -1, &debugStatement, nil) == SQLITE_OK {
            while sqlite3_step(debugStatement) == SQLITE_ROW {
                let storedChannelId = String(cString: sqlite3_column_text(debugStatement, 0))
                let messageCount = sqlite3_column_int(debugStatement, 1)
            }
        }
        sqlite3_finalize(debugStatement)
        
        let selectSQL = """
            SELECT message_data FROM messages 
            WHERE channel_id = ? 
            ORDER BY created_at DESC 
            LIMIT ? OFFSET ?
        """
        
        var statement: OpaquePointer?
        var messages: [Message] = []
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            
            // DEBUG: Check parameter binding
            let channelIdCString = channelId.cString(using: .utf8)!
            
            sqlite3_bind_text(statement, 1, channelIdCString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(statement, 2, Int32(limit))
            sqlite3_bind_int(statement, 3, Int32(offset))
            
            // DEBUG: Test direct query without parameters
            var testStatement: OpaquePointer?
            let directSQL = "SELECT COUNT(*) FROM messages WHERE channel_id = '\(channelId)'"
            if sqlite3_prepare_v2(db, directSQL, -1, &testStatement, nil) == SQLITE_OK {
                if sqlite3_step(testStatement) == SQLITE_ROW {
                    let directCount = sqlite3_column_int(testStatement, 0)
                }
            }
            sqlite3_finalize(testStatement)
            
            var stepCount = 0
            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                stepCount += 1
                
                if let blob = sqlite3_column_blob(statement, 0) {
                    let size = sqlite3_column_bytes(statement, 0)
                    let data = Data(bytes: blob, count: Int(size))
                    
                    // DEBUG: Check what's in the blob data
                    if stepCount <= 3 {
                        if let dataString = String(data: data, encoding: .utf8) {
                            let preview = String(dataString.prefix(200))
                        } else {
                        }
                    }
                    
                    do {
                        let message = try JSONDecoder().decode(Message.self, from: data)
                        messages.append(message)
                        if stepCount <= 3 {
                        }
                    } catch {
                        if stepCount <= 3 {
                        }
                    }
                } else {
                }
                
                stepResult = sqlite3_step(statement)
            }
            
            if stepResult != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
            } else {
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
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
        
        let lastMessage = messages.max { cacheCreatedAt(id: $0.id) < cacheCreatedAt(id: $1.id) }
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
                return content.content
            case .user_added(let userData):
                return "User \(userData.by ?? "") added \(userData.id)"
            case .user_removed(let userData):
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
            case .message_pinned:
                return "Message pinned"
            case .message_unpinned:
                return "Message unpinned"
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
                let needsRefresh = self?._needsCacheRefresh(for: channelId) ?? false
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