//
//  MessageCellHeightCache.swift
//  Revolt
//
//  Performance optimization: Cache calculated cell heights to avoid expensive recalculations
//

import UIKit

class MessageCellHeightCache {
    // Singleton instance
    static let shared = MessageCellHeightCache()
    
    // Cache structure: [channelId: [messageId: height]]
    private var cache: [String: [String: CGFloat]] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    /// Get cached height for a message in a specific channel
    func height(for messageId: String, in channelId: String) -> CGFloat? {
        lock.lock()
        defer { lock.unlock() }
        return cache[channelId]?[messageId]
    }
    
    /// Cache height for a message in a specific channel
    func setHeight(_ height: CGFloat, for messageId: String, in channelId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if cache[channelId] == nil {
            cache[channelId] = [:]
        }
        cache[channelId]?[messageId] = height
    }
    
    /// Clear cache for a specific channel (e.g., when leaving channel)
    func clearCache(for channelId: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: channelId)
    }
    
    /// Clear all cached heights (e.g., on memory warning)
    func clearAllCaches() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
    
    /// Get cache statistics for debugging
    func getCacheStats() -> (channels: Int, totalMessages: Int) {
        lock.lock()
        defer { lock.unlock() }
        let totalMessages = cache.values.reduce(0) { $0 + $1.count }
        return (cache.count, totalMessages)
    }
}

