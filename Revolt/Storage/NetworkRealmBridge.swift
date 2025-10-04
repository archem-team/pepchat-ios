//
//  NetworkRealmBridge.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types
import OSLog

actor NetworkRealmBridge {
    
    static let shared = NetworkRealmBridge()
    private init() {}
    
    private let logger = Logger(subsystem: "Revolt", category: "NetworkRealmBridge")
    
    // MARK: - WebSocket Ready Event
    
    func saveReadyEvent(users: [Types.User], servers: [Types.Server], channels: [Types.Channel], members: [Types.Member], emojis: [Types.Emoji]) async {
        logger.info("Saving WebSocket ready event to Realm...")
        logger.info("   - Users: \(users.count)")
        logger.info("   - Servers: \(servers.count)")
        logger.info("   - Channels: \(channels.count)")
        logger.info("   - Members: \(members.count)")
        logger.info("   - Emojis: \(emojis.count)")
        
        do {
            let realm = try await Realm()
            
            let usersRealm = users.map { $0.toRealm() }
            let serversRealm = servers.map { $0.toRealm() }
            let channelsRealm = channels.map { $0.toRealm() }
            let membersRealm = members.map { $0.toRealm() }
            let emojisRealm = emojis.map { $0.toRealm() }
            
            try await realm.asyncWrite {
                realm.add(usersRealm, update: .modified)
                realm.add(serversRealm, update: .modified)
                realm.add(channelsRealm, update: .modified)
                realm.add(membersRealm, update: .modified)
                realm.add(emojisRealm, update: .modified)
            }
            
            logger.info("Ready event saved to Realm successfully")
        } catch {
            logger.error("Failed to save ready event: \(error.localizedDescription)")
        }
    }
    
    // MARK: - User Operations
    
    func saveUser(_ user: Types.User) async {
        do {
            let realm = try await Realm()
            let userRealm = user.toRealm()
            
            try await realm.asyncWrite {
                realm.add(userRealm, update: .modified)
            }
            
            logger.debug("User saved: \(user.id)")
        } catch {
            logger.error("Failed to save user \(user.id): \(error.localizedDescription)")
        }
    }
    
    func saveUsers(_ users: [Types.User]) async {
        guard !users.isEmpty else { return }
        
        do {
            let realm = try await Realm()
            let usersRealm = users.map { $0.toRealm() }
            
            try await realm.asyncWrite {
                realm.add(usersRealm, update: .modified)
            }
            
            logger.debug("Saved \(users.count) users")
        } catch {
            logger.error("Failed to save users: \(error.localizedDescription)")
        }
    }
    
    func deleteUser(id: String) async {
        do {
            let realm = try await Realm()
            
            if let user = realm.object(ofType: UserRealm.self, forPrimaryKey: id) {
                try await realm.asyncWrite {
                    realm.delete(user)
                }
                logger.debug("User deleted: \(id)")
            }
        } catch {
            logger.error("Failed to delete user \(id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Message Operations
    
    func saveMessage(_ message: Types.Message) async {
        do {
            let realm = try await Realm()
            let messageRealm = message.toRealm()
            
            try await realm.asyncWrite {
                realm.add(messageRealm, update: .modified)
            }
            
            logger.debug("Message saved: \(message.id)")
        } catch {
            logger.error("Failed to save message \(message.id): \(error.localizedDescription)")
        }
    }
    
    func saveMessages(_ messages: [Types.Message]) async {
        guard !messages.isEmpty else { return }
        
        do {
            let realm = try await Realm()
            let messagesRealm = messages.map { $0.toRealm() }
            
            try await realm.asyncWrite {
                realm.add(messagesRealm, update: .modified)
            }
            
            logger.debug("Saved \(messages.count) messages")
        } catch {
            logger.error("Failed to save messages: \(error.localizedDescription)")
        }
    }
    
    func deleteMessage(id: String) async {
        do {
            let realm = try await Realm()
            
            if let message = realm.object(ofType: MessageRealm.self, forPrimaryKey: id) {
                try await realm.asyncWrite {
                    realm.delete(message)
                }
                logger.debug("Message deleted: \(id)")
            }
        } catch {
            logger.error("Failed to delete message \(id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Channel Operations
    
    func saveChannel(_ channel: Types.Channel) async {
        do {
            let realm = try await Realm()
            let channelRealm = channel.toRealm()
            
            try await realm.asyncWrite {
                realm.add(channelRealm, update: .modified)
            }
            
            logger.debug("Channel saved: \(channel.id)")
        } catch {
            logger.error("Failed to save channel \(channel.id): \(error.localizedDescription)")
        }
    }
    
    func saveChannels(_ channels: [Types.Channel]) async {
        guard !channels.isEmpty else { return }
        
        do {
            let realm = try await Realm()
            let channelsRealm = channels.map { $0.toRealm() }
            
            try await realm.asyncWrite {
                realm.add(channelsRealm, update: .modified)
            }
            
            logger.debug("Saved \(channels.count) channels")
        } catch {
            logger.error("Failed to save channels: \(error.localizedDescription)")
        }
    }
    
    func deleteChannel(id: String) async {
        do {
            let realm = try await Realm()
            
            if let channel = realm.object(ofType: ChannelRealm.self, forPrimaryKey: id) {
                try await realm.asyncWrite {
                    realm.delete(channel)
                }
                logger.debug("Channel deleted: \(id)")
            }
        } catch {
            logger.error("Failed to delete channel \(id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Server Operations
    
    func saveServer(_ server: Types.Server) async {
        do {
            let realm = try await Realm()
            let serverRealm = server.toRealm()
            
            try await realm.asyncWrite {
                realm.add(serverRealm, update: .modified)
            }
            
            logger.debug("Server saved: \(server.id)")
        } catch {
            logger.error("Failed to save server \(server.id): \(error.localizedDescription)")
        }
    }
    
    func saveServers(_ servers: [Types.Server]) async {
        guard !servers.isEmpty else { return }
        
        do {
            let realm = try await Realm()
            let serversRealm = servers.map { $0.toRealm() }
            
            try await realm.asyncWrite {
                realm.add(serversRealm, update: .modified)
            }
            
            logger.debug("Saved \(servers.count) servers")
        } catch {
            logger.error("Failed to save servers: \(error.localizedDescription)")
        }
    }
    
    func deleteServer(id: String) async {
        do {
            let realm = try await Realm()
            
            if let server = realm.object(ofType: ServerRealm.self, forPrimaryKey: id) {
                try await realm.asyncWrite {
                    realm.delete(server)
                }
                logger.debug("Server deleted: \(id)")
            }
        } catch {
            logger.error("Failed to delete server \(id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Member Operations
    
    func saveMember(_ member: Types.Member) async {
        do {
            let realm = try await Realm()
            let memberRealm = member.toRealm()
            
            try await realm.asyncWrite {
                realm.add(memberRealm, update: .modified)
            }
            
            logger.debug("Member saved: \(member.id.user) in server \(member.id.server)")
        } catch {
            logger.error("Failed to save member: \(error.localizedDescription)")
        }
    }
    
    func saveMembers(_ members: [Types.Member]) async {
        guard !members.isEmpty else { return }
        
        do {
            let realm = try await Realm()
            let membersRealm = members.map { $0.toRealm() }
            
            try await realm.asyncWrite {
                realm.add(membersRealm, update: .modified)
            }
            
            logger.debug("Saved \(members.count) members")
        } catch {
            logger.error("Failed to save members: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Emoji Operations
    
    func saveEmoji(_ emoji: Types.Emoji) async {
        do {
            let realm = try await Realm()
            let emojiRealm = emoji.toRealm()
            
            try await realm.asyncWrite {
                realm.add(emojiRealm, update: .modified)
            }
            
            logger.debug("Emoji saved: \(emoji.id)")
        } catch {
            logger.error("Failed to save emoji \(emoji.id): \(error.localizedDescription)")
        }
    }
    
    func saveEmojis(_ emojis: [Types.Emoji]) async {
        guard !emojis.isEmpty else { return }
        
        do {
            let realm = try await Realm()
            let emojisRealm = emojis.map { $0.toRealm() }
            
            try await realm.asyncWrite {
                realm.add(emojisRealm, update: .modified)
            }
            
            logger.debug("Saved \(emojis.count) emojis")
        } catch {
            logger.error("Failed to save emojis: \(error.localizedDescription)")
        }
    }
    
    func deleteEmoji(id: String) async {
        do {
            let realm = try await Realm()
            
            if let emoji = realm.object(ofType: EmojiRealm.self, forPrimaryKey: id) {
                try await realm.asyncWrite {
                    realm.delete(emoji)
                }
                logger.debug("Emoji deleted: \(id)")
            }
        } catch {
            logger.error("Failed to delete emoji \(id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Batch Operations
    
    func clearAllData() async {
        do {
            let realm = try await Realm()
            
            try await realm.asyncWrite {
                realm.deleteAll()
            }
            
            logger.info("All Realm data cleared")
        } catch {
            logger.error("Failed to clear Realm data: \(error.localizedDescription)")
        }
    }
}

