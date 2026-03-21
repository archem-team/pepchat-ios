//
//  MessageCell+Layout.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

extension MessageCell {
    internal func updateAppearanceForContinuation() {
        // Hide avatar and username for continuation messages
        avatarImageView.isHidden = isContinuation
        usernameLabel.isHidden = isContinuation
        timeLabel.isHidden = isContinuation
        bridgeBadgeLabel.isHidden = isContinuation || currentMessage?.masquerade == nil

        // PERF Issue #9: Toggle pre-built constraint sets instead of scanning/removing/recreating.
        // Deactivate all four sets first, then activate the correct one.
        NSLayoutConstraint.deactivate(continuationNoReplyConstraints)
        NSLayoutConstraint.deactivate(continuationWithReplyConstraints)
        NSLayoutConstraint.deactivate(nonContinuationNoReplyConstraints)
        NSLayoutConstraint.deactivate(nonContinuationWithReplyConstraints)

        if isContinuation {
            if replyView.isHidden {
                NSLayoutConstraint.activate(continuationNoReplyConstraints)
            } else {
                NSLayoutConstraint.activate(continuationWithReplyConstraints)
            }
        } else {
            if replyView.isHidden {
                NSLayoutConstraint.activate(nonContinuationNoReplyConstraints)
            } else {
                NSLayoutConstraint.activate(nonContinuationWithReplyConstraints)
            }
        }

        // Force layout so embed/attachment constraints resolve before first draw.
        // Without this, link previews can overlap the content label (docs/Fix/LinkPreviewImage.md).
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    internal func updatePendingAppearance() {
        let alpha: CGFloat = isPendingMessage ? 0.6 : 1.0
        
        // Apply reduced opacity to all message elements when pending
        UIView.animate(withDuration: 0.2) {
            self.avatarImageView.alpha = alpha
            self.usernameLabel.alpha = alpha
            self.contentLabel.alpha = alpha
            self.timeLabel.alpha = alpha
            self.bridgeBadgeLabel.alpha = alpha
            self.replyView.alpha = alpha
            self.imageAttachmentsContainer?.alpha = alpha
            self.fileAttachmentsContainer?.alpha = alpha
            self.reactionsContainerView.alpha = alpha
        }
        
        // Add a subtle pending indicator if needed
        if isPendingMessage {
            // Add a clock icon to indicate pending status
            if timeLabel.text?.contains("⏳") == false {
                timeLabel.text = "⏳ " + (timeLabel.text ?? "")
            }
        } else {
            // Remove pending indicator
            if let text = timeLabel.text, text.hasPrefix("⏳ ") {
                timeLabel.text = String(text.dropFirst(2))
            }
        }
    }
    
    internal func clearContentLabelBottomConstraints() {
        // PERF Issue #9: Deactivate tracked bottom constraint instead of scanning all constraints
        contentLabelBottomToContentViewConstraint?.isActive = false
        contentLabelBottomToContentViewConstraint = nil
    }
    
    internal func clearDynamicConstraints() {
        // PERF Issue #9: Username/contentLabel constraints are now pooled (toggled in
        // updateAppearanceForContinuation). Only scan for attachment/reactions/spacer constraints.
        var constraintsToRemove: [NSLayoutConstraint] = []

        for constraint in contentView.constraints {
            let shouldRemove = (
                // Image attachments container constraints
                (constraint.firstItem === imageAttachmentsContainer) ||
                (constraint.secondItem === imageAttachmentsContainer) ||
                // File attachments container constraints
                (constraint.firstItem === fileAttachmentsContainer) ||
                (constraint.secondItem === fileAttachmentsContainer) ||
                // Reactions container constraints
                (constraint.firstItem === reactionsContainerView) ||
                (constraint.secondItem === reactionsContainerView) ||
                // Spacer view constraints (tag 1001)
                (constraint.firstItem is UIView && (constraint.firstItem as? UIView)?.tag == 1001) ||
                (constraint.secondItem is UIView && (constraint.secondItem as? UIView)?.tag == 1001)
            )

            if shouldRemove {
                constraintsToRemove.append(constraint)
            }
        }

        constraintsToRemove.forEach { $0.isActive = false }
    }
    
    internal func clearReactionsContainerConstraints() {
        // Clear all constraints related to reactions container
        var constraintsToRemove: [NSLayoutConstraint] = []
        
        for constraint in contentView.constraints {
            if constraint.firstItem === reactionsContainerView || constraint.secondItem === reactionsContainerView {
                constraintsToRemove.append(constraint)
            }
        }
        
        // CRITICAL FIX: Only remove BOTTOM constraints from attachment containers
        // Keep all other constraints intact to maintain proper sizing and positioning
        for constraint in contentView.constraints {
            if let imageContainer = imageAttachmentsContainer,
               (constraint.firstItem === imageContainer && constraint.firstAttribute == .bottom) ||
               (constraint.secondItem === imageContainer && constraint.secondAttribute == .bottom) {
                // Only remove bottom constraints that connect to contentView
                if (constraint.secondItem === contentView || constraint.firstItem === contentView) {
                    constraintsToRemove.append(constraint)
                }
            }
        }
        
        // Also remove bottom constraints from file attachment containers
        for constraint in contentView.constraints {
            if let fileContainer = fileAttachmentsContainer,
               (constraint.firstItem === fileContainer && constraint.firstAttribute == .bottom) ||
               (constraint.secondItem === fileContainer && constraint.secondAttribute == .bottom) {
                if (constraint.secondItem === contentView || constraint.firstItem === contentView) {
                    constraintsToRemove.append(constraint)
                }
            }
        }
        
        // Remove constraints safely
        constraintsToRemove.forEach { $0.isActive = false }
        
        // Also clear any height constraints on the reactions container itself
        var heightConstraintsToRemove: [NSLayoutConstraint] = []
        reactionsContainerView.constraints.forEach { constraint in
            if constraint.firstAttribute == .height {
                heightConstraintsToRemove.append(constraint)
            }
        }
        
        // Remove height constraints safely
        heightConstraintsToRemove.forEach { $0.isActive = false }
    }
    
}
