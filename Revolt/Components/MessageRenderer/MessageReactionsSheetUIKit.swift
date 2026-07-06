//
//  MessageReactionsSheetUIKit.swift
//  Revolt
//
//  Created by Akshat Srivastava on 25/03/26.
//

import SwiftUI
import Foundation
import Types

struct MessageReactionsSheetUIKit: View {
    @EnvironmentObject var viewState: ViewState
    
    let message: Message
    let server: Server?
    
    @State private var selection: String
    @State private var loadingUserIds: Set<String> = []
    @State private var failedUserIds: Set<String> = []
    
    init(message: Message, server: Server?, initialEmoji: String) {
        self.message = message
        self.server = server
        
        let keys: [String] = message.reactions?.keys.map { $0 } ?? []
        let initialSelection = keys.contains(initialEmoji) ? initialEmoji : (keys.first ?? initialEmoji)
        self._selection = State(initialValue: initialSelection)
    }
    
    var body: some View {
        if let reactions = message.reactions, !reactions.isEmpty {
            VStack {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(reactions.keys), id: \.self) { emoji in
                            Button {
                                selection = emoji
                            } label: {
                                HStack(spacing: 8) {
                                    if emoji.count == 26 {
                                        LazyImage(source: .emoji(emoji), height: 16, width: 16, clipTo: Rectangle())
                                    } else {
                                        Text(verbatim: emoji)
                                            .font(.system(size: 16))
                                    }
                                    
                                    Text(verbatim: String(reactions[emoji]?.count ?? 0))
                                    
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .foregroundStyle(selection == emoji ? viewState.theme.background3 : viewState.theme.background2)
                            )
                        }
                    }
                    .padding(16)
                }
                
                let userIds = reactions[selection] ?? []
                
                List {
                    ForEach(userIds, id: \.self) { userId in
                        reactionUserRow(userId: userId)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(viewState.theme.background)
                }
                .task(id: selection) {
                    await loadMissingReactionUsers(userIds)
                }
                
            }
            .padding(.top, 15)
            .presentationDragIndicator(.visible)
            .presentationBackground(viewState.theme.background)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func reactionUserRow(userId: String) -> some View {
        if let user = reactionUser(for: userId) {
            let member = server.flatMap { viewState.members[$0.id]?[user.id] }

            Button {
                viewState.openUserSheet(user: user, member: member)
            } label: {
                HStack(spacing: 8) {
                    Avatar(user: user, member: member)

                    let displayName = member?.nickname ?? user.display_name ?? user.username
                    let isVerified = user.hasVerifiedBadge()

                    HStack(spacing: 4) {
                        Text(verbatim: displayName)
                            .foregroundStyle(isVerified ? .yellow : .primary)

                        if isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(failedUserIds.contains(userId) ? "Unknown User" : "Loading user...")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
        }
    }

    private func reactionUser(for userId: String) -> User? {
        viewState.users[userId] ?? viewState.allEventUsers[userId]
    }

    private func loadMissingReactionUsers(_ userIds: [String]) async {
        let missingUserIds = await MainActor.run {
            userIds.filter {
                reactionUser(for: $0) == nil && !loadingUserIds.contains($0) && !failedUserIds.contains($0)
            }
        }
        guard !missingUserIds.isEmpty else { return }

        await MainActor.run {
            loadingUserIds.formUnion(missingUserIds)
        }

        for userId in missingUserIds {
            let result = await viewState.http.fetchUser(user: userId)
            await MainActor.run {
                loadingUserIds.remove(userId)
                if case .success(let user) = result {
                    viewState.users[user.id] = user
                    viewState.allEventUsers[user.id] = user
                    failedUserIds.remove(userId)
                } else {
                    failedUserIds.insert(userId)
                }
            }
        }
    }
}
