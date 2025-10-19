//
//  DatabaseObserver.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import SwiftUI
import Types

/// DatabaseObserver manages Realm database listeners and notifies ViewState of changes
@MainActor
class DatabaseObserver: ObservableObject {
    
    // MARK: - Properties
    
    private var tokens: [NotificationToken] = []
    
    weak var viewState: ViewState?
    
    @Published var users: [UserRealm] = []
    @Published var messages: [MessageRealm] = []
    @Published var channels: [ChannelRealm] = []
    @Published var servers: [ServerRealm] = []
    @Published var friends: [UserRealm] = []
    @Published var members: [MemberRealm] = []
    
    private let processingQueue = DispatchQueue(label: "com.revolt.database.observer", qos: .utility)
    
    // MARK: - Initialization
    
    init(viewState: ViewState?) {
        self.viewState = viewState
        setupObservers()
    }
    
    deinit {
        tokens.forEach { $0.invalidate() }
        tokens.removeAll()
    }
    
    // MARK: - Observer Setup
    
    private func setupObservers() {
        
        Task {
            await observeUsers()
            await observeMessages() 
            await observeChannels()
            await observeServers()
            
        }
    }
    
    // MARK: - User Observation
    
    private func observeUsers() async {
        do {
            let realm = try await Realm()
            let users = realm.objects(UserRealm.self)
            
            
            let token = users.observe { [weak self] changes in
                Task { @MainActor in
                    await self?.handleUsersChange(changes)
                }
            }
            
            tokens.append(token)
            
            await MainActor.run {
                self.users = Array(users)
            }
            
        } catch {
        }
    }
    
    private func handleUsersChange(_ changes: RealmCollectionChange<Results<UserRealm>>) async {
        switch changes {
        case .initial(let results):
            users = Array(results)
            notifyViewStateUsersChanged()
            
        case .update(let results, let deletions, let insertions, let modifications):
            users = Array(results)
            notifyViewStateUsersChanged()
            
        case .error(let error):
			break
        }
    }
    
    private func notifyViewStateUsersChanged() {
        let convertedUsers = self.users.compactMap { $0.toOriginal() as Types.User? }
        let usersDictionary = Dictionary(uniqueKeysWithValues: convertedUsers.map { ($0.id, $0) })
        self.viewState?.updateUsersFromDatabase(usersDictionary)
    }
    
    // MARK: - Message Observation
    
    private func observeMessages() async {
        do {
            let realm = try await Realm()
            let messages = realm.objects(MessageRealm.self)
            
            
            let token = messages.observe { [weak self] changes in
                Task { @MainActor in
                    await self?.handleMessagesChange(changes)
                }
            }
            
            tokens.append(token)
            
            await MainActor.run {
                self.messages = Array(messages)
            }
            
        } catch {
        }
    }
    
    private func handleMessagesChange(_ changes: RealmCollectionChange<Results<MessageRealm>>) async {
        switch changes {
        case .initial(let results):
            messages = Array(results)
            notifyViewStateMessagesChanged(affectedChannelIds: Array(Set(messages.map { $0.channel })))
            
        case .update(let results, let deletions, let insertions, let modifications):
            messages = Array(results)
            // Compute affected channelIds using indexes
            var channelIds = Set<String>()
            for index in deletions {
                if index < results.count { channelIds.insert(results[index].channel) }
            }
            for index in insertions {
                if index < results.count { channelIds.insert(results[index].channel) }
            }
            for index in modifications {
                if index < results.count { channelIds.insert(results[index].channel) }
            }
            notifyViewStateMessagesChanged(affectedChannelIds: Array(channelIds))
            
        case .error(let error):
            break
        }
    }
    
    private func notifyViewStateMessagesChanged(affectedChannelIds: [String]) {
        let convertedMessages = self.messages.compactMap { $0.toOriginal() as Types.Message? }
        let messagesDictionary = Dictionary(uniqueKeysWithValues: convertedMessages.map { ($0.id, $0) })
        self.viewState?.updateMessagesFromDatabase(messagesDictionary)
        
        // POST NOTIFICATION FOR UI - Reactive architecture
        // Explicitly dispatch to main thread to ensure observers receive it
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("DatabaseMessagesUpdated"),
                object: nil,
                userInfo: ["channelIds": affectedChannelIds]
            )
        }
    }
    
    // MARK: - Channel Observation
    
    private func observeChannels() async {
        do {
            let realm = try await Realm()
            let channels = realm.objects(ChannelRealm.self)
            
            
            let token = channels.observe { [weak self] changes in
                Task { @MainActor in
                    await self?.handleChannelsChange(changes)
                }
            }
            
            tokens.append(token)
            
            await MainActor.run {
                self.channels = Array(channels)
            }
            
        } catch {
        }
    }
    
    private func handleChannelsChange(_ changes: RealmCollectionChange<Results<ChannelRealm>>) async {
        switch changes {
        case .initial(let results):
            channels = Array(results)
            notifyViewStateChannelsChanged()
            
        case .update(let results, let deletions, let insertions, let modifications):
            channels = Array(results)
            notifyViewStateChannelsChanged()
            
        case .error(let error):
            break
        }
    }
    
    private func notifyViewStateChannelsChanged() {
        let convertedChannels = self.channels.compactMap { $0.toOriginal() as Types.Channel? }
        let channelsDictionary = Dictionary(uniqueKeysWithValues: convertedChannels.map { ($0.id, $0) })
        self.viewState?.updateChannelsFromDatabase(channelsDictionary)
    }
    
    // MARK: - Server Observation
    
    private func observeServers() async {
        do {
            let realm = try await Realm()
            let servers = realm.objects(ServerRealm.self)
            
            
            let token = servers.observe { [weak self] changes in
                Task { @MainActor in
                    await self?.handleServersChange(changes)
                }
            }
            
            tokens.append(token)
            
            await MainActor.run {
                self.servers = Array(servers)
            }
            
        } catch {
        }
    }
    
    private func handleServersChange(_ changes: RealmCollectionChange<Results<ServerRealm>>) async {
        switch changes {
        case .initial(let results):
            servers = Array(results)
            notifyViewStateServersChanged()
            
        case .update(let results, let deletions, let insertions, let modifications):
            servers = Array(results)
            notifyViewStateServersChanged()
            
        case .error(let error):
			break
        }
    }
    
    private func notifyViewStateServersChanged() {
        let convertedServers = self.servers.compactMap { $0.toOriginal() as Types.Server? }
        let serversDictionary = Dictionary(uniqueKeysWithValues: convertedServers.map { ($0.id, $0) })
        self.viewState?.updateServersFromDatabase(serversDictionary)
    }
    
    // MARK: - Friends Observer
    
    private func observeFriends() async {
        
        do {
            let realm = try await Realm()
            let results = realm.objects(UserRealm.self)
                .filter("relationship == 'Friend' OR relationship == 'Incoming' OR relationship == 'Outgoing' OR relationship == 'Blocked' OR relationship == 'BlockedOther'")
            
            let token = results.observe { [weak self] changes in
                Task { @MainActor in
                    self?.handleFriendsChanges(changes)
                }
            }
            
            tokens.append(token)
            
            // Initial load
            await MainActor.run {
                self.friends = Array(results)
                self.notifyViewStateFriendsChanged()
            }
            
            
        } catch {
        }
    }
    
    private func handleFriendsChanges(_ changes: RealmCollectionChange<Results<UserRealm>>) {
        switch changes {
        case .initial(let results):
            self.friends = Array(results)
            self.notifyViewStateFriendsChanged()
            
        case .update(let results, let deletions, let insertions, let modifications):
            self.friends = Array(results)
            self.notifyViewStateFriendsChanged()
            
        case .error(let error):
            break
        }
    }
    
    private func notifyViewStateFriendsChanged() {
        let convertedFriends = self.friends.compactMap { $0.toOriginal() as Types.User? }
        let friendsDictionary = Dictionary(uniqueKeysWithValues: convertedFriends.map { ($0.id, $0) })
        self.viewState?.updateUsersFromDatabase(friendsDictionary)
    }
    
    // MARK: - Members Observer
    
    private func observeMembers() async {
        
        do {
            let realm = try await Realm()
            let results = realm.objects(MemberRealm.self)
            
            let token = results.observe { [weak self] changes in
                Task { @MainActor in
                    self?.handleMembersChanges(changes)
                }
            }
            
            tokens.append(token)
            
            // Initial load
            await MainActor.run {
                self.members = Array(results)
                self.notifyViewStateMembersChanged()
            }
            
            
        } catch {
        }
    }
    
    private func handleMembersChanges(_ changes: RealmCollectionChange<Results<MemberRealm>>) {
        switch changes {
        case .initial(let results):
            self.members = Array(results)
            self.notifyViewStateMembersChanged()
            
        case .update(let results, let deletions, let insertions, let modifications):
            self.members = Array(results)
            self.notifyViewStateMembersChanged()
            
        case .error(let error):
            break
        }
    }
    
    private func notifyViewStateMembersChanged() {
        let convertedMembers = self.members.compactMap { $0.toOriginal() as Types.Member? }
        
        // Group members by server
        var membersByServer: [String: [String: Types.Member]] = [:]
        for member in convertedMembers {
            let serverId = member.id.server
            let userId = member.id.user
            
            if membersByServer[serverId] == nil {
                membersByServer[serverId] = [:]
            }
            membersByServer[serverId]?[userId] = member
        }
        
        self.viewState?.updateMembersFromDatabase(membersByServer)
    }
    
    // MARK: - Public Methods
    
    func refreshAllObservers() {
        
        Task {
            await observeUsers()
            await observeMessages()
            await observeChannels()
            await observeServers()
            await observeFriends()
            await observeMembers()
        }
    }
    
    func getObserverStats() -> (users: Int, messages: Int, channels: Int, servers: Int, friends: Int, members: Int) {
        return (
            users: users.count,
            messages: messages.count,
            channels: channels.count,
            servers: servers.count,
            friends: friends.count,
            members: members.count
        )
    }
}

// MARK: - ViewState Update Methods (DATABASE-FIRST ARCHITECTURE)
// ViewState update methods removed - data no longer accumulated in singleton
// Views now load data directly from repositories on-demand
// DatabaseObserver only posts NotificationCenter notifications for reactive updates

extension ViewState {
    func updateUsersFromDatabase(_ users: [String: Types.User]) {
        // DATABASE-FIRST: Don't accumulate in ViewState
        // Views will load users directly from UserRepository when needed
        // Post notification for any views that need to react
        NotificationCenter.default.post(
            name: NSNotification.Name("DatabaseUsersUpdated"),
            object: nil,
            userInfo: ["userIds": Array(users.keys)]
        )
    }
    
    func updateMessagesFromDatabase(_ messages: [String: Types.Message]) {
        // DATABASE-FIRST: Don't accumulate in ViewState
        // ChannelDataManager will load messages from MessageRepository
        // Post notification already handled in notifyViewStateMessagesChanged()
    }
    
    func updateChannelsFromDatabase(_ channels: [String: Types.Channel]) {
        // DATABASE-FIRST: Only store channels temporarily for navigation
        // Full channel data loaded from ChannelRepository when needed
        for (id, channel) in channels {
            self.channels[id] = channel
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("DatabaseChannelsUpdated"),
            object: nil
        )
    }
    
    func updateServersFromDatabase(_ servers: [String: Types.Server]) {
        // DATABASE-FIRST: Only store servers temporarily for navigation
        for (id, server) in servers {
            self.servers[id] = server
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("DatabaseServersUpdated"),
            object: nil
        )
    }
    
    func updateMembersFromDatabase(_ membersByServer: [String: [String: Types.Member]]) {
        // DATABASE-FIRST: Don't accumulate members
        // Load from MemberRepository when needed
        NotificationCenter.default.post(
            name: NSNotification.Name("DatabaseMembersUpdated"),
            object: nil
        )
    }
}
