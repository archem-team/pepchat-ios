//
//  MessageableChannelViewController+ScrollPosition.swift
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
    // MARK: - Scroll Position Preservation

    /// Maintains the user's visual scroll position when inserting messages at the top of the table view.
    /// This ensures the user continues looking at the same message after new content is added above.
    ///
    /// - Parameters:
    ///   - insertionIndex: The index where new rows will be inserted (typically 0 for top insertion)
    ///   - count: The number of rows being inserted
    ///   - animated: Whether to animate the insertion
    private func maintainScrollPositionAfterInsertingMessages(
        at insertionIndex: Int, count: Int, animated: Bool
    ) {
        guard count > 0 else { return }

        // Step 1: Find an anchor cell before insertion
        let anchorInfo = findAnchorCellBeforeInsertion()

        // Step 2: Perform the insertion
        let indexPaths = (0..<count).map { IndexPath(row: insertionIndex + $0, section: 0) }

        if animated {
            tableView.performBatchUpdates({
                self.tableView.insertRows(at: indexPaths, with: .none)
            }) { _ in
                // Step 3: Restore position after insertion completes
                if let anchor = anchorInfo {
                    self.restoreScrollPositionToAnchor(anchor, insertedCount: count)
                }
            }
        } else {
            // For non-animated updates, we need to handle this more carefully
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            tableView.beginUpdates()
            tableView.insertRows(at: indexPaths, with: .none)
            tableView.endUpdates()

            // Immediately restore position
            if let anchor = anchorInfo {
                restoreScrollPositionToAnchor(anchor, insertedCount: count)
            }

            CATransaction.commit()
        }
    }

    /// Represents information about an anchor cell used for scroll position preservation
    private struct AnchorCellInfo {
        let indexPath: IndexPath
        let distanceFromTop: CGFloat
        let cellFrame: CGRect
    }

    /// Finds a suitable anchor cell to use for maintaining scroll position.
    /// Returns the first fully visible cell that's not at the very top.
    private func findAnchorCellBeforeInsertion() -> AnchorCellInfo? {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
            !visibleIndexPaths.isEmpty
        else {
            return nil
        }

        let contentOffset = tableView.contentOffset
        let topInset = tableView.contentInset.top

        // Find the first fully visible cell (not partially clipped)
        // We skip the very first visible cell as it might be partially visible
        for (index, indexPath) in visibleIndexPaths.enumerated() {
            let cellFrame = tableView.rectForRow(at: indexPath)
            let cellTop = cellFrame.origin.y
            let cellBottom = cellFrame.origin.y + cellFrame.height

            let visibleTop = contentOffset.y + topInset
            let visibleBottom =
                contentOffset.y + tableView.bounds.height - tableView.contentInset.bottom

            // Check if cell is fully visible
            let isFullyVisible = cellTop >= visibleTop && cellBottom <= visibleBottom

            // Use the second or third fully visible cell as anchor (more stable)
            if isFullyVisible && index >= 1 {
                let distanceFromTop = cellTop - contentOffset.y

                return AnchorCellInfo(
                    indexPath: indexPath,
                    distanceFromTop: distanceFromTop,
                    cellFrame: cellFrame
                )
            }
        }

        // Fallback: use the first visible cell if no fully visible cell found
        if let firstVisible = visibleIndexPaths.first {
            let cellFrame = tableView.rectForRow(at: firstVisible)
            let distanceFromTop = cellFrame.origin.y - contentOffset.y

            return AnchorCellInfo(
                indexPath: firstVisible,
                distanceFromTop: distanceFromTop,
                cellFrame: cellFrame
            )
        }

        return nil
    }

    /// Restores the scroll position so the anchor cell appears at the same visual position
    private func restoreScrollPositionToAnchor(_ anchor: AnchorCellInfo, insertedCount: Int) {
        // The anchor cell's index has shifted down by the number of inserted rows
        let newIndexPath = IndexPath(row: anchor.indexPath.row + insertedCount, section: 0)

        // Ensure the new index path is valid
        guard newIndexPath.row < tableView.numberOfRows(inSection: 0) else {
            // print("⚠️ Anchor cell index out of bounds after insertion")
            return
        }

        // Get the new frame of the anchor cell
        let newCellFrame = tableView.rectForRow(at: newIndexPath)

        // Calculate the new content offset to maintain the same visual position
        let newContentOffsetY = newCellFrame.origin.y - anchor.distanceFromTop

        // Apply the new content offset without animation to avoid visual jumps
        tableView.setContentOffset(CGPoint(x: 0, y: newContentOffsetY), animated: false)

        // print("📌 Maintained scroll position: anchor cell \(anchor.indexPath.row) → \(newIndexPath.row), offset: \(newContentOffsetY)")
    }

    /// Alternative implementation using a message ID as anchor instead of index path
    /// This is more robust when dealing with data source changes
    private func maintainScrollPositionWithMessageAnchor(insertedCount: Int) {
        guard insertedCount > 0 else {
            return
        }

        // Force layout to ensure frames are up to date
        tableView.layoutIfNeeded()

        // Get visible index paths before the change
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
            !visibleIndexPaths.isEmpty
        else {
            // print("⚠️ No visible cells to use as anchor")
            return
        }

        // Find a stable message to use as anchor
        var anchorMessageId: String?
        var anchorDistanceFromTop: CGFloat = 0

        let contentOffset = tableView.contentOffset

        // print("📍 Looking for anchor cell among \(visibleIndexPaths.count) visible cells")

        // Look for a good anchor message (preferably the second or third visible)
        // IMPORTANT: At this point, localMessages already contains the new messages
        // We need to find a message that was visible BEFORE the insertion
        for (index, indexPath) in visibleIndexPaths.enumerated() {
            // Skip if the index is invalid
            if indexPath.row >= localMessages.count {
                continue
            }

            let messageId = localMessages[indexPath.row]
            let cellFrame = tableView.rectForRow(at: indexPath)

            // Prefer cells that are not at the very top for stability
            if index >= 1 || visibleIndexPaths.count == 1 {
                anchorMessageId = messageId
                anchorDistanceFromTop = cellFrame.origin.y - contentOffset.y
                // print("📍 Selected anchor: message at index \(indexPath.row), ID: \(messageId), distance from top: \(anchorDistanceFromTop)")
                break
            }
        }

        // Fallback to first visible if no suitable anchor found
        if anchorMessageId == nil, let firstVisible = visibleIndexPaths.first {
            if firstVisible.row < localMessages.count {
                anchorMessageId = localMessages[firstVisible.row]
                let cellFrame = tableView.rectForRow(at: firstVisible)
                anchorDistanceFromTop = cellFrame.origin.y - contentOffset.y
                // print("📍 Fallback anchor: message at index \(firstVisible.row)")
            }
        }

        // If we found an anchor, restore its position after the table updates
        if let anchorId = anchorMessageId {
            // Force another layout pass to ensure all cells are sized correctly
            tableView.layoutIfNeeded()

            // Find the anchor message's new position
            if let newIndex = localMessages.firstIndex(of: anchorId) {
                let newIndexPath = IndexPath(row: newIndex, section: 0)

                // Ensure the index is valid
                if newIndex < tableView.numberOfRows(inSection: 0) {
                    let newCellFrame = tableView.rectForRow(at: newIndexPath)
                    let newContentOffsetY = newCellFrame.origin.y - anchorDistanceFromTop

                    // print("📍 Restoring position: anchor now at index \(newIndex), new offset: \(newContentOffsetY)")

                    // Apply the new content offset without animation
                    tableView.setContentOffset(CGPoint(x: 0, y: newContentOffsetY), animated: false)
                } else {
                    // print("⚠️ New index \(newIndex) is out of bounds")
                }
            } else {
                // print("⚠️ Could not find anchor message in updated array")
            }
        } else {
            // print("⚠️ No anchor message selected")
        }
    }
}
