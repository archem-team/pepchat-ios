//
//  MessageableChannelViewController+EmptyState.swift
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

// MARK: - Empty State Handling
extension MessageableChannelViewController {

    internal func showEmptyStateView() {
        // If the empty state view already exists, just make sure it's visible
        if let existingView = view.viewWithTag(100) {
            existingView.isHidden = false
            return
        }

        // Create empty state container
        let emptyStateView = UIView()
        emptyStateView.tag = 100
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.backgroundColor = UIColor(named: "bgDefaultPurple13") ?? .systemBackground
        view.addSubview(emptyStateView)

        // Position between header and input view
        NSLayoutConstraint.activate([
            emptyStateView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: messageInputView.topAnchor),
        ])

        // Create container for content
        let contentContainer = UIStackView()
        contentContainer.axis = .vertical
        contentContainer.alignment = .center
        contentContainer.spacing = 16
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(contentContainer)

        // Center stack view in the empty state view
        NSLayoutConstraint.activate([
            contentContainer.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            contentContainer.centerYAnchor.constraint(
                equalTo: emptyStateView.centerYAnchor, constant: -40),  // Slight offset for better visual balance
            contentContainer.widthAnchor.constraint(
                lessThanOrEqualTo: emptyStateView.widthAnchor, multiplier: 0.8),
        ])

        // Channel Icon
        let channelIconView = UIImageView()
        channelIconView.translatesAutoresizingMaskIntoConstraints = false
        channelIconView.contentMode = .scaleAspectFit
        channelIconView.clipsToBounds = true
        channelIconView.layer.cornerRadius = 40
        channelIconView.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        channelIconView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        channelIconView.heightAnchor.constraint(equalToConstant: 80).isActive = true

        // Load channel icon based on channel type
        switch viewModel.channel {
        case .text_channel(let c):
            if let icon = c.icon {
                // Try to get the full URL for the channel icon
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(with: iconUrl)
                }
            } else {
                // Use hashtag icon for text channels
                channelIconView.image = UIImage(systemName: "number")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor.clear
            }

        case .voice_channel(let c):
            if let icon = c.icon {
                // Try to get the full URL for the channel icon
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(with: iconUrl)
                }
            } else {
                // Use speaker icon for voice channels
                channelIconView.image = UIImage(systemName: "speaker.wave.2.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor.clear
            }

        case .group_dm_channel(let c):
            if let icon = c.icon {
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(with: iconUrl)
                }
            } else {
                // Use group icon for group DM channels
                channelIconView.image = UIImage(systemName: "person.2.circle.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor(named: "bgGreen07")
            }

        case .dm_channel(let c):
            // For DM channels, show the other user's avatar
            if let recipient = viewModel.viewState.getDMPartnerName(channel: c) {
                let avatarInfo = viewModel.viewState.resolveAvatarUrl(
                    user: recipient, member: nil, masquerade: nil)

                // Always load avatar (either actual or default) from URL
                channelIconView.kf.setImage(with: avatarInfo.url)

                // Set background color based on whether user has avatar or not
                if !avatarInfo.isAvatarSet {
                    channelIconView.backgroundColor = UIColor(
                        hue: CGFloat(recipient.username.hashValue % 100) / 100.0,
                        saturation: 0.8,
                        brightness: 0.8,
                        alpha: 1.0
                    )
                } else {
                    channelIconView.backgroundColor = UIColor.clear
                }
            } else {
                // Fallback icon when recipient is nil
                channelIconView.image = UIImage(systemName: "person.circle.fill")
                channelIconView.tintColor = .iconDefaultGray01
                channelIconView.backgroundColor = UIColor(named: "bgGray11")
            }

        case .saved_messages(_):
            // Use bookmark icon for saved messages
            channelIconView.image = UIImage(systemName: "bookmark.circle.fill")
            channelIconView.tintColor = .iconDefaultGray01
            channelIconView.backgroundColor = UIColor(named: "bgGreen07")
        }

        // Channel name label
        let channelNameLabel = UILabel()
        channelNameLabel.text = viewModel.channel.getName(viewModel.viewState)
        channelNameLabel.font = UIFont.boldSystemFont(ofSize: 24)
        channelNameLabel.textColor = UIColor(named: "textDefaultGray01") ?? .label
        channelNameLabel.textAlignment = .center

        // Message label
        let messageLabel = UILabel()
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 16)
        messageLabel.textColor = UIColor(named: "textGray06") ?? .secondaryLabel

        // Choose appropriate message based on channel type
        let title: String
        if viewModel.channel.isDM {
            title = "This space is ready for your words. Start the convo!"
        } else if viewModel.channel.isTextOrVoiceChannel {
            title = "Your Channel Awaits. Say hi and break the ice with your first message."
        } else {
            title = "Your Group Awaits. Say hi and break the ice with your first message."
        }
        messageLabel.text = title

        // Add views to container
        contentContainer.addArrangedSubview(channelIconView)
        contentContainer.addArrangedSubview(channelNameLabel)
        contentContainer.addArrangedSubview(messageLabel)

        // Add spacing
        contentContainer.setCustomSpacing(24, after: channelIconView)
        contentContainer.setCustomSpacing(8, after: channelNameLabel)

        // Bring to front
        view.bringSubviewToFront(emptyStateView)
    }

    internal func hideEmptyStateView() {
        if let emptyStateView = view.viewWithTag(100) {
            emptyStateView.isHidden = true
        }
    }
}
