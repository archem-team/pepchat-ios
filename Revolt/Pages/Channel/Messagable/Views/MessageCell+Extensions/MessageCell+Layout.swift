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
        // Debug log for tracking
        // if !(currentMessage?.attachments?.isEmpty ?? true) {
        //     // print("🖼️ updateAppearanceForContinuation: isContinuation: \(isContinuation)")
        // }
        
        // Hide avatar and username for continuation messages
        avatarImageView.isHidden = isContinuation
        usernameLabel.isHidden = isContinuation
        timeLabel.isHidden = isContinuation
        bridgeBadgeLabel.isHidden = isContinuation || currentMessage?.masquerade == nil
        
        // Note: We no longer automatically hide reply view for continuation messages
        // This allows replies to be shown even in continuation messages
        
        // Remove ALL existing constraints that we want to modify - more comprehensive cleanup
        var constraintsToRemove: [NSLayoutConstraint] = []
        
        for constraint in contentView.constraints {
            let shouldRemove = (
                // Content label constraints
                (constraint.firstItem === contentLabel &&
                 (constraint.firstAttribute == .top || constraint.firstAttribute == .leading)) ||
                // Username label constraints
                (constraint.firstItem === usernameLabel &&
                 (constraint.firstAttribute == .top || constraint.firstAttribute == .height)) ||
                // Constraints that connect to username label
                (constraint.secondItem === usernameLabel &&
                 (constraint.secondAttribute == .bottom || constraint.secondAttribute == .top))
            )
            
            if shouldRemove {
                constraintsToRemove.append(constraint)
            }
        }
        
        // Remove the identified constraints
        constraintsToRemove.forEach { $0.isActive = false }
        
        // Apply appropriate constraints based on continuation status
        if isContinuation {
            // For continuation messages, adjust layout for with/without reply
            if replyView.isHidden {
                // Standard continuation without reply
                NSLayoutConstraint.activate([
                    contentLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                    contentLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10)
                ])
            } else {
                // Continuation with reply
                NSLayoutConstraint.activate([
                    contentLabel.topAnchor.constraint(equalTo: replyView.bottomAnchor, constant: 8),
                    contentLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10)
                ])
            }
        } else {
            // For first messages in a group, ALWAYS set username constraints
            let topAnchor = replyView.isHidden ? contentView.topAnchor : replyView.bottomAnchor
            let usernameTopConstraint = usernameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8)
            let usernameHeightConstraint = usernameLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 19)
            usernameHeightConstraint.priority = UILayoutPriority.defaultHigh // Lower priority to avoid conflicts
            let contentTopConstraint = contentLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 4)
            let contentLeadingConstraint = contentLabel.leadingAnchor.constraint(equalTo: usernameLabel.leadingAnchor)
            
            NSLayoutConstraint.activate([
                usernameTopConstraint,
                usernameHeightConstraint,
                contentTopConstraint,
                contentLeadingConstraint
            ])
            
            // Extra debug log
            // if !(currentMessage?.attachments?.isEmpty ?? true) {
            //     // print("🖼️ Set username constraints for message with attachments - username should be visible")
            // }
        }
        
        // Force layout update to ensure proper positioning
        setNeedsLayout()
        layoutIfNeeded()
        
        // Final debug log after layout
        // if !(currentMessage?.attachments?.isEmpty ?? true) {
        //     // print("🖼️ Final check - usernameLabel.isHidden: \(usernameLabel.isHidden), frame: \(usernameLabel.frame)")
        // }
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
        // Remove any existing bottom constraints for the content label
        for constraint in contentView.constraints {
            if constraint.firstItem === contentLabel &&
               constraint.firstAttribute == .bottom {
                constraint.isActive = false
            }
        }
    }
    
    internal func clearDynamicConstraints() {
        // Remove all dynamic constraints that are created during configuration
        var constraintsToRemove: [NSLayoutConstraint] = []
        
        for constraint in contentView.constraints {
            let shouldRemove = (
                // Content label dynamic constraints
                (constraint.firstItem === contentLabel &&
                 (constraint.firstAttribute == .top || constraint.firstAttribute == .leading)) ||
                // Username label dynamic constraints
                (constraint.firstItem === usernameLabel &&
                 (constraint.firstAttribute == .top || constraint.firstAttribute == .height)) ||
                // Constraints that connect to username label
                (constraint.secondItem === usernameLabel &&
                 (constraint.secondAttribute == .bottom || constraint.secondAttribute == .top)) ||
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
        
        // Remove the identified constraints safely
        constraintsToRemove.forEach { constraint in
            constraint.isActive = false
        }
        
        // Clear the array to help with memory management
        constraintsToRemove.removeAll()
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
