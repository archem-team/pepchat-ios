//
//  MessageableChannelViewController+Setup.swift
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
    internal func setupCustomHeader() {
        // Create the header container
        headerView = UIView()
        headerView.backgroundColor = .bgDefaultPurple13  // Changed from .bgGray12 to match chat background
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        // Back button (left)
        backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        backButton.tintColor = .textDefaultGray01
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        headerView.addSubview(backButton)

        // Channel icon (next to back button)
        channelIconView = UIImageView()
        channelIconView.translatesAutoresizingMaskIntoConstraints = false
        channelIconView.contentMode = .scaleAspectFit
        channelIconView.clipsToBounds = true
        channelIconView.layer.cornerRadius = 18  // Adjusted for the larger size (36/2)
        channelIconView.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        channelIconView.isUserInteractionEnabled = true
        headerView.addSubview(channelIconView)

        // Add tap gesture to channel icon
        let iconTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(channelHeaderTapped))
        channelIconView.addGestureRecognizer(iconTapGesture)

        // Channel name (next to icon)
        channelNameLabel = UILabel()
        channelNameLabel.text = viewModel.channel.getName(viewModel.viewState)
        channelNameLabel.textColor = .textDefaultGray01
        channelNameLabel.font = UIFont.boldSystemFont(ofSize: 16)
        channelNameLabel.translatesAutoresizingMaskIntoConstraints = false
        channelNameLabel.textAlignment = .left
        channelNameLabel.isUserInteractionEnabled = true
        headerView.addSubview(channelNameLabel)

        // Add tap gesture to channel name
        let nameTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(channelHeaderTapped))
        channelNameLabel.addGestureRecognizer(nameTapGesture)

        // Search button (right)
        searchButton = UIButton(type: .system)
        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.tintColor = .textDefaultGray01
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.addTarget(self, action: #selector(searchButtonTapped), for: .touchUpInside)
        headerView.addSubview(searchButton)

        // Load channel icon based on channel type
        switch viewModel.channel {
        case .text_channel(let c):
            if let icon = c.icon {
                // Try to get the full URL for the channel icon
                if let iconUrl = URL(string: viewModel.viewState.formatUrl(with: icon)) {
                    channelIconView.kf.setImage(
                        with: iconUrl,
                        placeholder: UIImage(systemName: "number"),
                        options: [
                            .transition(.fade(0.2)),
                            .cacheOriginalImage,
                        ]
                    )
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
                    channelIconView.kf.setImage(
                        with: iconUrl,
                        placeholder: UIImage(systemName: "speaker.wave.2.fill"),
                        options: [
                            .transition(.fade(0.2)),
                            .cacheOriginalImage,
                        ]
                    )
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
                    channelIconView.kf.setImage(
                        with: iconUrl,
                        placeholder: UIImage(systemName: "person.2.circle.fill"),
                        options: [
                            .transition(.fade(0.2)),
                            .cacheOriginalImage,
                        ]
                    )
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
                channelIconView.kf.setImage(
                    with: avatarInfo.url,
                    placeholder: UIImage(systemName: "person.circle.fill"),
                    options: [
                        .transition(.fade(0.2)),
                        .cacheOriginalImage,
                    ]
                )

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

        // Add bottom separator
        let separator = UIView()
        separator.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        separator.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(separator)

        // Setup constraints to position everything
        NSLayoutConstraint.activate([
            // Header view - Anchor to top edge of screen, not safe area
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 95),  // Reduced from 100

            // Back button - Position at the bottom left
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            backButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -15),  // Adjusted for smaller header
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 28),

            // Channel icon - Positioned next to back button
            channelIconView.leadingAnchor.constraint(
                equalTo: backButton.trailingAnchor, constant: 10),
            channelIconView.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            channelIconView.widthAnchor.constraint(equalToConstant: 36),  // Increased from 30
            channelIconView.heightAnchor.constraint(equalToConstant: 36),  // Increased from 30

            // Channel name - Positioned next to channel icon
            channelNameLabel.leadingAnchor.constraint(
                equalTo: channelIconView.trailingAnchor, constant: 10),
            channelNameLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            channelNameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: searchButton.leadingAnchor, constant: -10),

            // Search button - Position at the bottom right
            searchButton.trailingAnchor.constraint(
                equalTo: headerView.trailingAnchor, constant: -16),
            searchButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 28),
            searchButton.heightAnchor.constraint(equalToConstant: 28),

            // Separator at the bottom
            separator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 0),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
    
    internal func setupTableView() {
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false

        // Initialize the data source first (use LocalMessagesDataSource)
        dataSource = LocalMessagesDataSource(
            viewModel: viewModel, viewController: self, localMessages: localMessages)

        // Set up the table view
        tableView.delegate = self
        tableView.dataSource = dataSource
        tableView.prefetchDataSource = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: "MessageCell")
        tableView.register(SystemMessageCell.self, forCellReuseIdentifier: "SystemMessageCell")
        tableView.separatorStyle = .none
        tableView.backgroundColor = .bgDefaultPurple13

        tableView.keyboardDismissMode = .interactive
        tableView.estimatedRowHeight = 80  // Reduced for better performance
        tableView.rowHeight = UITableView.automaticDimension

        // PERFORMANCE: Enable cell prefetching and optimize scrolling
        tableView.isPrefetchingEnabled = true
        tableView.dragInteractionEnabled = false  // Disable drag to improve performance

        // PERFORMANCE: Optimize table view for better scrolling
        tableView.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0.996)  // Custom slower deceleration for longer scroll distance
        tableView.showsVerticalScrollIndicator = true
        tableView.showsHorizontalScrollIndicator = false

        // PERFORMANCE: Optimize content inset adjustment
        if #available(iOS 11.0, *) {
            tableView.contentInsetAdjustmentBehavior = .never
        }

        tableView.contentInsetAdjustmentBehavior = .never

        // Disable bouncing by default - will be enabled when content exceeds visible area
        tableView.alwaysBounceVertical = false
        tableView.bounces = false

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0.996)  // Custom slower deceleration for longer scroll distance

        // Don't add loading header view initially - will be added when needed
        // tableView.tableHeaderView = loadingHeaderView

        // CRITICAL: Hide table view initially to prevent visual jump
        tableView.alpha = 0.0

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // print some setup information for debugging
        // print("📋 Table view setup complete:")
        // print("   • ViewModel has \(viewModel.messages.count) messages")
        // print("   • ViewState has \(viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0) channel messages")
    }
    
    internal func setupMessageInput() {
        // Create a container for message input
        messageInputView = MessageInputView(frame: .zero)
        messageInputView.translatesAutoresizingMaskIntoConstraints = false
        messageInputView.delegate = messageInputHandler
        view.addSubview(messageInputView)

        // Add constraints for message input
        messageInputBottomConstraint = messageInputView.bottomAnchor.constraint(
            equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            messageInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageInputBottomConstraint!,
        ])

        // Update table view constraints to position it above the message input
        NSLayoutConstraint.activate([
            tableView.bottomAnchor.constraint(equalTo: messageInputView.topAnchor)
        ])

        // Reply container view is now managed by RepliesManager

        // Check permission and update UI accordingly
        if !permissionsManager.sendMessagePermission {
            messageInputView.isHidden = true
            permissionsManager.createAndShowNoPermissionView()
        }

        // Configure upload button based on uploadFiles permission
        messageInputView.uploadButtonEnabled = permissionsManager.userHasPermission(
            Types.Permissions.uploadFiles)

        // CRITICAL: Configure textView delegate BEFORE setting up mention functionality
        let textView = messageInputView.textView
        textView.delegate = self
        // print("DEBUG: Set textView.delegate to self (MessageableChannelViewController)")

        // Setup mention functionality AFTER setting delegate
        messageInputView.setupMentionFunctionality(
            viewState: viewModel.viewState, channel: viewModel.channel, server: viewModel.server)
    }
    
    // Setup new message button for scrolling to bottom
    internal func setupNewMessageButton() {
        // New message button
        newMessageButton = UIButton(type: .system)
        newMessageButton.translatesAutoresizingMaskIntoConstraints = false
        newMessageButton.backgroundColor = .systemBlue
        newMessageButton.layer.cornerRadius = 16
        newMessageButton.layer.masksToBounds = true
        newMessageButton.setTitle("New Messages", for: .normal)
        newMessageButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        newMessageButton.setTitleColor(.white, for: .normal)
        newMessageButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        newMessageButton.addTarget(
            self, action: #selector(newMessageButtonTapped), for: .touchUpInside)
        newMessageButton.layer.shadowColor = UIColor.black.cgColor
        newMessageButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        newMessageButton.layer.shadowOpacity = 0.3
        newMessageButton.layer.shadowRadius = 3

        // Add an icon to the button
        let arrowImage = UIImage(systemName: "arrow.down")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: arrowImage)
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        newMessageButton.addSubview(imageView)

        // Position the image on the left side of the button
        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: newMessageButton.centerYAnchor),
            imageView.leadingAnchor.constraint(
                equalTo: newMessageButton.leadingAnchor, constant: 10),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Adjust button title insets to make room for the image
        newMessageButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)

        // Hide the button initially
        newMessageButton.alpha = 0
        newMessageButton.isHidden = true

        // Add to view hierarchy
        view.addSubview(newMessageButton)

        // Position at the bottom center of the screen, above the message input
        NSLayoutConstraint.activate([
            newMessageButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            newMessageButton.bottomAnchor.constraint(
                equalTo: messageInputView.topAnchor, constant: -16),
            newMessageButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }
    
    internal func setupSwipeGesture() {
        // Create a pan gesture recognizer for left-to-right swipe
        let panGesture = UIPanGestureRecognizer(
            target: self, action: #selector(handleSwipeGesture(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }
    
    internal func setupBindings() {
        // Observe messages array changes in viewModel via NotificationCenter
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(messagesDidChange),
            name: NSNotification.Name("MessagesDidChange"),
            object: nil  // Changed from object: nil to capture all notifications with this name
        )

        // Observe message content edits (e.g. recipient edited message) for real-time UI update
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMessageContentDidChange),
            name: NSNotification.Name("MessageContentDidChange"),
            object: nil
        )

        // Add a direct observer to watch the tableView contentSize
        // This helps detect when new content is added
        tableView.addObserver(self, forKeyPath: "contentSize", options: [.new, .old], context: nil)
        contentSizeObserverRegistered = true

        // Initial reload
        refreshMessages()
    }
    
    // Additional helper to force scroll after a message is added
    internal func setupAdditionalMessageObservers() {
        // Listen for new messages through a simple notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewMessages),
            name: NSNotification.Name("NewMessagesReceived"),
            object: nil
        )

        // Add a network error observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkError),
            name: NSNotification.Name("NetworkErrorOccurred"),
            object: nil
        )

        // Add observer for new socket messages ONLY for new message indicator
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewSocketMessage),
            name: NSNotification.Name("NewSocketMessageReceived"),
            object: nil
        )

        // Add a timer to periodically check for scroll needed, but with a longer interval
        // This reduces unnecessary checks that could cause unwanted scrolling
        // CRITICAL FIX: Store timer to prevent memory leak
        scrollCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) {
            [weak self] _ in
            self?.checkForScrollNeeded()
        }

        // Start automatic memory cleanup timer to prevent memory crashes
        startMemoryCleanupTimer()

        // Add observer for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Add observer for channel search closed to detect returning from search
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChannelSearchClosed),
            name: NSNotification.Name("ChannelSearchClosed"),
            object: nil
        )

        // Add observer for video player dismiss
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVideoPlayerDismiss),
            name: NSNotification.Name("VideoPlayerDidDismiss"),
            object: nil
        )
    }
    
}
