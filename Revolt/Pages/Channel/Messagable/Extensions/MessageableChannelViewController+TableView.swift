//
//  MessageableChannelViewController+TableView.swift
//  Revolt
//
//

import UIKit
import Types

// MARK: - UITableViewDelegate
extension MessageableChannelViewController: UITableViewDelegate {
    // Note: UITableViewDataSource methods are now handled by LocalMessagesDataSource class
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // For reversed table view: last row (bottom) is the oldest message
        // Mark as loading when we reach the last row (bottom) where older messages should load
        if !localMessages.isEmpty && indexPath.row == localMessages.count - 1 {
            isLoadingMore = true
        }
        
        // Safety check for localMessages count
        guard !localMessages.isEmpty, indexPath.row < localMessages.count else {
            return
        }
        
        // PERFORMANCE: Cache cell height for future use
        let messageId = localMessages[indexPath.row]
        let cellHeight = cell.frame.height
        heightCache.setHeight(cellHeight, for: messageId, in: viewModel.channel.id)
        
        // For reversed table: row 0 is newest, so mark as seen when displayed
        if indexPath.row == 0 {
            markLastMessageAsSeen()
        }
        
        if let currentCell = cell as? MessageCell {
            if indexPath.row < localMessages.count - 1 {
                let nextMessageId = localMessages[indexPath.row + 1]
                let currentMessageId = localMessages[indexPath.row]
                
                if let nextMessage = viewModel.viewState.messages[nextMessageId],
                   let currentMessage = viewModel.viewState.messages[currentMessageId] {
                    if nextMessage.author != currentMessage.author {
                        currentCell.contentView.layoutMargins.bottom = 16
                    } else {
                        currentCell.contentView.layoutMargins.bottom = 4
                    }
                }
            }
        }
        
        loadMoreMessagesIfNeeded(for: indexPath)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Always use automatic dimension to let constraints determine the height
        // This prevents overlapping issues and ensures proper cell sizing
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // PERFORMANCE: Return cached height if available, otherwise use default estimate
        guard indexPath.row < localMessages.count else {
            return 150
        }
        
        let messageId = localMessages[indexPath.row]
        if let cachedHeight = heightCache.height(for: messageId, in: viewModel.channel.id) {
            return cachedHeight
        }
        
        return 150 // Default estimate for messages with markdown/embeds
    }

    
    // MARK: - Helper Methods
    
    func refreshMessagesWithoutScrolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Don't refresh if target message protection is active
            if self.targetMessageProtectionActive {
                return
            }
            
            // Just reload the data without scrolling
            self.tableView.reloadData()
            
            // Update empty state visibility
            self.updateEmptyStateVisibility()
        }
    }
    
    func updateEmptyStateVisibility() {
        // CRITICAL FIX: Don't show empty state during target message loading
        if targetMessageProtectionActive || messageLoadingState == .loading {
            hideEmptyStateView()
            return
        }
        
        if localMessages.isEmpty {
            showEmptyStateView()
        } else {
            hideEmptyStateView()
        }
    }
    
    private func showEmptyStateView() {
        // Check if already exists
        if view.viewWithTag(100) != nil {
            return
        }
        
        let emptyStateView = UIView()
        emptyStateView.tag = 100
        emptyStateView.backgroundColor = .clear
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create content container
        let contentContainer = UIStackView()
        contentContainer.axis = .vertical
        contentContainer.spacing = 16
        contentContainer.alignment = .center
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Channel icon
        let channelIconView = UIImageView()
        channelIconView.contentMode = .scaleAspectFit
        channelIconView.tintColor = UIColor(named: "iconGray04")
        channelIconView.translatesAutoresizingMaskIntoConstraints = false
        
        // Set icon based on channel type
        let iconName: String
        if viewModel.channel.isDM {
            iconName = "peptideDM"
        } else if viewModel.channel.isTextOrVoiceChannel {
            iconName = "peptideChannel"
        } else {
            iconName = "peptideGroup"
        }
        channelIconView.image = UIImage(named: iconName)
        
        // Channel name
        let channelNameLabel = UILabel()
        channelNameLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        channelNameLabel.textColor = UIColor(named: "textGray02")
        channelNameLabel.textAlignment = .center
        channelNameLabel.numberOfLines = 0
        
        if viewModel.channel.isDM {
            if let otherUserId = viewModel.channel.recipients.first(where: { $0 != viewModel.viewState.currentUser?.id }),
               let otherUser = viewModel.viewState.users[otherUserId] {
                channelNameLabel.text = otherUser.display_name ?? otherUser.username
            } else {
                channelNameLabel.text = "Direct Message"
            }
        } else {
            channelNameLabel.text = viewModel.channel.name ?? "Channel"
        }
        
        // Message
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
        
        emptyStateView.addSubview(contentContainer)
        view.addSubview(emptyStateView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: messageInputView.topAnchor),
            
            contentContainer.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            contentContainer.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            contentContainer.leadingAnchor.constraint(greaterThanOrEqualTo: emptyStateView.leadingAnchor, constant: 32),
            contentContainer.trailingAnchor.constraint(lessThanOrEqualTo: emptyStateView.trailingAnchor, constant: -32),
            
            channelIconView.widthAnchor.constraint(equalToConstant: 64),
            channelIconView.heightAnchor.constraint(equalToConstant: 64)
        ])
        
        // Bring to front
        view.bringSubviewToFront(emptyStateView)
    }
    
    private func hideEmptyStateView() {
        if let emptyStateView = view.viewWithTag(100) {
            emptyStateView.isHidden = true
            emptyStateView.removeFromSuperview()
        }
    }
}

