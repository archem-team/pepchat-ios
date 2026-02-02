//
//  MessageCell+AVPlayer.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

// MARK: - AVPlayerViewControllerDelegate
extension MessageCell {
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        cleanupTempVideos()
    }
    
    func playerViewControllerWillDismiss(_ playerViewController: AVPlayerViewController) {
        // print("🎬 Player will dismiss")
        cleanupTempVideos()
        
        // Stop the player to free resources
        playerViewController.player?.pause()
        playerViewController.player?.replaceCurrentItem(with: nil)
    }
    
    func playerViewControllerDidDismiss(_ playerViewController: AVPlayerViewController) {
        // print("🎬 Player did dismiss")
        cleanupTempVideos()
        
        // Hide and remove the video window
        DispatchQueue.main.async {
            MessageCell.videoWindow?.isHidden = true
            MessageCell.videoWindow?.resignKey()
            MessageCell.videoWindow = nil
            // print("🎬 Video window removed")
            
            // Post notification to refresh navigation state
            NotificationCenter.default.post(name: NSNotification.Name("VideoPlayerDidDismiss"), object: nil)
            
            // Try to fix navigation bar directly
            if let viewController = self.findParentViewController() {
                // print("🎬 Found parent controller: \(type(of: viewController))")
                
                // Check if it's MessageableChannelViewController
                if viewController is MessageableChannelViewController {
                    // print("🎬 It's MessageableChannelViewController, hiding navigation bar...")
                    viewController.navigationController?.setNavigationBarHidden(true, animated: false)
                    
                    // Force update the view
                    viewController.view.setNeedsLayout()
                    viewController.view.layoutIfNeeded()
                    
                    // Additional attempt to ensure navigation bar is hidden
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewController.navigationController?.setNavigationBarHidden(true, animated: false)
                    }
                }
            }
        }
    }
    
    func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        cleanupTempVideos()
    }
    
    // Also clean up when player finishes
    func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        cleanupTempVideos()
        
        // Clean up window when ending full screen
        coordinator.animate(alongsideTransition: nil) { _ in
            DispatchQueue.main.async {
                MessageCell.videoWindow?.isHidden = true
                MessageCell.videoWindow?.resignKey()
                MessageCell.videoWindow = nil
                // print("🎬 Video window removed after full screen ended")
            }
        }
    }
}
