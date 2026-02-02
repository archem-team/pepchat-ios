//
//  ViewState+Navigation.swift
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
    
    func selectServer(withId id: String) {
        // Unload previous server's channels if switching servers
        if case .server(let previousServerId) = currentSelection, previousServerId != id {
            unloadServerChannels(serverId: previousServerId)
        }
        
        currentSelection = .server(id)
        
        // LAZY LOADING: Load channels for this server
        loadServerChannels(serverId: id)
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // PERFORMANCE: Start preloading messages for this server's channels
            preloadMessagesForServer(serverId: id)
            
            // ENHANCED: Also trigger smart preloading for important channels
            Task {
                await preloadImportantChannels()
            }
            print("🚀 PRELOAD_ENABLED: Started automatic preloading for server \(id)")
        } else {
            print("📵 PRELOAD_DISABLED: Skipped automatic preloading for server \(id) channels")
        }
        
        if let last = userSettingsStore.store.lastOpenChannels[id] {
            currentChannel = .channel(last)
        } else if let server = servers[id] {
            if let firstChannel = server.channels.compactMap({
                switch channels[$0] {
                case .text_channel(let c):
                    return c
                default:
                    return nil
                }
            }).first {
                currentChannel = .channel(firstChannel.id)
            } else {
                currentChannel = .noChannel
            }
        }
    }
    
    func selectChannel(inServer server: String, withId id: String) {
        // Clear messages from previous channel before switching
        if case .channel(let previousChannelId) = currentChannel, previousChannelId != id {
            clearChannelMessages(channelId: previousChannelId)
        }
        
        // CRITICAL FIX: Only clear target message ID if we're navigating to a DIFFERENT channel
        // Don't clear it if we're navigating TO the target channel (from links/replies)
        if let targetId = currentTargetMessageId {
            // If target message is for current channel, keep it; otherwise clear it
            if let targetMessage = messages[targetId], targetMessage.channel != id {
                print("🎯 SELECT_CHANNEL: Clearing currentTargetMessageId - target is for different channel")
                currentTargetMessageId = nil
            } else if messages[targetId] == nil {
                // Target message not loaded yet, assume it might be for this channel - keep it
                print("🎯 SELECT_CHANNEL: Keeping currentTargetMessageId for channel \(id) - target message not loaded yet")
            } else {
                print("🎯 SELECT_CHANNEL: Keeping currentTargetMessageId for target channel \(id)")
            }
        }
        
        currentChannel = .channel(id)
        userSettingsStore.store.lastOpenChannels[server] = id
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // AGGRESSIVE PRELOADING: Immediately preload this channel
            Task {
                await preloadSpecificChannel(channelId: id)
            }
            print("🚀 PRELOAD_ENABLED: Started automatic preloading for selected channel \(id)")
        } else {
            print("📵 PRELOAD_DISABLED: Skipped automatic preloading for selected channel \(id)")
        }
        
        // CRITICAL FIX: Load users for visible messages when entering channel
        loadUsersForVisibleMessages(channelId: id)
    }
    
    func selectDms() {
        DispatchQueue.main.async {
            // Unload current server's channels when switching to DMs
            if case .server(let serverId) = self.currentSelection {
                self.unloadServerChannels(serverId: serverId)
            }
            
            self.currentSelection = .dms
            
            if let last = self.userSettingsStore.store.lastOpenChannels["dms"] {
                self.currentChannel = .channel(last)
            } else {
                // print("🏠 HOME_REDIRECT: Going to home because no last DM channel saved")
                self.currentChannel = .home
            }
            
            // FIX: Reinitialize DM list if it was cleared or not initialized
            if !self.isDmListInitialized || self.dms.isEmpty {
                self.reinitializeDmListFromCache()
            }
            
            // CRITICAL FIX: Load users for visible messages when entering DM view
            if case .channel(let channelId) = self.currentChannel {
                self.loadUsersForVisibleMessages(channelId: channelId)
            }
        }
    }
    
    func selectDiscover() {
        DispatchQueue.main.async {
            // Unload current server's channels when switching to Discover
            if case .server(let serverId) = self.currentSelection {
                self.unloadServerChannels(serverId: serverId)
            }
            
            self.currentSelection = .discover
            self.currentChannel = .home
            
            // Clear navigation path to go back to home/discover view
            self.path.removeAll()
        }
    }
    
    @MainActor
    func selectDm(withId id: String) {
        // Clear messages from previous channel before switching
        if case .channel(let previousChannelId) = self.currentChannel, previousChannelId != id {
            self.clearChannelMessages(channelId: previousChannelId)
        }
        
        // CRITICAL FIX: Only clear target message ID if we're navigating to a DIFFERENT channel
        // Don't clear it if we're navigating TO the target channel (from links/replies)
        if let targetId = currentTargetMessageId {
            // If target message is for current channel, keep it; otherwise clear it
            if let targetMessage = messages[targetId], targetMessage.channel != id {
                print("🎯 SELECT_DM: Clearing currentTargetMessageId - target is for different channel")
                currentTargetMessageId = nil
            } else if messages[targetId] == nil {
                // Target message not loaded yet, assume it might be for this channel - keep it
                print("🎯 SELECT_DM: Keeping currentTargetMessageId for DM \(id) - target message not loaded yet")
            } else {
                print("🎯 SELECT_DM: Keeping currentTargetMessageId for target DM \(id)")
            }
        }
        
        self.currentChannel = .channel(id)
        guard let channel = self.channels[id] else { return }
        
        switch channel {
        case .dm_channel, .group_dm_channel:
            self.userSettingsStore.store.lastOpenChannels["dms"] = id
        default:
            self.userSettingsStore.store.lastOpenChannels.removeValue(forKey: "dms")
            
        }
        
        // CONDITIONAL: Only preload if automatic preloading is enabled
        if enableAutomaticPreloading {
            // AGGRESSIVE PRELOADING: Immediately preload this DM
            Task {
                await preloadSpecificChannel(channelId: id)
            }
            print("🚀 PRELOAD_ENABLED: Started automatic preloading for selected DM \(id)")
        } else {
            print("📵 PRELOAD_DISABLED: Skipped automatic preloading for selected DM \(id)")
        }
        
        // CRITICAL FIX: Load users for visible messages when entering DM
        self.loadUsersForVisibleMessages(channelId: id)
    }
    
    // Handle channel change and memory cleanup
    @MainActor
    internal func handleChannelChange(from previousChannelId: String?, to newChannel: ChannelSelection) {
        // Extract previous channel ID from current channel before change
        let actualPreviousChannelId: String?
        if case .channel(let channelId) = currentChannel {
            actualPreviousChannelId = channelId
        } else {
            actualPreviousChannelId = nil
        }
        
        // Extract new channel ID
        let newChannelId: String?
        if case .channel(let channelId) = newChannel {
            newChannelId = channelId
        } else {
            newChannelId = nil
        }
        
        // Clear messages from previous channel when switching channels
        if let actualPreviousChannelId = actualPreviousChannelId, actualPreviousChannelId != newChannelId {
            // print("🧠 MEMORY: Switching channels from \(actualPreviousChannelId) to \(newChannelId ?? "none")")
            clearChannelMessages(channelId: actualPreviousChannelId)
            
            // CRITICAL: Clear target message ID when switching channels to prevent re-targeting
            print("🎯 CHANNEL_CHANGE: Clearing currentTargetMessageId when switching channels")
            currentTargetMessageId = nil
        }
        
        // Update previous channel ID for next time
        self.previousChannelId = newChannelId
    }
    
    // Handle path changes to detect when leaving channel view
    @MainActor
    internal func handlePathChange(oldPath: [NavigationDestination], newPath: [NavigationDestination]) {
        let wasInChannelView = oldPath.contains { destination in
            if case .maybeChannelView = destination {
                return true
            }
            return false
        }
        
        let isInChannelView = newPath.contains { destination in
            if case .maybeChannelView = destination {
                return true
            }
            return false
        }
        
        // Clear messages when leaving channel view to free memory
        if wasInChannelView && !isInChannelView {
            if case .channel(let channelId) = currentChannel {
                // print("🧠 MEMORY: Left channel view, clearing messages for channel: \(channelId) to free memory")
                clearChannelMessages(channelId: channelId)
            }
        }
        
        // If we're entering channel view, check if we need to show loading
        if !wasInChannelView && isInChannelView {
            if case .channel(let channelId) = currentChannel {
                let hasMessages = (channelMessages[channelId]?.count ?? 0) > 0
                if !hasMessages {
                    // print("🧠 LOADING: Entering channel with no messages, showing loading state")
                    setChannelLoadingState(isLoading: true)
                }
            }
        }
    }
    
}
