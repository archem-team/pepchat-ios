//
//  MessageableChannelViewController+GlobalFix.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import Combine
import Kingfisher
import ObjectiveC
import SwiftUI
import Types
import UIKit
import ULID

extension MessageableChannelViewController {
    // MARK: - Global Fix for Black Screen
    internal func applyGlobalFix() {
        // print("🔧 [FIX] Applying global fix for black screen...")

        // CRITICAL FIX: Don't apply global fix if target message protection is active
        if targetMessageProtectionActive {
            print("🔧 [FIX] BLOCKED: Global fix blocked - target message protection active")
            return
        }

        // Store current scroll position before fix
        let currentOffset = self.tableView.contentOffset.y
        let wasNearBottom = self.isUserNearBottom()

        // Synchronize message arrays
        if let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id],
            !channelMessages.isEmpty
        {
            // CRITICAL: Check if actual message objects exist
            let hasActualMessages =
                channelMessages.first(where: { viewModel.viewState.messages[$0] != nil }) != nil

            if hasActualMessages {
                self.localMessages = channelMessages
                self.viewModel.messages = self.localMessages
                // print("🔄 [FIX] Synced all message arrays with \(self.localMessages.count) messages")
            } else {
                // print("⚠️ [FIX] Found message IDs but no actual messages - need to load from API")
                // Clear the arrays and load fresh
                self.localMessages = []
                self.viewModel.messages = []
                viewModel.viewState.channelMessages[viewModel.channel.id] = []

                // Trigger API load
                Task {
                    await loadInitialMessages()
                }
                return
            }
        } else if !self.localMessages.isEmpty {
            viewModel.viewState.channelMessages[viewModel.channel.id] = self.localMessages
            self.viewModel.messages = self.localMessages
            // print("🔄 [FIX] Populated viewState from localMessages with \(self.localMessages.count) messages")
        } else if !self.viewModel.messages.isEmpty {
            self.localMessages = self.viewModel.messages
            viewModel.viewState.channelMessages[viewModel.channel.id] = self.localMessages
            // print("🔄 [FIX] Populated from viewModel.messages with \(self.viewModel.messages.count) messages")
        }

        // Remove any excess contentInset
        if self.tableView.contentInset != .zero {
            UIView.animate(withDuration: 0.2) {
                self.tableView.contentInset = .zero
            }
            // print("📏 [FIX] Reset content insets to zero")
        }

        // Ensure DataSource is up-to-date
        self.dataSource = LocalMessagesDataSource(
            viewModel: self.viewModel,
            viewController: self,
            localMessages: self.localMessages
        )
        self.tableView.dataSource = self.dataSource

        // Reload and position properly
        DispatchQueue.main.async {
            // Reload table
            self.tableView.reloadData()
            // print("🔄 [FIX] Reloaded tableView")

            // Update table view bouncing behavior
            self.updateTableViewBouncing()

            // COMPREHENSIVE TARGET MESSAGE PROTECTION
            if self.targetMessageProtectionActive {
                print("🎯 [FIX] Target message protection active, maintaining current position")
                self.tableView.contentOffset = CGPoint(x: 0, y: currentOffset)
                return
            }

            // ONLY scroll to bottom if user was near bottom OR if table was empty before
            if wasNearBottom || currentOffset <= 0 {
                // print("🔽 [FIX] User was near bottom or at top, positioning at bottom")
                self.positionTableAtBottomBeforeShowing()
            } else {
                // Try to maintain scroll position if user was somewhere in the middle
                // print("📏 [FIX] User was not near bottom, attempting to maintain scroll position")
                self.tableView.contentOffset = CGPoint(x: 0, y: currentOffset)
            }
        }
    }
}
