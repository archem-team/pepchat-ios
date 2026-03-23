//
//  CellHeightCache.swift
//  Revolt
//

import UIKit

struct CellHeightCacheKey: Hashable {
    let messageId: String
    let isContinuation: Bool
    let tableWidth: Int
}

@MainActor
final class CellHeightCache {
    private var cache: [CellHeightCacheKey: CGFloat] = [:]
    private var messageIdToKeys: [String: Set<CellHeightCacheKey>] = [:]

    func height(for key: CellHeightCacheKey) -> CGFloat? {
        cache[key]
    }

    func store(height: CGFloat, for key: CellHeightCacheKey) {
        cache[key] = height
        messageIdToKeys[key.messageId, default: []].insert(key)
    }

    func invalidate(messageId: String) {
        guard let keys = messageIdToKeys.removeValue(forKey: messageId) else { return }
        for key in keys { cache.removeValue(forKey: key) }
    }

    func invalidateAll() {
        cache.removeAll()
        messageIdToKeys.removeAll()
    }
}
