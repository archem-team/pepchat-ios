//
//  MessageableChannelViewController+TableBouncing.swift
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
    // MARK: - Helper method to update table view bouncing behavior
    internal func updateTableViewBouncing() {
        // First check if table view is ready
        guard tableView.window != nil else { return }
        
        tableView.layoutIfNeeded()

        // FIX (search result scroll freeze): When target message protection is active we still
        // must apply scroll/bounce settings. Previously we returned here and never set
        // isScrollEnabled = true after the nearby load, so the table stayed non-scrollable.
        // We now run the full logic; the only protection-specific behavior remains at the
        // "content fits" branch below (we do not reset contentOffset when protection is active).
        
//        if targetMessageProtectionActive {
//            print("📏 BOUNCE_BLOCKED: Bouncing update blocked - target message protection active")
//            return
//        }

        let rowCount = tableView.numberOfRows(inSection: 0)

        // If no rows, disable scrolling completely
        guard rowCount > 0 else {
            tableView.isScrollEnabled = false
            tableView.alwaysBounceVertical = false
            tableView.bounces = false
            tableView.showsVerticalScrollIndicator = false
            tableView.contentInset = .zero
            tableView.scrollIndicatorInsets = .zero
            // Remove header to prevent scrolling
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }
            print("📏 Disabled scrolling - no messages")
            return
        }

        // Use the table's contentSize for actual content height (reliable after layout); fallback to sum of rectForRow if contentSize not yet valid
        let contentSizeValid = tableView.contentSize.height > 0
        var actualContentHeight: CGFloat = tableView.contentSize.height
        if actualContentHeight <= 0 {
            for i in 0..<rowCount {
                let indexPath = IndexPath(row: i, section: 0)
                actualContentHeight += tableView.rectForRow(at: indexPath).height
            }
            if let header = tableView.tableHeaderView, !header.isHidden {
                actualContentHeight += header.frame.height
            }
            if let footer = tableView.tableFooterView, !footer.isHidden {
                actualContentHeight += footer.frame.height
            }
        }

        // Calculate visible height
        let visibleHeight = tableView.bounds.height - keyboardHeight

        // Be very strict - only enable scrolling if content truly exceeds visible area
        let shouldEnableScrolling = actualContentHeight > visibleHeight + 10  // 10px margin

        // Never disable scrolling when we have many rows: contentSize can be read before layout completes (e.g. when re-entering chat), giving a transient low value and leaving scroll stuck disabled.
        let tooManyRowsToDisable = rowCount >= 5

        // Force update scrolling and bouncing settings
        if shouldEnableScrolling || tooManyRowsToDisable {
            // Enable scroll when content exceeds visible, or when we have 5+ rows (avoid disabling on transient low contentSize when re-entering chat)
            tableView.isScrollEnabled = true
            tableView.alwaysBounceVertical = true
            tableView.bounces = true
            tableView.showsVerticalScrollIndicator = true

            // Re-add header only if it was removed AND we are loading
            if tableView.tableHeaderView == nil && isLoadingMore {
                tableView.tableHeaderView = loadingHeaderView
            }

        } else if contentSizeValid {
            // Only disable when we have a reliable measurement and 1–4 rows where "content fits" is unambiguous
            // Completely disable scrolling when content fits
            tableView.isScrollEnabled = false
            tableView.alwaysBounceVertical = false
            tableView.bounces = false
            tableView.showsVerticalScrollIndicator = false
            // CRITICAL: Remove all content insets when scrolling is disabled
            tableView.contentInset = .zero
            tableView.scrollIndicatorInsets = .zero

            // Remove header to prevent any scrolling
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }

            // CRITICAL FIX: Don't reset scroll position during target message operations
            if !targetMessageProtectionActive {
                // Reset scroll position to top
                tableView.contentOffset = .zero
            }

            print(
                "📏 Disabled scrolling completely - actual content: \(actualContentHeight), visible: \(visibleHeight), rows: \(rowCount)"
            )
        }
    }

    // MARK: - Position Table at Bottom Before Showing
    internal func positionTableAtBottomBeforeShowing() {
        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            print(
                "🎯 [POSITION] Target message protection active, just showing table without positioning"
            )
            showTableViewWithFade()
            return
        }

        // Force layout to calculate content size
        tableView.layoutIfNeeded()

        let rowCount = tableView.numberOfRows(inSection: 0)
        let messagesCount = localMessages.count

        // print("📊 [POSITION] Positioning table: rows=\(rowCount), messages=\(messagesCount)")

        // If no messages, just show the table
        guard rowCount > 0, messagesCount > 0 else {
            // print("📊 [POSITION] No messages, showing empty table")
            showTableViewWithFade()
            return
        }

        // Update bouncing behavior based on content
        updateTableViewBouncing()

        // Position at bottom (newest messages) only if no target message
        let lastRowIndex = rowCount - 1
        let indexPath = IndexPath(row: lastRowIndex, section: 0)
        guard tableView.dataSource != nil else { return }
        guard tableView.numberOfSections > 0, lastRowIndex < tableView.numberOfRows(inSection: 0) else { return }
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        // print("🔽 [POSITION] Positioned at bottom (newest messages)")

        // Show the table view now that it's properly positioned
        showTableViewWithFade()

        // CRITICAL FIX: Check for missing reply content after positioning with longer delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1.0 seconds
            await self.checkAndFetchMissingReplies()
        }
    }

    // Helper method to show table view with smooth fade-in
    internal func showTableViewWithFade() {
        UIView.animate(withDuration: 0.2) {
            self.tableView.alpha = 1.0
        }
        // print("✨ [POSITION] Table view shown with fade-in")
    }
}
