//
//  MessageCell+ContextMenu.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

extension MessageCell {
    @objc internal func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
       guard gesture.state == .began, let message = currentMessage else { return }
       
       // Show custom option sheet instead of UIAlertController
       if let viewController = findViewController() {
           // Capture the message to avoid nil references
           let capturedMessage = message
           
           // Check if user has permission to send messages (for reply option)
           let canReply = checkCanReply()
           
           let optionSheet = MessageOptionViewController(
               message: message,
               isMessageAuthor: isCurrentUserAuthor(),
               canDeleteMessage: canDeleteMessage(),
               canReply: canReply,
               onOptionSelected: { [weak self] action in
                   if let strongSelf = self {
                       strongSelf.onMessageAction?(action, capturedMessage)
                   }
               }
           )
           
           // Present as a modal with custom style
           optionSheet.modalPresentationStyle = .pageSheet
           if #available(iOS 15.0, *) {
               if let sheet = optionSheet.sheetPresentationController {
                   sheet.prefersGrabberVisible = true
                   sheet.detents = [.medium()]
                   sheet.preferredCornerRadius = 16
               }
           }
           
           viewController.present(optionSheet, animated: true)
       }
   }
    
    
    internal func showLinkContextMenu(for url: URL, at location: CGPoint) {
        // Create haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
                  // Find the view controller to present the menu
         guard let viewController = findParentViewController() else { return }
        
        // Create UIAlertController with action sheet style
        let alertController = UIAlertController(title: url.absoluteString, message: nil, preferredStyle: .actionSheet)
        
        // Copy Link action
        let copyAction = UIAlertAction(title: "Copy Link", style: .default) { _ in
            UIPasteboard.general.string = url.absoluteString
            Task { @MainActor in
                if let viewState = self.viewState {
                    viewState.showAlert(message: "Link Copied!", icon: .peptideLink)
                }
            }
        }
        
        // Open Link action
        let openAction = UIAlertAction(title: "Open Link", style: .default) { _ in
            // Handle internal peptide.chat links differently
            if url.absoluteString.hasPrefix("https://peptide.chat/") ||
               url.absoluteString.hasPrefix("https://app.revolt.chat/") {
                self.handleInternalURL(url, from: viewController)
            } else {
                // Open external links in Safari
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }
        }
        
        // Share Link action
        let shareAction = UIAlertAction(title: "Share Link", style: .default) { _ in
            let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            // For iPad, set source view for popover
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = self.contentLabel
                popover.sourceRect = CGRect(origin: location, size: CGSize(width: 1, height: 1))
            }
            
            viewController.present(activityController, animated: true)
        }
        
        // Cancel action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        // Add actions to alert controller
        alertController.addAction(copyAction)
        alertController.addAction(openAction)
        alertController.addAction(shareAction)
        alertController.addAction(cancelAction)
        
        // For iPad, set source view for popover
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = contentLabel
            popover.sourceRect = CGRect(origin: location, size: CGSize(width: 1, height: 1))
        }
        
        // Present the menu
        viewController.present(alertController, animated: true)
    }
    
    internal func checkCanReply() -> Bool {
        guard let viewState = viewState, let currentUser = viewState.currentUser else {
            return false
        }
        
        // Check if this is a DM channel
        if let channel = viewState.channels.first(where: { $0.key == currentMessage?.channel })?.value {
            if case .dm_channel(let dmChannel) = channel {
                if let otherUser = dmChannel.recipients.filter({ $0 != currentUser.id }).first {
                    let relationship = viewState.users.first(where: { $0.value.id == otherUser })?.value.relationship
                    return relationship != .Blocked && relationship != .BlockedOther
                }
            } else {
                // For server channels, check send messages permission
                if let server = viewState.servers.first(where: { $0.value.channels.contains(channel.id) })?.value {
                    let member = viewState.members[server.id]?[currentUser.id]
                    
                    let permissions = resolveChannelPermissions(
                        from: currentUser,
                        targettingUser: currentUser,
                        targettingMember: member,
                        channel: channel,
                        server: server
                    )
                    
                    return permissions.contains(Types.Permissions.sendMessages)
                }
            }
        }
        
        return true
    }
    
}
