//
//  MessageReactionsSheet.swift
//  Revolt
//
//  Created by Angelo on 11/09/2024.
//

import Foundation
import SwiftUI
import Types

/// A SwiftUI view that displays a sheet for viewing and selecting message reactions.
///
/// This view allows users to see all reactions to a specific message, select a reaction to view the users who reacted with it,
/// and open a user sheet for each user who reacted.
///
/// - Parameters:
///   - viewModel: An instance of `MessageContentsViewModel` that holds the message data and related information.
struct MessageReactionsSheet: View {
    @EnvironmentObject var viewState: ViewState

    @ObservedObject var viewModel: MessageContentsViewModel
    @State var selection: String
    @State private var reactionKeys: [String]
    @State private var loadingUserIds: Set<String> = []
    @State private var failedUserIds: Set<String> = []

    /// Initializes a new instance of `MessageReactionsSheet`.
    ///
    /// - Parameter viewModel: The `MessageContentsViewModel` that contains the message and its reactions.
    init(viewModel: MessageContentsViewModel) {
        self.viewModel = viewModel
        let sorted = viewModel.message.reactions.map { Array($0.keys).sorted() } ?? []
        _reactionKeys = State(initialValue: sorted)
        _selection = State(initialValue: sorted.first ?? "")
    }

    /// The body of the `MessageReactionsSheet`.
    ///
    /// This view consists of a horizontal scrollable list of emoji reactions and a list of users who reacted with the selected emoji.
    var body: some View {
        VStack {
            if let reactions = viewModel.message.reactions, !reactions.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(reactionKeys, id: \.self) { emoji in
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
            } else {
                Text("No reactions")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 16)
        .presentationDragIndicator(.visible)
        .presentationBackground(viewState.theme.background)
    }

    @ViewBuilder
    private func reactionUserRow(userId: String) -> some View {
        if let user = reactionUser(for: userId) {
            let member = viewModel.server.flatMap { viewState.members[$0.id]?[user.id] }

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
