//
//  MessageCell+GestureRecognizer.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

// MARK: - UIGestureRecognizerDelegate Extension
extension MessageCell {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = panGesture.velocity(in: contentView)
            
            // Only accept primarily horizontal gestures with a significant horizontal velocity
            return abs(velocity.x) > abs(velocity.y) * 2 && abs(velocity.x) > 300
        }
        
        // For link long press gestures on content label, check if it's on a link
        if let longPressGesture = gestureRecognizer as? UILongPressGestureRecognizer,
           longPressGesture.view == contentLabel {
            let location = longPressGesture.location(in: contentLabel)
            let characterIndex = contentLabel.layoutManager.characterIndex(for: location, in: contentLabel.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            
            // Only allow long press gesture if it's on a link
            if characterIndex < contentLabel.textStorage.length {
                let attributes = contentLabel.textStorage.attributes(at: characterIndex, effectiveRange: nil)
                return attributes[.link] != nil
            }
            return false
        }
        
        // For tap gestures on content label, check if it's on a link
        if let tapGesture = gestureRecognizer as? UITapGestureRecognizer,
           tapGesture.view == contentLabel {
            let location = tapGesture.location(in: contentLabel)
            let characterIndex = contentLabel.layoutManager.characterIndex(for: location, in: contentLabel.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            
            // Only allow tap gesture if it's on a link
            if characterIndex < contentLabel.textStorage.length {
                let attributes = contentLabel.textStorage.attributes(at: characterIndex, effectiveRange: nil)
                return attributes[.link] != nil
            }
            return false
        }
        
        return true
    }
    
    // Allow simultaneous recognition with other gesture recognizers (like tableView's pan gesture)
    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't allow simultaneous recognition between tap and long press gestures
        if gestureRecognizer is UITapGestureRecognizer && otherGestureRecognizer is UILongPressGestureRecognizer {
            return false
        }
        
        if gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer {
            return false
        }
        
        // For pan gestures, check the direction
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
           let otherPanGesture = otherGestureRecognizer as? UIPanGestureRecognizer {
            
            let velocity = panGesture.velocity(in: contentView)
            let otherVelocity = otherPanGesture.velocity(in: contentView)
            
            // If our gesture is primarily horizontal and the other is primarily vertical,
            // they can work simultaneously
            let isHorizontal = abs(velocity.x) > abs(velocity.y)
            let isOtherVertical = abs(otherVelocity.y) > abs(otherVelocity.x)
            
            return isHorizontal && isOtherVertical
        }
        
        return true
    }
}
