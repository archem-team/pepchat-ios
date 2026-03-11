//
//  ViewState+DMChannel.swift
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
    /// Sets the `active` property of a DMChannel with the given ID to `false`.
    /// - Parameter id: The ID of the channel to update.
    func deactivateDMChannel(with id: String) {
        Task { @MainActor in
            if let index = dms.firstIndex(where: {
                if case let .dm_channel(dmChannel) = $0 {
                    return dmChannel.id == id && dmChannel.active
                }
                return false
            }) {
                if case var .dm_channel(dmChannel) = dms[index] {
                    // Update the active state to false
                    dmChannel.active = false
                    dms[index] = .dm_channel(dmChannel) // Update the channel in the list
                }
            }
        }
    }
    
    /// Closes the DM group by calling an API and deactivating the DM channel in the `dms` list.
    /// - Parameter channelId: The ID of the channel to close.
    func closeDMGroup(channelId: String) async {
        do {
            // Call the API to close the DM group
            let _ = try await self.http.closeDMGroup(channelId: channelId).get()
            
            // Deactivate the DM channel in the list
            await MainActor.run {
                self.deactivateDMChannel(with: channelId)
            }
        } catch let error {
            print("Error closing DM group: \(error)")
        }
    }
    
    
    func isCurrentUserOwner(of serverID: String) -> Bool {
        guard let currentUser = currentUser else {
            return false
        }
        
        guard let server = servers[serverID] else {
            return false
        }
        
        return server.owner == currentUser.id
    }
    
    
    func removeServer(with serverID: String) {
        Task { @MainActor in
            // Channel.md §9.10: Full purge for that server (§0.30)
            guard let server = servers[serverID] else {
                updateMembershipCache(serverId: serverID, isMember: false)
                selectDms()
                return
            }
            for channelId in server.channels {
                channels.removeValue(forKey: channelId)
                channelMessages.removeValue(forKey: channelId)
                unreads.removeValue(forKey: channelId)
                preloadedChannels.remove(channelId)
                allEventChannels.removeValue(forKey: channelId)
            }
            loadedServerChannels.remove(serverID)
            if case .channel(let id) = currentChannel, server.channels.contains(id) {
                path = []
                currentChannel = .home
            }
            servers.removeValue(forKey: serverID)
            updateMembershipCache(serverId: serverID, isMember: false)
            saveChannelCacheAsync()
            saveServersCacheAsync()
            selectDms()
        }
    }
    
    @MainActor
    func removeChannel(with channelID: String, initPath: Bool = true) {
        // Channel.md §9.8: If server channel, sync-remove from server graph, allEventChannels, channelMessages, unreads, preloadedChannels; enqueue save; delayed for channels, dms, path, selectDms()
        let channelObj = allEventChannels[channelID] ?? channels[channelID]
        if let serverId = channelObj?.server, var server = servers[serverId] {
            server.channels.removeAll { $0 == channelID }
            if var cats = server.categories {
                for i in cats.indices {
                    cats[i].channels.removeAll { $0 == channelID }
                }
                server.categories = cats
            }
            servers[serverId] = server
            allEventChannels.removeValue(forKey: channelID)
            channelMessages.removeValue(forKey: channelID)
            unreads.removeValue(forKey: channelID)
            preloadedChannels.remove(channelID)
            saveChannelCacheAsync()
            saveServersCacheAsync()
        }
        if initPath {
            path = .init()
            selectDms()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.channels.removeValue(forKey: channelID)
            self.dms = self.dms.filter { $0.id != channelID }
        }
    }
}
