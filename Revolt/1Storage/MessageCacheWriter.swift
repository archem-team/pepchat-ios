//
//  MessageCacheWriter.swift
//  Revolt
//
//  Single serialized, session-scoped cache write path. All cache writes from
//  ViewModel, WebSocket, MessageInputHandler, RepliesManager, MessageContentsView
//  go through this writer to prevent races and cross-account leakage.
//

import Foundation
import Types

/// Flush timeout so sign-out never blocks indefinitely (plan: 2–5 seconds).
private let flushTimeoutSeconds: TimeInterval = 4.0

final class MessageCacheWriter {
    static let shared = MessageCacheWriter()
    
    private let queue = DispatchQueue(label: "com.revolt.messagecache.writer", qos: .userInitiated)
    private var pending: [() -> Void] = []
    private var sessionUserId: String?
    private var sessionBaseURL: String?
    private var invalidated = false
    private let lock = NSLock()
    
    private init() {}
    
    /// Bind session when user signs in or app becomes active with a session.
    func setSession(userId: String?, baseURL: String?) {
        lock.lock()
        sessionUserId = userId
        sessionBaseURL = baseURL
        lock.unlock()
    }
    
    /// Invalidate writer. If flushFirst == true, drain queue with bounded timeout so
    /// last-moment edit/delete intents are persisted; then clear caches. Sign-out uses flushFirst: true.
    func invalidate(flushFirst: Bool) {
        if flushFirst {
            let sem = DispatchSemaphore(value: 0)
            queue.async { [weak self] in
                self?.drainPendingSync()
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + flushTimeoutSeconds)
        }
        lock.lock()
        invalidated = true
        pending.removeAll()
        lock.unlock()
        MessageCacheManager.shared.clearAllCaches()
        setSession(userId: nil, baseURL: nil)
    }
    
    /// Run all currently pending jobs synchronously on the writer queue (called during flush).
    private func drainPendingSync() {
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                lock.unlock()
                return
            }
            let job = pending.removeFirst()
            lock.unlock()
            job()
        }
    }
    
    private func enqueue(_ work: @escaping () -> Void) {
        lock.lock()
        guard !invalidated else {
            lock.unlock()
            return
        }
        pending.append(work)
        lock.unlock()
        queue.async { [weak self] in
            self?.runNext()
        }
    }
    
    private func runNext() {
        lock.lock()
        guard !invalidated, !pending.isEmpty else {
            lock.unlock()
            return
        }
        let job = pending.removeFirst()
        lock.unlock()
        job()
        queue.async { [weak self] in
            self?.runNext()
        }
    }
    
    private func sessionMatches(userId: String, baseURL: String) -> Bool {
        lock.lock()
        let match = sessionUserId == userId && sessionBaseURL == baseURL && !invalidated
        lock.unlock()
        return match
    }
    
    func enqueueCacheMessagesAndUsers(_ messages: [Message], users: [User], channelId: String, userId: String, baseURL: String, lastMessageId: String?) {
        enqueue { [weak self] in
            guard self?.sessionMatches(userId: userId, baseURL: baseURL) == true else { return }
            MessageCacheManager.shared.cacheMessagesAndUsers(messages, users: users, channelId: channelId, userId: userId, baseURL: baseURL, lastMessageId: lastMessageId)
        }
    }
    
    func enqueueUpdateMessage(id messageId: String, content: String?, editedAt: Date?, channelId: String, userId: String, baseURL: String) {
        enqueue { [weak self] in
            guard self?.sessionMatches(userId: userId, baseURL: baseURL) == true else { return }
            MessageCacheManager.shared.updateCachedMessage(id: messageId, content: content, editedAt: editedAt, channelId: channelId, userId: userId, baseURL: baseURL)
        }
    }

    /// Updates cache by message id when channel is unknown (e.g. message_update received and message not in ViewState). Use so edits from other users are persisted.
    func enqueueUpdateMessageById(id messageId: String, content: String?, editedAt: Date?, userId: String, baseURL: String) {
        enqueue { [weak self] in
            guard self?.sessionMatches(userId: userId, baseURL: baseURL) == true else { return }
            MessageCacheManager.shared.updateCachedMessageById(id: messageId, content: content, editedAt: editedAt, userId: userId, baseURL: baseURL)
        }
    }

    func enqueueDeleteMessage(id messageId: String, channelId: String, userId: String, baseURL: String) {
        enqueue { [weak self] in
            guard self?.sessionMatches(userId: userId, baseURL: baseURL) == true else { return }
            MessageCacheManager.shared.deleteCachedMessage(id: messageId, channelId: channelId, userId: userId, baseURL: baseURL)
        }
    }
}
