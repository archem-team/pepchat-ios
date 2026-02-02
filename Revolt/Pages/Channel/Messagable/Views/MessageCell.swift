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
    internal let avatarImageView = UIImageView()
    internal let usernameLabel = UILabel()
    internal let contentLabel = UITextView() // Changed from UILabel to UITextView
    internal let timeLabel = UILabel()
    internal let bridgeBadgeLabel = UILabel() // Badge for bridged messages
    internal var imageAttachmentsContainer: UIView?
    internal var imageAttachmentViews: [UIImageView] = []
    internal var fileAttachmentsContainer: UIView?
    internal var fileAttachmentViews: [UIView] = []
    internal var viewState: ViewState?
    

    
    // Reply components
    internal let replyView = UIView()
    internal let replyLineView = UIView()
    internal let replyAuthorLabel = UILabel()
    internal let replyContentLabel = UILabel()
    internal var currentReplyId: String? // Store the ID of the message being replied to
    internal let replyLoadingIndicator = UIActivityIndicatorView(style: .medium)
    
    // Loading alert reference and timeout timer
    private weak var loadingAlert: UIAlertController?
    private var loadingAlertTimer: Timer?
    
    // Reply loading timeout work item
    internal var replyLoadingTimeoutWorkItem: DispatchWorkItem?
    
    // Add access to contentLabel
    var textViewContent: UITextView {
        return contentLabel
    }
    
    // Store message and author for use in context menu actions
    internal var currentMessage: Message?
    private var currentAuthor: User?
    internal var currentMember: Member?
    
    // Reactions container
    internal let reactionsContainerView = UIView()
    
    // Swipe to reply properties
    internal var initialTouchPoint: CGPoint = .zero
    
    deinit {
        // Clean up any existing loading alert and timer
        loadingAlertTimer?.invalidate()
        loadingAlert?.dismiss(animated: false)
        
        // Cancel any pending reply loading timeout
        replyLoadingTimeoutWorkItem?.cancel()
    }
    internal var originalCenter: CGPoint = .zero
    internal var swipeReplyIconView: UIView?
    internal var replyIconImageView: UIImageView?
    internal var isSwiping: Bool = false
    internal var actionTriggered: Bool = false
    internal var swipeThreshold: CGFloat = 80.0
    
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
    internal func cleanupTempVideos() {
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
    
    internal func isCurrentUserAuthor() -> Bool {
        guard let message = currentMessage, let viewState = viewState else { return false }
        return message.author == viewState.currentUser?.id
    }
    
    internal func canDeleteMessage() -> Bool {
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
    
    internal func findParentViewController() -> UIViewController? {
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
    
    internal func createFileAttachmentView(for attachment: Types.File, viewState: ViewState) -> UIView {
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
    internal func addLoadingOverlayToImageView(_ imageView: UIImageView, attachmentId: String, queuedMessage: QueuedMessage) {
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
    
    @objc internal func handleAvatarTap() {
        onAvatarTap?()
    }
    
    @objc internal func handleUsernameTap() {
        onUsernameTap?()
    }
    
    internal func showReplyNotFoundMessage() {
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
    
    internal func showReplyLoadingIndicator() {
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
    
    internal func hideReplyLoadingIndicator() {
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
    
    internal func showCrossChannelReplyAlert(replyMessage: Message) {
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
    
    @objc internal func handleImageCellTap(_ gesture: UITapGestureRecognizer) {
        guard let imageView = gesture.view as? UIImageView,
              let image = imageView.image else { return }
        
        onImageTapped?(image)
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
    
    @objc internal func reactionButtonTapped(_ gesture: UITapGestureRecognizer) {
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

    internal func playVideo(at urlString: String) {
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
    internal static var videoWindow: UIWindow?
    
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


// MARK: - Safe Array Access Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

