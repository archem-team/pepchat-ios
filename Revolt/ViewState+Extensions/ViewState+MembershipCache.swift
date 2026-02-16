//
//  ViewState+MembershipCache.swift
//  Revolt
//
//  Discover server membership cache: JSON-backed cache so the Discover screen
//  shows last known state instantly on launch and stays in sync when the user
//  joins/leaves servers from this device or from web/Android (via WebSocket).
//

import Foundation
@preconcurrency import Types

extension ViewState {

    /// URL for the membership cache file (Application Support / membership_cache.json).
    static func membershipCacheURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ZekoChat")
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("❌ [MembershipCache] Failed to create Application Support directory:", error)
            return nil
        }
        return dir.appendingPathComponent("membership_cache.json")
    }

    /// Load membership cache synchronously on app launch for instant Discover UI.
    static func loadMembershipCacheSync() -> [String: Bool] {
        guard let url = membershipCacheURL(), FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: Bool].self, from: data)
            // Debug: print membership cache JSON (serverId -> isMember for Discover green tick)
            if let prettyData = try? JSONSerialization.data(withJSONObject: decoded, options: .prettyPrinted),
               let jsonString = String(data: prettyData, encoding: .utf8) {
                print("📋 [MembershipCache] Discover membership cache JSON:\n\(jsonString)")
            }
            return decoded
        } catch {
            print("❌ [MembershipCache] Failed to load:", error)
            return [:]
        }
    }

    /// Persist current in-memory membership cache to disk (background).
    func saveMembershipCacheAsync() {
        let snapshot = discoverMembershipCache
        Task.detached(priority: .background) { [snapshot] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                if let url = await ViewState.membershipCacheURL() {
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                print("❌ [MembershipCache] Failed to write:", error)
            }
        }
    }

    /// Persist current in-memory cache to disk synchronously. Use for leave events so the update is not lost.
    func saveMembershipCacheSync() {
        guard let url = ViewState.membershipCacheURL() else { return }
        do {
            let data = try JSONEncoder().encode(discoverMembershipCache)
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ [MembershipCache] Failed to write (sync):", error)
        }
    }

    /// Update a single server’s membership. Optionally persist to disk.
    /// - Parameters:
    ///   - serverId: Server ID.
    ///   - isMember: Whether the current user is a member.
    ///   - persist: If true (default), write to disk. Set to false when updating from the async Discover fetch so we never persist partial/incomplete data. Only authoritative join/leave events should persist.
    func updateMembershipCache(serverId: String, isMember: Bool, persist: Bool = true) {
        var next = discoverMembershipCache
        next[serverId] = isMember
        discoverMembershipCache = next
        guard persist else { return }
        if isMember {
            saveMembershipCacheAsync()
        } else {
            saveMembershipCacheSync()
        }
    }
}
