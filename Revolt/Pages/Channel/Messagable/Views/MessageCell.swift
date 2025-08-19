//
//  MessageCell.swift
//  Revolt
//

import UIKit
import Types
import Kingfisher
import AVKit

// MARK: - MessageCell
class MessageCell: UITableViewCell, UITextViewDelegate, AVPlayerViewControllerDelegate {
    private let messageContentView = UIView()
    private let avatarImageView = UIImageView()
    private let usernameLabel = UILabel()
    private let contentLabel = UITextView() // Changed from UILabel to UITextView
    private let timeLabel = UILabel()
    private let bridgeBadgeLabel = UILabel() // Badge for bridged messages
    private var imageAttachmentsContainer: UIView?
    private var imageAttachmentViews: [UIImageView] = []
    private var fileAttachmentsContainer: UIView?
    private var fileAttachmentViews: [UIView] = []
    private var viewState: ViewState?
    

    
    // Reply components
    private let replyView = UIView()
    private let replyLineView = UIView()
    private let replyAuthorLabel = UILabel()
    private let replyContentLabel = UILabel()
    private var currentReplyId: String? // Store the ID of the message being replied to
    private let replyLoadingIndicator = UIActivityIndicatorView(style: .medium)
    
    // Loading alert reference and timeout timer
    private weak var loadingAlert: UIAlertController?
    private var loadingAlertTimer: Timer?
    
    // Reply loading timeout work item
    private var replyLoadingTimeoutWorkItem: DispatchWorkItem?
    
    // Add access to contentLabel
    var textViewContent: UITextView {
        return contentLabel
    }
    
    // Store message and author for use in context menu actions
    private var currentMessage: Message?
    private var currentAuthor: User?
    private var currentMember: Member?
    
    // Reactions container
    private let reactionsContainerView = UIView()
    
    // Swipe to reply properties
    private var initialTouchPoint: CGPoint = .zero
    
    deinit {
        // Clean up any existing loading alert and timer
        loadingAlertTimer?.invalidate()
        loadingAlert?.dismiss(animated: false)
        
        // Cancel any pending reply loading timeout
        replyLoadingTimeoutWorkItem?.cancel()
    }
    private var originalCenter: CGPoint = .zero
    private var swipeReplyIconView: UIView?
    private var replyIconImageView: UIImageView?
    private var isSwiping: Bool = false
    private var actionTriggered: Bool = false
    private var swipeThreshold: CGFloat = 80.0
    
    // MARK: - Custom highlight properties
    // Use a descriptive property name to avoid conflicts with UITableViewCell's isHighlighted
    public var isTargetMessageHighlighted: Bool = false
    public var originalBackgroundColorForHighlight: UIColor?
    
    // Additional property to determine if this is a continuation message
    var isContinuation: Bool = false {
        didSet {
            updateAppearanceForContinuation()
        }
    }
    
    // Property to track if this message is pending (optimistic update)
    var isPendingMessage: Bool = false {
        didSet {
            updatePendingAppearance()
        }
    }
    
    // Callback for message actions
    var onMessageAction: ((MessageAction, Message) -> Void)?
    var onImageTapped: ((UIImage) -> Void)?
    var onAvatarTap: (() -> Void)?
    var onUsernameTap: (() -> Void)?
    
    enum MessageAction {
        case edit
        case delete
        case report
        case copy
        case reply
        case mention
        case markUnread
        case copyLink
        case copyId
        case react(String)
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        setupGestureRecognizer()
        setupSwipeGestureRecognizer()
        
        // Set default layout margins
        contentView.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // PERFORMANCE OPTIMIZATION: Clear all content to prevent overlapping issues
        avatarImageView.image = nil
        contentLabel.text = nil
        contentLabel.attributedText = nil // Clear rich text
        contentLabel.isSelectable = false // Reset selection state
        contentLabel.isUserInteractionEnabled = true // Reset interaction state
        usernameLabel.text = nil
        timeLabel.text = nil
        
        // Hide bridge badge
        bridgeBadgeLabel.isHidden = true
        
        // Reset reply view
        replyAuthorLabel.text = nil
        replyContentLabel.text = nil
        replyView.isHidden = true
        currentReplyId = nil // Reset reply ID
        replyLoadingIndicator.stopAnimating() // Stop loading indicator
        replyAuthorLabel.isHidden = false // Reset visibility
        replyContentLabel.isHidden = false // Reset visibility
        replyContentLabel.font = UIFont.systemFont(ofSize: 12) // Reset font
        replyContentLabel.textColor = UIColor(named: "textGray06") ?? .systemGray // Reset color
        
        // CRITICAL: Clean up any existing loading alert
        hideReplyLoadingIndicator()
        
        // Cancel any pending reply loading timeout
        replyLoadingTimeoutWorkItem?.cancel()
        
        // PERFORMANCE: Cancel any ongoing image downloads with priority
        avatarImageView.kf.cancelDownloadTask()
        
        // PERFORMANCE: Aggressively clean up image attachments
        imageAttachmentViews.forEach { imageView in
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
            // Remove any loading overlays
            imageView.subviews.forEach { if $0.tag == 9998 { $0.removeFromSuperview() } }
            imageView.removeFromSuperview() // Ensure removal from view hierarchy
        }
        imageAttachmentViews.removeAll(keepingCapacity: false) // Don't keep capacity
        imageAttachmentsContainer?.removeFromSuperview()
        imageAttachmentsContainer = nil
        
        // PERFORMANCE: Aggressively clean up file attachments
        fileAttachmentViews.forEach { fileView in
            // If this is an audio player view, stop any playback immediately
            if let audioPlayerView = fileView as? AudioPlayerView {
                // Force stop any audio playback for this cell
                audioPlayerView.stopPlayback()
            }
            fileView.removeFromSuperview() // Ensure removal from view hierarchy
        }
        fileAttachmentViews.removeAll(keepingCapacity: false) // Don't keep capacity
        fileAttachmentsContainer?.removeFromSuperview()
        fileAttachmentsContainer = nil
        
        // PERFORMANCE: Clear reactions aggressively
        reactionsContainerView.subviews.forEach { subview in
            // Cancel any Kingfisher tasks on emoji images
            if let stackView = subview.subviews.first as? UIStackView {
                stackView.arrangedSubviews.forEach { arrangedSubview in
                    if let emojiImageView = arrangedSubview as? UIImageView {
                        emojiImageView.kf.cancelDownloadTask()
                        emojiImageView.image = nil
                    }
                }
            }
            subview.removeFromSuperview()
        }
        reactionsContainerView.isHidden = true
        clearReactionsContainerConstraints()
        
        // PERFORMANCE: Clear embeds container
        if let embedContainer = contentView.viewWithTag(2000) {
            embedContainer.removeFromSuperview()
        }
        
        // PERFORMANCE: Clear content label bottom constraints for clean reuse
        clearContentLabelBottomConstraints()
        
        // PERFORMANCE: Clear ALL dynamic constraints that might cause layout conflicts
        clearDynamicConstraints()
        
        // PERFORMANCE: Reset visibility states to defaults quickly
        avatarImageView.isHidden = false
        usernameLabel.isHidden = false
        timeLabel.isHidden = false
        bridgeBadgeLabel.isHidden = true
        
        // PERFORMANCE: Reset properties to defaults (avoid retain cycles)
        // NOTE: Don't reset currentMessage, currentAuthor, currentMember, viewState here 
        // as they might be needed for delayed UI interactions like reaction taps
        // They will be properly set in configure() method
        isPendingMessage = false
        
        // PERFORMANCE: Reset swipe state immediately
        isSwiping = false
        actionTriggered = false
        contentView.transform = .identity
        swipeReplyIconView?.isHidden = true
        
        // PERFORMANCE: Clear highlight state when reusing cell
        isTargetMessageHighlighted = false
        originalBackgroundColorForHighlight = nil
        contentView.transform = .identity
        contentView.layer.borderWidth = 0.0
        contentView.backgroundColor = .clear
        tag = 0
        
        // PERFORMANCE: Clean up any temp video files immediately
        cleanupTempVideos()
        
        // PERFORMANCE: Clean up video window if cell is reused
        if MessageCell.videoWindow != nil {
            MessageCell.videoWindow?.isHidden = true
            MessageCell.videoWindow?.resignKey()
            MessageCell.videoWindow = nil
        }
        
        // PERFORMANCE: Remove any spacer views
        if let spacerView = contentView.viewWithTag(1001) {
            spacerView.removeFromSuperview()
        }
        
        // PERFORMANCE: Clear debug spacer
        if let debugSpacer = contentView.viewWithTag(9999) {
            debugSpacer.removeFromSuperview()
        }
    }
    
    // MARK: - Cleanup Helper
    private func cleanupTempVideos() {
        if !tempVideoURLs.isEmpty {
            // print("🧹 Cleaning up \(tempVideoURLs.count) temp video files...")
        }
        for url in tempVideoURLs {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    // print("✅ Deleted temp video: \(url.lastPathComponent)")
                }
            } catch {
                // print("❌ Failed to delete temp video: \(error)")
            }
        }
        tempVideoURLs.removeAll()
    }
    

    private func setupUI() {
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
    
    private func updateAppearanceForContinuation() {
        // Debug log for tracking
        // if !(currentMessage?.attachments?.isEmpty ?? true) {
        //     // print("🖼️ updateAppearanceForContinuation: isContinuation: \(isContinuation)")
        // }
        
        // Hide avatar and username for continuation messages
        avatarImageView.isHidden = isContinuation
        usernameLabel.isHidden = isContinuation
        timeLabel.isHidden = isContinuation
        bridgeBadgeLabel.isHidden = isContinuation || currentMessage?.masquerade == nil
        
        // Note: We no longer automatically hide reply view for continuation messages
        // This allows replies to be shown even in continuation messages
        
        // Remove ALL existing constraints that we want to modify - more comprehensive cleanup
        var constraintsToRemove: [NSLayoutConstraint] = []
        
        for constraint in contentView.constraints {
            let shouldRemove = (
                // Content label constraints
                (constraint.firstItem === contentLabel && 
                 (constraint.firstAttribute == .top || constraint.firstAttribute == .leading)) ||
                // Username label constraints
                (constraint.firstItem === usernameLabel && 
                 (constraint.firstAttribute == .top || constraint.firstAttribute == .height)) ||
                // Constraints that connect to username label
                (constraint.secondItem === usernameLabel && 
                 (constraint.secondAttribute == .bottom || constraint.secondAttribute == .top))
            )
            
            if shouldRemove {
                constraintsToRemove.append(constraint)
            }
        }
        
        // Remove the identified constraints
        constraintsToRemove.forEach { $0.isActive = false }
        
        // Apply appropriate constraints based on continuation status
        if isContinuation {
            // For continuation messages, adjust layout for with/without reply
            if replyView.isHidden {
                // Standard continuation without reply
                NSLayoutConstraint.activate([
                    contentLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                    contentLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10)
                ])
            } else {
                // Continuation with reply
                NSLayoutConstraint.activate([
                    contentLabel.topAnchor.constraint(equalTo: replyView.bottomAnchor, constant: 8),
                    contentLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10)
                ])
            }
        } else {
            // For first messages in a group, ALWAYS set username constraints
            let topAnchor = replyView.isHidden ? contentView.topAnchor : replyView.bottomAnchor
            let usernameTopConstraint = usernameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8)
            let usernameHeightConstraint = usernameLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 19)
            usernameHeightConstraint.priority = UILayoutPriority.defaultHigh // Lower priority to avoid conflicts
            let contentTopConstraint = contentLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 4)
            let contentLeadingConstraint = contentLabel.leadingAnchor.constraint(equalTo: usernameLabel.leadingAnchor)
            
            NSLayoutConstraint.activate([
                usernameTopConstraint,
                usernameHeightConstraint,
                contentTopConstraint,
                contentLeadingConstraint
            ])
            
            // Extra debug log
            // if !(currentMessage?.attachments?.isEmpty ?? true) {
            //     // print("🖼️ Set username constraints for message with attachments - username should be visible")
            // }
        }
        
        // Force layout update to ensure proper positioning
        setNeedsLayout()
        layoutIfNeeded()
        
        // Final debug log after layout
        // if !(currentMessage?.attachments?.isEmpty ?? true) {
        //     // print("🖼️ Final check - usernameLabel.isHidden: \(usernameLabel.isHidden), frame: \(usernameLabel.frame)")
        // }
    }
    
    private func updatePendingAppearance() {
        let alpha: CGFloat = isPendingMessage ? 0.6 : 1.0
        
        // Apply reduced opacity to all message elements when pending
        UIView.animate(withDuration: 0.2) {
            self.avatarImageView.alpha = alpha
            self.usernameLabel.alpha = alpha
            self.contentLabel.alpha = alpha
            self.timeLabel.alpha = alpha
            self.bridgeBadgeLabel.alpha = alpha
            self.replyView.alpha = alpha
            self.imageAttachmentsContainer?.alpha = alpha
            self.fileAttachmentsContainer?.alpha = alpha
            self.reactionsContainerView.alpha = alpha
        }
        
        // Add a subtle pending indicator if needed
        if isPendingMessage {
            // Add a clock icon to indicate pending status
            if timeLabel.text?.contains("⏳") == false {
                timeLabel.text = "⏳ " + (timeLabel.text ?? "")
            }
        } else {
            // Remove pending indicator
            if let text = timeLabel.text, text.hasPrefix("⏳ ") {
                timeLabel.text = String(text.dropFirst(2))
            }
        }
    }
    
    private func loadEmbeds(embeds: [Embed], viewState: ViewState) {
        // Remove any existing embed container
        if let embedContainer = contentView.viewWithTag(2000) {
            embedContainer.removeFromSuperview()
        }
        
        // Show all embed types for link previews
        guard !embeds.isEmpty else { return }
        
        // Create container for embeds
        let embedContainer = UIStackView()
        embedContainer.axis = .vertical
        embedContainer.spacing = 8
        embedContainer.translatesAutoresizingMaskIntoConstraints = false
        embedContainer.tag = 2000
        
        // Add each embed
        for embed in embeds {
            let linkPreview = LinkPreviewView()
            linkPreview.translatesAutoresizingMaskIntoConstraints = false
            linkPreview.configure(with: embed, viewState: viewState)
            embedContainer.addArrangedSubview(linkPreview)
        }
        
        // Only add container if it has content
        if !embedContainer.arrangedSubviews.isEmpty {
            contentView.addSubview(embedContainer)
            
            // Position below content label or attachments to prevent overlap
            var topAnchor: NSLayoutYAxisAnchor
            var topConstant: CGFloat = 12
            
            if let fileContainer = fileAttachmentsContainer, !fileContainer.isHidden {
                topAnchor = fileContainer.bottomAnchor
            } else if let imageContainer = imageAttachmentsContainer, !imageContainer.isHidden {
                topAnchor = imageContainer.bottomAnchor
                topConstant = 16 // Extra spacing after images
            } else {
                topAnchor = contentLabel.bottomAnchor
            }
            
            // Create bottom constraint to ensure embeds contribute to cell height
            let bottomConstraint = embedContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
            bottomConstraint.priority = UILayoutPriority.defaultHigh
            
            NSLayoutConstraint.activate([
                embedContainer.topAnchor.constraint(equalTo: topAnchor, constant: topConstant),
                embedContainer.leadingAnchor.constraint(equalTo: contentLabel.leadingAnchor),
                embedContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                bottomConstraint
            ])
        }
    }
    
    private func setupGestureRecognizer() {
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
    
    private func setupSwipeGestureRecognizer() {
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
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        // Check if user has permission to reply before allowing swipe
        guard checkCanReply() else {
            return
        }
        
        let translation = gesture.translation(in: contentView)
        
        switch gesture.state {
        case .began:
            // Store original positions
            originalCenter = contentView.center
            initialTouchPoint = gesture.location(in: contentView)
            isSwiping = false
            actionTriggered = false
            
        case .changed:
            // Determine if this is a horizontal swipe
            let horizontalMovement = abs(translation.x) > abs(translation.y)
            
            // Only respond to left swipes (negative x translation)
            if horizontalMovement && translation.x < 0 {
                isSwiping = true
                
                // Move the content view
                let newX = originalCenter.x + translation.x
                contentView.center = CGPoint(x: newX, y: originalCenter.y)
                
                // Show and update the reply icon
                updateSwipeReplyIcon(withOffset: abs(translation.x))
                
                // Trigger the reply action if swiped far enough
                if abs(translation.x) >= swipeThreshold && !actionTriggered {
                    actionTriggered = true
                    triggerReplyAction()
                }
            }
            
        case .ended, .cancelled:
            if isSwiping {
                // Animate back to original position
                UIView.animate(
                    withDuration: 0.5,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0.5,
                    options: [.curveEaseInOut],
                    animations: { [weak self] in
                        self?.contentView.center = self?.originalCenter ?? .zero
                        self?.swipeReplyIconView?.isHidden = true
                        self?.isSwiping = false
                    }, 
                    completion: nil
                )
            }
            
        default:
            break
        }
    }
    
    private func updateSwipeReplyIcon(withOffset offset: CGFloat) {
        guard let swipeReplyIconView = swipeReplyIconView,
              let circleView = swipeReplyIconView.subviews.first else { return }
        
        // Show the reply icon
        swipeReplyIconView.isHidden = false
        
        // Calculate size based on swipe distance (min 32, max 40)
        let iconSize = min(40, max(32, 32 + (offset / swipeThreshold) * 8))
        
        // Update circle size
        circleView.layer.cornerRadius = iconSize / 2
        
        // Update constraints
        for constraint in circleView.constraints {
            if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                constraint.constant = iconSize
            }
        }
        
        // Update icon size
        if let iconImageView = circleView.subviews.first {
            for constraint in iconImageView.constraints {
                if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                    constraint.constant = iconSize * 0.5
                }
            }
        }
    }
    
    private func triggerReplyAction() {
        // Add haptic feedback to indicate action triggered successfully
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        // Call the reply action with a slight delay to ensure the animation is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, let message = self.currentMessage else { return }
            self.onMessageAction?(.reply, message)
        }
    }
    
    @objc private func handleContentTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: contentLabel)
        
        // Check if tap is on a link
        let textContainer = contentLabel.textContainer
        let layoutManager = contentLabel.layoutManager
        let textStorage = contentLabel.textStorage
        
        // Convert the tap location to text position
        let characterIndex = layoutManager.characterIndex(for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        
        // Check if the character at this index has a link attribute
        if characterIndex < textStorage.length {
            let attributes = textStorage.attributes(at: characterIndex, effectiveRange: nil)
            if let url = attributes[.link] as? URL {
                // Handle the link tap manually
                _ = textView(contentLabel, shouldInteractWith: url, in: NSRange(location: characterIndex, length: 1), interaction: .invokeDefaultAction)
                return
            }
        }
        
        // If no link was tapped, do nothing (let other gestures handle it)
    }
    
    @objc private func handleLinkLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        
        let location = gesture.location(in: contentLabel)
        
        // Check if long press is on a link
        let textContainer = contentLabel.textContainer
        let layoutManager = contentLabel.layoutManager
        let textStorage = contentLabel.textStorage
        
        // Convert the tap location to text position
        let characterIndex = layoutManager.characterIndex(for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        
        // Check if the character at this index has a link attribute
        if characterIndex < textStorage.length {
            let attributes = textStorage.attributes(at: characterIndex, effectiveRange: nil)
            if let url = attributes[.link] as? URL {
                // Show link-specific context menu
                showLinkContextMenu(for: url, at: location)
                return
            }
                 }
     }
     
     private func showLinkContextMenu(for url: URL, at location: CGPoint) {
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
     
     @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
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
    
    private func isCurrentUserAuthor() -> Bool {
        guard let message = currentMessage, let viewState = viewState else { return false }
        return message.author == viewState.currentUser?.id
    }
    
    private func canDeleteMessage() -> Bool {
        guard let message = currentMessage, let viewState = viewState, let currentUser = viewState.currentUser else {
            return isCurrentUserAuthor()
        }
        
        // Check if user is the message author
        if isCurrentUserAuthor() {
            return true
        }
        
        // For DM channels, only the author can delete messages
        if case .dm_channel(_) = viewState.channels[message.channel] {
            return false
        }
        if case .group_dm_channel(_) = viewState.channels[message.channel] {
            return false
        }
        
        // For server channels, check if user has manage messages permission
        guard let channel = viewState.channels[message.channel],
              let server = channel.server.flatMap({ viewState.servers[$0] }) else {
            return false
        }
        
        let member = viewState.members[server.id]?[currentUser.id]
        
        let permissions = resolveChannelPermissions(
            from: currentUser,
            targettingUser: currentUser,
            targettingMember: member,
            channel: channel,
            server: server
        )
        
        return permissions.contains(.manageMessages)
    }
    
    private func checkCanReply() -> Bool {
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
    
    private func findParentViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            responder = responder?.next
            if let viewController = responder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
    
    // Find the root view controller
    private func findRootViewController() -> UIViewController? {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        return window.rootViewController
    }
    
    private func clearContentLabelBottomConstraints() {
        // Remove any existing bottom constraints for the content label
        for constraint in contentView.constraints {
            if constraint.firstItem === contentLabel && 
               constraint.firstAttribute == .bottom {
                constraint.isActive = false
            }
        }
    }
    
    private func clearDynamicConstraints() {
        // Remove all dynamic constraints that are created during configuration
        var constraintsToRemove: [NSLayoutConstraint] = []
        
        for constraint in contentView.constraints {
            let shouldRemove = (
                // Content label dynamic constraints
                (constraint.firstItem === contentLabel && 
                 (constraint.firstAttribute == .top || constraint.firstAttribute == .leading)) ||
                // Username label dynamic constraints  
                (constraint.firstItem === usernameLabel && 
                 (constraint.firstAttribute == .top || constraint.firstAttribute == .height)) ||
                // Constraints that connect to username label
                (constraint.secondItem === usernameLabel && 
                 (constraint.secondAttribute == .bottom || constraint.secondAttribute == .top)) ||
                // Image attachments container constraints
                (constraint.firstItem === imageAttachmentsContainer) ||
                (constraint.secondItem === imageAttachmentsContainer) ||
                // File attachments container constraints
                (constraint.firstItem === fileAttachmentsContainer) ||
                (constraint.secondItem === fileAttachmentsContainer) ||
                // Reactions container constraints
                (constraint.firstItem === reactionsContainerView) ||
                (constraint.secondItem === reactionsContainerView) ||
                // Spacer view constraints (tag 1001)
                (constraint.firstItem is UIView && (constraint.firstItem as? UIView)?.tag == 1001) ||
                (constraint.secondItem is UIView && (constraint.secondItem as? UIView)?.tag == 1001)
            )
            
            if shouldRemove {
                constraintsToRemove.append(constraint)
            }
        }
        
        // Remove the identified constraints safely
        constraintsToRemove.forEach { constraint in
            constraint.isActive = false
        }
        
        // Clear the array to help with memory management
        constraintsToRemove.removeAll()
    }
    
    
    func configure(with message: Message, author: User, member: Member?, viewState: ViewState, isContinuation: Bool = false) {
        // Store the data for later use in context menu
        self.currentMessage = message
        self.currentAuthor = author
        self.currentMember = member
        self.viewState = viewState
        self.isContinuation = isContinuation
        
        // Pending state will be set by the data source based on queued messages
        
        // Clear any existing dynamic constraints before configuration to prevent overlapping
        clearDynamicConstraints()
        
        // Configure reply view
        if let replies = message.replies, !replies.isEmpty {
            replyView.isHidden = false
            configureReplyView(message: message, replies: replies, viewState: viewState)
        } else {
            replyView.isHidden = true
        }
        
        // Configure username (prioritize masquerade name, then nickname, then display name)
        let displayName = message.masquerade?.name ?? member?.nickname ?? author.display_name ?? author.username
        usernameLabel.text = displayName
        usernameLabel.font = UIFont.boldSystemFont(ofSize: 16)
        
        // Show bridge badge if message has masquerade (indicating it's bridged)
        bridgeBadgeLabel.isHidden = message.masquerade == nil
        
        // Configure content with improved performance
        configureMessageContent(message: message, viewState: viewState)
        
        // Configure time - for pending messages, try to get queued timestamp, otherwise use createdAt
        let date: Date
        if isPendingMessage, 
           let channelQueuedMessages = viewState.queuedMessages[message.channel],
           let queuedMessage = channelQueuedMessages.first(where: { $0.nonce == message.id }) {
            // For pending messages, use the actual timestamp from when it was queued
            date = queuedMessage.timestamp
        } else {
            // For all other messages (real or pending without queued data), use createdAt (now safe)
            date = createdAt(id: message.id)
        }
        timeLabel.text = formatMessageDate(date)
        
        // Configure avatar
        configureAvatar(author: author, member: member, message: message, viewState: viewState)
        
        // Load attachments
        loadAttachments(message: message, viewState: viewState)
        
        // Handle embeds for link previews
        if let embeds = message.embeds, !embeds.isEmpty {
            loadEmbeds(embeds: embeds, viewState: viewState)
        }
        
        // Update reactions
        updateReactions(for: message, viewState: viewState)
        
        // Update appearance for continuation
        updateAppearanceForContinuation()
        
        // Set bottom constraints
        setBottomConstraints(message: message)
        
        // Force layout
        setNeedsLayout()
        
        // Preload audio durations in background
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.preloadAudioDurations(for: message, viewState: viewState)
        }
    }
    

    
    // Helper function to process channel mentions simply (for reply view)
    private func processChannelMentionsSimple(in text: String, viewState: ViewState) -> String {
        var result = text
        
        // Regular expression to match channel mention format: <#channel_id>
        let pattern = "<#([A-Za-z0-9]+)>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: result.utf16.count)
            
            // Find all matches
            let matches = regex.matches(in: result, range: range)
            
            // Process matches in reverse to avoid index issues when replacing
            for match in matches.reversed() {
                if let channelIdRange = Range(match.range(at: 1), in: result) {
                    let channelId = String(result[channelIdRange])
                    
                    // Try to find channel in viewState
                    if let channel = viewState.channels[channelId] ?? viewState.allEventChannels[channelId] {
                        // Get the mention range
                        let mentionRange = Range(match.range, in: result)!
                        
                        // Get channel name based on channel type
                        let channelName: String
                        switch channel {
                        case .text_channel(let textChannel):
                            channelName = textChannel.name
                        case .voice_channel(let voiceChannel):
                            channelName = voiceChannel.name
                        case .dm_channel:
                            channelName = "DM"
                        case .group_dm_channel(let groupDM):
                            channelName = groupDM.name ?? "Group DM"
                        case .saved_messages:
                            channelName = "Saved Messages"
                        }
                        
                        // Replace the mention with channel name
                        result.replaceSubrange(mentionRange, with: "#\(channelName)")
                    } else {
                        // If channel not found, replace with #unknown-channel to avoid showing raw ID
                        let mentionRange = Range(match.range, in: result)!
                        result.replaceSubrange(mentionRange, with: "#unknown-channel")
                    }
                }
            }
        } catch {
            // print("Error creating regex for channel mentions: \(error)")
        }
        
        return result
    }
    
    // New helper function to replace mention tags with user names
    private func replaceMentionsWithUsernames(in text: String, viewState: ViewState) -> String {
        var result = text
        
        // Regular expression to match mention format: <@user_id>
        let pattern = "<@([A-Za-z0-9]+)>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: result.utf16.count)
            
            // Find all matches
            let matches = regex.matches(in: result, range: range)
            
            // Process matches in reverse to avoid index issues when replacing
            for match in matches.reversed() {
                if let userIdRange = Range(match.range(at: 1), in: result) {
                    let userId = String(result[userIdRange])
                    
                    // Try to find user in viewState
                    if let user = viewState.users[userId] {
                        // Get the mention range
                        let mentionRange = Range(match.range, in: result)!
                        
                        // Replace the mention with username (use display name if available)
                        let displayName = user.display_name ?? user.username
                        result.replaceSubrange(mentionRange, with: "@\(displayName)")
                    } else {
                        // If user not found, replace with @Unknown User to avoid showing raw ID
                        let mentionRange = Range(match.range, in: result)!
                        result.replaceSubrange(mentionRange, with: "@Unknown User")
                    }
                }
            }
        } catch {
            // print("Error creating regex for mentions: \(error)")
        }
        
        return result
    }
    
    // New function to create attributed text with clickable mentions
    private func createAttributedTextWithClickableMentions(from text: String, viewState: ViewState) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString(string: text)
        
        // Set default attributes for the entire text
        mutableAttributedString.addAttributes([
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.textDefaultGray01
        ], range: NSRange(location: 0, length: mutableAttributedString.length))
        
        // First handle channel mentions: <#channel_id>
        // Update pattern to match any alphanumeric ID (not just 26 chars)
        let channelPattern = "<#([A-Za-z0-9]+)>"
        
        do {
            let channelRegex = try NSRegularExpression(pattern: channelPattern)
            let textLength = mutableAttributedString.length
            
            // Safety check for text length
            guard textLength > 0 else {
                return mutableAttributedString
            }
            
            let range = NSRange(location: 0, length: textLength)
            
            // Find all channel matches
            let channelMatches = channelRegex.matches(in: text, range: range)
            
            // Debug: Print found matches
            print("🔍 MessageCell Channel mention processing: Found \(channelMatches.count) matches in: \(text)")
            
            // Process matches in reverse to avoid index issues when replacing
            for match in channelMatches.reversed() {
                if let channelIdRange = Range(match.range(at: 1), in: text) {
                    let channelId = String(text[channelIdRange])
                    
                    // Try to find channel in viewState
                    print("🔍 MessageCell Processing channel ID: \(channelId)")
                    if let channel = viewState.channels[channelId] ?? viewState.allEventChannels[channelId] {
                        print("✅ MessageCell Found channel: \(channel.getName(viewState)) for ID: \(channelId)")
                        // Get the mention range in the original text
                        let mentionRange = match.range
                        
                        // Safety check for range bounds in mutable string
                        guard mentionRange.location >= 0,
                              mentionRange.location < mutableAttributedString.length,
                              mentionRange.location + mentionRange.length <= mutableAttributedString.length else {
                            // print("DEBUG: Invalid channel mention range: \(mentionRange) for string length: \(mutableAttributedString.length)")
                            continue
                        }
                        
                        // Get channel name based on channel type
                        let channelName: String
                        switch channel {
                        case .text_channel(let textChannel):
                            channelName = textChannel.name
                        case .voice_channel(let voiceChannel):
                            channelName = voiceChannel.name
                        case .dm_channel:
                            channelName = "DM"
                        case .group_dm_channel(let groupDM):
                            channelName = groupDM.name ?? "Group DM"
                        case .saved_messages:
                            channelName = "Saved Messages"
                        }
                        
                        // Create channel mention text with # prefix
                        let mentionText = "#\(channelName)"
                        
                        // Replace the text
                        mutableAttributedString.replaceCharacters(in: mentionRange, with: mentionText)
                        
                        // Create the new range for the replaced text using UTF-16 count
                        let newRange = NSRange(location: mentionRange.location, length: (mentionText as NSString).length)
                        
                        // Safety check for new range
                        guard newRange.location >= 0,
                              newRange.location + newRange.length <= mutableAttributedString.length else {
                            // print("DEBUG: Invalid new channel range: \(newRange) for string length: \(mutableAttributedString.length)")
                            continue
                        }
                        
                        // Add clickable attributes to the channel mention
                        do {
                            if let linkURL = URL(string: "channel://\(channelId)") {
                                mutableAttributedString.addAttributes([
                                    .foregroundColor: UIColor.systemBlue,
                                    .link: linkURL // Custom URL scheme for channels
                                    // Removed underline
                                ], range: newRange)
                            }
                        } catch {
                            // print("DEBUG: Error adding attributes to channel mention: \(error)")
                        }
                    } else {
                        print("❌ MessageCell Channel not found for ID: \(channelId)")
                        // Channel not found - replace with #unknown-channel
                        let mentionRange = match.range
                        guard mentionRange.location >= 0,
                              mentionRange.location < mutableAttributedString.length,
                              mentionRange.location + mentionRange.length <= mutableAttributedString.length else {
                            continue
                        }
                        
                        let mentionText = "#unknown-channel"
                        mutableAttributedString.replaceCharacters(in: mentionRange, with: mentionText)
                        
                        let newRange = NSRange(location: mentionRange.location, length: (mentionText as NSString).length)
                        guard newRange.location >= 0,
                              newRange.location + newRange.length <= mutableAttributedString.length else {
                            continue
                        }
                        
                        mutableAttributedString.addAttributes([
                            .foregroundColor: UIColor.systemGray
                        ], range: newRange)
                    }
                }
            }
        } catch {
            // print("Error creating regex for channel mentions: \(error)")
        }
        
        // Then handle user mentions: <@user_id>
        // Update pattern to match any alphanumeric ID (not just 26 chars)
        let pattern = "<@([A-Za-z0-9]+)>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let textLength = mutableAttributedString.length
            
            // Safety check for text length
            guard textLength > 0 else {
                return mutableAttributedString
            }
            
            let range = NSRange(location: 0, length: textLength)
            
            // Find all matches
            let matches = regex.matches(in: mutableAttributedString.string, range: range) // Use updated string
            
            // Process matches in reverse to avoid index issues when replacing
            for match in matches.reversed() {
                if let userIdRange = Range(match.range(at: 1), in: mutableAttributedString.string) {
                    let userId = String(mutableAttributedString.string[userIdRange])
                    
                    // Try to find user in viewState
                    if let user = viewState.users[userId] {
                        // Get the mention range in the current string
                        let mentionRange = match.range
                        
                        // Safety check for range bounds in mutable string
                        guard mentionRange.location >= 0,
                              mentionRange.location < mutableAttributedString.length,
                              mentionRange.location + mentionRange.length <= mutableAttributedString.length else {
                            // print("DEBUG: Invalid mention range: \(mentionRange) for string length: \(mutableAttributedString.length)")
                            continue
                        }
                        
                        // Replace the mention with username (use display name if available)
                        let displayName = user.display_name ?? user.username
                        let mentionText = "@\(displayName)"
                        
                        // Replace the text
                        mutableAttributedString.replaceCharacters(in: mentionRange, with: mentionText)
                        
                        // Create the new range for the replaced text using UTF-16 count
                        let newRange = NSRange(location: mentionRange.location, length: (mentionText as NSString).length)
                        
                        // Safety check for new range
                        guard newRange.location >= 0,
                              newRange.location + newRange.length <= mutableAttributedString.length else {
                            // print("DEBUG: Invalid new range: \(newRange) for string length: \(mutableAttributedString.length)")
                            continue
                        }
                        
                        // Add clickable attributes to the mention
                        do {
                            if let linkURL = URL(string: "mention://\(userId)") {
                                mutableAttributedString.addAttributes([
                                    .foregroundColor: UIColor.systemBlue,
                                    .link: linkURL // Custom URL scheme for mentions
                                    // Removed underline
                                ], range: newRange)
                            }
                        } catch {
                            // print("DEBUG: Error adding attributes to mention: \(error)")
                        }
                    }
                }
            }
        } catch {
            // print("Error creating regex for mentions: \(error)")
        }
        
        return mutableAttributedString
    }
    
    private func formatMessageDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        // Check if message is from today
        if calendar.isDateInToday(date) {
            return "Today \(timeFormatter.string(from: date))"
        }
        
        // Check if message is from yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(timeFormatter.string(from: date))"
        }
        
        // For other dates, show DD/MM format with time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM"
        return "\(dateFormatter.string(from: date)) \(timeFormatter.string(from: date))"
    }
    
    private func loadImageAttachments(attachments: [String], viewState: ViewState) {
        guard !attachments.isEmpty else {
            // If no attachments, remove any existing container
            imageAttachmentsContainer?.removeFromSuperview()
            imageAttachmentsContainer = nil
            imageAttachmentViews.removeAll()
            
            // Also remove any spacer view
            if let spacerView = contentView.viewWithTag(1001) {
                spacerView.removeFromSuperview()
            }
            
            // Note: Content label bottom constraint will be set conditionally later
            // based on presence of reactions, embeds, or attachments
            return
        }
        
        // Create or reuse attachments container
        if imageAttachmentsContainer == nil {
            // Create a spacer view to ensure separation between text and images
            let spacerView = UIView()
            spacerView.translatesAutoresizingMaskIntoConstraints = false
            spacerView.backgroundColor = .clear
            spacerView.tag = 1001 // Tag for identification
            contentView.addSubview(spacerView)
            
            // Create the container for all image attachments
            imageAttachmentsContainer = UIView()
            imageAttachmentsContainer!.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(imageAttachmentsContainer!)
        } else {
            // Clear existing image views
            imageAttachmentViews.forEach { imageView in
                imageView.kf.cancelDownloadTask()
                imageView.removeFromSuperview()
            }
            imageAttachmentViews.removeAll()
            
            // Make sure the container is visible
            imageAttachmentsContainer!.isHidden = false
            
            // Remove existing spacer view if any
            if let existingSpacerView = contentView.viewWithTag(1001) {
                existingSpacerView.removeFromSuperview()
            }
            
            // Create a new spacer view
            let spacerView = UIView()
            spacerView.translatesAutoresizingMaskIntoConstraints = false
            spacerView.backgroundColor = .clear
            spacerView.tag = 1001
            contentView.addSubview(spacerView)
        }
        
        // Get reference to spacer view
        let spacerView = contentView.viewWithTag(1001)!
        
        // Clear any existing constraints for the container
        for constraint in contentView.constraints {
            if constraint.firstItem === imageAttachmentsContainer ||
               constraint.secondItem === imageAttachmentsContainer {
                constraint.isActive = false
            }
        }
        
        // Clear any existing bottom constraint for content label
        clearContentLabelBottomConstraints()
        
        // Also clear any existing constraints that might connect content label to spacer or other views
        for constraint in contentView.constraints {
            if constraint.firstItem === contentLabel && constraint.firstAttribute == .bottom {
                constraint.isActive = false
                // // print("🖼️ Deactivated contentLabel bottom constraint: \(constraint)")
            }
        }
        
        // Set up new constraints with spacer view to guarantee separation
        let contentToSpacerConstraint = contentLabel.bottomAnchor.constraint(equalTo: spacerView.topAnchor)
        contentToSpacerConstraint.priority = UILayoutPriority.defaultHigh
        
        let spacerHeightConstraint = spacerView.heightAnchor.constraint(equalToConstant: 20) // Increased spacing
        spacerHeightConstraint.priority = UILayoutPriority.defaultHigh // Lower priority to prevent conflicts
        
        let containerBottomConstraint = imageAttachmentsContainer!.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        containerBottomConstraint.priority = UILayoutPriority.defaultHigh // High but not required to allow flexibility
        
        // // print("🖼️ Setting up image attachments constraints - spacing: 20px")
        
        // Calculate available width first - needed for constraints
        let maxImagesPerRow = 2
        let imageSpacing: CGFloat = 8
        // Calculate available width based on actual layout constraints
        // Account for: avatar leading (16) + avatar width (40) + avatar spacing (10) + content trailing margin (16)
        let totalMargins: CGFloat = 16 + 40 + 10 + 16 // Total: 82px
        let availableWidth = UIScreen.main.bounds.width - totalMargins
        
        // Add a maximum width constraint to prevent overflow - use lower priority to avoid conflicts
        let maxWidthConstraint = imageAttachmentsContainer!.widthAnchor.constraint(lessThanOrEqualToConstant: availableWidth)
        maxWidthConstraint.priority = UILayoutPriority(999) // High but not required to prevent conflicts
        
        NSLayoutConstraint.activate([
            // Content label bottom connects to spacer top
            contentToSpacerConstraint,
            
            // Spacer has fixed height to guarantee separation
            spacerHeightConstraint,
            spacerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            spacerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Container top connects to spacer bottom
            imageAttachmentsContainer!.topAnchor.constraint(equalTo: spacerView.bottomAnchor),
            imageAttachmentsContainer!.leadingAnchor.constraint(equalTo: contentLabel.leadingAnchor),
            imageAttachmentsContainer!.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerBottomConstraint,
            
            // Critical: Prevent container from exceeding available width
            maxWidthConstraint
        ])
        
        // Create image views for each attachment
        let finalImageWidth: CGFloat = attachments.count == 1 ? min(availableWidth * 0.7, 220) : min((availableWidth - imageSpacing) / 2, 150)
        let imageHeight: CGFloat = attachments.count == 1 ? min(finalImageWidth * 0.75, 165) : min(finalImageWidth * 0.75, 110)
        
        // print("🖼️ Calculated sizes - Image width: \(finalImageWidth), Image height: \(imageHeight), Available width: \(availableWidth), Screen width: \(UIScreen.main.bounds.width)")
        
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var imagesInCurrentRow = 0
        
        for (index, attachmentId) in attachments.enumerated() {
            // Create image view for this attachment
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit // Show entire image, preserve aspect ratio
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 8
            imageView.backgroundColor = UIColor.gray.withAlphaComponent(0.1) // Lighter background
            imageView.isUserInteractionEnabled = true
            imageView.tag = index // Store index for tap handling
            
            // Add tap gesture recognizer for fullscreen view
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleImageCellTap(_:)))
            imageView.addGestureRecognizer(tapGesture)
            
            imageAttachmentsContainer!.addSubview(imageView)
            imageAttachmentViews.append(imageView)
            
            // Calculate position
            if imagesInCurrentRow >= maxImagesPerRow || (currentX + finalImageWidth > availableWidth) {
                // Move to next row if we've hit the max images per row OR if the next image would overflow
                currentX = 0
                let rowImageHeight = min(finalImageWidth * 0.75, 165) // Match the updated max height
                currentY += rowImageHeight + 10 // Match container calculation
                imagesInCurrentRow = 0
            }
            
            // Set up simple constraints for this image
            let imageViewHeight = min(finalImageWidth * 0.75, 165) // Match container calculation with updated max height
            
            // Ensure the image width doesn't exceed the remaining space in the container
            let remainingWidth = availableWidth - currentX
            let actualImageWidth = min(finalImageWidth, remainingWidth)
            
            // Create width constraint with lower priority to prevent conflicts
            let widthConstraint = imageView.widthAnchor.constraint(equalToConstant: actualImageWidth)
            widthConstraint.priority = UILayoutPriority(999) // High but not required
            
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: imageAttachmentsContainer!.leadingAnchor, constant: currentX),
                imageView.topAnchor.constraint(equalTo: imageAttachmentsContainer!.topAnchor, constant: currentY),
                widthConstraint,
                imageView.heightAnchor.constraint(equalToConstant: imageViewHeight),
                // Add trailing constraint to ensure image doesn't exceed container bounds - this is the critical constraint
                imageView.trailingAnchor.constraint(lessThanOrEqualTo: imageAttachmentsContainer!.trailingAnchor)
            ])
            
            // Check if this is a pending/uploading image with local data
            if isPendingMessage,
               let currentMessage = currentMessage,
               let channelQueuedMessages = viewState.queuedMessages[currentMessage.channel],
               let queuedMessage = channelQueuedMessages.first(where: { $0.nonce == currentMessage.id }),
               let localImageData = queuedMessage.attachmentData.first(where: { $0.1.contains(attachmentId.replacingOccurrences(of: "\(queuedMessage.nonce)_", with: "")) })?.0 {
                
                // For pending messages, show local image data with loading overlay
                if let localImage = UIImage(data: localImageData) {
                    imageView.image = localImage
                    
                    // Add loading overlay to show upload progress
                    addLoadingOverlayToImageView(imageView, attachmentId: attachmentId, queuedMessage: queuedMessage)
                } else {
                    imageView.image = UIImage(systemName: "photo")
                }
                
            } else {
                // For real messages, load from server using Kingfisher
                if let url = URL(string: viewState.formatUrl(fromId: attachmentId, withTag: "attachments")) {
                    imageView.kf.setImage(
                        with: url,
                        placeholder: UIImage(systemName: "photo"),
                        options: [
                            .transition(.fade(0.3)),
                            .cacheOriginalImage,
                            .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))
                        ],
                        completionHandler: { [weak self] result in
                            switch result {
                            case .success(_):
                                // Ensure cell hasn't been reused for a different message
                                if let currentAttachments = self?.currentMessage?.attachments,
                                   currentAttachments.contains(where: { $0.id == attachmentId }) {
                                    // Success: keep the loaded image
                                    
                                    // Force layout update to ensure proper positioning
                                    self?.contentView.setNeedsLayout()
                                    self?.contentView.layoutIfNeeded()
                                } else {
                                    // Cell has been reused for a different message
                                    imageView.image = nil
                                }
                            case .failure(let error):
                                // print("Error loading image: \(error.localizedDescription)")
                                // Show error placeholder
                                imageView.image = UIImage(systemName: "exclamationmark.triangle")
                            }
                        }
                    )
                }
            }
            
            // Update position for next image
            currentX += actualImageWidth + imageSpacing
            imagesInCurrentRow += 1
        }
        
        // Calculate exact container height based on actual image layout
        let numberOfRows = (attachments.count + maxImagesPerRow - 1) / maxImagesPerRow
        let containerImageHeight: CGFloat = min(finalImageWidth * 0.75, 165) // Updated max height to match image constraints
        let totalHeight = CGFloat(numberOfRows) * containerImageHeight + CGFloat(max(0, numberOfRows - 1)) * 10 // 10px spacing between rows
        
        let heightConstraint = imageAttachmentsContainer!.heightAnchor.constraint(equalToConstant: totalHeight)
        heightConstraint.priority = UILayoutPriority.defaultHigh // Lower priority to prevent conflicts
        heightConstraint.isActive = true
        
        // // print("🖼️ Set fixed container height: \(totalHeight) for \(numberOfRows) rows")
        // // print("🖼️ Image details - Width: \(finalImageWidth), Height: \(containerImageHeight), Attachments: \(attachments.count)")
    }
    
    // MARK: - File Attachments Support
    
    private func isImageFile(_ file: Types.File) -> Bool {
        return file.content_type.hasPrefix("image/")
    }
    
    private func isAudioFile(_ file: Types.File) -> Bool {
        let contentType = file.content_type.lowercased()
        let filename = file.filename.lowercased()
        
        let isAudio = contentType.hasPrefix("audio/") || 
                     contentType.contains("audio") ||
                     filename.hasSuffix(".mp3") ||
                     filename.hasSuffix(".wav") ||
                     filename.hasSuffix(".m4a") ||
                     filename.hasSuffix(".aac") ||
                     filename.hasSuffix(".ogg") ||
                     filename.hasSuffix(".flac")
        
        // print("🔍 AUDIO CHECK: '\(file.filename)'")
        // print("  📋 Content-Type: '\(file.content_type)'")
        // print("  📋 Lowercase: '\(contentType)'")
        // print("  📋 Filename: '\(filename)'")
        // print("  ✅ Is Audio: \(isAudio)")
        
        if isAudio {
            // print("  🎵 DETECTED AS AUDIO FILE!")
        } else {
            // print("  📄 Not an audio file")
        }
        
        return isAudio
    }
    
    private func isVideoFile(_ file: Types.File) -> Bool {
        let contentType = file.content_type.lowercased()
        let filename = file.filename.lowercased()
        
        let isVideo = contentType.hasPrefix("video/") || 
                     contentType.contains("video") ||
                     filename.hasSuffix(".mp4") ||
                     filename.hasSuffix(".mov") ||
                     filename.hasSuffix(".avi") ||
                     filename.hasSuffix(".mkv") ||
                     filename.hasSuffix(".webm") ||
                     filename.hasSuffix(".m4v") ||
                     filename.hasSuffix(".wmv") ||
                     filename.hasSuffix(".flv")
        
        // print("🎬 VIDEO CHECK: '\(file.filename)'")
        // print("  📋 Content-Type: '\(file.content_type)'")
        // print("  ✅ Is Video: \(isVideo)")
        
        return isVideo
    }
    
    private func loadFileAttachments(attachments: [Types.File], viewState: ViewState) {
        // print("🎯 loadFileAttachments called with \(attachments.count) attachments")
        for (index, att) in attachments.enumerated() {
            // print("  [\(index)] \(att.filename) - ID: \(att.id)")
        }
        
        guard !attachments.isEmpty else {
            // If no attachments, remove any existing container
            fileAttachmentsContainer?.removeFromSuperview()
            fileAttachmentsContainer = nil
            fileAttachmentViews.removeAll()
            return
        }
        
        // Create or reuse file attachments container
        if fileAttachmentsContainer == nil {
            fileAttachmentsContainer = UIView()
            fileAttachmentsContainer!.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(fileAttachmentsContainer!)
        } else {
            // Clear existing file views
            // print("🧹 CLEARING EXISTING FILE VIEWS: \(fileAttachmentViews.count) views")
            fileAttachmentViews.forEach { fileView in
                // If it's an AudioPlayerView, stop any playing audio
                if let audioPlayer = fileView as? AudioPlayerView {
                    // print("🧹 Removing audio player")
                }
                fileView.removeFromSuperview()
            }
            fileAttachmentViews.removeAll()
            
            // Clear all subviews from container to be sure
            fileAttachmentsContainer!.subviews.forEach { $0.removeFromSuperview() }
            // print("🧹 Cleared all subviews from file container")
        }
        
        // Clear any existing constraints for the container
        NSLayoutConstraint.deactivate(fileAttachmentsContainer!.constraints)
        for constraint in contentView.constraints {
            if constraint.firstItem === fileAttachmentsContainer || constraint.secondItem === fileAttachmentsContainer {
                constraint.isActive = false
            }
        }
        
        // Set up constraints for file attachments container
        // Position it below the content label or images
        var topAnchor: NSLayoutYAxisAnchor
        var topConstant: CGFloat = 8
        
        if imageAttachmentsContainer != nil && !imageAttachmentsContainer!.isHidden {
            // Position below image attachments
            topAnchor = imageAttachmentsContainer!.bottomAnchor
        } else {
            // Position below content label
            topAnchor = contentLabel.bottomAnchor
        }
        
        NSLayoutConstraint.activate([
            fileAttachmentsContainer!.topAnchor.constraint(equalTo: topAnchor, constant: topConstant),
            fileAttachmentsContainer!.leadingAnchor.constraint(equalTo: contentLabel.leadingAnchor),
            fileAttachmentsContainer!.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
        
        // Create file views for each attachment
        var currentY: CGFloat = 0
        let audioPlayerHeight: CGFloat = 80
        let videoPlayerHeight: CGFloat = 200
        let regularFileHeight: CGFloat = 50
        let fileSpacing: CGFloat = 8
        
        // Keep track of processed attachment IDs to avoid duplicates
        var processedAttachmentIds = Set<String>()
        
        for (index, attachment) in attachments.enumerated() {
            // Skip if already processed (prevents duplicates)
            if processedAttachmentIds.contains(attachment.id) {
                // print("⚠️ Skipping duplicate attachment: \(attachment.filename) - ID: \(attachment.id)")
                continue
            }
            processedAttachmentIds.insert(attachment.id)
            
            let fileView: UIView
            let viewHeight: CGFloat
            
            if isAudioFile(attachment) {
                // Create audio player view for audio files
                let audioPlayer = AudioPlayerView()
                let audioURL = viewState.formatUrl(fromId: attachment.id, withTag: "attachments")
                // print("🎵 Creating audio player with:")
                // print("  ↳ filename: \(attachment.filename)")
                // print("  ↳ size: \(attachment.size) bytes")
                
                // Store OGG indicator in the audio player
                let isOggFile = attachment.filename.lowercased().hasSuffix(".ogg") || 
                               attachment.filename.lowercased().contains(".oog")
                if isOggFile {
                    // print("  ↳ OGG file detected: \(attachment.filename)")
                }
                
                audioPlayer.configure(with: audioURL, filename: attachment.filename, fileSize: attachment.size, sessionToken: viewState.sessionToken)
                audioPlayer.tag = isOggFile ? 7777 : 0 // Use tag to indicate OGG file
                audioPlayer.translatesAutoresizingMaskIntoConstraints = false
                fileView = audioPlayer
                viewHeight = audioPlayerHeight
                // print("🎵 Created audio player for: \(attachment.filename)")
            } else if isVideoFile(attachment) {
                // Create video player view for video files
                let videoPlayer = VideoPlayerView()
                let videoURL = viewState.formatUrl(fromId: attachment.id, withTag: "attachments")
                var headers: [String: String] = [:]
                if let token = viewState.sessionToken {
                    headers["x-session-token"] = token
                }
                // print("🎬 Creating video player with:")
                // print("  ↳ attachment id: \(attachment.id)")
                // print("  ↳ filename: \(attachment.filename)")
                // print("  ↳ size: \(attachment.size) bytes")
                // print("  ↳ video URL: \(videoURL)")
                // print("  ↳ headers: \(headers.keys.joined(separator: ", "))")
                videoPlayer.configure(with: videoURL, filename: attachment.filename, fileSize: attachment.size, headers: headers)
                videoPlayer.translatesAutoresizingMaskIntoConstraints = false
                
                // Set up callback for play button
                videoPlayer.onPlayTapped = { [weak self] videoURL in
                    self?.playVideo(at: videoURL)
                }
                
                fileView = videoPlayer
                viewHeight = videoPlayerHeight
                // print("🎬 Created video player for: \(attachment.filename)")
            } else {
                // Create regular file view for non-audio/video files
                fileView = createFileAttachmentView(for: attachment, viewState: viewState)
                viewHeight = regularFileHeight
            }
            
            fileAttachmentsContainer!.addSubview(fileView)
            fileAttachmentViews.append(fileView)
            
            NSLayoutConstraint.activate([
                fileView.topAnchor.constraint(equalTo: fileAttachmentsContainer!.topAnchor, constant: currentY),
                fileView.leadingAnchor.constraint(equalTo: fileAttachmentsContainer!.leadingAnchor),
                fileView.trailingAnchor.constraint(equalTo: fileAttachmentsContainer!.trailingAnchor),
                fileView.heightAnchor.constraint(equalToConstant: viewHeight)
            ])
            
            currentY += viewHeight + fileSpacing
        }
        
        // Set container height
        let totalHeight = max(0, currentY - fileSpacing) // Remove last spacing
        
        // Remove any existing height constraints
        for constraint in fileAttachmentsContainer!.constraints {
            if constraint.firstAttribute == .height {
                constraint.isActive = false
            }
        }
        
        fileAttachmentsContainer!.heightAnchor.constraint(equalToConstant: totalHeight).isActive = true
        
        // print("📐 Set file container height to: \(totalHeight) with \(fileAttachmentViews.count) views")
    }
    
    private func createFileAttachmentView(for attachment: Types.File, viewState: ViewState) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.3)
        containerView.layer.cornerRadius = 8
        containerView.clipsToBounds = true
        
        // Check if this is an uploading file
        let isUploading = getUploadProgress(for: attachment.filename, viewState: viewState) != nil
        
        // Add tap gesture for download (only if not uploading)
        if !isUploading {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleFileAttachmentTap(_:)))
            containerView.addGestureRecognizer(tapGesture)
            containerView.isUserInteractionEnabled = true
            containerView.tag = fileAttachmentViews.count // Store index for tap handling
        }
        
        // File icon
        let iconImageView = UIImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = isUploading ? UIColor.systemOrange : UIColor.systemBlue
        iconImageView.image = getFileIcon(for: attachment)
        containerView.addSubview(iconImageView)
        
        // File name label
        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = attachment.filename
        nameLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        nameLabel.textColor = UIColor.label
        nameLabel.lineBreakMode = .byTruncatingMiddle
        containerView.addSubview(nameLabel)
        
        // File size label
        let sizeLabel = UILabel()
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.text = formatFileSize(attachment.size)
        sizeLabel.font = UIFont.systemFont(ofSize: 13)
        sizeLabel.textColor = UIColor.secondaryLabel
        containerView.addSubview(sizeLabel)
        
        // Upload progress or download icon
        let rightIconView: UIView
        
        if isUploading, let progress = getUploadProgress(for: attachment.filename, viewState: viewState) {
            // Create progress view
            let progressView = createUploadProgressView(progress: progress)
            rightIconView = progressView
        } else {
            // Download icon
            let downloadIconView = UIImageView()
            downloadIconView.translatesAutoresizingMaskIntoConstraints = false
            downloadIconView.contentMode = .scaleAspectFit
            downloadIconView.tintColor = UIColor.systemBlue
            downloadIconView.image = UIImage(systemName: "arrow.down.circle")
            rightIconView = downloadIconView
        }
        
        containerView.addSubview(rightIconView)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: rightIconView.leadingAnchor, constant: -12),
            
            sizeLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            sizeLabel.trailingAnchor.constraint(equalTo: rightIconView.leadingAnchor, constant: -12),
            
            rightIconView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            rightIconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            rightIconView.widthAnchor.constraint(equalToConstant: 24),
            rightIconView.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return containerView
    }
    
    // Helper function to get upload progress for a file
    private func getUploadProgress(for filename: String, viewState: ViewState) -> Double? {
        guard let message = currentMessage,
              let channelQueuedMessages = viewState.queuedMessages[message.channel],
              let queuedMessage = channelQueuedMessages.first(where: { $0.nonce == message.id }) else {
            return nil
        }
        
        return queuedMessage.uploadProgress[filename]
    }
    
    // Create upload progress view
    private func createUploadProgressView(progress: Double) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Background circle
        let backgroundCircle = UIView()
        backgroundCircle.translatesAutoresizingMaskIntoConstraints = false
        backgroundCircle.backgroundColor = UIColor.systemGray4
        backgroundCircle.layer.cornerRadius = 12
        containerView.addSubview(backgroundCircle)
        
        // Progress circle
        let progressLayer = CAShapeLayer()
        let circularPath = UIBezierPath(arcCenter: CGPoint(x: 12, y: 12), radius: 10, startAngle: -.pi/2, endAngle: 3 * .pi/2, clockwise: true)
        progressLayer.path = circularPath.cgPath
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.systemOrange.cgColor
        progressLayer.lineWidth = 2
        progressLayer.strokeEnd = CGFloat(progress)
        progressLayer.lineCap = .round
        containerView.layer.addSublayer(progressLayer)
        
        // Upload icon in center
        let uploadIcon = UIImageView()
        uploadIcon.translatesAutoresizingMaskIntoConstraints = false
        uploadIcon.image = UIImage(systemName: "arrow.up")
        uploadIcon.tintColor = UIColor.systemOrange
        uploadIcon.contentMode = .scaleAspectFit
        containerView.addSubview(uploadIcon)
        
        NSLayoutConstraint.activate([
            backgroundCircle.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            backgroundCircle.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            backgroundCircle.widthAnchor.constraint(equalToConstant: 24),
            backgroundCircle.heightAnchor.constraint(equalToConstant: 24),
            
            uploadIcon.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            uploadIcon.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            uploadIcon.widthAnchor.constraint(equalToConstant: 12),
            uploadIcon.heightAnchor.constraint(equalToConstant: 12)
        ])
        
        return containerView
    }
    
    private func getFileIcon(for attachment: Types.File) -> UIImage? {
        let contentType = attachment.content_type.lowercased()
        
        if contentType.hasPrefix("image/") {
            return UIImage(systemName: "photo")
        } else if contentType.hasPrefix("video/") {
            return UIImage(systemName: "video")
        } else if contentType.hasPrefix("audio/") {
            return UIImage(systemName: "music.note")
        } else if contentType.contains("pdf") {
            return UIImage(systemName: "doc.text")
        } else if contentType.contains("zip") || contentType.contains("archive") {
            return UIImage(systemName: "archivebox")
        } else if contentType.contains("text") {
            return UIImage(systemName: "doc.text")
        } else {
            return UIImage(systemName: "doc")
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // Add loading overlay to image view for upload progress
    private func addLoadingOverlayToImageView(_ imageView: UIImageView, attachmentId: String, queuedMessage: QueuedMessage) {
        // Remove any existing overlay
        imageView.subviews.forEach { if $0.tag == 9998 { $0.removeFromSuperview() } }
        
        // Create loading overlay
        let overlayView = UIView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        overlayView.layer.cornerRadius = imageView.layer.cornerRadius
        overlayView.tag = 9998 // Tag for identification
        
        // Create activity indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        activityIndicator.startAnimating()
        
        // Create loading label
        let loadingLabel = UILabel()
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.text = "Uploading..."
        loadingLabel.textColor = .white
        loadingLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 0
        
        overlayView.addSubview(activityIndicator)
        overlayView.addSubview(loadingLabel)
        imageView.addSubview(overlayView)
        
        NSLayoutConstraint.activate([
            // Overlay covers entire image
            overlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            
            // Center activity indicator
            activityIndicator.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor, constant: -10),
            
            // Position label below indicator
            loadingLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 8)
        ])
    }
    
    @objc private func handleFileAttachmentTap(_ gesture: UITapGestureRecognizer) {
        guard let containerView = gesture.view,
              let message = currentMessage,
              let attachments = message.attachments,
              attachments.indices.contains(containerView.tag) else { return }
        
        let attachment = attachments[containerView.tag]
        downloadFile(attachment: attachment)
    }
    
    private func downloadFile(attachment: Types.File) {
        guard let viewState = self.viewState else { return }
        
        // Create the download URL
        let downloadURL = viewState.formatUrl(fromId: attachment.id, withTag: "attachments")
        
        guard let url = URL(string: downloadURL) else {
            // print("❌ Invalid download URL: \(downloadURL)")
            return
        }
        
        // print("📁 Downloading file: \(attachment.filename) from \(downloadURL)")
        
        // Open the URL in Safari for download
        // In a real app, you might want to handle this differently
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }
    
    // Method to highlight this cell as the target
    public func setAsTargetMessage() {
        // print("🎨 MessageCell.setAsTargetMessage() CALLED")
        // print("🎨 Current backgroundColor: \(contentView.backgroundColor?.description ?? "nil")")
        // print("🎨 Current tag: \(tag)")
        
        // Save original background color if not already saved
        if originalBackgroundColorForHighlight == nil {
            originalBackgroundColorForHighlight = contentView.backgroundColor ?? .clear
            // print("🎨 Saved original background color: \(originalBackgroundColorForHighlight?.description ?? "nil")")
        }
        
        isTargetMessageHighlighted = true
        tag = 9999 // Tag for identification
        // print("🎨 Set isTargetMessageHighlighted = true, tag = 9999")
        
        // Apply highlight effect
        contentView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.3)
        contentView.layer.borderWidth = 1.5
        contentView.layer.borderColor = UIColor.systemOrange.cgColor
        contentView.layer.cornerRadius = 8.0
        // print("🎨 Applied orange background, border, and corner radius")
        
        // Apply a subtle scale effect
        contentView.transform = CGAffineTransform(scaleX: 1.01, y: 1.01)
        // print("🎨 Applied scale transform")
        
        // print("✅ MessageCell.setAsTargetMessage() COMPLETED")
    }
    
    // Method to clear highlight
    public func clearHighlight() {
        // print("🧹 MessageCell.clearHighlight() CALLED")
        // print("🧹 isTargetMessageHighlighted: \(isTargetMessageHighlighted)")
        // print("🧹 Current tag: \(tag)")
        
        if isTargetMessageHighlighted {
            // print("🧹 Starting clear highlight animation")
            UIView.animate(withDuration: 0.3) {
                self.contentView.backgroundColor = self.originalBackgroundColorForHighlight
                self.contentView.transform = .identity
                self.contentView.layer.borderWidth = 0.0
                // print("🧹 Clear highlight animation properties applied")
            }
            
            isTargetMessageHighlighted = false
            tag = 0 // Reset tag
            // print("🧹 Reset isTargetMessageHighlighted = false, tag = 0")
        } else {
            // print("🧹 Cell was not highlighted, no action needed")
        }
        
        // print("✅ MessageCell.clearHighlight() COMPLETED")
    }
    
    private func configureReplyView(message: Message, replies: [String], viewState: ViewState) {
        // Remove the continuation check - allow reply view for continuations too
        
        // Get the first reply message for simplicity (in a real app you might handle multiple replies differently)
        if let firstReplyId = replies.first {
            // Store the reply ID for tap handling even if message is not loaded yet
            self.currentReplyId = firstReplyId
            
            // Show the reply view
            replyView.isHidden = false
            
            if let replyMessage = viewState.messages[firstReplyId] {
                // Reply message is available - show full details
                replyLoadingIndicator.stopAnimating() // Hide loading indicator
                replyAuthorLabel.isHidden = false
                replyContentLabel.isHidden = false
                
                // Get the author of the message being replied to
                let replyAuthorId = replyMessage.author
                if let replyAuthor = viewState.users[replyAuthorId] {
                    // Get member info for the reply author
                    let replyMember = viewState.channels[message.channel]?.server.flatMap { serverId in
                        viewState.members[serverId]?[replyAuthorId]
                    }
                    
                    // Set the author name (prioritize masquerade name, then nickname, then display name)
                    let replyAuthorName = replyMessage.masquerade?.name ?? replyMember?.nickname ?? replyAuthor.display_name ?? replyAuthor.username
                    replyAuthorLabel.text = replyAuthorName
                    
                    // Set the message content (truncated if needed)
                    if let content = replyMessage.content, !content.isEmpty {
                        // Process both channel and user mentions in reply content
                        var processedContent = processChannelMentionsSimple(in: content, viewState: viewState)
                        processedContent = replaceMentionsWithUsernames(in: processedContent, viewState: viewState)
                        let truncatedContent = processedContent.count > 30 ? String(processedContent.prefix(30)) + "..." : processedContent
                        replyContentLabel.text = truncatedContent
                        replyContentLabel.font = UIFont.systemFont(ofSize: 12) // Reset to normal font
                    } else if !(replyMessage.attachments?.isEmpty ?? true) {
                        let attachmentCount = replyMessage.attachments?.count ?? 0
                        if attachmentCount == 1 {
                            replyContentLabel.text = "[attachment]"
                        } else {
                            replyContentLabel.text = "[\(attachmentCount) attachments]"
                        }
                        replyContentLabel.font = UIFont.systemFont(ofSize: 12) // Reset to normal font
                    } else {
                        replyContentLabel.text = ""
                    }
                    replyContentLabel.textColor = UIColor(named: "textGray06") ?? .systemGray // Reset color
                } else {
                    // Fallback if author not found
                    replyAuthorLabel.text = ""
                    replyContentLabel.text = ""
                    replyContentLabel.textColor = UIColor(named: "textGray06") ?? .systemGray // Reset color
                }
            } else {
                // Reply message not loaded yet - show placeholder
                // CRITICAL: Only show loading indicator if we expect the message to be loadable
                // For deleted messages, we should show an error state instead of infinite loading
                replyLoadingIndicator.startAnimating() // Show loading indicator
                replyAuthorLabel.isHidden = true
                replyContentLabel.isHidden = true
                replyAuthorLabel.text = ""
                replyContentLabel.text = ""
                replyContentLabel.font = UIFont.italicSystemFont(ofSize: 12)
                
                // Don't automatically load reply messages - only load when user taps
                // This prevents unnecessary nearby API calls when viewing messages with replies
                // print("ℹ️ Reply message not loaded yet, will load when user taps")
                
                // ENHANCEMENT: Add timeout for loading indicator to prevent infinite loading
                // If message is not loaded within 10 seconds, assume it's deleted
                replyLoadingTimeoutWorkItem?.cancel() // Cancel any existing timeout
                
                let timeoutWorkItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    // Check if loading indicator is still running and message still not loaded
                    if self.replyLoadingIndicator.isAnimating && 
                       self.currentReplyId == firstReplyId {
                        
                        // Double-check if message is still not available
                        Task { @MainActor in
                            let currentViewState = self.viewState
                            if currentViewState?.messages[firstReplyId] == nil {
                                print("⏰ REPLY_TIMEOUT: Stopping loading indicator for reply \(firstReplyId) - likely deleted")
                                self.replyLoadingIndicator.stopAnimating()
                                
                                // Show "message deleted" placeholder
                                self.replyAuthorLabel.isHidden = false
                                self.replyContentLabel.isHidden = false
                                self.replyAuthorLabel.text = "Deleted Message"
                                self.replyContentLabel.text = "This message was deleted"
                                self.replyContentLabel.textColor = UIColor(named: "textGray08") ?? .systemGray2
                                self.replyContentLabel.font = UIFont.italicSystemFont(ofSize: 12)
                            }
                        }
                    }
                }
                
                replyLoadingTimeoutWorkItem = timeoutWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: timeoutWorkItem)
            }
        } else {
            // No replies at all
            replyView.isHidden = true
            currentReplyId = nil // Reset reply ID
        }
    }
    
    @objc private func handleAvatarTap() {
        onAvatarTap?()
    }
    
    @objc private func handleUsernameTap() {
        onUsernameTap?()
    }
    
    @objc private func handleReplyTap() {
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
    
    private func showReplyNotFoundMessage() {
        // First ensure the loading indicator is hidden
        hideReplyLoadingIndicator()
        
        // CRITICAL: Also stop the inline reply loading indicator
        replyLoadingIndicator.stopAnimating()
        
        DispatchQueue.main.async {
            if let viewController = self.findParentViewController() {
                // Create a simple notification
                let alert = UIAlertController(
                    title: "Message Not Found",
                    message: "The original message could not be found. It may have been deleted or you don't have access to it.",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                viewController.present(alert, animated: true)
            }
        }
    }
    
    private func showReplyLoadingIndicator() {
        DispatchQueue.main.async {
            // Dismiss any existing alert first
            self.hideReplyLoadingIndicator()
            
            // Create a simple toast-like loading indicator without using accessoryView
            if let viewController = self.findParentViewController() {
                let alertController = UIAlertController(title: "Finding message...", message: "\n\n", preferredStyle: .alert)
                
                let loadingIndicator = UIActivityIndicatorView(style: .medium)
                loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
                loadingIndicator.hidesWhenStopped = true
                loadingIndicator.startAnimating()
                
                alertController.view.addSubview(loadingIndicator)
                alertController.view.tag = 9999 // Tag to identify this loading alert
                
                // Position the loading indicator in the center of the alert
                NSLayoutConstraint.activate([
                    loadingIndicator.centerXAnchor.constraint(equalTo: alertController.view.centerXAnchor),
                    loadingIndicator.centerYAnchor.constraint(equalTo: alertController.view.centerYAnchor, constant: 10)
                ])
                
                // Store reference to the alert
                self.loadingAlert = alertController
                
                // Set up automatic timeout to dismiss the alert after 8 seconds (reduced for better UX)
                self.loadingAlertTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
                    print("⏰ LOADING_ALERT_TIMEOUT: Auto-dismissing 'Finding message...' alert after 8 seconds")
                    self?.hideReplyLoadingIndicator()
                    
                    // Show the standard "message not found" alert
                    self?.showReplyNotFoundMessage()
                }
                
                viewController.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    private func hideReplyLoadingIndicator() {
        DispatchQueue.main.async {
            // Cancel the timeout timer
            self.loadingAlertTimer?.invalidate()
            self.loadingAlertTimer = nil
            
            // CRITICAL: Stop the inline reply loading indicator
            self.replyLoadingIndicator.stopAnimating()
            
            // Approach 1: Use stored reference if available
            if let loadingAlert = self.loadingAlert {
                loadingAlert.dismiss(animated: true) {
                    self.loadingAlert = nil
                }
                return
            }
            
            // Approach 2: Try multiple approaches to find and dismiss the loading alert
            if let viewController = self.findParentViewController() {
                // Check if there's a presented alert with our tag
                if let presentedController = viewController.presentedViewController as? UIAlertController,
                   presentedController.view.tag == 9999 {
                    presentedController.dismiss(animated: true)
                    return
                }
                
                // Check all child view controllers for alerts with our tag
                func dismissAlertRecursively(in controller: UIViewController) {
                    // Check current controller
                    if let alertController = controller as? UIAlertController,
                       alertController.view.tag == 9999 {
                        alertController.dismiss(animated: true)
                        return
                    }
                    
                    // Check presented controller
                    if let presented = controller.presentedViewController {
                        if let alertController = presented as? UIAlertController,
                           alertController.view.tag == 9999 {
                            alertController.dismiss(animated: true)
                            return
                        }
                        dismissAlertRecursively(in: presented)
                    }
                    
                    // Check child controllers
                    for child in controller.children {
                        dismissAlertRecursively(in: child)
                    }
                }
                
                // Start recursive search from the view controller
                dismissAlertRecursively(in: viewController)
                
                // Check navigation controller and its view controllers
                if let navController = viewController.navigationController {
                    dismissAlertRecursively(in: navController)
                }
                
                // Check if there's a window-level presented controller
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    if let rootController = window.rootViewController {
                        dismissAlertRecursively(in: rootController)
                    }
                }
            }
        }
    }
    
    private func showCrossChannelReplyAlert(replyMessage: Message) {
        // First ensure the loading indicator is hidden
        hideReplyLoadingIndicator()
        
        guard let viewController = findParentViewController() else { return }
        
        let alert = UIAlertController(
            title: "Reply in Different Channel",
            message: "This reply is from a different channel. Would you like to navigate to that channel?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Go to Channel", style: .default) { _ in
            // Navigate to the channel containing the reply
            if let viewState = self.viewState {
                // Clear existing messages for the target channel
                viewState.channelMessages[replyMessage.channel] = []
                
                // Check if it's a server channel or DM
                if let channel = viewState.channels[replyMessage.channel] {
                    DispatchQueue.main.async {
                        // CRITICAL FIX: Set target message BEFORE navigation
                        viewState.currentTargetMessageId = replyMessage.id
                        print("🎯 MessageCell: Setting target message ID BEFORE cross-channel navigation: \(replyMessage.id)")
                        
                        if let serverId = channel.server {
                            // Server channel
                            viewState.selectServer(withId: serverId)
                            viewState.selectChannel(inServer: serverId, withId: replyMessage.channel)
                        } else {
                            // DM channel
                            viewState.selectDm(withId: replyMessage.channel)
                        }
                        
                        viewState.path.append(NavigationDestination.maybeChannelView)
                        
                        print("🎯 MessageCell: Cross-channel Navigation completed - new view controller will handle target message")
                    }
                }
            }
        })
        
        viewController.present(alert, animated: true)
    }
    
    @objc private func handleImageCellTap(_ gesture: UITapGestureRecognizer) {
        guard let imageView = gesture.view as? UIImageView,
              let image = imageView.image else { return }
        
        onImageTapped?(image)
    }
    
    // MARK: - Reactions Management
    
    private func updateReactions(for message: Message, viewState: ViewState) {
        // CRITICAL FIX: Always get the latest message from ViewState instead of using the passed message
        let latestMessage = viewState.messages[message.id] ?? message
        print("🔥 updateReactions called for message: \(message.id)")
        print("🔥 Original message reactions: \(message.reactions?.keys.joined(separator: ", ") ?? "none")")
        print("🔥 Latest message reactions: \(latestMessage.reactions?.keys.joined(separator: ", ") ?? "none")")
        
        // CRITICAL FIX: Ensure complete cleanup to prevent duplicate reactions
        reactionsContainerView.subviews.forEach { subview in
            subview.removeFromSuperview()
        }
        reactionsContainerView.isHidden = true // Always hide first
        
        // CRITICAL: Also clean up any existing reaction spacer views
        if let existingSpacerView = contentView.viewWithTag(9999) {
            existingSpacerView.removeFromSuperview()
        }
        
        // Check if latest message has reactions
        guard let reactions = latestMessage.reactions, !reactions.isEmpty else {
            print("🔥 No reactions found, hiding container")
            reactionsContainerView.isHidden = true
            return
        }
        
        print("🔥 Found \(reactions.count) reactions, showing container")
        reactionsContainerView.isHidden = false
        
        // Position spacer below images/content
        let spacerView = UIView()
        spacerView.translatesAutoresizingMaskIntoConstraints = false
        spacerView.backgroundColor = UIColor.clear // Remove debug color, make it invisible
        spacerView.tag = 9999 // Special tag for spacer
        contentView.addSubview(spacerView)
        
        // Find what to anchor to
        var topAnchor: NSLayoutYAxisAnchor
        if let embedContainer = contentView.viewWithTag(2000), !embedContainer.isHidden {
            topAnchor = embedContainer.bottomAnchor
        } else if let imageContainer = imageAttachmentsContainer, !imageContainer.isHidden {
            topAnchor = imageContainer.bottomAnchor
        } else if let fileContainer = fileAttachmentsContainer, !fileContainer.isHidden {
            topAnchor = fileContainer.bottomAnchor
        } else {
            topAnchor = contentLabel.bottomAnchor
        }
        
        // Position spacer below content/images
        let heightConstraint = spacerView.heightAnchor.constraint(equalToConstant: 50)
        heightConstraint.priority = UILayoutPriority(999) // High but not required to avoid conflicts
        
        NSLayoutConstraint.activate([
            spacerView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            spacerView.leadingAnchor.constraint(equalTo: contentLabel.leadingAnchor), // Align with text content
            spacerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            spacerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16), // Increased bottom padding
            heightConstraint
        ])
        
        // Add all reaction buttons to spacer in a row
        var currentX: CGFloat = 0
        let buttonSpacing: CGFloat = 8
        
        for (emoji, users) in reactions {
            let reactionButton = createSimpleReactionButton(emoji: emoji, count: users.count, viewState: viewState)
            spacerView.addSubview(reactionButton)
            
            // Position button in a horizontal layout
            NSLayoutConstraint.activate([
                reactionButton.centerYAnchor.constraint(equalTo: spacerView.centerYAnchor),
                reactionButton.leadingAnchor.constraint(equalTo: spacerView.leadingAnchor, constant: currentX),
                reactionButton.heightAnchor.constraint(equalToConstant: 32),
                reactionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
            ])
            
            // Update position for next button
            currentX += 68 // 60 + 8 spacing
        }
        
        // print("🔥 Added spacer and reaction button to force cell expansion")
        
        // Force layout update to ensure proper rendering
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    private func layoutReactionsWithFlowLayout(buttons: [UIView]) {
        // FIXED: No need to clear subviews here since updateReactions already cleared them
        // This prevents duplicate reactions from appearing
        
        guard !buttons.isEmpty else { return }
        
        let containerWidth: CGFloat = UIScreen.main.bounds.width - 32 - 50 // Account for margins and avatar
        let spacing: CGFloat = 8
        let lineSpacing: CGFloat = 8
        
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeightInRow: CGFloat = 32 // Default reaction height
        
        for button in buttons {
            // Add button to container
            reactionsContainerView.addSubview(button)
            
            // Calculate button width
            button.translatesAutoresizingMaskIntoConstraints = false
            let buttonSize = button.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let buttonWidth = max(buttonSize.width, 50) // Minimum width
            
            // Check if button fits in current row
            if currentX + buttonWidth > containerWidth && currentX > 0 {
                // Move to next row
                currentX = 0
                currentY += maxHeightInRow + lineSpacing
                maxHeightInRow = 32
            }
            
            // Position the button
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: reactionsContainerView.leadingAnchor, constant: currentX),
                button.topAnchor.constraint(equalTo: reactionsContainerView.topAnchor, constant: currentY),
                button.heightAnchor.constraint(equalToConstant: 32)
            ])
            
            // Update position for next button
            currentX += buttonWidth + spacing
            maxHeightInRow = max(maxHeightInRow, 32)
        }
        
        // Set container height based on total rows
        let totalHeight = currentY + maxHeightInRow
        reactionsContainerView.heightAnchor.constraint(equalToConstant: totalHeight).isActive = true
    }
    
    private func clearReactionsContainerConstraints() {
        // Clear all constraints related to reactions container
        var constraintsToRemove: [NSLayoutConstraint] = []
        
        for constraint in contentView.constraints {
            if constraint.firstItem === reactionsContainerView || constraint.secondItem === reactionsContainerView {
                constraintsToRemove.append(constraint)
            }
        }
        
        // CRITICAL FIX: Only remove BOTTOM constraints from attachment containers
        // Keep all other constraints intact to maintain proper sizing and positioning
        for constraint in contentView.constraints {
            if let imageContainer = imageAttachmentsContainer,
               (constraint.firstItem === imageContainer && constraint.firstAttribute == .bottom) ||
               (constraint.secondItem === imageContainer && constraint.secondAttribute == .bottom) {
                // Only remove bottom constraints that connect to contentView
                if (constraint.secondItem === contentView || constraint.firstItem === contentView) {
                    constraintsToRemove.append(constraint)
                }
            }
        }
        
        // Also remove bottom constraints from file attachment containers
        for constraint in contentView.constraints {
            if let fileContainer = fileAttachmentsContainer,
               (constraint.firstItem === fileContainer && constraint.firstAttribute == .bottom) ||
               (constraint.secondItem === fileContainer && constraint.secondAttribute == .bottom) {
                if (constraint.secondItem === contentView || constraint.firstItem === contentView) {
                    constraintsToRemove.append(constraint)
                }
            }
        }
        
        // Remove constraints safely
        constraintsToRemove.forEach { $0.isActive = false }
        
        // Also clear any height constraints on the reactions container itself
        var heightConstraintsToRemove: [NSLayoutConstraint] = []
        reactionsContainerView.constraints.forEach { constraint in
            if constraint.firstAttribute == .height {
                heightConstraintsToRemove.append(constraint)
            }
        }
        
        // Remove height constraints safely
        heightConstraintsToRemove.forEach { $0.isActive = false }
    }
    
    private func setupReactionsContainerConstraints() {
        // Find what should be above the reactions container
        var anchorView: UIView
        var constant: CGFloat = 12 // Increased spacing to prevent overlap with content
        
        // Priority order: embeds -> file attachments -> image attachments -> content label
        if let embedContainer = contentView.viewWithTag(2000), !embedContainer.isHidden {
            anchorView = embedContainer
            constant = 12 // Spacing from embeds
        } else if let container = fileAttachmentsContainer, !container.isHidden {
            anchorView = container
            constant = 12 // Increased spacing from files
        } else if let container = imageAttachmentsContainer, !container.isHidden {
            anchorView = container
            constant = 20 // CRITICAL FIX: Much larger spacing from images to prevent overlap
        } else {
            anchorView = contentLabel
            constant = 12 // More spacing from text content
        }
        
        
        // Create constraints with proper priorities
        let topConstraint = reactionsContainerView.topAnchor.constraint(equalTo: anchorView.bottomAnchor, constant: constant)
        topConstraint.priority = .required
        
        let leadingConstraint = reactionsContainerView.leadingAnchor.constraint(equalTo: contentLabel.leadingAnchor)
        leadingConstraint.priority = .required
        
        let trailingConstraint = reactionsContainerView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
        trailingConstraint.priority = .required
        
        // Set bottom constraint to contentView to properly define cell height
        let bottomConstraint = reactionsContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        bottomConstraint.priority = .defaultHigh // High but not required to avoid conflicts
        
        NSLayoutConstraint.activate([
            topConstraint,
            leadingConstraint,
            trailingConstraint,
            bottomConstraint
        ])
        
        // Set proper content hugging and compression resistance
        reactionsContainerView.setContentHuggingPriority(.required, for: .horizontal)
        reactionsContainerView.setContentHuggingPriority(.required, for: .vertical)
        reactionsContainerView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // CRITICAL FIX: Force layout update after constraint changes to prevent image jumping
        DispatchQueue.main.async { [weak self] in
            self?.contentView.setNeedsLayout()
            self?.contentView.layoutIfNeeded()
        }
    }
    
    // Proper reaction button design with custom emoji support and click functionality
    private func createSimpleReactionButton(emoji: String, count: Int, viewState: ViewState) -> UIView {
        guard let message = currentMessage else { return UIView() }
        
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Check if current user has reacted with this emoji
        let currentUserId = viewState.currentUser?.id ?? ""
        let users = message.reactions?[emoji] ?? []
        let hasCurrentUserReacted = users.contains(currentUserId)
        
        // Style the container based on user's reaction status
        if hasCurrentUserReacted {
            // User has reacted - highlight the button
            container.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
            container.layer.borderWidth = 1.5
            container.layer.borderColor = UIColor.systemBlue.cgColor
        } else {
            // User hasn't reacted - normal style
            container.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.8)
            container.layer.borderWidth = 1
            container.layer.borderColor = UIColor.systemGray4.cgColor
        }
        
        container.layer.cornerRadius = 16
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.alignment = .center
        
        // Check if this is a custom emoji (26 character ID) or Unicode emoji
        let isCustomEmoji = emoji.count == 26 // Custom emoji IDs are 26 characters long
        
        if isCustomEmoji {
            // Custom emoji - load from URL
            let emojiImageView = UIImageView()
            emojiImageView.translatesAutoresizingMaskIntoConstraints = false
            emojiImageView.contentMode = .scaleAspectFit
            emojiImageView.clipsToBounds = true
            
            // Use ViewState formatUrl method to construct the custom emoji URL
            let emojiURL = URL(string: viewState.formatUrl(fromEmoji: emoji))
            
            // Load the custom emoji using Kingfisher
            emojiImageView.kf.setImage(
                with: emojiURL,
                placeholder: UIImage(systemName: "face.smiling"),
                options: [
                    .transition(.fade(0.2)),
                    .cacheOriginalImage
                ],
                completionHandler: { result in
                    switch result {
                    case .success(_):
                        break
                    case .failure(let error):
                        print("Error loading custom emoji in reaction: \(error.localizedDescription)")
                    }
                }
            )
            
            stackView.addArrangedSubview(emojiImageView)
            
            // Set size constraints for the image
            NSLayoutConstraint.activate([
                emojiImageView.widthAnchor.constraint(equalToConstant: 18),
                emojiImageView.heightAnchor.constraint(equalToConstant: 18)
            ])
        } else {
            // Unicode emoji - display as text
            let emojiLabel = UILabel()
            emojiLabel.text = emoji
            emojiLabel.font = UIFont.systemFont(ofSize: 16)
            stackView.addArrangedSubview(emojiLabel)
        }
        
        // Count label
        let countLabel = UILabel()
        countLabel.text = "\(count)"
        countLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        countLabel.textColor = hasCurrentUserReacted ? UIColor.systemBlue : UIColor.label
        
        stackView.addArrangedSubview(countLabel)
        container.addSubview(stackView)
        
        // Add tap gesture for interaction
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(reactionButtonTapped(_:)))
        container.addGestureRecognizer(tapGesture)
        container.isUserInteractionEnabled = true
        
        // Store emoji in container's accessibility label for retrieval
        container.accessibilityLabel = emoji
        
        // CRITICAL FIX: Store message ID for reaction handling
        if let message = currentMessage {
            container.restorationIdentifier = message.id
        }
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        ])
        
        return container
    }
    

    
    private func createReactionButton(emoji: String, users: [String], viewState: ViewState, message: Message) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Check if current user has reacted
        let hasCurrentUserReacted = users.contains(viewState.currentUser?.id ?? "")
        
        // Background view with improved styling
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = 14 // More rounded
        
        if hasCurrentUserReacted {
            // User has reacted - purple/blue theme
            backgroundView.backgroundColor = UIColor(named: "bgPurple11") ?? UIColor.systemBlue.withAlphaComponent(0.15)
            backgroundView.layer.borderWidth = 1.5
            backgroundView.layer.borderColor = (UIColor(named: "borderPurple07") ?? UIColor.systemBlue).cgColor
        } else {
            // User hasn't reacted - gray theme
            backgroundView.backgroundColor = UIColor(named: "bgGray11") ?? UIColor.systemGray6
            backgroundView.layer.borderWidth = 1
            backgroundView.layer.borderColor = (UIColor(named: "borderGray11") ?? UIColor.systemGray4).cgColor
        }
        
        containerView.addSubview(backgroundView)
        
        // Create a horizontal stack for emoji and count
        let contentStackView = UIStackView()
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .horizontal
        contentStackView.spacing = 6
        contentStackView.alignment = .center
        contentStackView.distribution = .fill
        backgroundView.addSubview(contentStackView)
        
        // Check if this is a custom emoji (26 character ID like in MessageReactions.swift) or Unicode emoji
        let isCustomEmoji = emoji.count == 26 // Custom emoji IDs are 26 characters long
        
        if isCustomEmoji {
            // Custom emoji - load from URL using ViewState formatUrl method
            let emojiImageView = UIImageView()
            emojiImageView.translatesAutoresizingMaskIntoConstraints = false
            emojiImageView.contentMode = .scaleAspectFit
            emojiImageView.clipsToBounds = true
            
            // Use ViewState formatUrl method to construct the custom emoji URL
            let emojiURL = URL(string: viewState.formatUrl(fromEmoji: emoji))
            
            // Load the custom emoji using Kingfisher with weak self to prevent retain cycles
            emojiImageView.kf.setImage(
                with: emojiURL,
                placeholder: UIImage(systemName: "face.smiling"), // Placeholder while loading
                options: [
                    .transition(.fade(0.2)),
                    .cacheOriginalImage
                ],
                completionHandler: { [weak emojiImageView] result in
                    // Use weak reference to prevent retain cycles
                    switch result {
                    case .success(_):
                        // Image loaded successfully, no additional action needed
                        break
                    case .failure(let error):
                        // print("Error loading custom emoji: \(error.localizedDescription)")
                        // Set fallback emoji on failure
                        emojiImageView?.image = UIImage(systemName: "face.smiling")
                    }
                }
            )
            
            contentStackView.addArrangedSubview(emojiImageView)
            
            // Set size constraints for the image
            NSLayoutConstraint.activate([
                emojiImageView.widthAnchor.constraint(equalToConstant: 18),
                emojiImageView.heightAnchor.constraint(equalToConstant: 18)
            ])
        } else {
            // Unicode emoji - display as text
            let emojiLabel = UILabel()
            emojiLabel.translatesAutoresizingMaskIntoConstraints = false
            emojiLabel.font = UIFont.systemFont(ofSize: 18) // Slightly larger
            emojiLabel.text = emoji
            emojiLabel.textAlignment = .center
            contentStackView.addArrangedSubview(emojiLabel)
        }
        
        // Count label with improved styling
        let countLabel = UILabel()
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold) // Slightly bolder
        countLabel.text = "\(users.count)"
        
        if hasCurrentUserReacted {
            countLabel.textColor = UIColor(named: "textPurple01") ?? UIColor.systemBlue
        } else {
            countLabel.textColor = UIColor(named: "textDefaultGray01") ?? UIColor.label
        }
        
        contentStackView.addArrangedSubview(countLabel)
        
        // Button for interaction
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(reactionButtonTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = emoji // Store emoji for later retrieval
        
        // Add press animation
        button.addTarget(self, action: #selector(reactionButtonPressed(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(reactionButtonReleased(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        containerView.addSubview(button)
        
        // Set up constraints with proper sizing
        NSLayoutConstraint.activate([
            // Container height - fixed
            containerView.heightAnchor.constraint(equalToConstant: 32),
            
            // Background view fills container
            backgroundView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            backgroundView.topAnchor.constraint(equalTo: containerView.topAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            // Content stack view with proper padding
            contentStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 10),
            contentStackView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 6),
            contentStackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),
            contentStackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -6),
            
            // Button covers the entire container for touch interaction
            button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            button.topAnchor.constraint(equalTo: containerView.topAnchor),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Set content hugging and compression resistance to prevent stretching
        containerView.setContentHuggingPriority(.required, for: .horizontal)
        containerView.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStackView.setContentHuggingPriority(.required, for: .horizontal)
        contentStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        return containerView
    }
    
    @objc private func reactionButtonTapped(_ gesture: UITapGestureRecognizer) {
        print("🔥 REACTION BUTTON TAPPED!")
        guard let containerView = gesture.view,
              let emoji = containerView.accessibilityLabel else { 
            print("🔥 ERROR: Missing containerView or emoji")
            return 
        }
        
        // CRITICAL FIX: Get message from ViewState using stored tag instead of currentMessage
        guard let messageId = containerView.restorationIdentifier,
              let viewState = self.viewState,
              let message = viewState.messages[messageId] else {
            print("🔥 ERROR: Cannot find message for reaction - messageId: \(containerView.restorationIdentifier ?? "nil")")
            return
        }
        
        print("🔥 Reaction tap: emoji=\(emoji), message=\(message.id)")
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Add visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            containerView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                containerView.transform = .identity
            }
        }
        
        // Call the message action handler with the reaction
        print("🔥 CALLBACK CHECK: onMessageAction is \(onMessageAction == nil ? "NIL" : "SET")")
        onMessageAction?(.react(emoji), message)
    }
    
    @objc private func reactionButtonPressed(_ sender: UIButton) {
        // Add press animation
        UIView.animate(withDuration: 0.1) {
            sender.superview?.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }
    
    @objc private func reactionButtonReleased(_ sender: UIButton) {
        // Remove press animation
        UIView.animate(withDuration: 0.1) {
            sender.superview?.transform = .identity
        }
    }
    
    // MARK: - Markdown Processing Helpers
    
    /// Removes empty Markdown links from the given text
    /// Empty links are defined as links with no visible text content in the label
    /// Examples: [](url), [ ](url), [  ](url) will be removed
    /// Valid links like [profile](url) will remain untouched
    private func removeEmptyMarkdownLinks(from text: String) -> String {
        // Regular expression to match markdown links: [label](url)
        // This pattern captures:
        // - Group 1: The entire link [label](url)
        // - Group 2: The label content between [ and ]
        // - Group 3: The URL content between ( and )
        let pattern = #"(\[([^\]]*)\]\([^)]+\))"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: text.utf16.count)
            
            // Find all matches and process them in reverse order to avoid index issues
            let matches = regex.matches(in: text, range: range)
            var result = text
            
            for match in matches.reversed() {
                // Extract the label content (group 2)
                if let labelRange = Range(match.range(at: 2), in: text) {
                    let label = String(text[labelRange])
                    
                    // Check if label is empty or contains only whitespace
                    if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Remove the entire link (group 1) from the text
                        if let linkRange = Range(match.range(at: 1), in: result) {
                            result.removeSubrange(linkRange)
                        }
                    }
                }
            }
            
            return result
        } catch {
            // print("Error processing markdown links: \(error)")
            return text // Return original text if regex fails
        }
    }
    
    // MARK: - Audio Duration Preloading
    private func preloadAudioDurations(for message: Message, viewState: ViewState) {
        // print("🎯 PRELOAD FUNCTION CALLED for message \(message.id)")
        
        guard let attachments = message.attachments else { 
            // print("🎵 PRELOAD: No attachments for message \(message.id)")
            return 
        }
        
        // print("🎵 PRELOAD: Checking \(attachments.count) attachments for message \(message.id)")
        
        // Filter audio attachments
        let audioAttachments = attachments.filter { isAudioFile($0) }
        
        if audioAttachments.isEmpty {
            // print("🎵 PRELOAD: No audio files found in \(attachments.count) attachments")
            for attachment in attachments {
                // print("  📄 Non-audio: \(attachment.filename) (type: \(attachment.content_type))")
            }
            return
        }
        
        // print("🎵 PRELOAD: Found \(audioAttachments.count) audio files in message \(message.id)")
        
        let audioManager = AudioPlayerManager.shared
        
        // Set session token in audio manager
        if let token = viewState.sessionToken {
            audioManager.setSessionToken(token)
            // print("🔐 PRELOAD: Set session token in AudioManager")
        }
        
        // Preload duration for each audio file
        for (index, attachment) in audioAttachments.enumerated() {
            let audioURL = viewState.formatUrl(fromId: attachment.id, withTag: "attachments")
            
            // print("🔍 PRELOAD [\(index + 1)/\(audioAttachments.count)]: Starting for \(attachment.filename)")
            // print("  📋 URL: \(audioURL)")
            // print("  📊 Size: \(attachment.size) bytes")
            // print("  🏷️ Type: \(attachment.content_type)")
            
            // Pass file size for better estimation
            audioManager.preloadDuration(for: audioURL, fileSize: attachment.size) { duration in
                if let duration = duration {
                    // print("✅ PRELOAD SUCCESS [\(index + 1)/\(audioAttachments.count)]: \(attachment.filename) = \(String(format: "%.1f", duration))s")
                } else {
                    // print("❌ PRELOAD FAILED [\(index + 1)/\(audioAttachments.count)]: \(attachment.filename)")
                }
            }
        }
        
        // print("🎵 PRELOAD: Initiated for all \(audioAttachments.count) audio files in message \(message.id)")
    }
    
    // Store temp video URLs for cleanup
    private var tempVideoURLs: Set<URL> = []
    
    private func createLoadingView() -> UIView {
        let loadingView = UIView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        loadingView.layer.cornerRadius = 10
        
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        activityIndicator.startAnimating()
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Loading video..."
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14)
        
        loadingView.addSubview(activityIndicator)
        loadingView.addSubview(label)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor, constant: -15),
            
            label.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            label.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 10)
        ])
        
        return loadingView
    }
    
    private func removeLoadingView(from viewController: UIViewController) {
        // Remove loading view by tag
        if let loadingView = viewController.view.viewWithTag(99999) {
            loadingView.removeFromSuperview()
        }
        
        // Also check in all windows
        if #available(iOS 13.0, *) {
            // iOS 13+ - use scenes
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        if let loadingView = window.viewWithTag(99999) {
                            loadingView.removeFromSuperview()
                        }
                    }
                }
            }
        } else {
            // iOS 12 and below
            for window in UIApplication.shared.windows {
                if let loadingView = window.viewWithTag(99999) {
                    loadingView.removeFromSuperview()
                }
            }
        }
    }

    private func playVideo(at urlString: String) {
        // print("🎬 playVideo called with URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            // print("❌ Failed to create URL from: \(urlString)")
            return
        }
        
        guard let viewController = findParentViewController() else {
            // print("❌ Failed to find parent view controller")
            return
        }
        
        // Show loading indicator
        let loadingView = createLoadingView()
        loadingView.tag = 99999 // Tag for identification
        
        // Make sure we're adding to the right view
        let targetView = viewController.view ?? UIApplication.shared.windows.first?.rootViewController?.view
        targetView?.addSubview(loadingView)
        
        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: targetView?.centerXAnchor ?? loadingView.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: targetView?.centerYAnchor ?? loadingView.centerYAnchor),
            loadingView.widthAnchor.constraint(equalToConstant: 120),
            loadingView.heightAnchor.constraint(equalToConstant: 120)
        ])
        
        // Download video to temp file first
        Task {
            do {
                // print("📥 Starting video download task...")
                let videoData = try await downloadVideo(from: urlString)
                // print("📥 Video data received: \(videoData.count) bytes")
                
                // Save to temp file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_video_\(UUID().uuidString).mp4")
                // print("📥 Saving to temp file: \(tempURL.path)")
                try videoData.write(to: tempURL)
                // print("✅ Video saved successfully")
                
                await MainActor.run {
                    // Store URL for cleanup
                    self.tempVideoURLs.insert(tempURL)
                    
                    // Remove loading view safely
                    self.removeLoadingView(from: viewController)
                    
                    // Play from local file
                    self.playLocalVideo(at: tempURL, from: viewController)
                }
            } catch {
                // print("❌ Failed to download video: \(error)")
                await MainActor.run {
                    // Remove loading view safely
                    self.removeLoadingView(from: viewController)
                    
                    // Show error
                    let errorMessage = error.localizedDescription
                    let errorAlert = UIAlertController(
                        title: "Error",
                        message: "Failed to load video: \(errorMessage)",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    viewController.present(errorAlert, animated: true)
                }
            }
        }
    }
    
    private func downloadVideo(from urlString: String) async throws -> Data {
        // print("📥 Starting video download from: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        
        // Add auth header
        if let viewState = self.viewState, let token = viewState.sessionToken {
            request.setValue(token, forHTTPHeaderField: "x-session-token")
            // print("📥 Added auth token to request")
        } else {
            // print("⚠️ No auth token available")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            // print("❌ Invalid response type")
            throw URLError(.badServerResponse)
        }
        
        // print("📥 Response status code: \(httpResponse.statusCode)")
        // print("📥 Response headers: \(httpResponse.allHeaderFields)")
        
        // Check content type
        if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String {
            // print("📥 Content-Type: \(contentType)")
        }
        
        guard httpResponse.statusCode == 200 else {
            // print("❌ Bad status code: \(httpResponse.statusCode)")
            
            // If we get a 401, it's likely an auth issue
            if httpResponse.statusCode == 401 {
                // print("❌ Authentication failed - token might be invalid")
            }
            
            // Try to read error body
            if let errorString = String(data: data, encoding: .utf8) {
                // print("❌ Error response: \(errorString)")
            }
            
            throw URLError(.badServerResponse)
        }
        
        // print("✅ Downloaded \(data.count) bytes")
        return data
    }
    
    // Store reference to video window
    private static var videoWindow: UIWindow?
    
    private func playLocalVideo(at url: URL, from viewController: UIViewController) {
        // print("🎬 Playing local video from: \(url)")
        
        // Verify file exists
        if FileManager.default.fileExists(atPath: url.path) {
            // print("✅ Video file exists at path")
            
            // Check file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? NSNumber {
                // print("📊 Video file size: \(fileSize.intValue) bytes")
            }
        } else {
            // print("❌ Video file does NOT exist at path!")
            return
        }
        
        // Create AVPlayer with local file
        let player = AVPlayer(url: url)
        
        // Create AVPlayerViewController
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        // Clean up temp file when done
        playerViewController.delegate = self
        
        // Set modal presentation style to full screen
        playerViewController.modalPresentationStyle = .fullScreen
        
        // Enable standard video player features
        playerViewController.showsPlaybackControls = true
        playerViewController.allowsPictureInPicturePlayback = false // Disable PiP to avoid issues
        playerViewController.entersFullScreenWhenPlaybackBegins = true
        playerViewController.exitsFullScreenWhenPlaybackEnds = true
        
        // print("🎬 Creating separate window for video player...")
        
        // Create a new window for the video player
        let window: UIWindow
        
        if #available(iOS 13.0, *) {
            // For iOS 13+, get the proper window scene
            if let windowScene = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .first as? UIWindowScene {
                window = UIWindow(windowScene: windowScene)
            } else {
                window = UIWindow(frame: UIScreen.main.bounds)
            }
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        
        // Set window level to be above normal windows
        window.windowLevel = .statusBar + 1
        
        // Create a simple root view controller to present from
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .black
        window.rootViewController = rootVC
        
        // Store window reference
        MessageCell.videoWindow = window
        
        // Make window visible
        window.makeKeyAndVisible()
        
        // Present player from the window's root view controller
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            rootVC.present(playerViewController, animated: true) {
                // print("✅ Video player presented in separate window, starting playback...")
                // Start playback
                player.play()
                
                // Check player status after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let error = player.currentItem?.error {
                        // print("❌ Player error: \(error)")
                    } else {
                        // print("✅ Player seems to be working")
                    }
                }
            }
        }
    }
    

    
    private func configureMessageContent(message: Message, viewState: ViewState) {
        if let content = message.content, !content.isEmpty {
            // Process content for display
            let processedContent = removeEmptyMarkdownLinks(from: content)
            
            // Check if content contains mentions
            let hasMentions = processedContent.contains("<@") || processedContent.contains("<#")
            
            if hasMentions {
                // Use clickable mentions
                let mutableAttributedText = NSMutableAttributedString(attributedString: createAttributedTextWithClickableMentions(from: processedContent, viewState: viewState))
                // Process custom emojis
                processCustomEmojis(in: mutableAttributedText, textView: contentLabel)
                contentLabel.attributedText = mutableAttributedText
                contentLabel.isSelectable = true
            } else {
                // Use markdown processing
                let mutableAttributedText = NSMutableAttributedString(attributedString: processMarkdownOptimized(processedContent))
                // Process custom emojis
                processCustomEmojis(in: mutableAttributedText, textView: contentLabel)
                contentLabel.attributedText = mutableAttributedText
                contentLabel.isSelectable = false
            }
        } else {
            contentLabel.text = ""
            contentLabel.isSelectable = false
        }
    }
    
    // MARK: - Emoji Processing
    private func processCustomEmojis(in attributedString: NSMutableAttributedString, textView: UITextView) {
        // Process custom emoji with IDs like :01J6GCN9DDDRJV1R0STZYB8432:
        let customEmojiPattern = ":([A-Za-z0-9]{26}):"
        
        do {
            let regex = try NSRegularExpression(pattern: customEmojiPattern)
            let text = attributedString.string
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
            
            // Process matches in reverse to avoid index issues
            for match in matches.reversed() {
                if let emojiIdRange = Range(match.range(at: 1), in: text) {
                    let emojiId = String(text[emojiIdRange])
                    let fullMatchRange = match.range
                    
                    // Create text attachment for the emoji
                    let attachment = NSTextAttachment()
                    let emojiSize = CGSize(width: 20, height: 20)
                    attachment.bounds = CGRect(x: 0, y: -4, width: emojiSize.width, height: emojiSize.height)
                    
                    // Load the emoji from the URL using dynamic API endpoint
                    if let apiInfo = viewState?.apiInfo,
                       let url = URL(string: "\(apiInfo.features.autumn.url)/emojis/\(emojiId)") {
                        // Use Kingfisher to load and set the image
                        KF.url(url)
                            .placeholder(.none)
                            .appendProcessor(ResizingImageProcessor(referenceSize: emojiSize, mode: .aspectFit))
                            .set(to: attachment, attributedView: textView)
                    }
                    
                    // Replace the emoji code with the attachment
                    let attachmentString = NSAttributedString(attachment: attachment)
                    attributedString.replaceCharacters(in: fullMatchRange, with: attachmentString)
                }
            }
        } catch {
            print("Error processing custom emojis with IDs: \(error)")
        }
        
        // Process named emoji shortcodes like :smile:, :1234:, etc.
        let namedEmojiPattern = ":([a-zA-Z0-9_+-]+):"
        
        do {
            let regex = try NSRegularExpression(pattern: namedEmojiPattern)
            let text = attributedString.string
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
            
            // Process matches in reverse to avoid index issues
            for match in matches.reversed() {
                if let shortcodeRange = Range(match.range(at: 1), in: text) {
                    let shortcode = String(text[shortcodeRange])
                    let fullMatchRange = match.range
                    
                    // Check if this is an emoji shortcode using EmojiParser
                    if let emoji = EmojiParser.findEmojiByShortcode(shortcode) {
                        if emoji.hasPrefix("custom:") {
                            // Handle custom emoji with image attachment
                            let attachment = NSTextAttachment()
                            let emojiSize = CGSize(width: 20, height: 20)
                            attachment.bounds = CGRect(x: 0, y: -4, width: emojiSize.width, height: emojiSize.height)
                            
                            let customEmojiURL = EmojiParser.parseEmoji(emoji, apiInfo: viewState?.apiInfo)
                            if let url = URL(string: customEmojiURL) {
                                KF.url(url)
                                    .placeholder(.none)
                                    .appendProcessor(ResizingImageProcessor(referenceSize: emojiSize, mode: .aspectFit))
                                    .set(to: attachment, attributedView: textView)
                            }
                            
                            let attachmentString = NSAttributedString(attachment: attachment)
                            attributedString.replaceCharacters(in: fullMatchRange, with: attachmentString)
                        } else {
                            // Handle Unicode emoji - replace with the actual emoji character
                            let emojiAttributedString = NSAttributedString(string: emoji)
                            attributedString.replaceCharacters(in: fullMatchRange, with: emojiAttributedString)
                        }
                    }
                }
            }
        } catch {
            print("Error processing named emoji shortcodes: \(error)")
        }
    }
    
    private func configureAvatar(author: User, member: Member?, message: Message, viewState: ViewState) {
        let avatarInfo = viewState.resolveAvatarUrl(user: author, member: member, masquerade: message.masquerade)
        
        avatarImageView.kf.setImage(
            with: avatarInfo.url,
            placeholder: UIImage(systemName: "person.circle.fill"),
            options: [
                .transition(.fade(0.2)),
                .cacheOriginalImage
            ]
        )
        
        // Set background color if no avatar
        if !avatarInfo.isAvatarSet {
            let displayName = message.masquerade?.name ?? member?.nickname ?? author.display_name ?? author.username
            avatarImageView.backgroundColor = UIColor(
                hue: CGFloat(displayName.hashValue % 100) / 100.0,
                saturation: 0.8,
                brightness: 0.8,
                alpha: 1.0
            )
        } else {
            avatarImageView.backgroundColor = UIColor.clear
        }
    }
    
    private func loadAttachments(message: Message, viewState: ViewState) {
        guard let attachments = message.attachments, !attachments.isEmpty else {
            // Remove existing attachments
            imageAttachmentsContainer?.removeFromSuperview()
            imageAttachmentsContainer = nil
            imageAttachmentViews.removeAll()
            
            fileAttachmentsContainer?.removeFromSuperview()
            fileAttachmentsContainer = nil
            fileAttachmentViews.removeAll()
            
            return
        }
        
        // Clear existing constraints
        clearContentLabelBottomConstraints()
        
        // Separate attachments by type
        let imageAttachments = attachments.filter { isImageFile($0) }
        let fileAttachments = attachments.filter { !isImageFile($0) }
        
        // Load image attachments
        if !imageAttachments.isEmpty {
            let imageIds = imageAttachments.map { $0.id }
            loadImageAttachments(attachments: imageIds, viewState: viewState)
        }
        
        // Load file attachments
        if !fileAttachments.isEmpty {
            loadFileAttachments(attachments: fileAttachments, viewState: viewState)
        }
    }
    
    private func setBottomConstraints(message: Message) {
        let hasReactions = !(message.reactions?.isEmpty ?? true)
        let hasAttachments = !(message.attachments?.isEmpty ?? true)
        let hasImageAttachments = imageAttachmentsContainer != nil && !imageAttachmentsContainer!.isHidden
        let hasFileAttachments = fileAttachmentsContainer != nil && !fileAttachmentsContainer!.isHidden
        let hasEmbeds = contentView.viewWithTag(2000) != nil
        
        if !hasReactions {
            // Priority order: embeds (always bottommost when present) -> file attachments -> image attachments -> content
            if hasEmbeds, let embedContainer = contentView.viewWithTag(2000) {
                // Embeds are handled in loadEmbeds() - they already have bottom constraint
                // Just ensure no conflicting bottom constraints from other elements
                removeConflictingBottomConstraints()
            } else if hasFileAttachments {
                let bottomConstraint = fileAttachmentsContainer!.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
                bottomConstraint.priority = UILayoutPriority.defaultHigh
                bottomConstraint.isActive = true
            } else if hasImageAttachments {
                // Image attachments already have bottom constraint
            } else if !hasAttachments {
                let bottomConstraint = contentLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
                bottomConstraint.priority = UILayoutPriority.defaultHigh
                bottomConstraint.isActive = true
            }
        }
        
        // Minimum height constraint
        let minHeightConstraint = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        minHeightConstraint.priority = UILayoutPriority.defaultLow
        minHeightConstraint.isActive = true
    }
    
    private func removeConflictingBottomConstraints() {
        // Remove bottom constraints from attachment containers when embeds are present
        // This prevents conflicts since embeds should be the bottommost element
        var constraintsToRemove: [NSLayoutConstraint] = []
        
        for constraint in contentView.constraints {
            // Remove bottom constraints from image and file containers that connect to contentView
            if let imageContainer = imageAttachmentsContainer,
               (constraint.firstItem === imageContainer && constraint.firstAttribute == .bottom && constraint.secondItem === contentView) ||
               (constraint.secondItem === imageContainer && constraint.secondAttribute == .bottom && constraint.firstItem === contentView) {
                constraintsToRemove.append(constraint)
            }
            
            if let fileContainer = fileAttachmentsContainer,
               (constraint.firstItem === fileContainer && constraint.firstAttribute == .bottom && constraint.secondItem === contentView) ||
               (constraint.secondItem === fileContainer && constraint.secondAttribute == .bottom && constraint.firstItem === contentView) {
                constraintsToRemove.append(constraint)
            }
        }
        
        constraintsToRemove.forEach { $0.isActive = false }
    }
}

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

// MARK: - UITextViewDelegate Extension for MessageCell
extension MessageCell {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        // Only handle if this is the content label and it's an invoke action
        guard textView == contentLabel && interaction == .invokeDefaultAction else {
            return true
        }
        
        print("🔗 MessageCell: URL tapped: \(URL.absoluteString)")
        
        // Check if this is a mention URL
        if URL.scheme == "mention", let userId = URL.host {
            // Handle mention tap - open user sheet using current view state
            if let viewState = self.viewState, let user = viewState.users[userId] {
                let member: Member? = {
                    if let serverId = currentMember?.id.server {
                        return viewState.members[serverId]?[userId]
                    }
                    return nil
                }()
                viewState.openUserSheet(user: user, member: member)
            }
            return false // Prevent default behavior
        }
        
        // Check if this is a channel URL
        if URL.scheme == "channel", let channelId = URL.host {
            // Handle channel mention tap - navigate to channel
            if let viewState = self.viewState, 
               let channel = viewState.channels[channelId] ?? viewState.allEventChannels[channelId] {
                
                // print("📱 Channel mention tapped: channel \(channelId)")
                
                // Get current user
                guard let currentUser = viewState.currentUser else {
                    // print("❌ Current user not found")
                    return false
                }
                
                // Check if it's a server channel
                if let serverId = channel.server {
                    // Check if user is a member of the server
                    let userMember = viewState.getMember(byServerId: serverId, userId: currentUser.id)
                    
                    if userMember != nil {
                        // User is a member - navigate to the channel
                        // print("✅ User is member of server, navigating to channel")
                        viewState.channelMessages[channelId] = []
                        
                        DispatchQueue.main.async {
                            viewState.selectServer(withId: serverId)
                            viewState.selectChannel(inServer: serverId, withId: channelId)
                            viewState.path.append(NavigationDestination.maybeChannelView)
                        }
                    } else {
                        // User is not a member - navigate to Discover
                        // print("🔍 User is not member of server \(serverId), navigating to Discover")
                        DispatchQueue.main.async {
                            // Clear path first to avoid navigation conflicts
                            viewState.path.removeAll()
                            viewState.selectDiscover()
                        }
                    }
                } else {
                    // DM or Group DM channel
                    var hasAccess = false
                    
                    // Check access based on channel type
                    switch channel {
                    case .dm_channel(let dmChannel):
                        hasAccess = dmChannel.recipients.contains(currentUser.id)
                    case .group_dm_channel(let groupDmChannel):
                        hasAccess = groupDmChannel.recipients.contains(currentUser.id)
                    case .saved_messages(let savedMessages):
                        hasAccess = savedMessages.user == currentUser.id
                    default:
                        hasAccess = true // For other types, allow access
                    }
                    
                    if hasAccess {
                        // User has access - navigate to the channel
                        // print("✅ User has access to channel, navigating")
                        viewState.channelMessages[channelId] = []
                        
                        DispatchQueue.main.async {
                            viewState.selectDm(withId: channelId)
                            viewState.path.append(NavigationDestination.maybeChannelView)
                        }
                    } else {
                        // User doesn't have access - navigate to Discover
                        // print("🔍 User doesn't have access to channel \(channelId), navigating to Discover")
                        DispatchQueue.main.async {
                            // Clear path first to avoid navigation conflicts
                            viewState.path.removeAll()
                            viewState.selectDiscover()
                        }
                    }
                }
            } else {
                // Channel not found - navigate to Discover
                // print("🔍 Channel \(channelId) not found, navigating to Discover")
                if let viewState = self.viewState {
                    DispatchQueue.main.async {
                        // Clear path first to avoid navigation conflicts
                        viewState.path.removeAll()
                        viewState.selectDiscover()
                    }
                }
            }
            return false // Prevent default behavior
        }
        
        // Check if this is a peptide.chat or app.revolt.chat link that should be handled internally
        if URL.absoluteString.hasPrefix("https://peptide.chat/server/") ||
           URL.absoluteString.hasPrefix("https://peptide.chat/channel/") ||
           URL.absoluteString.hasPrefix("https://peptide.chat/invite/") ||
           URL.absoluteString.hasPrefix("https://app.revolt.chat/server/") ||
           URL.absoluteString.hasPrefix("https://app.revolt.chat/channel/") ||
           URL.absoluteString.hasPrefix("https://app.revolt.chat/invite/") {
            
            print("🔗 MessageCell: Handling internal peptide.chat link")
            
            // Find the view controller to handle the URL
            if let viewController = findParentViewController() {
                handleInternalURL(URL, from: viewController)
            }
            
            return false // Prevent default behavior (going to Safari)
        }
        
        // For all other URLs, open in Safari
        // print("🔗 MessageCell: Opening external URL in Safari")
        
        // Temporarily suspend WebSocket to reduce network conflicts
        if let viewState = self.viewState {
            viewState.temporarilySuspendWebSocket()
        }
        
        // Explicitly open URL in Safari
        DispatchQueue.main.async {
            UIApplication.shared.open(URL, options: [:]) { success in
                // print("🌐 Safari open result for \(URL.absoluteString): \(success)")
            }
        }
        return false // Prevent default behavior
    }
    
    private func handleInternalURL(_ url: URL, from viewController: UIViewController) {
        guard let viewState = self.viewState else { 
            print("❌ MessageCell: ViewState is nil")
            return 
        }
        
        print("🔗 MessageCell: Handling URL: \(url.absoluteString)")
        
        if url.absoluteString.hasPrefix("https://peptide.chat/server/") ||
           url.absoluteString.hasPrefix("https://app.revolt.chat/server/") {
            let components = url.pathComponents
            print("🔗 MessageCell: URL components: \(components)")
            
            if components.count >= 6 {
                let serverId = components[2]
                let channelId = components[4]
                let messageId = components.count >= 6 ? components[5] : nil
                
                print("🔗 MessageCell: Parsed - Server: \(serverId), Channel: \(channelId), Message: \(messageId ?? "nil")")
                print("🔗 MessageCell: Server exists: \(viewState.servers[serverId] != nil)")
                print("🔗 MessageCell: Channel exists: \(viewState.channels[channelId] != nil)")
                
                // Check if server and channel exist
                if viewState.servers[serverId] != nil && (viewState.channels[channelId] != nil || viewState.allEventChannels[channelId] != nil) {
                    // Check if user is a member of the server
                    guard let currentUser = viewState.currentUser else {
                        // print("❌ MessageCell: Current user not found")
                        return
                    }
                    
                    let userMember = viewState.getMember(byServerId: serverId, userId: currentUser.id)
                    
                    if userMember != nil {
                        // User is a member - navigate to the channel
                        print("✅ MessageCell: User is member, navigating to channel")
                        
                        DispatchQueue.main.async {
                            // CRITICAL FIX: Set target message BEFORE navigation
                            // This ensures the new view controller will pick it up correctly
                            if let messageId = messageId {
                                viewState.currentTargetMessageId = messageId
                                print("🎯 MessageCell: Setting target message ID BEFORE navigation: \(messageId)")
                            } else {
                                viewState.currentTargetMessageId = nil
                            }
                            
                            // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                            // This ensures that when user presses back, they go to server list instead of previous channel
                            print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel")
                            viewState.path = []
                            
                            // CRITICAL FIX: Clear existing messages for target channel to force reload
                            viewState.channelMessages[channelId] = []
                            viewState.preloadedChannels.remove(channelId)
                            viewState.atTopOfChannel.remove(channelId)
                            
                            // Navigate to the server and channel
                            viewState.selectServer(withId: serverId)
                            viewState.selectChannel(inServer: serverId, withId: channelId)
                            
                            // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewState.path.append(NavigationDestination.maybeChannelView)
                                print("🎯 MessageCell: Navigation completed - new view controller will handle target message")
                            }
                        }
                    } else {
                        // User is not a member - navigate to Discover
                        print("🔍 MessageCell: User is not member, navigating to Discover")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewState.selectDiscover()
                        }
                    }
                } else {
                    // print("🔍 MessageCell: Server or channel not found, navigating to Discover")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewState.selectDiscover()
                    }
                }
            } else {
                // print("❌ MessageCell: Invalid URL format - not enough components")
            }
        } else if url.absoluteString.hasPrefix("https://peptide.chat/channel/") ||
                  url.absoluteString.hasPrefix("https://app.revolt.chat/channel/") {
            let components = url.pathComponents
            print("🔗 MessageCell: Channel URL components: \(components)")
            
                                                      if components.count >= 3 {
                let channelId = components[2]
                let messageId = components.count >= 4 ? components[3] : nil
                
                print("🔗 MessageCell: Parsed - Channel: \(channelId), Message: \(messageId ?? "nil")")
                print("🔗 MessageCell: Channel exists: \(viewState.channels[channelId] != nil)")
                
                if let channel = viewState.channels[channelId] ?? viewState.allEventChannels[channelId] {
                    // For DM channels, check if user has access
                    switch channel {
                    case .dm_channel(let dmChannel):
                        // Check if current user is in the recipients list
                        guard let currentUser = viewState.currentUser else {
                            // print("❌ MessageCell: Current user not found")
                            return
                        }
                        
                        if dmChannel.recipients.contains(currentUser.id) {
                            // User has access to this DM - navigate to it
                            // print("✅ MessageCell: User has access to DM, navigating")
                            
                            DispatchQueue.main.async {
                                // CRITICAL FIX: Set target message BEFORE navigation
                                if let messageId = messageId {
                                    viewState.currentTargetMessageId = messageId
                                    print("🎯 MessageCell: Setting target message ID BEFORE DM navigation: \(messageId)")
                                } else {
                                    viewState.currentTargetMessageId = nil
                                }
                                
                                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                // This ensures that when user presses back, they go to server list instead of previous channel
                                print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel (DM)")
                                viewState.path = []
                                
                                // CRITICAL FIX: Clear existing messages for target channel to force reload
                                viewState.channelMessages[channelId] = []
                                viewState.preloadedChannels.remove(channelId)
                                viewState.atTopOfChannel.remove(channelId)
                                
                                // Navigate to the channel
                                viewState.selectDm(withId: channelId)
                                
                                // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                    print("🎯 MessageCell: DM Navigation completed - new view controller will handle target message")
                                }
                            }
                        } else {
                            // User doesn't have access - navigate to Discover
                            // print("🔍 MessageCell: User doesn't have access to DM, navigating to Discover")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewState.selectDiscover()
                            }
                        }
                    case .group_dm_channel(let groupDmChannel):
                        // Check if current user is in the recipients list
                        guard let currentUser = viewState.currentUser else {
                            // print("❌ MessageCell: Current user not found")
                            return
                        }
                        
                        if groupDmChannel.recipients.contains(currentUser.id) {
                            // User has access to this group DM - navigate to it
                            // print("✅ MessageCell: User has access to group DM, navigating")
                            
                            DispatchQueue.main.async {
                                // CRITICAL FIX: Set target message BEFORE navigation
                                if let messageId = messageId {
                                    viewState.currentTargetMessageId = messageId
                                    print("🎯 MessageCell: Setting target message ID BEFORE Group DM navigation: \(messageId)")
                                } else {
                                    viewState.currentTargetMessageId = nil
                                }
                                
                                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel (Group DM)")
                                viewState.path = []
                                
                                // CRITICAL FIX: Clear existing messages for target channel to force reload
                                viewState.channelMessages[channelId] = []
                                viewState.preloadedChannels.remove(channelId)
                                viewState.atTopOfChannel.remove(channelId)
                                
                                // Navigate to the channel
                                viewState.selectDm(withId: channelId)
                                
                                // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                    print("🎯 MessageCell: Group DM Navigation completed - new view controller will handle target message")
                                }
                            }
                        } else {
                            // User doesn't have access - navigate to Discover
                            // print("🔍 MessageCell: User doesn't have access to group DM, navigating to Discover")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewState.selectDiscover()
                            }
                        }
                    default:
                        // For other channel types (text, voice, saved messages), check if it's a server channel
                        // print("✅ MessageCell: Navigating to channel")
                        
                        // Check if this channel belongs to a server
                        if let serverId = channel.server {
                            // This is a server channel - navigate to server first, then channel
                            print("🔗 MessageCell: Channel \(channelId) belongs to server \(serverId)")
                            
                            // Check if user has access to this server
                            guard let currentUser = viewState.currentUser else {
                                print("❌ MessageCell: Current user not found")
                                return
                            }
                            
                            let userMember = viewState.getMember(byServerId: serverId, userId: currentUser.id)
                            
                            if userMember != nil {
                                // User is a member - navigate to the server and channel
                                print("✅ MessageCell: User is member of server, navigating to server channel")
                                
                                DispatchQueue.main.async {
                                    // CRITICAL FIX: Set target message BEFORE navigation
                                    if let messageId = messageId {
                                        viewState.currentTargetMessageId = messageId
                                        print("🎯 MessageCell: Setting target message ID BEFORE server channel navigation: \(messageId)")
                                    } else {
                                        viewState.currentTargetMessageId = nil
                                    }
                                    
                                    // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                    print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel (Server Channel)")
                                    viewState.path = []
                                    
                                    // CRITICAL FIX: Clear existing messages for target channel to force reload
                                    viewState.channelMessages[channelId] = []
                                    viewState.preloadedChannels.remove(channelId)
                                    viewState.atTopOfChannel.remove(channelId)
                                    
                                    // Navigate to the server and channel
                                    viewState.selectServer(withId: serverId)
                                    viewState.selectChannel(inServer: serverId, withId: channelId)
                                    
                                    // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        viewState.path.append(NavigationDestination.maybeChannelView)
                                        print("🎯 MessageCell: Server Channel Navigation completed - new view controller will handle target message")
                                    }
                                }
                            } else {
                                // User is not a member - navigate to Discover
                                print("🔍 MessageCell: User is not member of server \(serverId), navigating to Discover")
                                DispatchQueue.main.async {
                                    viewState.selectDiscover()
                                }
                            }
                        } else {
                            // This is not a server channel (saved messages, etc.) - navigate as DM
                            print("🔗 MessageCell: Channel \(channelId) is not a server channel, treating as DM")
                            
                            DispatchQueue.main.async {
                                // CRITICAL FIX: Set target message BEFORE navigation
                                if let messageId = messageId {
                                    viewState.currentTargetMessageId = messageId
                                    print("🎯 MessageCell: Setting target message ID BEFORE DM navigation: \(messageId)")
                                } else {
                                    viewState.currentTargetMessageId = nil
                                }
                                
                                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel (Non-server Channel)")
                                viewState.path = []
                                
                                // CRITICAL FIX: Clear existing messages for target channel to force reload
                                viewState.channelMessages[channelId] = []
                                viewState.preloadedChannels.remove(channelId)
                                viewState.atTopOfChannel.remove(channelId)
                                
                                // Navigate to the channel
                                viewState.selectDm(withId: channelId)
                                
                                // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                }
                                print("🎯 MessageCell: DM Navigation completed - new view controller will handle target message")
                            }
                        }
                    }
                } else {
                    // print("🔍 MessageCell: Channel not found, navigating to Discover")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewState.selectDiscover()
                    }
                }
            } else {
                // print("❌ MessageCell: Invalid channel URL format")
            }
        } else if url.absoluteString.hasPrefix("https://peptide.chat/invite/") ||
                  url.absoluteString.hasPrefix("https://app.revolt.chat/invite/") {
            let components = url.pathComponents
            if let inviteCode = components.last {
                // print("🔗 MessageCell: Processing invite code: \(inviteCode)")
                
                // First, try to fetch invite info to check if user is already a member
                Task {
                    do {
                        // Fetch invite info
                        let inviteInfo = try await viewState.http.fetchInvite(code: inviteCode).get()
                        
                        await MainActor.run {
                            // Check if user is already a member of this server (only applies to server invites)
                            if let serverId = inviteInfo.getServerID(),
                               let currentUser = viewState.currentUser,
                               viewState.getMember(byServerId: serverId, userId: currentUser.id) != nil {
                                // User is already a member - navigate directly to the server
                                // print("✅ MessageCell: User is already a member of server \(serverId), navigating directly")
                                
                                // Clear existing messages for the default channel
                                if let server = viewState.servers[serverId],
                                   let channelId = inviteInfo.getChannelID() ?? server.channels.first {
                                    viewState.channelMessages[channelId] = []
                                }
                                
                                // Navigate to the server and channel
                                viewState.selectServer(withId: serverId)
                                
                                // If invite has a specific channel, go to it, otherwise go to first channel
                                if let channelId = inviteInfo.getChannelID() {
                                    viewState.selectChannel(inServer: serverId, withId: channelId)
                                } else if let server = viewState.servers[serverId],
                                          let firstChannelId = server.channels.first {
                                    viewState.selectChannel(inServer: serverId, withId: firstChannelId)
                                }
                                
                                viewState.path.append(NavigationDestination.maybeChannelView)
                            } else if case .group(let groupInfo) = inviteInfo {
                                // For group invites, check if user is already in the group
                                let channelId = groupInfo.channel_id
                                if let channel = viewState.channels[channelId],
                                   case .group_dm_channel(let groupDM) = channel,
                                   let currentUser = viewState.currentUser,
                                   groupDM.recipients.contains(currentUser.id) {
                                    // User is already in the group - navigate directly
                                    // print("✅ MessageCell: User is already in group \(channelId), navigating directly")
                                    viewState.channelMessages[channelId] = []
                                    viewState.selectDm(withId: channelId)
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                } else {
                                    // User is not in the group - show invite acceptance screen
                                    // print("🔗 MessageCell: User is not in group, showing invite screen")
                                    viewState.path.append(NavigationDestination.invite(inviteCode))
                                }
                            } else {
                                // User is not a member - show invite acceptance screen
                                // print("🔗 MessageCell: User is not a member, showing invite screen")
                                viewState.path.append(NavigationDestination.invite(inviteCode))
                            }
                        }
                    } catch {
                        // If we can't fetch invite info, just go to invite screen
                        // print("❌ MessageCell: Failed to fetch invite info: \(error)")
                        await MainActor.run {
                            viewState.path.append(NavigationDestination.invite(inviteCode))
                        }
                    }
                }
            }
        }
    }
}


// MARK: - UIGestureRecognizerDelegate Extension
extension MessageCell {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = panGesture.velocity(in: contentView)
            
            // Only accept primarily horizontal gestures with a significant horizontal velocity
            return abs(velocity.x) > abs(velocity.y) * 2 && abs(velocity.x) > 300
        }
        
        // For link long press gestures on content label, check if it's on a link
        if let longPressGesture = gestureRecognizer as? UILongPressGestureRecognizer,
           longPressGesture.view == contentLabel {
            let location = longPressGesture.location(in: contentLabel)
            let characterIndex = contentLabel.layoutManager.characterIndex(for: location, in: contentLabel.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            
            // Only allow long press gesture if it's on a link
            if characterIndex < contentLabel.textStorage.length {
                let attributes = contentLabel.textStorage.attributes(at: characterIndex, effectiveRange: nil)
                return attributes[.link] != nil
            }
            return false
        }
        
        // For tap gestures on content label, check if it's on a link
        if let tapGesture = gestureRecognizer as? UITapGestureRecognizer,
           tapGesture.view == contentLabel {
            let location = tapGesture.location(in: contentLabel)
            let characterIndex = contentLabel.layoutManager.characterIndex(for: location, in: contentLabel.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            
            // Only allow tap gesture if it's on a link
            if characterIndex < contentLabel.textStorage.length {
                let attributes = contentLabel.textStorage.attributes(at: characterIndex, effectiveRange: nil)
                return attributes[.link] != nil
            }
            return false
        }
        
        return true
    }
    
    // Allow simultaneous recognition with other gesture recognizers (like tableView's pan gesture)
    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't allow simultaneous recognition between tap and long press gestures
        if gestureRecognizer is UITapGestureRecognizer && otherGestureRecognizer is UILongPressGestureRecognizer {
            return false
        }
        
        if gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer {
            return false
        }
        
        // For pan gestures, check the direction
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
           let otherPanGesture = otherGestureRecognizer as? UIPanGestureRecognizer {
            
            let velocity = panGesture.velocity(in: contentView)
            let otherVelocity = otherPanGesture.velocity(in: contentView)
            
            // If our gesture is primarily horizontal and the other is primarily vertical,
            // they can work simultaneously
            let isHorizontal = abs(velocity.x) > abs(velocity.y)
            let isOtherVertical = abs(otherVelocity.y) > abs(otherVelocity.x)
            
            return isHorizontal && isOtherVertical
        }
        
        return true
    }
}

// MARK: - Custom Message Option View Controller
class MessageOptionViewController: UIViewController {
    private let message: Message
    private let isMessageAuthor: Bool
    private let canDeleteMessage: Bool
    private let canReply: Bool
    private let onOptionSelected: (MessageCell.MessageAction) -> Void
    
    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    
    // Emoji reactions list (based on MessageEmojisReact.swift)
    private let emojiItems: [[Int]] = [[128077], [129315], [9786,65039], [10084,65039], [128559]]
    
    // Array to store button actions
    private var actions: [() -> Void] = []
    
    init(message: Message, isMessageAuthor: Bool, canDeleteMessage: Bool, canReply: Bool, onOptionSelected: @escaping (MessageCell.MessageAction) -> Void) {
        self.message = message
        self.isMessageAuthor = isMessageAuthor
        self.canDeleteMessage = canDeleteMessage
        self.canReply = canReply
        self.onOptionSelected = onOptionSelected
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupEmojiReactions()
        setupOptions()
    }
    
    private func setupUI() {
        // Set background color to match SwiftUI version (.bgGray12)
        view.backgroundColor = UIColor(named: "bgGray12") ?? UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
        
        // Set corner radius to view to ensure it's visible on the sheet
        if #available(iOS 15.0, *) {
            // iOS 15+ will handle this with sheet presentation controller
        } else {
            view.layer.cornerRadius = 16
            view.clipsToBounds = true
        }
        
        // Set up scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
        
        // Set up content stack view
        contentStackView.axis = .vertical
        contentStackView.spacing = 24
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStackView)
        
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupEmojiReactions() {
        // Create emoji container
        let emojiStack = UIStackView()
        emojiStack.axis = .horizontal
        emojiStack.spacing = 12
        emojiStack.distribution = .fillEqually
        emojiStack.translatesAutoresizingMaskIntoConstraints = false
        emojiStack.alignment = .center
        
        // Center the emojis horizontally
        let containerStack = UIStackView()
        containerStack.axis = .vertical
        containerStack.alignment = .center
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(containerStack)
        containerStack.addArrangedSubview(emojiStack)
        
        // Add emoji buttons
        for emojiCodes in emojiItems {
            let emojiButton = createEmojiButton(with: emojiCodes)
            emojiStack.addArrangedSubview(emojiButton)
        }
        
        // Add "Add custom emoji" button
        let customEmojiButton = createCustomEmojiButton()
        emojiStack.addArrangedSubview(customEmojiButton)
        
        // Set height constraint for the emoji stack
        NSLayoutConstraint.activate([
            emojiStack.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    
    private func createEmojiButton(with codePoints: [Int]) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create background circle
        let circleView = UIView()
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = UIColor(named: "bgGray11") ?? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0)
        circleView.layer.cornerRadius = 24
        containerView.addSubview(circleView)
        
        // Create emoji label
        let emojiLabel = UILabel()
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Convert code points to emoji string
        let emojiString = codePoints.compactMap { UnicodeScalar($0) }.reduce(into: "") { result, scalar in
            result.append(Character(scalar))
        }
        
        emojiLabel.text = emojiString
        emojiLabel.font = UIFont.systemFont(ofSize: 24)
        emojiLabel.textAlignment = .center
        circleView.addSubview(emojiLabel)
        
        // Add highlight effect on touch
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(emojiButtonTapped(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUpOutside(_:)), for: .touchUpOutside)
        
        // Store emoji string in button's accessibilityLabel for later retrieval
        button.accessibilityLabel = emojiString
        containerView.addSubview(button)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            containerView.widthAnchor.constraint(equalToConstant: 48),
            containerView.heightAnchor.constraint(equalToConstant: 48),
            
            circleView.widthAnchor.constraint(equalToConstant: 48),
            circleView.heightAnchor.constraint(equalToConstant: 48),
            circleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            emojiLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            
            button.topAnchor.constraint(equalTo: containerView.topAnchor),
            button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    private func createCustomEmojiButton() -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create background circle
        let circleView = UIView()
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = UIColor(named: "bgGray11") ?? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0)
        circleView.layer.cornerRadius = 24
        containerView.addSubview(circleView)
        
        // Create icon - try to use Peptide icon if available
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(named: "iconDefaultGray01") ?? .white
        
        if let peptideImage = UIImage(named: "peptideSmile") {
            iconView.image = peptideImage
        } else {
            iconView.image = UIImage(systemName: "face.smiling.fill")
        }
        
        circleView.addSubview(iconView)
        
        // Add highlight effect on touch
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(customEmojiButtonTapped), for: .touchUpInside)
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUpOutside(_:)), for: .touchUpOutside)
        containerView.addSubview(button)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            containerView.widthAnchor.constraint(equalToConstant: 48),
            containerView.heightAnchor.constraint(equalToConstant: 48),
            
            circleView.widthAnchor.constraint(equalToConstant: 48),
            circleView.heightAnchor.constraint(equalToConstant: 48),
            circleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            iconView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            button.topAnchor.constraint(equalTo: containerView.topAnchor),
            button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    @objc private func emojiButtonTapped(_ sender: UIButton) {
        guard let emojiString = sender.accessibilityLabel else { return }
        dismiss(animated: true) {
            // Send the emoji reaction
            // print("Selected emoji reaction: \(emojiString)")
            // Add handling for the emoji reaction (we'll need to add this action type)
            self.onOptionSelected(.react(emojiString))
        }
    }
    
    @objc private func customEmojiButtonTapped() {
        dismiss(animated: true) {
            // Request custom emoji selector
            // print("Open custom emoji selector")
            self.onOptionSelected(.react("-1")) // -1 is used to indicate custom emoji selection
        }
    }
    
    private func setupOptions() {
        // Author-specific options
        if isMessageAuthor {
            let authorOptionsStack = createOptionsGroup()
            
            // Edit option
            let editOption = createOptionButton(
                title: "Edit Message",
                iconName: "pencil",
                action: { [weak self] in
                    self?.onOptionSelected(.edit)
                    self?.dismiss(animated: true)
                }
            )
            authorOptionsStack.addArrangedSubview(editOption)
            
            // Add divider
            addDividerToGroup(group: authorOptionsStack)
            
            // Reply option (only if user has permission)
            if canReply {
                let replyOption = createOptionButton(
                    title: "Reply",
                    iconName: "arrowshape.turn.up.left",
                    action: { [weak self] in
                        self?.onOptionSelected(.reply)
                        self?.dismiss(animated: true)
                    }
                )
                authorOptionsStack.addArrangedSubview(replyOption)
            }
            
            contentStackView.addArrangedSubview(authorOptionsStack)
        } else {
            // Reply option for non-authors (only if user has permission)
            if canReply {
                let replyOption = createOptionButton(
                    title: "Reply",
                    iconName: "arrowshape.turn.up.left",
                    action: { [weak self] in
                        self?.onOptionSelected(.reply)
                        self?.dismiss(animated: true)
                    }
                )
                let replyContainer = createOptionsGroup()
                replyContainer.addArrangedSubview(replyOption)
                contentStackView.addArrangedSubview(replyContainer)
            }
        }
        
        // Common options group
        let commonOptionsStack = createOptionsGroup()
        
        // Mention option (only if not author)
        if !isMessageAuthor {
            let mentionOption = createOptionButton(
                title: "Mention",
                iconName: "at",
                action: { [weak self] in
                    self?.onOptionSelected(.mention)
                    self?.dismiss(animated: true)
                }
            )
            commonOptionsStack.addArrangedSubview(mentionOption)
            addDividerToGroup(group: commonOptionsStack)
        }
        
        // Mark unread option
        let markUnreadOption = createOptionButton(
            title: "Mark Unread",
            iconName: "eye.slash",
            action: { [weak self] in
                self?.onOptionSelected(.markUnread)
                self?.dismiss(animated: true)
            }
        )
        commonOptionsStack.addArrangedSubview(markUnreadOption)
        addDividerToGroup(group: commonOptionsStack)
        
        // Copy text option
        let copyOption = createOptionButton(
            title: "Copy Text",
            iconName: "doc.on.doc",
            action: { [weak self] in
                self?.onOptionSelected(.copy)
                self?.dismiss(animated: true)
            }
        )
        commonOptionsStack.addArrangedSubview(copyOption)
        addDividerToGroup(group: commonOptionsStack)
        
        // Copy link option
        let copyLinkOption = createOptionButton(
            title: "Copy Message Link",
            iconName: "link",
            action: { [weak self] in
                self?.onOptionSelected(.copyLink)
                self?.dismiss(animated: true)
            }
        )
        commonOptionsStack.addArrangedSubview(copyLinkOption)
        addDividerToGroup(group: commonOptionsStack)
        
        // Copy ID option
        let copyIdOption = createOptionButton(
            title: "Copy Message ID",
            iconName: "number",
            action: { [weak self] in
                self?.onOptionSelected(.copyId)
                self?.dismiss(animated: true)
            }
        )
        commonOptionsStack.addArrangedSubview(copyIdOption)
        
        contentStackView.addArrangedSubview(commonOptionsStack)
        
        // Delete message option (if user is author or has permissions)
        if canDeleteMessage {
            let deleteOption = createOptionButton(
                title: "Delete Message",
                iconName: "trash",
                titleColor: UIColor(named: "textRed07") ?? .systemRed,
                iconColor: UIColor(named: "iconRed07") ?? .systemRed,
                action: { [weak self] in
                    self?.onOptionSelected(.delete)
                    self?.dismiss(animated: true)
                }
            )
            let deleteContainer = createOptionsGroup()
            deleteContainer.addArrangedSubview(deleteOption)
            contentStackView.addArrangedSubview(deleteContainer)
        }
        
        // Report option (only if not author)
        if !isMessageAuthor {
            let reportOption = createOptionButton(
                title: "Report Message",
                iconName: "flag",
                titleColor: UIColor(named: "textRed07") ?? .systemRed,
                iconColor: UIColor(named: "iconRed07") ?? .systemRed,
                action: { [weak self] in
                    self?.onOptionSelected(.report)
                    self?.dismiss(animated: true)
                }
            )
            let reportContainer = createOptionsGroup()
            reportContainer.addArrangedSubview(reportOption)
            contentStackView.addArrangedSubview(reportContainer)
        }
    }
    
    private func createOptionsGroup() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        // Apply rounded background with padding
        stack.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.isLayoutMarginsRelativeArrangement = true
        
        // Apply bgGray11 background color with rounded corners
        stack.backgroundColor = UIColor(named: "bgGray11") ?? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0)
        stack.layer.cornerRadius = 8
        stack.clipsToBounds = true
        
        return stack
    }
    
    private func createDivider() -> UIView {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor(named: "borderGray10") ?? UIColor.gray.withAlphaComponent(0.3)
        
        // Just set the height - leading constraint will be set after adding to stackView
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        return divider
    }
    
    // Method to add divider to group with padding
    private func addDividerToGroup(group: UIStackView) {
        let divider = createDivider()
        group.addArrangedSubview(divider)
        
        // Now that divider is added to stackView, we can set its constraints safely
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 12)
        ])
    }
    
    private func createOptionButton(title: String, iconName: String, titleColor: UIColor = UIColor(named: "textDefaultGray01") ?? .white, iconColor: UIColor = UIColor(named: "iconDefaultGray01") ?? .white, action: @escaping () -> Void) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Button background
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(optionButtonTapped(_:)), for: .touchUpInside)
        // Add highlight effect
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUpOutside(_:)), for: .touchUpOutside)
        button.tag = actions.count // Use tag to identify button action
        actions.append(action)
        
        containerView.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: containerView.topAnchor),
            button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Icon view
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = iconColor
        
        // Map from plain icon names to SF Symbol names
        let sfSymbolName = mapToSFSymbol(iconName)
        iconView.image = UIImage(systemName: sfSymbolName)
        
        containerView.addSubview(iconView)
        
        // Label
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = titleColor
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        
        containerView.addSubview(label)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            containerView.heightAnchor.constraint(equalToConstant: 48),
            
            iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -12)
        ])
        
        return containerView
    }
    
    private func mapToSFSymbol(_ iconName: String) -> String {
        // Map PeptideIcon names to SF Symbols
        switch iconName {
        case "pencil": return "pencil"
        case "arrowshape.turn.up.left": return "arrowshape.turn.up.left.fill"
        case "at": return "at"
        case "eye.slash": return "eye.slash.fill"
        case "doc.on.doc": return "doc.on.doc"
        case "link": return "link"
        case "number": return "number"
        case "trash": return "trash.fill"
        case "flag": return "flag.fill"
        default: return iconName
        }
    }
    
    @objc private func buttonTouchDown(_ sender: UIButton) {
        // Highlight effect when button is pressed
        UIView.animate(withDuration: 0.1) {
            sender.superview?.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        }
    }
    
    @objc private func buttonTouchUpOutside(_ sender: UIButton) {
        // Remove highlight when touch is cancelled
        UIView.animate(withDuration: 0.1) {
            sender.superview?.backgroundColor = nil
        }
    }
    
    @objc private func optionButtonTapped(_ sender: UIButton) {
        // Restore original background
        UIView.animate(withDuration: 0.1) {
            sender.superview?.backgroundColor = nil
        }
        
        // Execute the action
        if let action = actions[safe: sender.tag] {
            action()
        }
    }
    

}

// MARK: - Safe Array Access Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

