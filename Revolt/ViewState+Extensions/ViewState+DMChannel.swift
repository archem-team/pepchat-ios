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
            servers.removeValue(forKey: serverID)
            selectDms()
        }
    }
    
    @MainActor
    func removeChannel(with channelID : String, initPath: Bool = true){
        if(initPath){
            self.path = .init()
            selectDms()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            //TODO
            self.channels.removeValue(forKey: channelID)
            self.dms = self.dms.filter { $0.id != channelID }
        }
        
    }
}
