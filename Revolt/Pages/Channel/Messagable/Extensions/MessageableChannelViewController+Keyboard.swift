//
//  MessageableChannelViewController+Keyboard.swift
//  Revolt
//
//

import UIKit

// MARK: - Keyboard Handling
extension MessageableChannelViewController {
    func setupKeyboardObservers() {
        // Initialize the keyboard height observer
        _ = KeyboardHeightObserver.shared
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow), name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)
    }
    
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            // Get animation details from notification
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3
            let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
            
            // Calculate keyboard height relative to the view
            let keyboardHeight = keyboardFrame.height
            self.keyboardHeight = keyboardHeight
            
            // Update constraint to make input view stick to keyboard with small gap
            self.messageInputBottomConstraint.constant = -keyboardHeight + 8
            
            // Store current state before making changes
            let wasNearBottom = self.isUserNearBottom()
            
            // Animate using the same animation parameters as the keyboard
            UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve)) {
                self.view.layoutIfNeeded()
                
                // When keyboard appears, update bouncing behavior first
                self.updateTableViewBouncing()
                
                // CRITICAL FIX: Don't auto-scroll if target message was recently highlighted
                if let highlightTime = self.lastTargetMessageHighlightTime,
                   Date().timeIntervalSince(highlightTime) < 10.0 {
                } else if wasNearBottom && self.tableView.isScrollEnabled {
                    // Scroll to show the newest message (at top) above the input
                    // FIXED: Respect target message protection
                    if !self.localMessages.isEmpty && !self.targetMessageProtectionActive {
                        if self.tableView.numberOfRows(inSection: 0) > 0 {
                            let indexPath = IndexPath(row: 0, section: 0)
                            self.safeScrollToRow(at: indexPath, at: .top, animated: false, reason: "keyboard shown")
                        }
                    } else if self.targetMessageProtectionActive {
                    }
                    
                }
                
                // Update table view bouncing behavior as visible height changed
                self.updateTableViewBouncing()
            } completion: { _ in
                self.isKeyboardVisible = true
            }
        }
    }
    
    @objc func keyboardDidShow(_ notification: NSNotification) {
        // Remove all the complex logic from here to prevent double animation
        // The scroll adjustment should only happen in keyboardWillShow
        
        // Just ensure we're marked as keyboard visible
        self.isKeyboardVisible = true
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        // Get animation details from notification
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        
        // Reset keyboard height
        self.keyboardHeight = 0
        
        // Reset constraint
        self.messageInputBottomConstraint.constant = 0
        
        // Animate using the same animation parameters as the keyboard
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve)) {
            self.view.layoutIfNeeded()
            
            // Update table view bouncing behavior as visible height changed
            self.updateTableViewBouncing()
            
        } completion: { _ in
            self.isKeyboardVisible = false
        }
    }
    
    @objc func keyboardDidHide(_ notification: NSNotification) {
        // Reset flag after keyboard is fully hidden
        isKeyboardVisible = false
    }
    
    // Helper method to configure table view for better keyboard interaction
    func configureTableViewForKeyboard() {
        // Enable interactive keyboard dismissal
        tableView.keyboardDismissMode = .interactive
        
        // Don't set any initial content insets - let updateTableViewBouncing handle it
        tableView.contentInset = .zero
        tableView.scrollIndicatorInsets = .zero
        
        // Ensure table view handles keyboard properly
        if #available(iOS 11.0, *) {
            tableView.contentInsetAdjustmentBehavior = .never
        }
    }
}

