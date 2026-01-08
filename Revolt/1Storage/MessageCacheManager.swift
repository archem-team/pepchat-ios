import Foundation
import SQLite3
import Types
import OSLog

/// Helper function to extract creation date from message ID
fileprivate func messageCacheCreatedAt(id: String) -> Date {
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
    
    // MARK: - Schema Versioning
    private let currentSchemaVersion = 3
    private let schemaVersionKey = "messageCacheSchemaVersion"
    
    // MARK: - Constants
    private let maxMessagesPerChannel = 500
    private let maxCacheSizeMB = 100
    private let maxTombstonesPerChannel = 1000
    private let tombstoneRetentionDays = 7
    
    // MARK: - Database Schema
    private let createMessagesTable = """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT NOT NULL,
            channel_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            base_url TEXT NOT NULL,
            author_id TEXT NOT NULL,
            content TEXT,
            created_at INTEGER NOT NULL,
            edited_at INTEGER,
            message_data BLOB NOT NULL,
            PRIMARY KEY (id, channel_id, user_id, base_url)
        )
    """

    private let createMessagesIndex = """
        CREATE INDEX IF NOT EXISTS messages_channel_idx
        ON messages (channel_id, user_id, base_url, created_at)
    """
    
    private let createUsersTable = """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            base_url TEXT NOT NULL,
            username TEXT NOT NULL,
            display_name TEXT,
            avatar_url TEXT,
            user_data BLOB NOT NULL,
            PRIMARY KEY (id, user_id, base_url)
        )
    """
    
    private let createChannelInfoTable = """
        CREATE TABLE IF NOT EXISTS channel_info (
            channel_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            base_url TEXT NOT NULL,
            last_message_id TEXT,
            message_count INTEGER DEFAULT 0,
            last_updated INTEGER NOT NULL,
            PRIMARY KEY (channel_id, user_id, base_url)
        )
    """
    
    private let createTombstonesTable = """
        CREATE TABLE IF NOT EXISTS tombstones (
            message_id TEXT NOT NULL,
            channel_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            base_url TEXT NOT NULL,
            deleted_at INTEGER NOT NULL,
            PRIMARY KEY (message_id, channel_id, user_id, base_url)
        )
    """

    private let createTombstonesIndex = """
        CREATE INDEX IF NOT EXISTS tombstones_channel_idx
        ON tombstones (channel_id, user_id, base_url, deleted_at)
    """
    
    // MARK: - Initialization
    private init() {
        checkAndMigrateSchema()
        openDatabase()
        createTables()
    }
    
    // MARK: - Schema Migration
    private func checkAndMigrateSchema() {
        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if storedVersion < self.currentSchemaVersion || storedVersion > self.currentSchemaVersion {
            // Clear all caches on version mismatch
            clearAllCachesSync()
            UserDefaults.standard.set(self.currentSchemaVersion, forKey: schemaVersionKey)
            logger.info("Cache schema migrated from version \(storedVersion) to \(self.currentSchemaVersion)")
        } else if storedVersion == 0 {
            // First launch - if a legacy DB exists, clear it
            if hasExistingCacheDatabase() {
                clearAllCachesSync()
                logger.info("Cleared legacy cache database on first launch")
            }
            UserDefaults.standard.set(self.currentSchemaVersion, forKey: schemaVersionKey)
        }
    }

    private func hasExistingCacheDatabase() -> Bool {
        guard let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        let revoltDir = documentsPath.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
        let dbPath = revoltDir.appendingPathComponent("messages.sqlite")
        return FileManager.default.fileExists(atPath: dbPath.path)
    }
    
    private func clearAllCachesSync() {
        // This will be called during migration, so we need synchronous cleanup
        guard let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        let revoltDir = documentsPath.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
        let dbPath = revoltDir.appendingPathComponent("messages.sqlite")
        
        // Delete database file if it exists
        if FileManager.default.fileExists(atPath: dbPath.path) {
            try? FileManager.default.removeItem(at: dbPath)
            logger.info("Cleared cache database during schema migration")
        }
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
        
        let tables = [
            createMessagesTable,
            createUsersTable,
            createChannelInfoTable,
            createTombstonesTable,
            createMessagesIndex,
            createTombstonesIndex
        ]
        
        for tableSQL in tables {
            if sqlite3_exec(db, tableSQL, nil, nil, nil) != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db))
                logger.error("Error creating table: \(errmsg)")
            }
        }
    }
    
    // MARK: - Cache Key Helpers
    private func cacheKey(for channelId: String, userId: String, baseURL: String) -> String {
        return "\(userId)_\(baseURL)_\(channelId)"
    }

    private func cacheTrace(_ message: String) {
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        print("CACHE_TRACE t=\(timestamp) \(message)")
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value = value else {
            sqlite3_bind_null(statement, index)
            return
        }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }
    
    private func closeDatabase() {
        if sqlite3_close(db) != SQLITE_OK {
            logger.error("Error closing database")
        }
        db = nil
    }
    
    // MARK: - Message Operations
    
    /// Cache messages locally for instant loading
    func cacheMessages(_ messages: [Message], for channelId: String, userId: String, baseURL: String) {
        dbQueue.async { [weak self] in
            self?._cacheMessages(messages, for: channelId, userId: userId, baseURL: baseURL)
        }
    }

    /// Cache messages and users in a single queue block for deterministic ordering
    func cacheMessagesAndUsers(_ messages: [Message], users: [User], channelId: String, userId: String, baseURL: String, lastMessageId: String?) {
        cacheTrace("cacheMessagesAndUsers ENTERED channel=\(channelId) messages=\(messages.count) users=\(users.count) userId=\(userId) baseURL=\(baseURL)")
        dbQueue.async { [weak self] in
            guard let self = self else {
                self?.cacheTrace("cacheMessagesAndUsers FAILED - self is nil")
                return
            }
            self.cacheTrace("cacheMessagesAndUsers start channel=\(channelId) messages=\(messages.count) users=\(users.count)")
            self._cacheMessages(messages, for: channelId, userId: userId, baseURL: baseURL)
            self._cacheUsers(users, userId: userId, baseURL: baseURL)
            if let lastMessageId = lastMessageId {
                self._updateLastMessageId(channelId: channelId, userId: userId, baseURL: baseURL, lastMessageId: lastMessageId)
            }
            self.cacheTrace("cacheMessagesAndUsers end channel=\(channelId)")
        }
        cacheTrace("cacheMessagesAndUsers QUEUED to dbQueue for channel=\(channelId)")
    }
    
    private func _cacheMessages(_ messages: [Message], for channelId: String, userId: String, baseURL: String) {
        guard let db = db, !messages.isEmpty else {
            let dbState = db == nil ? "nil" : "open"
            cacheTrace("cacheMessages skipped channel=\(channelId) messages=\(messages.count) db=\(dbState)")
            return
        }
        
        // Enforce per-channel limit
        let limitedMessages = enforcePerChannelLimit(messages: messages, channelId: channelId, userId: userId, baseURL: baseURL)
        var insertedMessages: [Message] = []
        var failedInserts = 0
        
        let insertSQL = """
            INSERT OR REPLACE INTO messages 
            (id, channel_id, user_id, base_url, author_id, content, created_at, edited_at, message_data) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            
            let beginResult = sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            if beginResult != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db))
                logger.error("Error beginning transaction: \(errmsg)")
                sqlite3_finalize(statement)
                return
            }
            
            for message in limitedMessages {
                // Skip messages with large attachments (>5MB)
                if let attachments = message.attachments {
                    let totalSize = attachments.compactMap { $0.size }.reduce(0, +)
                    if totalSize > 5 * 1024 * 1024 { // 5MB
                        continue
                    }
                }
                
                // Extract basic info
                let content = extractMessageContent(from: message)
                let createdAt = Int64(messageCacheCreatedAt(id: message.id).timeIntervalSince1970)
                let editedAt: Int64? = message.edited.flatMap { editedString in
                    let formatter = ISO8601DateFormatter()
                    if let date = formatter.date(from: editedString) {
                        return Int64(date.timeIntervalSince1970)
                    }
                    return nil
                }
                
                // Serialize entire message
                guard let messageData = try? JSONEncoder().encode(message) else {
                    cacheTrace("Failed to encode message id=\(message.id)")
                    failedInserts += 1
                    continue
                }
                
                // Reset and clear bindings before reuse
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                
                // SQLITE_TRANSIENT tells SQLite to copy the string (so we can release our copy)
                let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

                sqlite3_bind_text(statement, 1, (message.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, (channelId as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, (userId as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, (baseURL as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, (message.author as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, (content as NSString).utf8String, -1, SQLITE_TRANSIENT)
                
                sqlite3_bind_int64(statement, 7, createdAt)
                
                if let editedAt = editedAt {
                    sqlite3_bind_int64(statement, 8, editedAt)
                } else {
                    sqlite3_bind_null(statement, 8)
                }
                
                // For blob, allocate and copy data - SQLite will free it via destructor
                let dataPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: messageData.count)
                messageData.copyBytes(to: dataPtr, count: messageData.count)
                sqlite3_bind_blob(statement, 9, dataPtr, Int32(messageData.count)) { ptr in
                    ptr?.deallocate()
                }
                
                let stepResult = sqlite3_step(statement)
                if stepResult != SQLITE_DONE {
                    let errmsg = String(cString: sqlite3_errmsg(db))
                    cacheTrace("Error inserting message id=\(message.id): \(errmsg) (code: \(stepResult))")
                    logger.error("Error inserting message \(message.id): \(errmsg)")
                    failedInserts += 1
                    // Free blob data if insert failed (SQLite won't call destructor on error)
                    dataPtr.deallocate()
                } else {
                    insertedMessages.append(message)
                }
            }
            
            let commitResult = sqlite3_exec(db, "COMMIT", nil, nil, nil)
            if commitResult != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db))
                logger.error("Error committing transaction: \(errmsg)")
                // Rollback on commit failure
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            logger.error("Error preparing insert statement: \(errmsg)")
        }
        
        sqlite3_finalize(statement)
        
        cacheTrace("cacheMessages completed - inserted=\(insertedMessages.count) failed=\(failedInserts) channel=\(channelId)")
        
        // Update channel info
        updateChannelInfo(channelId: channelId, userId: userId, baseURL: baseURL, messages: insertedMessages)
        cacheTrace("cacheMessages stored channel=\(channelId) inserted=\(insertedMessages.count) userId=\(userId) baseURL=\(baseURL)")
        
        // Verify what was actually stored
        for message in insertedMessages.prefix(3) {
            _logRowForMessage(id: message.id)
        }
        let verifyCount = _getMessageCount(channelId: channelId, userId: userId, baseURL: baseURL)
        let totalCount = _getTotalMessageCount()
        let channelOnlyCount = _getMessageCountByChannel(channelId: channelId)
        let channelUserCount = _getMessageCountByChannelUser(channelId: channelId, userId: userId)
        let channelBaseURLCount = _getMessageCountByChannelBaseURL(channelId: channelId, baseURL: baseURL)
        cacheTrace("cacheMessages verification - channel=\(channelId) userIdLen=\(userId.count) baseURLLen=\(baseURL.count) now has \(verifyCount) messages (total=\(totalCount), channelOnly=\(channelOnlyCount), channelUser=\(channelUserCount), channelBaseURL=\(channelBaseURLCount))")
        _logDistinctCacheKeys(for: channelId)
    }
    
    private func enforcePerChannelLimit(messages: [Message], channelId: String, userId: String, baseURL: String) -> [Message] {
        guard messages.count > maxMessagesPerChannel else { return messages }
        
        // Get current count
        let currentCount = _getMessageCount(channelId: channelId, userId: userId, baseURL: baseURL)
        
        // If adding these messages would exceed limit, evict oldest
        let totalAfterAdd = currentCount + messages.count
        if totalAfterAdd > maxMessagesPerChannel {
            let toEvict = totalAfterAdd - maxMessagesPerChannel
            _evictOldestMessages(channelId: channelId, userId: userId, baseURL: baseURL, count: toEvict)
        }
        
        return messages
    }
    
    private func _getMessageCount(channelId: String, userId: String, baseURL: String) -> Int {
        guard let db = db else { return 0 }
        
        let selectSQL = "SELECT COUNT(*) FROM messages WHERE channel_id = ? AND user_id = ? AND base_url = ?"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            } else {
                let errmsg = String(cString: sqlite3_errmsg(db))
                cacheTrace("getMessageCount step failed channel=\(channelId) error=\(errmsg)")
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            cacheTrace("getMessageCount prepare failed channel=\(channelId) error=\(errmsg)")
        }
        
        sqlite3_finalize(statement)
        return count
    }

    private func _getMessageCountByChannel(channelId: String) -> Int {
        guard let db = db else { return 0 }
        
        let selectSQL = "SELECT COUNT(*) FROM messages WHERE channel_id = ?"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            } else {
                let errmsg = String(cString: sqlite3_errmsg(db))
                cacheTrace("getMessageCountByChannel step failed channel=\(channelId) error=\(errmsg)")
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            cacheTrace("getMessageCountByChannel prepare failed channel=\(channelId) error=\(errmsg)")
        }
        
        sqlite3_finalize(statement)
        return count
    }

    private func _getMessageCountByChannelUser(channelId: String, userId: String) -> Int {
        guard let db = db else { return 0 }
        
        let selectSQL = "SELECT COUNT(*) FROM messages WHERE channel_id = ? AND user_id = ?"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            } else {
                let errmsg = String(cString: sqlite3_errmsg(db))
                cacheTrace("getMessageCountByChannelUser step failed channel=\(channelId) error=\(errmsg)")
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            cacheTrace("getMessageCountByChannelUser prepare failed channel=\(channelId) error=\(errmsg)")
        }
        
        sqlite3_finalize(statement)
        return count
    }

    private func _getMessageCountByChannelBaseURL(channelId: String, baseURL: String) -> Int {
        guard let db = db else { return 0 }
        
        let selectSQL = "SELECT COUNT(*) FROM messages WHERE channel_id = ? AND base_url = ?"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, baseURL)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            } else {
                let errmsg = String(cString: sqlite3_errmsg(db))
                cacheTrace("getMessageCountByChannelBaseURL step failed channel=\(channelId) error=\(errmsg)")
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            cacheTrace("getMessageCountByChannelBaseURL prepare failed channel=\(channelId) error=\(errmsg)")
        }
        
        sqlite3_finalize(statement)
        return count
    }

    private func _getTotalMessageCount() -> Int {
        guard let db = db else { return 0 }
        
        let selectSQL = "SELECT COUNT(*) FROM messages"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            } else {
                let errmsg = String(cString: sqlite3_errmsg(db))
                cacheTrace("getTotalMessageCount step failed error=\(errmsg)")
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            cacheTrace("getTotalMessageCount prepare failed error=\(errmsg)")
        }
        
        sqlite3_finalize(statement)
        return count
    }

    private func _logDistinctCacheKeys(for channelId: String) {
        guard let db = db else { return }
        
        let selectSQL = """
            SELECT DISTINCT user_id, base_url
            FROM messages
            WHERE channel_id = ?
            LIMIT 5
        """
        var statement: OpaquePointer?
        var didLog = false
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let userId = sqlite3_column_text(statement, 0).flatMap { String(cString: $0) } ?? "nil"
                let baseURL = sqlite3_column_text(statement, 1).flatMap { String(cString: $0) } ?? "nil"
                cacheTrace("cacheKeys channel=\(channelId) userId=\(userId) userIdLen=\(userId.count) baseURL=\(baseURL) baseURLLen=\(baseURL.count)")
                didLog = true
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            cacheTrace("cacheKeys prepare failed channel=\(channelId) error=\(errmsg)")
        }
        
        sqlite3_finalize(statement)
        
        if !didLog {
            cacheTrace("cacheKeys channel=\(channelId) none")
        }
    }

    private func _logRowForMessage(id: String) {
        guard let db = db else { return }
        
        let selectSQL = "SELECT channel_id, user_id, base_url FROM messages WHERE id = ? LIMIT 1"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, id)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let channelId = sqlite3_column_text(statement, 0).flatMap { String(cString: $0) } ?? "nil"
                let userId = sqlite3_column_text(statement, 1).flatMap { String(cString: $0) } ?? "nil"
                let baseURL = sqlite3_column_text(statement, 2).flatMap { String(cString: $0) } ?? "nil"
                cacheTrace("cacheRow id=\(id) channel=\(channelId) userId=\(userId) baseURL=\(baseURL)")
            } else {
                let errmsg = String(cString: sqlite3_errmsg(db))
                cacheTrace("cacheRow step failed id=\(id) error=\(errmsg)")
            }
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            cacheTrace("cacheRow prepare failed id=\(id) error=\(errmsg)")
        }
        
        sqlite3_finalize(statement)
    }
    
    private func _evictOldestMessages(channelId: String, userId: String, baseURL: String, count: Int) {
        guard let db = db, count > 0 else { return }
        
        let deleteSQL = """
            DELETE FROM messages 
            WHERE channel_id = ? AND user_id = ? AND base_url = ?
            AND id IN (
                SELECT id FROM messages 
                WHERE channel_id = ? AND user_id = ? AND base_url = ?
                ORDER BY created_at ASC 
                LIMIT ?
            )
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            bindText(statement, 4, channelId)
            bindText(statement, 5, userId)
            bindText(statement, 6, baseURL)
            sqlite3_bind_int(statement, 7, Int32(count))
            
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    /// Load cached messages instantly from local storage
    func loadCachedMessages(for channelId: String, userId: String, baseURL: String, limit: Int = 500, offset: Int = 0) async -> [Message] {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let messages = self?._loadCachedMessages(for: channelId, userId: userId, baseURL: baseURL, limit: limit, offset: offset) ?? []
                self?.cacheTrace("loadCachedMessages channel=\(channelId) count=\(messages.count)")
                continuation.resume(returning: messages)
            }
        }
    }
    
    private func _loadCachedMessages(for channelId: String, userId: String, baseURL: String, limit: Int, offset: Int) -> [Message] {
        guard let db = db else {
            cacheTrace("loadCachedMessages skipped channel=\(channelId) db=nil")
            return []
        }
        
        // Get deleted message IDs (tombstones) for this channel
        let deletedIds = _getDeletedMessageIds(channelId: channelId, userId: userId, baseURL: baseURL)
        
        let selectSQL = """
            SELECT message_data FROM messages 
            WHERE channel_id = ? AND user_id = ? AND base_url = ?
            AND id NOT IN (
                SELECT message_id FROM tombstones 
                WHERE channel_id = ? AND user_id = ? AND base_url = ?
            )
            ORDER BY created_at DESC 
            LIMIT ? OFFSET ?
        """
        
        var statement: OpaquePointer?
        var messages: [Message] = []
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            bindText(statement, 4, channelId)
            bindText(statement, 5, userId)
            bindText(statement, 6, baseURL)
            sqlite3_bind_int(statement, 7, Int32(limit))
            sqlite3_bind_int(statement, 8, Int32(offset))
            
        cacheTrace("loadCachedMessages query - channel=\(channelId) userId=\(userId) baseURL=\(baseURL) limit=\(limit)")
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let blob = sqlite3_column_blob(statement, 0) {
                    let size = sqlite3_column_bytes(statement, 0)
                    let data = Data(bytes: blob, count: Int(size))
                    
                    if let message = try? JSONDecoder().decode(Message.self, from: data) {
                        // Double-check against tombstone set (in-memory check for safety)
                        if !deletedIds.contains(message.id) {
                            messages.append(message)
                        }
                    }
                }
            }
        }
        
        sqlite3_finalize(statement)
        
        // Return in chronological order (oldest first)
        return messages.reversed()
    }

    /// Count cached messages for a channel/user/baseURL
    func cachedMessageCount(for channelId: String, userId: String, baseURL: String) async -> Int {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let count = self?._getMessageCount(channelId: channelId, userId: userId, baseURL: baseURL) ?? 0
                self?.cacheTrace("cachedMessageCount channel=\(channelId) count=\(count)")
                continuation.resume(returning: count)
            }
        }
    }
    
    /// Check if channel has cached messages
    func hasCachedMessages(for channelId: String, userId: String, baseURL: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let hasMessages = self?._hasCachedMessages(for: channelId, userId: userId, baseURL: baseURL) ?? false
                self?.cacheTrace("hasCachedMessages channel=\(channelId) has=\(hasMessages)")
                continuation.resume(returning: hasMessages)
            }
        }
    }
    
    private func _hasCachedMessages(for channelId: String, userId: String, baseURL: String) -> Bool {
        guard let db = db else {
            cacheTrace("hasCachedMessages skipped channel=\(channelId) db=nil")
            return false
        }
        
        let selectSQL = """
            SELECT COUNT(*) FROM messages 
            WHERE channel_id = ? AND user_id = ? AND base_url = ?
            AND id NOT IN (
                SELECT message_id FROM tombstones 
                WHERE channel_id = ? AND user_id = ? AND base_url = ?
            )
        """
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            bindText(statement, 4, channelId)
            bindText(statement, 5, userId)
            bindText(statement, 6, baseURL)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        
        sqlite3_finalize(statement)
        return count > 0
    }
    
    private func _getDeletedMessageIds(channelId: String, userId: String, baseURL: String) -> Set<String> {
        guard let db = db else { return [] }
        
        let selectSQL = """
            SELECT message_id FROM tombstones 
            WHERE channel_id = ? AND user_id = ? AND base_url = ?
        """
        var statement: OpaquePointer?
        var deletedIds = Set<String>()
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let messageId = sqlite3_column_text(statement, 0) {
                    deletedIds.insert(String(cString: messageId))
                }
            }
        }
        
        sqlite3_finalize(statement)
        return deletedIds
    }
    
    /// Cache user data for message authors (scoped by user_id and base_url)
    func cacheUsers(_ users: [User], userId: String, baseURL: String) {
        dbQueue.async { [weak self] in
            self?._cacheUsers(users, userId: userId, baseURL: baseURL)
        }
    }
    
    private func _cacheUsers(_ users: [User], userId: String, baseURL: String) {
        guard let db = db else { return }
        
        let insertSQL = """
            INSERT OR REPLACE INTO users 
            (id, user_id, base_url, username, display_name, avatar_url, user_data) 
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            
            for user in users {
                guard let userData = try? JSONEncoder().encode(user) else { continue }
                
                bindText(statement, 1, user.id)
                bindText(statement, 2, userId)
                bindText(statement, 3, baseURL)
                bindText(statement, 4, user.username)
                bindText(statement, 5, user.display_name)
                
                if let avatar = user.avatar {
                    bindText(statement, 6, avatar.id)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                
                sqlite3_bind_blob(statement, 7, userData.withUnsafeBytes { $0.baseAddress }, Int32(userData.count), nil)
                
                sqlite3_step(statement)
                sqlite3_reset(statement)
            }
            
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
        
        sqlite3_finalize(statement)
        cacheTrace("cacheUsers stored count=\(users.count)")
    }
    
    /// Load cached user data (scoped by current user_id and base_url)
    func loadCachedUsers(for userIds: [String], currentUserId: String, baseURL: String) async -> [String: User] {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let users = self?._loadCachedUsers(for: userIds, currentUserId: currentUserId, baseURL: baseURL) ?? [:]
                continuation.resume(returning: users)
            }
        }
    }
    
    private func _loadCachedUsers(for userIds: [String], currentUserId: String, baseURL: String) -> [String: User] {
        guard let db = db else { return [:] }
        
        var users: [String: User] = [:]
        
        for userId in userIds {
            let selectSQL = "SELECT user_data FROM users WHERE id = ? AND user_id = ? AND base_url = ?"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
                bindText(statement, 1, userId)
                bindText(statement, 2, currentUserId)
                bindText(statement, 3, baseURL)
                
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
    
    private func updateChannelInfo(channelId: String, userId: String, baseURL: String, messages: [Message]) {
        guard let db = db, !messages.isEmpty else { return }
        
        let lastMessage = messages.max { messageCacheCreatedAt(id: $0.id) < messageCacheCreatedAt(id: $1.id) }
        let now = Int64(Date().timeIntervalSince1970)
        
        let updateSQL = """
            INSERT OR REPLACE INTO channel_info 
            (channel_id, user_id, base_url, last_message_id, message_count, last_updated) 
            VALUES (?, ?, ?, ?, (SELECT COUNT(*) FROM messages WHERE channel_id = ? AND user_id = ? AND base_url = ?), ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            bindText(statement, 4, lastMessage?.id)
            bindText(statement, 5, channelId)
            bindText(statement, 6, userId)
            bindText(statement, 7, baseURL)
            sqlite3_bind_int64(statement, 8, now)
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    // MARK: - Last Message ID Management
    
    /// Update the last message ID for a channel (only when response includes newest messages)
    func updateLastMessageId(channelId: String, userId: String, baseURL: String, lastMessageId: String?) {
        guard let db = db, let lastMessageId = lastMessageId else { return }
        
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            let now = Int64(Date().timeIntervalSince1970)
            
            let updateSQL = """
                INSERT OR REPLACE INTO channel_info 
                (channel_id, user_id, base_url, last_message_id, message_count, last_updated)
                VALUES (
                    ?, ?, ?, ?,
                    COALESCE(
                        (SELECT message_count FROM channel_info WHERE channel_id = ? AND user_id = ? AND base_url = ?),
                        0
                    ),
                    ?
                )
            """
            
            self._updateLastMessageId(
                channelId: channelId,
                userId: userId,
                baseURL: baseURL,
                lastMessageId: lastMessageId,
                now: now,
                updateSQL: updateSQL
            )
        }
    }

    private func _updateLastMessageId(channelId: String, userId: String, baseURL: String, lastMessageId: String, now: Int64 = Int64(Date().timeIntervalSince1970), updateSQL: String? = nil) {
        guard let db = db else { return }
        let sql = updateSQL ?? """
            INSERT OR REPLACE INTO channel_info 
            (channel_id, user_id, base_url, last_message_id, message_count, last_updated)
            VALUES (
                ?, ?, ?, ?,
                COALESCE(
                    (SELECT message_count FROM channel_info WHERE channel_id = ? AND user_id = ? AND base_url = ?),
                    0
                ),
                ?
            )
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            bindText(statement, 4, lastMessageId)
            bindText(statement, 5, channelId)
            bindText(statement, 6, userId)
            bindText(statement, 7, baseURL)
            sqlite3_bind_int64(statement, 8, now)
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    /// Get the last cached message ID for a channel
    func getLastCachedMessageId(for channelId: String, userId: String, baseURL: String) async -> String? {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let lastId = self?._getLastCachedMessageId(channelId: channelId, userId: userId, baseURL: baseURL)
                continuation.resume(returning: lastId)
            }
        }
    }
    
    private func _getLastCachedMessageId(channelId: String, userId: String, baseURL: String) -> String? {
        guard let db = db else { return nil }
        
        let selectSQL = """
            SELECT last_message_id FROM channel_info 
            WHERE channel_id = ? AND user_id = ? AND base_url = ?
        """
        var statement: OpaquePointer?
        var lastId: String? = nil
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    lastId = String(cString: text)
                }
            }
        }
        
        sqlite3_finalize(statement)
        return lastId
    }
    
    // MARK: - Message Merge
    
    /// Merge cached and API messages with de-duplication
    func mergeMessages(cached: [Message], api: [Message], lastCachedId: String?, deletedIds: Set<String>, shouldUpdateLastMessageId: Bool) -> (merged: [Message], serverLastMessageId: String?) {
        let cachedIds = Set(cached.map { $0.id })
        
        // Compute server last message ID from API response (ULIDs are lexicographically sortable)
        // NOTE: Only valid when response includes newest messages (initial/latest or 'after' fetch)
        let serverLastMessageId = shouldUpdateLastMessageId ? api.map { $0.id }.max() : nil
        
        // Filter API messages: not in cache, not deleted, and (newer than lastCached OR filling gap)
        let newMessages = api.filter { message in
            !cachedIds.contains(message.id) &&
            !deletedIds.contains(message.id) &&
            (lastCachedId == nil || (lastCachedId.map { message.id > $0 } ?? false) || isFillingGap(message, cached))
        }
        
        // Combine and sort by ULID timestamp (stable sort)
        let merged = (cached + newMessages)
            .sorted { messageCacheCreatedAt(id: $0.id) < messageCacheCreatedAt(id: $1.id) }
        
        return (merged, serverLastMessageId)
    }
    
    private func isFillingGap(_ message: Message, _ cached: [Message]) -> Bool {
        // Check if message fills a gap in cached messages
        // This is a simple heuristic - if message ID is between two cached messages, it's filling a gap
        guard !cached.isEmpty else { return false }
        
        let messageTime = messageCacheCreatedAt(id: message.id)
        let cachedTimes = cached.map { messageCacheCreatedAt(id: $0.id) }
        
        // If message time is between min and max cached times, it might be filling a gap
        if let minTime = cachedTimes.min(), let maxTime = cachedTimes.max() {
            return messageTime >= minTime && messageTime <= maxTime
        }
        
        return false
    }
    
    // MARK: - Cache Updates (Edits/Deletes)
    
    /// Update a cached message (for edits)
    func updateCachedMessage(id messageId: String, content: String?, editedAt: Date?, channelId: String, userId: String, baseURL: String) {
        dbQueue.async { [weak self] in
            self?._updateCachedMessage(id: messageId, content: content, editedAt: editedAt, channelId: channelId, userId: userId, baseURL: baseURL)
        }
    }
    
    private func _updateCachedMessage(id messageId: String, content: String?, editedAt: Date?, channelId: String, userId: String, baseURL: String) {
        guard let db = db else { return }
        
        // Load existing message
        let selectSQL = """
            SELECT message_data FROM messages 
            WHERE id = ? AND channel_id = ? AND user_id = ? AND base_url = ?
        """
        var selectStatement: OpaquePointer?
        var messageData: Data? = nil
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &selectStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(selectStatement, 1, messageId, -1, nil)
            sqlite3_bind_text(selectStatement, 2, channelId, -1, nil)
            sqlite3_bind_text(selectStatement, 3, userId, -1, nil)
            sqlite3_bind_text(selectStatement, 4, baseURL, -1, nil)
            
            if sqlite3_step(selectStatement) == SQLITE_ROW {
                if let blob = sqlite3_column_blob(selectStatement, 0) {
                    let size = sqlite3_column_bytes(selectStatement, 0)
                    messageData = Data(bytes: blob, count: Int(size))
                }
            }
        }
        sqlite3_finalize(selectStatement)
        
        guard var messageData = messageData,
              var message = try? JSONDecoder().decode(Message.self, from: messageData) else {
            return
        }
        
        // Update message
        if let content = content {
            message.content = content
        }
        if let editedAt = editedAt {
            let formatter = ISO8601DateFormatter()
            message.edited = formatter.string(from: editedAt)
        }
        
        // Re-encode and save
        guard let updatedData = try? JSONEncoder().encode(message) else { return }
        
        // Only update content if provided, otherwise keep existing content
        let updateSQL: String
        if content != nil {
            updateSQL = """
                UPDATE messages 
                SET message_data = ?, content = ?, edited_at = ?
                WHERE id = ? AND channel_id = ? AND user_id = ? AND base_url = ?
            """
        } else {
            updateSQL = """
                UPDATE messages 
                SET message_data = ?, edited_at = ?
                WHERE id = ? AND channel_id = ? AND user_id = ? AND base_url = ?
            """
        }
        var updateStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_blob(updateStatement, 1, updatedData.withUnsafeBytes { $0.baseAddress }, Int32(updatedData.count), nil)
            
            var paramIndex = 2
            if let content = content {
                sqlite3_bind_text(updateStatement, Int32(paramIndex), content, -1, nil)
                paramIndex += 1
            }
            
            if let editedAt = editedAt {
                sqlite3_bind_int64(updateStatement, Int32(paramIndex), Int64(editedAt.timeIntervalSince1970))
                paramIndex += 1
            } else {
                sqlite3_bind_null(updateStatement, Int32(paramIndex))
                paramIndex += 1
            }
            
            sqlite3_bind_text(updateStatement, Int32(paramIndex), messageId, -1, nil)
            sqlite3_bind_text(updateStatement, Int32(paramIndex + 1), channelId, -1, nil)
            sqlite3_bind_text(updateStatement, Int32(paramIndex + 2), userId, -1, nil)
            sqlite3_bind_text(updateStatement, Int32(paramIndex + 3), baseURL, -1, nil)
            sqlite3_step(updateStatement)
        }
        
        sqlite3_finalize(updateStatement)
    }
    
    /// Delete a cached message and add to tombstone
    func deleteCachedMessage(id messageId: String, channelId: String, userId: String, baseURL: String) {
        dbQueue.async { [weak self] in
            self?._deleteCachedMessage(id: messageId, channelId: channelId, userId: userId, baseURL: baseURL)
        }
    }
    
    private func _deleteCachedMessage(id messageId: String, channelId: String, userId: String, baseURL: String) {
        guard let db = db else { return }
        
        // Add to tombstone
        let now = Int64(Date().timeIntervalSince1970)
        let insertTombstoneSQL = """
            INSERT OR REPLACE INTO tombstones 
            (message_id, channel_id, user_id, base_url, deleted_at) 
            VALUES (?, ?, ?, ?, ?)
        """
        var tombstoneStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertTombstoneSQL, -1, &tombstoneStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(tombstoneStatement, 1, messageId, -1, nil)
            sqlite3_bind_text(tombstoneStatement, 2, channelId, -1, nil)
            sqlite3_bind_text(tombstoneStatement, 3, userId, -1, nil)
            sqlite3_bind_text(tombstoneStatement, 4, baseURL, -1, nil)
            sqlite3_bind_int64(tombstoneStatement, 5, now)
            sqlite3_step(tombstoneStatement)
        }
        sqlite3_finalize(tombstoneStatement)
        
        // Delete from messages
        let deleteSQL = """
            DELETE FROM messages 
            WHERE id = ? AND channel_id = ? AND user_id = ? AND base_url = ?
        """
        var deleteStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStatement, 1, messageId, -1, nil)
            sqlite3_bind_text(deleteStatement, 2, channelId, -1, nil)
            sqlite3_bind_text(deleteStatement, 3, userId, -1, nil)
            sqlite3_bind_text(deleteStatement, 4, baseURL, -1, nil)
            sqlite3_step(deleteStatement)
        }
        sqlite3_finalize(deleteStatement)
        
        // Enforce tombstone limit
        _enforceTombstoneLimit(channelId: channelId, userId: userId, baseURL: baseURL)
    }
    
    // MARK: - Tombstone Management
    
    private func _enforceTombstoneLimit(channelId: String, userId: String, baseURL: String) {
        guard let db = db else { return }
        
        // Count tombstones for this channel
        let countSQL = "SELECT COUNT(*) FROM tombstones WHERE channel_id = ? AND user_id = ? AND base_url = ?"
        var countStatement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, countSQL, -1, &countStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(countStatement, 1, channelId, -1, nil)
            sqlite3_bind_text(countStatement, 2, userId, -1, nil)
            sqlite3_bind_text(countStatement, 3, baseURL, -1, nil)
            
            if sqlite3_step(countStatement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(countStatement, 0))
            }
        }
        sqlite3_finalize(countStatement)
        
        // If over limit, evict oldest
        if count > maxTombstonesPerChannel {
            let toEvict = count - maxTombstonesPerChannel
            let evictSQL = """
                DELETE FROM tombstones 
                WHERE channel_id = ? AND user_id = ? AND base_url = ?
                AND message_id IN (
                    SELECT message_id FROM tombstones 
                    WHERE channel_id = ? AND user_id = ? AND base_url = ?
                    ORDER BY deleted_at ASC 
                    LIMIT ?
                )
            """
            var evictStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, evictSQL, -1, &evictStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(evictStatement, 1, channelId, -1, nil)
                sqlite3_bind_text(evictStatement, 2, userId, -1, nil)
                sqlite3_bind_text(evictStatement, 3, baseURL, -1, nil)
                sqlite3_bind_text(evictStatement, 4, channelId, -1, nil)
                sqlite3_bind_text(evictStatement, 5, userId, -1, nil)
                sqlite3_bind_text(evictStatement, 6, baseURL, -1, nil)
                sqlite3_bind_int(evictStatement, 7, Int32(toEvict))
                sqlite3_step(evictStatement)
            }
            sqlite3_finalize(evictStatement)
        }
    }
    
    /// Expire tombstones older than specified days
    func expireTombstones(olderThan days: Int = 7) {
        dbQueue.async { [weak self] in
            self?._expireTombstones(olderThan: days)
        }
    }
    
    private func _expireTombstones(olderThan days: Int) {
        guard let db = db else { return }
        
        let cutoffDate = Int64(Date().addingTimeInterval(-Double(days * 24 * 60 * 60)).timeIntervalSince1970)
        let deleteSQL = "DELETE FROM tombstones WHERE deleted_at < ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, cutoffDate)
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    // MARK: - Cache Staleness
    
    /// Check if cache is stale
    func isCacheStale(channelId: String, userId: String, baseURL: String, maxAge: TimeInterval = 3600, serverLastMessageId: String?) -> Bool {
        return dbQueue.sync {
            return _isCacheStale(channelId: channelId, userId: userId, baseURL: baseURL, maxAge: maxAge, serverLastMessageId: serverLastMessageId)
        }
    }
    
    private func _isCacheStale(channelId: String, userId: String, baseURL: String, maxAge: TimeInterval, serverLastMessageId: String?) -> Bool {
        guard let db = db else { return true }
        
        let selectSQL = """
            SELECT last_updated, last_message_id FROM channel_info 
            WHERE channel_id = ? AND user_id = ? AND base_url = ?
        """
        var statement: OpaquePointer?
        var isStale = true
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let lastUpdated = sqlite3_column_int64(statement, 0)
                let lastUpdateDate = Date(timeIntervalSince1970: TimeInterval(lastUpdated))
                let age = Date().timeIntervalSince(lastUpdateDate)
                
                // Check age
                if age > maxAge {
                    isStale = true
                } else if let serverLastMessageId = serverLastMessageId {
                    // Check if server has newer messages
                    if let cachedLastId = sqlite3_column_text(statement, 1) {
                        let cachedLastIdString = String(cString: cachedLastId)
                        // ULIDs are lexicographically sortable
                        isStale = serverLastMessageId > cachedLastIdString
                    } else {
                        isStale = true // No cached last ID
                    }
                } else {
                    isStale = false
                }
            }
        }
        
        sqlite3_finalize(statement)
        return isStale
    }
    
    // MARK: - Cache Management
    
    /// Clear all caches (called on sign-out)
    func clearAllCaches() {
        dbQueue.async { [weak self] in
            self?._clearAllCaches()
        }
    }
    
    private func _clearAllCaches() {
        guard let db = db else { return }
        
        sqlite3_exec(db, "DELETE FROM messages", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM users", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM channel_info", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM tombstones", nil, nil, nil)
        
        logger.info("Cleared all message caches")
    }
    
    /// Clear cache for a specific channel
    func clearChannelCache(channelId: String, userId: String, baseURL: String) {
        dbQueue.async { [weak self] in
            self?._clearChannelCache(channelId: channelId, userId: userId, baseURL: baseURL)
        }
    }
    
    private func _clearChannelCache(channelId: String, userId: String, baseURL: String) {
        guard let db = db else { return }
        
        let deleteMessagesSQL = "DELETE FROM messages WHERE channel_id = ? AND user_id = ? AND base_url = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteMessagesSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        let deleteChannelInfoSQL = "DELETE FROM channel_info WHERE channel_id = ? AND user_id = ? AND base_url = ?"
        if sqlite3_prepare_v2(db, deleteChannelInfoSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        let deleteTombstonesSQL = "DELETE FROM tombstones WHERE channel_id = ? AND user_id = ? AND base_url = ?"
        if sqlite3_prepare_v2(db, deleteTombstonesSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
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
    func preloadFrequentChannels(channelIds: [String], userId: String, baseURL: String) {
        Task.detached(priority: .background) { [weak self] in
            for channelId in channelIds {
                // Check if channel already has recent cache
                let hasCached = await self?.hasCachedMessages(for: channelId, userId: userId, baseURL: baseURL) ?? false
                if !hasCached {
                    print("📦 PRELOAD: Channel \(channelId) has no cache, skipping preload")
                    continue
                }
                
                // Only preload if cache is older than 1 hour
                let needsRefresh = await self?._needsCacheRefresh(for: channelId, userId: userId, baseURL: baseURL) ?? false
                if needsRefresh {
                    print("📦 PRELOAD: Refreshing cache for channel \(channelId)")
                    // This would trigger a background API call to refresh messages
                    // Implementation depends on having access to HTTP client
                }
            }
        }
    }
    
    private func _needsCacheRefresh(for channelId: String, userId: String, baseURL: String) -> Bool {
        guard let db = db else { return true }
        
        let selectSQL = "SELECT last_updated FROM channel_info WHERE channel_id = ? AND user_id = ? AND base_url = ?"
        var statement: OpaquePointer?
        var needsRefresh = true
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, channelId)
            bindText(statement, 2, userId)
            bindText(statement, 3, baseURL)
            
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
        
        // Clean orphaned users (scoped by user_id and base_url)
        let cleanUsersSQL = """
            DELETE FROM users WHERE (user_id, base_url) NOT IN (
                SELECT DISTINCT user_id, base_url FROM messages
            )
        """
        
        sqlite3_exec(db, cleanUsersSQL, nil, nil, nil)
        
        // Expire old tombstones
        _expireTombstones(olderThan: tombstoneRetentionDays)

        // Refresh channel info after message eviction
        _refreshChannelInfoAfterEviction()
        
        // Enforce total cache size limit
        _enforceTotalCacheSizeLimit()
        
        // Vacuum database to reclaim space
        sqlite3_exec(db, "VACUUM", nil, nil, nil)
    }
    
    private func _enforceTotalCacheSizeLimit() {
        guard let db = db else { return }
        
        // Get current cache size
        var pageCount: Int32 = 0
        var pageSize: Int32 = 0
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA page_count", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                pageCount = sqlite3_column_int(statement, 0)
            }
        }
        sqlite3_finalize(statement)
        
        if sqlite3_prepare_v2(db, "PRAGMA page_size", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                pageSize = sqlite3_column_int(statement, 0)
            }
        }
        sqlite3_finalize(statement)
        
        let currentSizeMB = Double(pageCount * pageSize) / (1024 * 1024)
        
        // If over limit, evict oldest messages across all channels
        if currentSizeMB > Double(maxCacheSizeMB) {
            let overageMB = currentSizeMB - Double(maxCacheSizeMB)
            let targetReductionMB = overageMB * 1.2 // Remove 20% more to prevent rapid re-growth
            let targetReductionBytes = Int64(targetReductionMB * 1024 * 1024)
            
            // Estimate messages to remove (rough estimate: 2KB per message on average)
            let avgMessageSize = 2048
            let messagesToRemove = Int(targetReductionBytes / Int64(avgMessageSize))
            
            // Remove oldest messages across all channels
            let evictSQL = """
                DELETE FROM messages 
                WHERE id IN (
                    SELECT id FROM messages 
                    ORDER BY created_at ASC 
                    LIMIT ?
                )
            """
            
            if sqlite3_prepare_v2(db, evictSQL, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(messagesToRemove))
                sqlite3_step(statement)
                logger.info("Evicted \(messagesToRemove) oldest messages to enforce cache size limit")
            }
            sqlite3_finalize(statement)

            _refreshChannelInfoAfterEviction()
        }
    }

    private func _refreshChannelInfoAfterEviction() {
        guard let db = db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        sqlite3_exec(db, """
            DELETE FROM channel_info
            WHERE (channel_id, user_id, base_url) NOT IN (
                SELECT DISTINCT channel_id, user_id, base_url FROM messages
            )
        """, nil, nil, nil)

        sqlite3_exec(db, """
            UPDATE channel_info SET
                message_count = (
                    SELECT COUNT(*) FROM messages
                    WHERE channel_id = channel_info.channel_id
                      AND user_id = channel_info.user_id
                      AND base_url = channel_info.base_url
                ),
                last_message_id = (
                    SELECT id FROM messages
                    WHERE channel_id = channel_info.channel_id
                      AND user_id = channel_info.user_id
                      AND base_url = channel_info.base_url
                    ORDER BY created_at DESC
                    LIMIT 1
                ),
                last_updated = \(now)
        """, nil, nil, nil)
    }
    
    /// Evict old messages (older than specified days)
    func evictOldMessages(olderThan days: Int = 7) {
        cleanupOldMessages(olderThan: days)
    }
    
    /// Evict all cache for a channel
    func evictChannelCache(channelId: String, userId: String, baseURL: String) {
        clearChannelCache(channelId: channelId, userId: userId, baseURL: baseURL)
    }
    
    /// Enforce per-channel message limit
    func enforcePerChannelLimit(channelId: String, userId: String, baseURL: String, maxMessages: Int) {
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            let currentCount = self._getMessageCount(channelId: channelId, userId: userId, baseURL: baseURL)
            if currentCount > maxMessages {
                let toEvict = currentCount - maxMessages
                self._evictOldestMessages(channelId: channelId, userId: userId, baseURL: baseURL, count: toEvict)
            }
        }
    }
    
    /// Get cache statistics for a user
    func getCacheStats(userId: String, baseURL: String) async -> (messageCount: Int, userCount: Int, sizeInMB: Double) {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                let stats = self?._getCacheStats(userId: userId, baseURL: baseURL) ?? (0, 0, 0.0)
                continuation.resume(returning: stats)
            }
        }
    }
    
    private func _getCacheStats(userId: String, baseURL: String) -> (messageCount: Int, userCount: Int, sizeInMB: Double) {
        guard let db = db else { return (0, 0, 0.0) }
        
        var messageCount = 0
        var userCount = 0
        var sizeInMB = 0.0
        
        // Get message count for this user
        var statement: OpaquePointer?
        let messageCountSQL = "SELECT COUNT(*) FROM messages WHERE user_id = ? AND base_url = ?"
        if sqlite3_prepare_v2(db, messageCountSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, 1, userId)
            bindText(statement, 2, baseURL)
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
