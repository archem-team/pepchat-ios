//
//  MessageableChannelViewController+Skeleton.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import Combine
import Kingfisher
import ObjectiveC
import SwiftUI
import Types
import UIKit
import ULID

extension MessageableChannelViewController {
    // MARK: - Skeleton Loading Methods

    internal func showSkeletonView() {
        // Only show skeleton if not already shown
        guard skeletonView == nil else { return }

        let skeleton = MessageSkeletonView()
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(skeleton)

        NSLayoutConstraint.activate([
            skeleton.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            skeleton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeleton.bottomAnchor.constraint(equalTo: messageInputView.topAnchor),
        ])

        skeletonView = skeleton

        // Hide table view while showing skeleton
        tableView.alpha = 0.0

        print("💀 SKELETON: Showing skeleton loading view")
    }

    internal func hideSkeletonView() {
        guard let skeleton = skeletonView else { return }

        UIView.animate(
            withDuration: 0.3,
            animations: {
                skeleton.alpha = 0.0
            }
        ) { _ in
            skeleton.removeFromSuperview()
            self.skeletonView = nil
        }

        // Show table view
        UIView.animate(withDuration: 0.3) {
            self.tableView.alpha = 1.0
        }

        print("💀 SKELETON: Hiding skeleton loading view")
    }
}
