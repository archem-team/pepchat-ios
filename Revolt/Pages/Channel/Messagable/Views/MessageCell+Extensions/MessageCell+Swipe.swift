//
//  MessageCell+Swipe.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

extension MessageCell {
    @objc internal func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        // Check if user has permission to reply before allowing swipe
        guard checkCanReply() else {
            return
        }
        
        let translation = gesture.translation(in: contentView)
        
        switch gesture.state {
        case .began:
            // Store original positions
            originalCenter = contentView.center
            initialTouchPoint = gesture.location(in: contentView)
            isSwiping = false
            actionTriggered = false
            
        case .changed:
            // Determine if this is a horizontal swipe
            let horizontalMovement = abs(translation.x) > abs(translation.y)
            
            // Only respond to left swipes (negative x translation)
            if horizontalMovement && translation.x < 0 {
                isSwiping = true
                
                // Move the content view
                let newX = originalCenter.x + translation.x
                contentView.center = CGPoint(x: newX, y: originalCenter.y)
                
                // Show and update the reply icon
                updateSwipeReplyIcon(withOffset: abs(translation.x))
                
                // Trigger the reply action if swiped far enough
                if abs(translation.x) >= swipeThreshold && !actionTriggered {
                    actionTriggered = true
                    triggerReplyAction()
                }
            }
            
        case .ended, .cancelled:
            if isSwiping {
                // Animate back to original position
                UIView.animate(
                    withDuration: 0.5,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0.5,
                    options: [.curveEaseInOut],
                    animations: { [weak self] in
                        self?.contentView.center = self?.originalCenter ?? .zero
                        self?.swipeReplyIconView?.isHidden = true
                        self?.isSwiping = false
                    },
                    completion: nil
                )
            }
            
        default:
            break
        }
    }
    
    private func updateSwipeReplyIcon(withOffset offset: CGFloat) {
        guard let swipeReplyIconView = swipeReplyIconView,
              let circleView = swipeReplyIconView.subviews.first else { return }
        
        // Show the reply icon
        swipeReplyIconView.isHidden = false
        
        // Calculate size based on swipe distance (min 32, max 40)
        let iconSize = min(40, max(32, 32 + (offset / swipeThreshold) * 8))
        
        // Update circle size
        circleView.layer.cornerRadius = iconSize / 2
        
        // Update constraints
        for constraint in circleView.constraints {
            if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                constraint.constant = iconSize
            }
        }
        
        // Update icon size
        if let iconImageView = circleView.subviews.first {
            for constraint in iconImageView.constraints {
                if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                    constraint.constant = iconSize * 0.5
                }
            }
        }
    }
    
    private func triggerReplyAction() {
        // Add haptic feedback to indicate action triggered successfully
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        // Call the reply action with a slight delay to ensure the animation is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, let message = self.currentMessage else { return }
            self.onMessageAction?(.reply, message)
        }
    }
    
    @objc internal func handleContentTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: contentLabel)
        
        // Check if tap is on a link
        let textContainer = contentLabel.textContainer
        let layoutManager = contentLabel.layoutManager
        let textStorage = contentLabel.textStorage
        
        // Convert the tap location to text position
        let characterIndex = layoutManager.characterIndex(for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        
        // Check if the character at this index has a link attribute
        if characterIndex < textStorage.length {
            let attributes = textStorage.attributes(at: characterIndex, effectiveRange: nil)
            if let url = attributes[.link] as? URL {
                // Handle the link tap manually
                _ = textView(contentLabel, shouldInteractWith: url, in: NSRange(location: characterIndex, length: 1), interaction: .invokeDefaultAction)
                return
            }
        }
        
        // If no link was tapped, do nothing (let other gestures handle it)
    }
    
    @objc internal func handleLinkLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        
        let location = gesture.location(in: contentLabel)
        
        // Check if long press is on a link
        let textContainer = contentLabel.textContainer
        let layoutManager = contentLabel.layoutManager
        let textStorage = contentLabel.textStorage
        
        // Convert the tap location to text position
        let characterIndex = layoutManager.characterIndex(for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        
        // Check if the character at this index has a link attribute
        if characterIndex < textStorage.length {
            let attributes = textStorage.attributes(at: characterIndex, effectiveRange: nil)
            if let url = attributes[.link] as? URL {
                // Show link-specific context menu
                showLinkContextMenu(for: url, at: location)
                return
            }
                 }
     }
    
}
