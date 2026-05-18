//
//  ViewState+ShareIndex.swift
//  Revolt
//
//  Builds a compact recipient index for the iOS Share Extension.
//

import Foundation
import Collections
@preconcurrency import Types

extension ViewState {
    func saveShareRecipientIndexAsync() {
        guard let currentUserId = currentUser?.id, let baseURL else { return }

        let snapshot = makeShareRecipientIndex(userId: currentUserId, baseURL: baseURL)
        DispatchQueue.global(qos: .utility).async {
            ShareStorage.saveRecipientIndex(snapshot)
        }
    }

    func clearShareExtensionData() {
        ShareStorage.clearShareData()
    }

    private func makeShareRecipientIndex(userId: String, baseURL: String) -> ShareRecipientIndex {
        let dmChannels = allDmChannelIds.compactMap { channels[$0] ?? allEventChannels[$0] }
        let directDms = dmChannels.compactMap { makeDirectShareDestination(from: $0, currentUserId: userId) }
        let dms = directDms + makeFriendShareDestinations(currentUserId: userId, dmChannels: dmChannels)
        let groupDms = dmChannels.compactMap { makeGroupShareDestination(from: $0) }
        let serverDestinations = servers.values.compactMap { makeServerShareDestination(from: $0) }

        return ShareRecipientIndex(
            schemaVersion: AttachmentSharingConstants.shareIndexSchemaVersion,
            userId: userId,
            baseURL: baseURL,
            generatedAt: Date(),
            recentChannelIds: recentShareChannelIds(from: dmChannels, servers: serverDestinations),
            dms: dms,
            groupDms: groupDms,
            servers: serverDestinations
        )
    }

    private func makeDirectShareDestination(from channel: Channel, currentUserId: String) -> ShareDestination? {
        guard case .dm_channel(let dm) = channel, dm.active else { return nil }
        let otherUserId = dm.recipients.first { $0 != currentUserId } ?? dm.recipients.first
        let user = otherUserId.flatMap { users[$0] ?? allEventUsers[$0] }
        let title = user?.displayName() ?? "Direct Message"
        return ShareDestination(
            id: dm.id,
            title: title,
            subtitle: "Direct Message",
            avatarFileName: nil,
            type: .directMessage,
            canSendMessages: true,
            canUploadFiles: true,
            lastMessageId: dm.last_message_id,
            openUserId: nil
        )
    }

    private func makeFriendShareDestinations(currentUserId: String, dmChannels: [Channel]) -> [ShareDestination] {
        let dmRecipientIds = Set(dmChannels.compactMap { channel -> String? in
            guard case .dm_channel(let dm) = channel else { return nil }
            return dm.recipients.first { $0 != currentUserId }
        })

        return users.values
            .filter { user in
                user.id != currentUserId &&
                user.relationship == .Friend &&
                !dmRecipientIds.contains(user.id)
            }
            .sorted { $0.displayName().localizedCaseInsensitiveCompare($1.displayName()) == .orderedAscending }
            .map { user in
                ShareDestination(
                    id: user.id,
                    title: user.displayName(),
                    subtitle: "Friend",
                    avatarFileName: nil,
                    type: .directMessage,
                    canSendMessages: true,
                    canUploadFiles: true,
                    lastMessageId: nil,
                    openUserId: user.id
                )
            }
    }

    private func makeGroupShareDestination(from channel: Channel) -> ShareDestination? {
        guard case .group_dm_channel(let group) = channel else { return nil }
        return ShareDestination(
            id: group.id,
            title: group.name,
            subtitle: "\(group.recipients.count) members",
            avatarFileName: nil,
            type: .groupDM,
            canSendMessages: true,
            canUploadFiles: true,
            lastMessageId: group.last_message_id,
            openUserId: nil
        )
    }

    private func makeServerShareDestination(from server: Server) -> ShareServerDestination? {
        let channelDestinations = server.channels.compactMap { channelId -> ShareDestination? in
            guard let channel = allEventChannels[channelId] ?? channels[channelId],
                  case .text_channel(let textChannel) = channel
            else { return nil }

            return ShareDestination(
                id: textChannel.id,
                title: "# \(textChannel.name)",
                subtitle: server.name,
                avatarFileName: nil,
                type: .serverChannel,
                canSendMessages: true,
                canUploadFiles: true,
                lastMessageId: textChannel.last_message_id,
                openUserId: nil
            )
        }

        guard !channelDestinations.isEmpty else { return nil }
        return ShareServerDestination(
            id: server.id,
            title: server.name,
            iconFileName: nil,
            channels: channelDestinations
        )
    }

    private func recentShareChannelIds(from dms: [Channel], servers: [ShareServerDestination]) -> [String] {
        let dmIds = dms
            .sorted { ($0.last_message_id ?? "") > ($1.last_message_id ?? "") }
            .prefix(8)
            .map(\.id)
        let serverIds = servers
            .flatMap(\.channels)
            .sorted { ($0.lastMessageId ?? "") > ($1.lastMessageId ?? "") }
            .prefix(4)
            .map(\.id)
        return Array((dmIds + serverIds).prefix(12))
    }
}
