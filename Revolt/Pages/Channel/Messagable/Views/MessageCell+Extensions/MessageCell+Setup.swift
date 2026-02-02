//
//  MessageCell+Setup.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

extension MessageCell {
    
    internal func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        
        // Reply view setup
        replyView.translatesAutoresizingMaskIntoConstraints = false
        replyView.isHidden = true // Hidden by default
        contentView.addSubview(replyView)
        
        // Add tap gesture to reply view
        replyView.isUserInteractionEnabled = true
        let replyTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleReplyTap))
        replyView.addGestureRecognizer(replyTapGesture)
        
        // Add visual feedback for tap
        replyView.layer.cornerRadius = 4
        replyView.layer.masksToBounds = true
        
        // Reply vertical line
        replyLineView.translatesAutoresizingMaskIntoConstraints = false
        replyLineView.backgroundColor = UIColor.systemGray.withAlphaComponent(0.7)
        replyLineView.layer.cornerRadius = 1
        replyView.addSubview(replyLineView)
        
        // Reply author label
        replyAuthorLabel.translatesAutoresizingMaskIntoConstraints = false
        replyAuthorLabel.font = UIFont.boldSystemFont(ofSize: 12)
        replyAuthorLabel.textColor = UIColor(named: "textGray06") ?? .systemGray
        replyView.addSubview(replyAuthorLabel)
        
        // Reply content label
        replyContentLabel.translatesAutoresizingMaskIntoConstraints = false
        replyContentLabel.font = UIFont.systemFont(ofSize: 12)
        replyContentLabel.textColor = UIColor(named: "textGray06") ?? .systemGray
        replyContentLabel.lineBreakMode = .byTruncatingTail
        replyContentLabel.numberOfLines = 1
        replyView.addSubview(replyContentLabel)
        
        // Reply loading indicator
        replyLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        replyLoadingIndicator.hidesWhenStopped = true
        replyLoadingIndicator.color = UIColor(named: "textGray06") ?? .systemGray
        replyView.addSubview(replyLoadingIndicator)
        
        // Avatar image
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 20 // Increased from 16
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        contentView.addSubview(avatarImageView)
        
        // Enable avatar tap
        avatarImageView.isUserInteractionEnabled = true
        let avatarTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleAvatarTap))
        avatarImageView.addGestureRecognizer(avatarTapGesture)
        
        // Username label
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.font = UIFont.boldSystemFont(ofSize: 16) // Increased size and made bolder
        usernameLabel.textColor = .white // Make username white for better contrast
        usernameLabel.numberOfLines = 1
        usernameLabel.lineBreakMode = .byTruncatingTail
        usernameLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        usernameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        usernameLabel.isUserInteractionEnabled = true
        let usernameTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleUsernameTap))
        usernameLabel.addGestureRecognizer(usernameTapGesture)
        contentView.addSubview(usernameLabel)
        
        // Time label
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.textColor = .textGray06
        contentView.addSubview(timeLabel)
        
        // Bridge badge label
        bridgeBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        bridgeBadgeLabel.text = "BRIDGE"
        bridgeBadgeLabel.font = UIFont.boldSystemFont(ofSize: 10)
        bridgeBadgeLabel.textColor = .white
        bridgeBadgeLabel.backgroundColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0) // Blue color
        bridgeBadgeLabel.layer.cornerRadius = 6
        bridgeBadgeLabel.clipsToBounds = true
        bridgeBadgeLabel.textAlignment = .center
        bridgeBadgeLabel.isHidden = true // Hidden by default
        
        // Add padding to the badge
        bridgeBadgeLabel.layer.masksToBounds = true
        contentView.addSubview(bridgeBadgeLabel)
        
        // Content text view - optimized for markdown and performance
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.font = UIFont.systemFont(ofSize: 15, weight: .light)
        contentLabel.textColor = .textDefaultGray01
        contentLabel.backgroundColor = .clear // Make background transparent
        contentLabel.isScrollEnabled = false // Disable scrolling
        contentLabel.isEditable = false // Make non-editable
        // isSelectable is set dynamically based on content type
        contentLabel.delaysContentTouches = false // Allow immediate gesture recognition
        contentLabel.dataDetectorTypes = [] // Disable automatic link detection since we handle it manually
        contentLabel.textContainerInset = .zero // Remove internal margins
        contentLabel.textContainer.lineFragmentPadding = 0 // Remove line padding
        contentLabel.delegate = self // Set delegate to handle URL interactions
        
        // PERFORMANCE OPTIMIZATION: Limit maximum number of lines for very long messages
        contentLabel.textContainer.maximumNumberOfLines = 0 // 0 means unlimited, but we'll control this programmatically
        contentLabel.textContainer.lineBreakMode = .byWordWrapping
        
        // Set content hugging and compression resistance priorities
        contentLabel.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        
        // Configure link colors
        contentLabel.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue
            // Removed underline
        ]
        
        contentView.addSubview(contentLabel)
        
        // Reactions container setup
        reactionsContainerView.translatesAutoresizingMaskIntoConstraints = false
        reactionsContainerView.isHidden = true // Hidden by default
        contentView.addSubview(reactionsContainerView)
        
        // Note: Reactions will be laid out using custom flow layout instead of stack view
        
        NSLayoutConstraint.activate([
            // Reply view constraints
            replyView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            replyView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            replyView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])

        // Create height constraint with lower priority
        let replyHeightConstraint = replyView.heightAnchor.constraint(equalToConstant: 18)
        replyHeightConstraint.priority = UILayoutPriority(999) // Just below required but still high
        replyHeightConstraint.isActive = true

        // Activate the rest of the constraints
        NSLayoutConstraint.activate([
            // Reply line view
            replyLineView.leadingAnchor.constraint(equalTo: replyView.leadingAnchor),
            replyLineView.topAnchor.constraint(equalTo: replyView.topAnchor),
            replyLineView.bottomAnchor.constraint(equalTo: replyView.bottomAnchor),
            replyLineView.widthAnchor.constraint(equalToConstant: 2),
            
            // Reply author label
            replyAuthorLabel.leadingAnchor.constraint(equalTo: replyLineView.trailingAnchor, constant: 4),
            replyAuthorLabel.centerYAnchor.constraint(equalTo: replyView.centerYAnchor),
            
            // Reply content label
            replyContentLabel.leadingAnchor.constraint(equalTo: replyAuthorLabel.trailingAnchor, constant: 4),
            replyContentLabel.trailingAnchor.constraint(equalTo: replyView.trailingAnchor),
            replyContentLabel.centerYAnchor.constraint(equalTo: replyView.centerYAnchor),
            
            // Reply loading indicator
            replyLoadingIndicator.centerXAnchor.constraint(equalTo: replyView.centerXAnchor),
            replyLoadingIndicator.centerYAnchor.constraint(equalTo: replyView.centerYAnchor),
            
            // Avatar - increased size
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40), // Increased from 32
            avatarImageView.heightAnchor.constraint(equalToConstant: 40), // Increased from 32
            
            // Username - adjusted for larger avatar
            usernameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            // Note: Top constraint for username will be set dynamically in updateAppearanceForContinuation
            
            // Time
            timeLabel.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 8),
            timeLabel.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            
            // Bridge badge
            bridgeBadgeLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 8),
            bridgeBadgeLabel.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            bridgeBadgeLabel.widthAnchor.constraint(equalToConstant: 50),
            bridgeBadgeLabel.heightAnchor.constraint(equalToConstant: 16),
            bridgeBadgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            
            // Content - adjusted for larger avatar
            contentLabel.leadingAnchor.constraint(equalTo: usernameLabel.leadingAnchor),
            contentLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 4),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
        
        // Note: Reactions container constraints are set dynamically in setupReactionsContainerConstraints()
        // when reactions are actually present to ensure proper positioning relative to content
    }
    
    internal func setupGestureRecognizer() {
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = self
        contentView.addGestureRecognizer(longPressGesture)
        
        // Add a long press gesture specifically for links in content label
        let linkLongPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLinkLongPress))
        linkLongPressGesture.minimumPressDuration = 0.5
        linkLongPressGesture.delegate = self
        contentLabel.addGestureRecognizer(linkLongPressGesture)
        
        // Make message long press wait for link long press to fail
        longPressGesture.require(toFail: linkLongPressGesture)
        
        // Add a tap gesture to handle taps on the content label specifically
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleContentTap))
        tapGesture.delegate = self
        tapGesture.require(toFail: longPressGesture) // Only trigger if long press fails
        tapGesture.require(toFail: linkLongPressGesture) // Only trigger if link long press fails
        contentLabel.addGestureRecognizer(tapGesture)
    }
    
    internal func setupSwipeGestureRecognizer() {
        // Enable pan gesture on cell content
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        // Ensure this doesn't interfere with tableview scrolling
        panGesture.delegate = self
        contentView.addGestureRecognizer(panGesture)
        
        // Set up the swipe reply icon view (initially hidden)
        setupSwipeReplyIcon()
    }
    
    private func setupSwipeReplyIcon() {
        // Create container view for the reply icon
        swipeReplyIconView = UIView()
        swipeReplyIconView?.translatesAutoresizingMaskIntoConstraints = false
        swipeReplyIconView?.backgroundColor = .clear
        swipeReplyIconView?.isHidden = true
        
        // Add circular background
        let circleView = UIView()
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = UIColor(named: "bgYellow07") ?? .systemYellow
        circleView.layer.cornerRadius = 16 // Start with small size
        
        // Create reply icon - using the proper Peptide icon if available
        // If PeptideIcon is not directly available in UIKit, use a system icon as fallback
        if let peptideReplyImage = UIImage(named: "peptideReply") {
            replyIconImageView = UIImageView(image: peptideReplyImage)
        } else {
            // Fallback to system icon
            replyIconImageView = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))
        }
        
        replyIconImageView?.translatesAutoresizingMaskIntoConstraints = false
        replyIconImageView?.tintColor = UIColor(named: "iconInverseGray13") ?? .white
        replyIconImageView?.contentMode = .scaleAspectFit
        
        if let swipeReplyIconView = swipeReplyIconView, let replyIconImageView = replyIconImageView {
            contentView.addSubview(swipeReplyIconView)
            swipeReplyIconView.addSubview(circleView)
            circleView.addSubview(replyIconImageView)
            
            NSLayoutConstraint.activate([
                // Position at trailing edge
                swipeReplyIconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                swipeReplyIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                swipeReplyIconView.widthAnchor.constraint(equalToConstant: 40),
                swipeReplyIconView.heightAnchor.constraint(equalToConstant: 40),
                
                // Circle constraints
                circleView.centerXAnchor.constraint(equalTo: swipeReplyIconView.centerXAnchor),
                circleView.centerYAnchor.constraint(equalTo: swipeReplyIconView.centerYAnchor),
                circleView.widthAnchor.constraint(equalToConstant: 32),
                circleView.heightAnchor.constraint(equalToConstant: 32),
                
                // Icon constraints
                replyIconImageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
                replyIconImageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
                replyIconImageView.widthAnchor.constraint(equalToConstant: 16),
                replyIconImageView.heightAnchor.constraint(equalToConstant: 16)
            ])
        }
    }
    
}
