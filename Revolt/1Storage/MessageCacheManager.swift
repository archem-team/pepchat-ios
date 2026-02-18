import Foundation
import SQLite3
import Types
import OSLog

/// Extract creation date from message ID (fileprivate to avoid clashing with global createdAt).
/// Revolt message IDs are ULIDs; first 48 bits are timestamp in milliseconds.
fileprivate func messageCacheCreatedAt(id: String) -> Date {
    guard id.count == 26 else { return Date() }
    let base32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    let timestampPortion = String(id.prefix(10))
    var timestamp: UInt64 = 0
    for char in timestampPortion {
        timestamp = timestamp * 32
        if let idx = base32.firstIndex(of: char.uppercased().first!) {
            timestamp += UInt64(base32.distance(from: base32.startIndex, to: idx))
        }
    }
    return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
}

/// A high-performance message cache manager using SQLite for local storage
/// This provides instant message loading similar to Telegram's approach
class MessageCacheManager {
    static let shared = MessageCacheManager()
    
    private var db: OpaquePointer?
    private let logger = Logger(subsystem: "Revolt", category: "MessageCache")
    private let dbQueue = DispatchQueue(label: "com.revolt.messagecache", qos: .userInitiated)
    
    // MARK: - Schema Versioning
    /// Migration: when upgrading from channel-only (v1) to multi-tenant (v2), we cannot prove
    /// session at init, so we always purge to avoid cross-account leakage.
    private let currentSchemaVersion = 2
    private let schemaVersionKey = "messageCacheSchemaVersion"
    
    // MARK: - Database Schema (v2: channel_id + user_id + base_url)
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
    
    deinit {
        closeDatabase()
    }
    
    private func checkAndMigrateSchema() {
        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if storedVersion < currentSchemaVersion {
            clearAllCachesSync()
            UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
            logger.info("Message cache schema migrated to v\(self.currentSchemaVersion) (purge: session not proven at init)")
        } else if storedVersion == 0, hasExistingCacheDatabase() {
            clearAllCachesSync()
            UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
            logger.info("Cleared legacy cache database on first launch")
        } else if storedVersion == 0 {
            UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
        }
    }
    
    private func hasExistingCacheDatabase() -> Bool {
        guard let path = dbPathURL()?.path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
    
    private func dbPathURL() -> URL? {
        guard let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let bundleId = Bundle.main.bundleIdentifier else { return nil }
        return documentsPath.appendingPathComponent(bundleId, isDirectory: true).appendingPathComponent("messages.sqlite")
    }
    
    private func clearAllCachesSync() {
        closeDatabase()
        guard let url = dbPathURL(), FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
        logger.info("Cleared message cache database during schema migration")
    }
    
    private func openDatabase() {
        guard let revoltDir = dbPathURL()?.deletingLastPathComponent() else {
            logger.error("Failed to get documents directory")
            return
        }
        do {
            try FileManager.default.createDirectory(at: revoltDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Revolt directory: \(error.localizedDescription)")
            return
        }
        guard let dbPath = dbPathURL()?.path else { return }
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            logger.error("Unable to open database at path: \(dbPath)")
            db = nil
        } else {
            logger.info("Successfully opened message cache database")
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
                logger.error("Error creating table/index: \(errmsg)")
            }
        }
    }
    
    private func closeDatabase() {
        if let d = db {
            sqlite3_close(d)
            db = nil
        }
    }
    
    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value = value else {
            sqlite3_bind_null(statement, index)
            return
        }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }
    
    // MARK: - Message Operations
    
    /// Cache messages and users in one go (called from MessageCacheWriter).
    func cacheMessagesAndUsers(_ messages: [Message], users: [User], channelId: String, userId: String, baseURL: String, lastMessageId: String?) {
        dbQueue.async { [weak self] in
            if !messages.isEmpty {
                print("📂 [MessageCache] WRITE: caching \(messages.count) messages for channel \(channelId)")
            }
            self?._cacheMessages(messages, for: channelId, userId: userId, baseURL: baseURL)
            self?._cacheUsers(users, userId: userId, baseURL: baseURL)
            if let lid = lastMessageId {
                self?._updateChannelInfo(channelId: channelId, userId: userId, baseURL: baseURL, lastMessageId: lid)
            }
        }
    }
    
    private func _cacheMessages(_ messages: [Message], for channelId: String, userId: String, baseURL: String) {
        guard let db = db, !messages.isEmpty else { return }
        let insertSQL = """
            INSERT OR REPLACE INTO messages
            (id, channel_id, user_id, base_url, author_id, content, created_at, edited_at, message_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        for message in messages {
            let content = extractMessageContent(from: message)
            let createdAt = Int64(messageCacheCreatedAt(id: message.id).timeIntervalSince1970)
            var editedAt: Int64?
            if let ed = message.edited, let date = ISO8601DateFormatter().date(from: ed) {
                editedAt = Int64(date.timeIntervalSince1970)
            }
            guard let messageData = try? JSONEncoder().encode(message) else { continue }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(statement, 1, message.id)
            bindText(statement, 2, channelId)
            bindText(statement, 3, userId)
            bindText(statement, 4, baseURL)
            bindText(statement, 5, message.author)
            bindText(statement, 6, content)
            sqlite3_bind_int64(statement, 7, createdAt)
            if let ed = editedAt { sqlite3_bind_int64(statement, 8, ed) } else { sqlite3_bind_null(statement, 8) }
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: messageData.count)
            messageData.copyBytes(to: ptr, count: messageData.count)
            sqlite3_bind_blob(statement, 9, ptr, Int32(messageData.count)) { p in p?.deallocate() }
            sqlite3_step(statement)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        _updateChannelInfo(channelId: channelId, userId: userId, baseURL: baseURL, messages: messages)
    }
    
    /// Load cached messages (stable snapshot: one transaction for consistent ordering).
    func loadCachedMessages(for channelId: String, userId: String, baseURL: String, limit: Int = 500, offset: Int = 0) async -> [Message] {
        await withCheckedContinuation { cont in
            dbQueue.async { [weak self] in
                let list = self?._loadCachedMessages(for: channelId, userId: userId, baseURL: baseURL, limit: limit, offset: offset) ?? []
                if !list.isEmpty {
                    print("📂 [MessageCache] READ: loaded \(list.count) messages from cache for channel \(channelId) (offset \(offset))")
                }
                cont.resume(returning: list)
            }
        }
    }
    
    private func _getDeletedMessageIds(channelId: String, userId: String, baseURL: String) -> Set<String> {
        guard let db = db else { return [] }
        let sql = "SELECT message_id FROM tombstones WHERE channel_id = ? AND user_id = ? AND base_url = ?"
        var statement: OpaquePointer?
        var ids = Set<String>()
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, channelId)
        bindText(statement, 2, userId)
        bindText(statement, 3, baseURL)
        while sqlite3_step(statement) == SQLITE_ROW {
            if let c = sqlite3_column_text(statement, 0) {
                ids.insert(String(cString: c))
            }
        }
        return ids
    }
    
    private func _loadCachedMessages(for channelId: String, userId: String, baseURL: String, limit: Int, offset: Int) -> [Message] {
        guard let db = db else { return [] }
        let deletedIds = _getDeletedMessageIds(channelId: channelId, userId: userId, baseURL: baseURL)
        let selectSQL = """
            SELECT message_data FROM messages
            WHERE channel_id = ? AND user_id = ? AND base_url = ?
            AND id NOT IN (SELECT message_id FROM tombstones WHERE channel_id = ? AND user_id = ? AND base_url = ?)
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """
        var statement: OpaquePointer?
        var messages: [Message] = []
        guard sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, channelId)
        bindText(statement, 2, userId)
        bindText(statement, 3, baseURL)
        bindText(statement, 4, channelId)
        bindText(statement, 5, userId)
        bindText(statement, 6, baseURL)
        sqlite3_bind_int(statement, 7, Int32(limit))
        sqlite3_bind_int(statement, 8, Int32(offset))
        while sqlite3_step(statement) == SQLITE_ROW {
            if let blob = sqlite3_column_blob(statement, 0) {
                let size = sqlite3_column_bytes(statement, 0)
                let data = Data(bytes: blob, count: Int(size))
                if let message = try? JSONDecoder().decode(Message.self, from: data), !deletedIds.contains(message.id) {
                    messages.append(message)
                }
            }
        }
        return messages.reversed()
    }
    
    func cachedMessageCount(for channelId: String, userId: String, baseURL: String) async -> Int {
        await withCheckedContinuation { cont in
            dbQueue.async { [weak self] in
                let n = self?._cachedMessageCount(channelId: channelId, userId: userId, baseURL: baseURL) ?? 0
                cont.resume(returning: n)
            }
        }
    }
    
    private func _cachedMessageCount(channelId: String, userId: String, baseURL: String) -> Int {
        guard let db = db else { return 0 }
        let sql = """
            SELECT COUNT(*) FROM messages
            WHERE channel_id = ? AND user_id = ? AND base_url = ?
            AND id NOT IN (SELECT message_id FROM tombstones WHERE channel_id = ? AND user_id = ? AND base_url = ?)
        """
        var statement: OpaquePointer?
        var count = 0
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, channelId)
        bindText(statement, 2, userId)
        bindText(statement, 3, baseURL)
        bindText(statement, 4, channelId)
        bindText(statement, 5, userId)
        bindText(statement, 6, baseURL)
        if sqlite3_step(statement) == SQLITE_ROW { count = Int(sqlite3_column_int(statement, 0)) }
        return count
    }
    
    func hasCachedMessages(for channelId: String, userId: String, baseURL: String) async -> Bool {
        await cachedMessageCount(for: channelId, userId: userId, baseURL: baseURL) > 0
    }
    
    func updateCachedMessage(id messageId: String, content: String?, editedAt: Date?, channelId: String, userId: String, baseURL: String) {
        dbQueue.async { [weak self] in
            self?._updateCachedMessage(id: messageId, content: content, editedAt: editedAt, channelId: channelId, userId: userId, baseURL: baseURL)
        }
    }
    
    private func _updateCachedMessage(id messageId: String, content: String?, editedAt: Date?, channelId: String, userId: String, baseURL: String) {
        guard let db = db else { return }
        let sel = "SELECT message_data FROM messages WHERE id = ? AND channel_id = ? AND user_id = ? AND base_url = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sel, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, messageId)
        bindText(stmt, 2, channelId)
        bindText(stmt, 3, userId)
        bindText(stmt, 4, baseURL)
        guard sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) else { return }
        let size = sqlite3_column_bytes(stmt, 0)
        let data = Data(bytes: blob, count: Int(size))
        guard var message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        if let content = content { message.content = content }
        if let editedAt = editedAt { message.edited = ISO8601DateFormatter().string(from: editedAt) }
        guard let newData = try? JSONEncoder().encode(message) else { return }
        let upd = "UPDATE messages SET content = ?, edited_at = ?, message_data = ? WHERE id = ? AND channel_id = ? AND user_id = ? AND base_url = ?"
        var stmt2: OpaquePointer?
        guard sqlite3_prepare_v2(db, upd, -1, &stmt2, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt2) }
        bindText(stmt2, 1, message.content)
        if let ed = message.edited, let d = ISO8601DateFormatter().date(from: ed) {
            sqlite3_bind_int64(stmt2, 2, Int64(d.timeIntervalSince1970))
        } else { sqlite3_bind_null(stmt2, 2) }
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: newData.count)
        newData.copyBytes(to: ptr, count: newData.count)
        sqlite3_bind_blob(stmt2, 3, ptr, Int32(newData.count)) { p in p?.deallocate() }
        bindText(stmt2, 4, messageId)
        bindText(stmt2, 5, channelId)
        bindText(stmt2, 6, userId)
        bindText(stmt2, 7, baseURL)
        sqlite3_step(stmt2)
    }
    
    func deleteCachedMessage(id messageId: String, channelId: String, userId: String, baseURL: String) {
        dbQueue.async { [weak self] in
            self?._deleteCachedMessage(id: messageId, channelId: channelId, userId: userId, baseURL: baseURL)
        }
    }
    
    private func _deleteCachedMessage(id messageId: String, channelId: String, userId: String, baseURL: String) {
        guard let db = db else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let ins = "INSERT OR REPLACE INTO tombstones (message_id, channel_id, user_id, base_url, deleted_at) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, ins, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, messageId)
        bindText(stmt, 2, channelId)
        bindText(stmt, 3, userId)
        bindText(stmt, 4, baseURL)
        sqlite3_bind_int64(stmt, 5, now)
        sqlite3_step(stmt)
    }
    
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
        print("📂 [MessageCache] CLEARED: all caches wiped (e.g. sign-out)")
        logger.info("Cleared all message caches")
    }
    
    /// Cache user data for message authors (session-scoped).
    func cacheUsers(_ users: [User], userId: String, baseURL: String) {
        dbQueue.async { [weak self] in
            self?._cacheUsers(users, userId: userId, baseURL: baseURL)
        }
    }
    
    private func _cacheUsers(_ users: [User], userId: String, baseURL: String) {
        guard let db = db else { return }
        let insertSQL = """
            INSERT OR REPLACE INTO users (id, user_id, base_url, username, display_name, avatar_url, user_data)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        for user in users {
            guard let userData = try? JSONEncoder().encode(user) else { continue }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
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
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: userData.count)
            userData.copyBytes(to: ptr, count: userData.count)
            sqlite3_bind_blob(statement, 7, ptr, Int32(userData.count)) { p in p?.deallocate() }
            sqlite3_step(statement)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }
    
    /// Load cached users (session-scoped).
    func loadCachedUsers(for userIds: [String], currentUserId: String, baseURL: String) async -> [String: User] {
        await withCheckedContinuation { cont in
            dbQueue.async { [weak self] in
                let map = self?._loadCachedUsers(for: userIds, currentUserId: currentUserId, baseURL: baseURL) ?? [:]
                cont.resume(returning: map)
            }
        }
    }
    
    private func _loadCachedUsers(for userIds: [String], currentUserId: String, baseURL: String) -> [String: User] {
        guard let db = db else { return [:] }
        var users: [String: User] = [:]
        for uid in userIds {
            let sql = "SELECT user_data FROM users WHERE id = ? AND user_id = ? AND base_url = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, uid)
            bindText(stmt, 2, currentUserId)
            bindText(stmt, 3, baseURL)
            if sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) {
                let size = sqlite3_column_bytes(stmt, 0)
                let data = Data(bytes: blob, count: Int(size))
                if let user = try? JSONDecoder().decode(User.self, from: data) {
                    users[uid] = user
                }
            }
        }
        return users
    }
    
    // MARK: - Helper Methods
    
    private func _updateChannelInfo(channelId: String, userId: String, baseURL: String, messages: [Message]) {
        guard let db = db, !messages.isEmpty else { return }
        let lastMessage = messages.max { messageCacheCreatedAt(id: $0.id) < messageCacheCreatedAt(id: $1.id) }
        let now = Int64(Date().timeIntervalSince1970)
        let sql = """
            INSERT OR REPLACE INTO channel_info (channel_id, user_id, base_url, last_message_id, message_count, last_updated)
            VALUES (?, ?, ?, ?, (SELECT COUNT(*) FROM messages WHERE channel_id = ? AND user_id = ? AND base_url = ?), ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, channelId)
        bindText(stmt, 2, userId)
        bindText(stmt, 3, baseURL)
        bindText(stmt, 4, lastMessage?.id)
        bindText(stmt, 5, channelId)
        bindText(stmt, 6, userId)
        bindText(stmt, 7, baseURL)
        sqlite3_bind_int64(stmt, 8, now)
        sqlite3_step(stmt)
    }
    
    private func _updateChannelInfo(channelId: String, userId: String, baseURL: String, lastMessageId: String) {
        guard let db = db else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let sql = """
            INSERT OR REPLACE INTO channel_info (channel_id, user_id, base_url, last_message_id, message_count, last_updated)
            VALUES (?, ?, ?, ?, (SELECT COUNT(*) FROM messages WHERE channel_id = ? AND user_id = ? AND base_url = ?), ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, channelId)
        bindText(stmt, 2, userId)
        bindText(stmt, 3, baseURL)
        bindText(stmt, 4, lastMessageId)
        bindText(stmt, 5, channelId)
        bindText(stmt, 6, userId)
        bindText(stmt, 7, baseURL)
        sqlite3_bind_int64(stmt, 8, now)
        sqlite3_step(stmt)
    }
    
    private func extractMessageContent(from message: Message) -> String {
        if let system = message.system {
            switch system {
            case .text(let content):
                return content.content
            case .user_added(let userData):
                return "User \(userData.by) added \(userData.id)"
            case .user_removed(let userData):
                return "User \(userData.by) removed \(userData.id)"
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
    
    /// Preload messages for frequently accessed channels (requires session for v2 schema).
    func preloadFrequentChannels(channelIds: [String], userId: String, baseURL: String) {
        Task.detached(priority: .background) { [weak self] in
            for channelId in channelIds {
                let hasCached = await self?.hasCachedMessages(for: channelId, userId: userId, baseURL: baseURL) ?? false
                if !hasCached {
                    continue
                }
                let needsRefresh = await self?._needsCacheRefresh(for: channelId, userId: userId, baseURL: baseURL) ?? false
                if needsRefresh {
                    // Caller can trigger background API refresh
                }
            }
        }
    }
    
    private func _needsCacheRefresh(for channelId: String, userId: String, baseURL: String) -> Bool {
        guard let db = db else { return true }
        let sql = "SELECT last_updated FROM channel_info WHERE channel_id = ? AND user_id = ? AND base_url = ?"
        var stmt: OpaquePointer?
        var needsRefresh = true
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return true }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, channelId)
        bindText(stmt, 2, userId)
        bindText(stmt, 3, baseURL)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let lastUpdated = sqlite3_column_int64(stmt, 0)
            needsRefresh = Date(timeIntervalSince1970: TimeInterval(lastUpdated)) < Date().addingTimeInterval(-3600)
        }
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
