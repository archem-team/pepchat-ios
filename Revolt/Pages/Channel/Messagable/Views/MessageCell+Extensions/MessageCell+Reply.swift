//
//  MessageCell+Reply.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

extension MessageCell {
    @objc internal func handleReplyTap() {
        guard let replyId = currentReplyId else {
            print("❌ REPLY_TAP_CELL: No currentReplyId found")
            return
        }
        
        // Cancel any pending reply loading timeout since user is actively interacting
        replyLoadingTimeoutWorkItem?.cancel()
        
        print("🔗 REPLY_TAP_CELL: MessageCell reply tap detected!")
        print("🔗 REPLY_TAP_CELL: replyId=\(replyId)")
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.replyView.alpha = 0.7
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.replyView.alpha = 1.0
            }
        }
        
        // Check if the reply message exists in viewState
        if let viewState = self.viewState, let replyMessage = viewState.messages[replyId] {
            print("✅ REPLY_TAP_CELL: Found reply message in viewState")
            print("🔗 REPLY_TAP_CELL: Reply message channel=\(replyMessage.channel)")
            
            // Check if the reply is in the same channel
            if let currentMessage = self.currentMessage,
               replyMessage.channel == currentMessage.channel {
                // Same channel - navigate to message
                // print("📱 Reply is in same channel, navigating to message")
                
                // Find the parent MessageableChannelViewController
                if let viewController = findParentViewController() as? MessageableChannelViewController {
                    // CRITICAL FIX: Activate target message protection to prevent jumping
                    print("🛡️ REPLY_TAP_CELL: Activating target message protection")
                    viewController.activateTargetMessageProtection(reason: "reply tap")
                    
                    // Clear any existing target message first
                    let previousTarget = viewController.targetMessageId
                    // print("📱 Clearing previous target: \(previousTarget ?? "none") -> setting new target: \(replyId)")
                    viewController.targetMessageId = nil
                    
                    // Use async task to refresh with target message
                    Task {
                        // print("🔄 Starting refreshWithTargetMessage for reply: \(replyId)")
                        do {
                            await viewController.refreshWithTargetMessage(replyId)
                            // Hide loading indicator after completion
                            await MainActor.run {
                                self.hideReplyLoadingIndicator()
                                
                                // Check if the message was successfully loaded and is visible
                                if !viewController.viewModel.messages.contains(replyId) {
                                    // Message was not found or could not be loaded
                                    self.showReplyNotFoundMessage()
                                } else {
                                    // print("✅ Reply message \(replyId) successfully loaded and visible")
                                }
                                
                                // FIXED: Don't clear protection with timer - let scroll detection handle it
                                // The target message protection will be cleared when user actually scrolls away
                                print("✅ REPLY_TAP_CELL: Message loaded successfully, protection will be maintained until user scrolls away")
                            }
                        } catch {
                            // Ensure loading indicator is hidden on error
                            await MainActor.run {
                                self.hideReplyLoadingIndicator()
                                self.showReplyNotFoundMessage()
                                
                                // Reset loading state in view controller
                                viewController.messageLoadingState = .notLoading
                                viewController.loadingHeaderView.isHidden = true
                                viewController.targetMessageId = nil
                                viewController.viewModel.viewState.currentTargetMessageId = nil
                                
                                print("❌ REPLY_TAP_CELL: Error loading reply message, states reset")
                            }
                        }
                        
                        // CRITICAL: Add fallback cleanup in case refreshWithTargetMessage doesn't throw but also doesn't succeed
                        await MainActor.run {
                            // Wait a bit then check if message was actually loaded
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if !viewController.viewModel.messages.contains(replyId) {
                                    print("⚠️ REPLY_TAP_CELL: Fallback cleanup - message still not loaded after refresh")
                                    self.hideReplyLoadingIndicator()
                                    self.showReplyNotFoundMessage()
                                    
                                    // Reset loading state
                                    viewController.messageLoadingState = .notLoading
                                    viewController.loadingHeaderView.isHidden = true
                                    viewController.targetMessageId = nil
                                    viewController.viewModel.viewState.currentTargetMessageId = nil
                                }
                            }
                        }
                    }
                } else {
                    hideReplyLoadingIndicator()
                    showReplyNotFoundMessage()
                    // print("❌ Could not find MessageableChannelViewController")
                }
            } else {
                // Different channel - show info message
                // print("📱 Reply is in different channel")
                showCrossChannelReplyAlert(replyMessage: replyMessage)
            }
        } else {
            // Reply message not found in viewState, try to load it
            // print("📱 Reply message not found in viewState, attempting to load")
            
            // Find the parent MessageableChannelViewController
            if let viewController = findParentViewController() as? MessageableChannelViewController {
                // CRITICAL FIX: Activate target message protection to prevent jumping
                print("🛡️ REPLY_TAP_CELL: Activating target message protection for loading")
                viewController.activateTargetMessageProtection(reason: "reply tap loading")
                
                // Clear any existing target message first
                let previousTarget = viewController.targetMessageId
                // print("📱 Clearing previous target: \(previousTarget ?? "none") -> setting new target: \(replyId)")
                viewController.targetMessageId = nil
                
                // Show loading indicator
                showReplyLoadingIndicator()
                
                // Use async task to refresh with target message
                Task {
                    do {
                        await viewController.refreshWithTargetMessage(replyId)
                        // Hide loading indicator after completion
                        await MainActor.run {
                            self.hideReplyLoadingIndicator()
                            
                            // Check if the message was successfully loaded and is visible
                            if !viewController.viewModel.messages.contains(replyId) {
                                // Message was not found or could not be loaded
                                self.showReplyNotFoundMessage()
                            } else {
                                print("✅ REPLY_TAP_CELL: Message loaded successfully after refresh")
                            }
                            
                            // FIXED: Don't clear protection with timer - let scroll detection handle it
                            // The target message protection will be cleared when user actually scrolls away
                            print("✅ REPLY_TAP_CELL: Loading completed, protection maintained until user scrolls away")
                        }
                    } catch {
                        // Ensure loading indicator is hidden on error
                        await MainActor.run {
                            self.hideReplyLoadingIndicator()
                            self.showReplyNotFoundMessage()
                            
                            // Reset loading state in view controller
                            viewController.messageLoadingState = .notLoading
                            viewController.loadingHeaderView.isHidden = true
                            viewController.targetMessageId = nil
                            viewController.viewModel.viewState.currentTargetMessageId = nil
                            
                            print("❌ REPLY_TAP_CELL: Error loading reply message (second path), states reset")
                        }
                    }
                    
                    // CRITICAL: Add fallback cleanup in case refreshWithTargetMessage doesn't throw but also doesn't succeed
                    await MainActor.run {
                        // Wait a bit then check if message was actually loaded
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if !viewController.viewModel.messages.contains(replyId) {
                                print("⚠️ REPLY_TAP_CELL: Fallback cleanup (path 2) - message still not loaded after refresh")
                                self.hideReplyLoadingIndicator()
                                self.showReplyNotFoundMessage()
                                
                                // Reset loading state
                                viewController.messageLoadingState = .notLoading
                                viewController.loadingHeaderView.isHidden = true
                                viewController.targetMessageId = nil
                                viewController.viewModel.viewState.currentTargetMessageId = nil
                            }
                        }
                    }
                }
            } else {
                hideReplyLoadingIndicator()
                showReplyNotFoundMessage()
                // print("❌ Could not find MessageableChannelViewController")
            }
        }
    }
}
