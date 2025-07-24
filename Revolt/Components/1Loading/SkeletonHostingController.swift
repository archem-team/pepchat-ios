import UIKit
import SwiftUI

/// A UIKit wrapper for SwiftUI skeleton loading views
/// This allows us to use SwiftUI skeleton components in UIKit view controllers
class SkeletonHostingController: UIHostingController<ChatSkeletonView> {
    
    init(messageCount: Int = 8) {
        let skeletonView = ChatSkeletonView(messageCount: messageCount)
        super.init(rootView: skeletonView)
        
        // Set background to match the chat interface
        view.backgroundColor = UIColor.bgDefaultPurple13
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure the hosting controller
        view.translatesAutoresizingMaskIntoConstraints = false
    }
}

/// Extension to help integrate skeleton view into existing table view setup
extension MessageableChannelViewController {
    
    /// Shows skeleton loading view while messages are being loaded
    func showSkeletonLoadingView() {
        // Remove any existing spinner
        tableView.tableFooterView = nil
        
        // If we have no messages, show full skeleton overlay
        if localMessages.isEmpty {
            showFullSkeletonOverlay()
        } else {
            // If we have some messages, just show loading footer
            showSkeletonFooter()
        }
    }
    
    /// Shows a full skeleton overlay covering the entire table view
    private func showFullSkeletonOverlay() {
        // Remove any existing skeleton view
        hideSkeletonLoadingView()
        
        let skeletonController = SkeletonHostingController(messageCount: 6)
        
        // Add as child view controller
        addChild(skeletonController)
        view.addSubview(skeletonController.view)
        
        // Position it over the table view
        skeletonController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            skeletonController.view.topAnchor.constraint(equalTo: tableView.topAnchor),
            skeletonController.view.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            skeletonController.view.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            skeletonController.view.bottomAnchor.constraint(equalTo: tableView.bottomAnchor)
        ])
        
        skeletonController.didMove(toParent: self)
        
        // Store reference for cleanup
        view.accessibilityIdentifier = "skeletonOverlay"
        skeletonController.view.tag = 999 // Tag for easy identification
        
        // Hide the actual table view content
        tableView.alpha = 0.3
    }
    
    /// Shows skeleton footer for when loading more messages
    private func showSkeletonFooter() {
        let footerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 200))
        
        let skeletonController = SkeletonHostingController(messageCount: 3)
        footerView.addSubview(skeletonController.view)
        
        skeletonController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            skeletonController.view.topAnchor.constraint(equalTo: footerView.topAnchor),
            skeletonController.view.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            skeletonController.view.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            skeletonController.view.bottomAnchor.constraint(equalTo: footerView.bottomAnchor)
        ])
        
        tableView.tableFooterView = footerView
    }
    
    /// Hides skeleton loading view and shows actual content
    func hideSkeletonLoadingView() {
        // Remove skeleton overlay
        if let skeletonView = view.subviews.first(where: { $0.tag == 999 }) {
            if let parentController = children.first(where: { $0.view == skeletonView }) {
                parentController.willMove(toParent: nil)
                parentController.view.removeFromSuperview()
                parentController.removeFromParent()
            }
        }
        
        // Remove footer skeleton
        if tableView.tableFooterView != nil {
            tableView.tableFooterView = nil
        }
        
        // Restore table view visibility
        tableView.alpha = 1.0
    }
} 