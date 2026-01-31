//
//  ViewState+ServerCache.swift
//  Revolt
//
//  Created by Akshat Srivastava on 31/01/26.
//

import Foundation
import Combine
import SwiftUI
import Alamofire
import ULID
import Collections
import Sentry
@preconcurrency import Types
import UserNotifications
import KeychainAccess
import Darwin
import Network

extension ViewState {
    
    // Defining the path of the cache and type of the cache
    static func serversCacheURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ZekoChat")
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create Application Support directory:", error)
            return nil
        }
        return dir.appendingPathComponent("servers_cache.json")
    }
    
    // Load the cache when app boots up
    static func loadServersCacheSync() -> OrderedDictionary <String, Server> {
        guard let url = serversCacheURL(), FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        do {
            let data  = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(OrderedDictionary<String, Server>.self, from: data)
        } catch {
            print("❌ Failed to load servers cache:", error)
            return [:]
        }
    }
    
    func saveServersCacheAsync() {
        let serversSnapshot = self.servers
        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(serversSnapshot)
                if let url = await ViewState.serversCacheURL() {
                    try data.write(to: url, options: .atomic)
                    print("✅ Saved servers cache to \(url.path)")
                }
            } catch {
                print("❌ Failed to write servers cache:", error)
            }
        }
    }
    
    
    func applyServerOrdering() {
        let ordering = self.userSettingsStore.cache.orderSettings.servers
        let allServers = Array(self.servers.values)

        let serverDict = Dictionary(uniqueKeysWithValues: allServers.map { ($0.id, $0) })
        let orderedServers = ordering.compactMap { serverDict[$0] }
        let remainingServers = allServers.filter { !ordering.contains($0.id) }

        let finalServers = orderedServers + remainingServers

        // Update `servers` preserving key-value order
        var newServers = OrderedDictionary<String, Server>()
        for server in finalServers {
            newServers[server.id] = server
        }
        self.servers = newServers
    }
}
