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
            notifyViewStateMessagesChanged()
            
        case .update(let results, let deletions, let insertions, let modifications):
            messages = Array(results)
            notifyViewStateMessagesChanged()
            
        case .error(let error):
            break
        }
    }
    
    private func notifyViewStateMessagesChanged() {
        let convertedMessages = self.messages.compactMap { $0.toOriginal() as Types.Message? }
        let messagesDictionary = Dictionary(uniqueKeysWithValues: convertedMessages.map { ($0.id, $0) })
        self.viewState?.updateMessagesFromDatabase(messagesDictionary)
        
        // POST NOTIFICATION FOR UI - Reactive architecture
        NotificationCenter.default.post(
            name: NSNotification.Name("DatabaseMessagesUpdated"),
            object: nil
        )
        
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

// MARK: - ViewState Update Methods

extension ViewState {
    func updateUsersFromDatabase(_ users: [String: Types.User]) {
        for (id, user) in users {
            self.users[id] = user
            self.allEventUsers[id] = user
        }
    }
    
    func updateMessagesFromDatabase(_ messages: [String: Types.Message]) {
        for (id, message) in messages {
            self.messages[id] = message
            
            if var channelMsgs = self.channelMessages[message.channel] {
                if !channelMsgs.contains(id) {
                    channelMsgs.append(id)
                    self.channelMessages[message.channel] = channelMsgs
                }
            } else {
                self.channelMessages[message.channel] = [id]
            }
        }
    }
    
    func updateChannelsFromDatabase(_ channels: [String: Types.Channel]) {
        for (id, channel) in channels {
            self.channels[id] = channel
            
            switch channel {
            case .dm_channel(_), .group_dm_channel(_):
                if !self.dms.contains(where: { $0.id == id }) {
                    self.dms.append(channel)
                }
            default:
                break
            }
        }
    }
    
    func updateServersFromDatabase(_ servers: [String: Types.Server]) {
        for (id, server) in servers {
            self.servers[id] = server
        }
    }
    
    func updateMembersFromDatabase(_ membersByServer: [String: [String: Types.Member]]) {
        for (serverId, serverMembers) in membersByServer {
            if self.members[serverId] == nil {
                self.members[serverId] = [:]
            }
            
            for (userId, member) in serverMembers {
                self.members[serverId]?[userId] = member
            }
        }
    }
}
