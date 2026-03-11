//
//  ViewState+ChannelCache.swift
//  Revolt
//
//  Server channel list cache: persist per-server text/voice channels for future restore (Option B).
//  Option A: write-only; cleared on signOut/destroyCache. See Channel.md.
//

import Foundation
import Collections
@preconcurrency import Types

/// Payload for the channel cache file. Only text/voice channels per server.
private struct ChannelCachePayload: Codable {
    static let cacheSchemaVersion = 2
    
    let cacheSchemaVersion: Int
    let generation: String
    let servers: [String: [Channel]]
    
    init(generation: String, servers: [String: [Channel]]) {
        self.cacheSchemaVersion = Self.cacheSchemaVersion
        self.generation = generation
        self.servers = servers
    }
}

extension ViewState {
    
    // MARK: - URL and identity
    
    /// Returns the channel cache file URL for the given identity. User-keyed for account safety (§0.7).
    /// - Parameters:
    ///   - userId: Current user id; if nil, used for "clear all" convention.
    ///   - baseURL: API base URL; canonicalized then sanitized for path safety.
    /// - Returns: URL to the cache file, or nil if directory unavailable or identity incomplete.
    static func channelCacheURL(userId: String?, baseURL: String?) -> URL? {
        guard let userId = userId, let baseURL = baseURL, !userId.isEmpty, !baseURL.isEmpty else {
            return nil
        }
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ZekoChat")
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let canonical = canonicalizeBaseURL(baseURL)
        let sanitized = sanitizeBaseURLForFilename(canonical)
        let filename = "channels_cache_\(userId)_\(sanitized).json"
        return dir.appendingPathComponent(filename)
    }
    
    /// Canonicalize base URL for stable cache key (§0.31): lowercase host, strip trailing slash.
    private static func canonicalizeBaseURL(_ baseURL: String) -> String {
        var s = baseURL.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") {
            s = String(s.dropLast())
        }
        return s
    }
    
    /// Sanitize for use in filename: replace unsafe characters (§0.7).
    private static func sanitizeBaseURLForFilename(_ baseURL: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return baseURL
            .components(separatedBy: "/")
            .joined(separator: "_")
            .components(separatedBy: ":")
            .joined(separator: "_")
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
    }
    
    // MARK: - Load (Option B only; not used with Option A)
    
    /// Loads channel cache from disk. With Option A this is not called (§0.1, §0.32).
    /// When a read path exists: validate integrity per §0.27; if version missing/unsupported or decode fails, return empty.
    static func loadChannelCacheSync(userId: String, baseURL: String) -> [String: [Channel]] {
        guard let url = channelCacheURL(userId: userId, baseURL: baseURL),
              FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(ChannelCachePayload.self, from: data)
            if payload.cacheSchemaVersion != ChannelCachePayload.cacheSchemaVersion {
                try? FileManager.default.removeItem(at: url)
                return [:]
            }
            var result: [String: [Channel]] = [:]
            for (serverId, channels) in payload.servers {
                let valid = channels.filter { ch in
                    guard let chServer = ch.server else { return false }
                    return chServer == serverId
                }
                if !valid.isEmpty {
                    result[serverId] = valid
                }
            }
            return result
        } catch {
            try? FileManager.default.removeItem(at: url)
            return [:]
        }
    }
    
    // MARK: - Save (serialized, session-guarded)
    
    /// Enqueues a single channel cache save. Only one save runs at a time; when it runs, if session token no longer matches, the write is skipped (§0.3).
    func saveChannelCacheAsync() {
        let token = channelCacheSessionToken
        let serversSnapshot = servers
        let allEventChannelsSnapshot = allEventChannels
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                let current = self.channelCacheSessionToken
                if token?.userId != current?.userId || token?.baseURL != current?.baseURL {
                    return
                }
                guard let userId = self.currentUser?.id, let baseURL = self.baseURL else {
                    return
                }
                var payloadServers: [String: [Channel]] = [:]
                for (serverId, _) in serversSnapshot {
                    let serverChannels = allEventChannelsSnapshot.values.filter { ch in
                        ch.server == serverId
                    }
                    if !serverChannels.isEmpty {
                        payloadServers[serverId] = serverChannels
                    }
                }
                let generation = "\(userId)_\(baseURL)_\(Date().timeIntervalSince1970)"
                let payload = ChannelCachePayload(generation: generation, servers: payloadServers)
                self.channelCacheSaveWorkItem = nil
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let data = try JSONEncoder().encode(payload)
                        if let url = ViewState.channelCacheURL(userId: userId, baseURL: baseURL) {
                            try data.write(to: url, options: .atomic)
                        }
                    } catch {
                        print("❌ Failed to write channel cache:", error)
                    }
                }
            }
        }
        channelCacheSaveWorkItem?.cancel()
        channelCacheSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    // MARK: - Clear
    
    /// Removes channel cache file(s). If either userId or baseURL is nil, removes all channel cache files in Application Support (§0.11).
    static func clearChannelCacheFile(userId: String?, baseURL: String?) {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ZekoChat")
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        if let uid = userId, let base = baseURL, !uid.isEmpty, !base.isEmpty {
            if let url = channelCacheURL(userId: uid, baseURL: base) {
                try? fileManager.removeItem(at: url)
            }
        } else {
            for url in contents where url.lastPathComponent.hasPrefix("channels_cache_") && url.pathExtension == "json" {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
