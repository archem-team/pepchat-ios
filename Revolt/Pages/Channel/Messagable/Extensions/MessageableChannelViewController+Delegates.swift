//
//  MessageableChannelViewController+Delegates.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//

import UIKit

// MARK: - NSFWOverlayViewDelegate
extension MessageableChannelViewController {
    func nsfwOverlayViewDidConfirm(_ view: NSFWOverlayView) {
        view.dismiss(animated: true)
        over18HasSeen = true
    }
}

// MARK: - UIGestureRecognizerDelegate
extension MessageableChannelViewController {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow the swipe gesture to work simultaneously with table view scrolling
        return true
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
            let translation = panGesture.translation(in: view)
            let velocity = panGesture.velocity(in: view)
            
            // Only recognize horizontal swipes that are more horizontal than vertical
            // and are moving from left to right
            return abs(velocity.x) > abs(velocity.y) && velocity.x > 0 && translation.x > 0
        }
        return true
    }
}
