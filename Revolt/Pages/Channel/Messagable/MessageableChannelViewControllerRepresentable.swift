import SwiftUI
import UIKit
import Types

struct MessageableChannelViewControllerRepresentable: UIViewControllerRepresentable {
    var viewModel: MessageableChannelViewModel
    var toggleSidebar: () -> Void
    var targetMessageId: String?
    
    func makeUIViewController(context: Context) -> MessageableChannelViewController {
        let controller = MessageableChannelViewController(
            viewModel: viewModel, 
            toggleSidebar: toggleSidebar,
            targetMessageId: targetMessageId
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: MessageableChannelViewController, context: Context) {
        // print("🔄 updateUIViewController CALLED")
        
        // Update the view controller when the viewModel changes
        // CRITICAL FIX: Don't refresh messages if we have a target message ID
        // because refreshMessages might interfere with target scrolling
        if targetMessageId == nil {
            // print("🔄 Calling refreshMessages (no targetMessageId)")
            uiViewController.refreshMessages()
        } else {
            // print("🔄 Skipping refreshMessages (have targetMessageId: \(targetMessageId!))")
        }
        
        // Update target message ID if changed
        if uiViewController.targetMessageId != targetMessageId {
            // print("🚀 ========== REPRESENTABLE UPDATE ==========")
            // print("🔄 MessageableChannelViewControllerRepresentable: targetMessageId changed from \(uiViewController.targetMessageId ?? "nil") to \(targetMessageId ?? "nil")")
            // print("🔄 Current time: \(Date())")
            
            uiViewController.targetMessageId = targetMessageId
            
            if let messageId = targetMessageId {
                // print("🎯 MessageableChannelViewControllerRepresentable: Starting refreshWithTargetMessage for \(messageId)")
                
                // CRITICAL FIX: Check if target message is for the correct channel before calling refreshWithTargetMessage
                // This prevents calling it from the wrong view controller during navigation
                if let targetMessage = viewModel.viewState.messages[messageId] {
                    if targetMessage.channel == uiViewController.viewModel.channel.id {
                        // Target message is for this view controller's channel - safe to call
                        // print("🎯 REPRESENTABLE: Target message is for current channel \(uiViewController.viewModel.channel.id), calling refreshWithTargetMessage")
                        Task {
                            await uiViewController.refreshWithTargetMessage(messageId)
                        }
                    } else {
                        // Target message is for different channel - let the NEW view controller handle it
                        // print("🎯 REPRESENTABLE: Target message is for different channel \(targetMessage.channel), skipping (current: \(uiViewController.viewModel.channel.id))")
                    }
                } else {
                    // Target message not loaded yet - assume it's for different channel during navigation
                    // print("🎯 REPRESENTABLE: Target message not loaded yet, assuming cross-channel navigation - skipping")
                }
            } else {
                // print("🚫 MessageableChannelViewControllerRepresentable: targetMessageId was cleared")
            }
        } else {
            if let targetId = targetMessageId {
                // print("🔄 targetMessageId unchanged: \(targetId)")
                // REMOVED: Don't force refresh for unchanged targetMessageId to prevent multiple highlights
                // print("🔄 Skipping refresh for unchanged targetMessageId to prevent multiple highlights")
            }
        }
    }
    
    // Ensure the view uses the maximum available screen space
    static func dismantleUIViewController(_ uiViewController: MessageableChannelViewController, coordinator: ()) {
        // Clean up the view controller when it's being removed
    }
} 

// Extension to make sure the view takes up all available space
extension MessageableChannelViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MessageableChannelViewControllerRepresentable
        
        init(_ parent: MessageableChannelViewControllerRepresentable) {
            self.parent = parent
        }
    }
} 
