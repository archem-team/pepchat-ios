//
//  RepliesContainerView.swift
//  Revolt
//
//

import UIKit
import Kingfisher
import Types

// Import ReplyMessage from MessageableChannelViewController
@_implementationOnly import Revolt

// MARK: - RepliesContainerViewDelegate
protocol RepliesContainerViewDelegate: AnyObject {
    func repliesContainerView(_ view: RepliesContainerView, didRemoveReplyAt id: String)
    func getViewState() -> ViewState
}

// MARK: - RepliesContainerView
class RepliesContainerView: UIView {
    private var stackView: UIStackView!
    private var replies: [ReplyMessage] = []
    weak var delegate: RepliesContainerViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Match chat background color
        backgroundColor = .bgDefaultPurple13 // Changed from bgGray12
        
        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func configure(with replies: [ReplyMessage], viewState: ViewState) {
        self.replies = replies
        
        // Clear existing reply views
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add new reply views
        for reply in replies {
            let replyView = ReplyItemView(messageReply: reply, viewState: viewState)
            replyView.delegate = self
            stackView.addArrangedSubview(replyView)
        }
        
        // Update height constraint based on number of replies
        let desiredHeight = max(40, replies.count * 40) // Each reply is 40pt tall
        
        // Find and update height constraint or create a new one
        if let heightConstraint = constraints.first(where: { $0.firstAttribute == .height }) {
            heightConstraint.constant = CGFloat(desiredHeight)
        } else {
            heightAnchor.constraint(equalToConstant: CGFloat(desiredHeight)).isActive = true
        }
        
        layoutIfNeeded()
    }
}

// MARK: - ReplyItemViewDelegate
extension RepliesContainerView: ReplyItemViewDelegate {
    func replyItemViewDidPressRemove(_ view: ReplyItemView, replyId: String) {
        delegate?.repliesContainerView(self, didRemoveReplyAt: replyId)
    }
    
    func replyItemViewDidPressReply(_ view: ReplyItemView, messageId: String, channelId: String) {
        // Pass the reply click to the delegate (which should be RepliesManager)
        print("🔗 RepliesContainerView: Reply clicked, messageId: \(messageId), channelId: \(channelId)")
        if let repliesManagerDelegate = delegate as? RepliesManager {
            print("🔗 RepliesContainerView: Delegating to RepliesManager")
            repliesManagerDelegate.replyItemViewDidPressReply(messageId: messageId, channelId: channelId)
        } else {
            print("❌ RepliesContainerView: Delegate is not RepliesManager, delegate type: \(type(of: delegate))")
        }
    }
}

// MARK: - ReplyItemView and Delegate
protocol ReplyItemViewDelegate: AnyObject {
    func replyItemViewDidPressRemove(_ view: ReplyItemView, replyId: String)
    func replyItemViewDidPressReply(_ view: ReplyItemView, messageId: String, channelId: String)
}

class ReplyItemView: UIView {
    private var messageReply: ReplyMessage
    private var viewState: ViewState
    private var closeButton: UIButton!
    private var userIconView: UIImageView!
    private var usernameLabel: UILabel!
    
    weak var delegate: ReplyItemViewDelegate?
    
    init(messageReply: ReplyMessage, viewState: ViewState) {
        self.messageReply = messageReply
        self.viewState = viewState
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Match slightly darker background for better visibility
        backgroundColor = UIColor(named: "bgGray10") ?? UIColor.darkGray.withAlphaComponent(0.5)
        layer.cornerRadius = 8
        
        // Close button
        closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .textDefaultGray01
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        addSubview(closeButton)
        
        // User icon
        userIconView = UIImageView()
        userIconView.translatesAutoresizingMaskIntoConstraints = false
        userIconView.layer.cornerRadius = 12
        userIconView.clipsToBounds = true
        userIconView.backgroundColor = .gray
        userIconView.contentMode = .scaleAspectFill
        addSubview(userIconView)
        
        // Username label
        usernameLabel = UILabel()
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.font = UIFont.systemFont(ofSize: 14)
        usernameLabel.textColor = .textDefaultGray01
        
        // Get username from message using ViewState
        let authorName: String
        if let masqueradeName = messageReply.message.masquerade?.name {
            authorName = masqueradeName
        } else if let author = viewState.users[messageReply.message.author] {
            // Try to get member info for nickname
            let member = getMemberForMessage()
            authorName = member?.nickname ?? author.display_name ?? author.username
        } else {
            authorName = ""
        }
        
        usernameLabel.text = "Replying to \(authorName)"
        
        addSubview(usernameLabel)
        
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            
            userIconView.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
            userIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            userIconView.widthAnchor.constraint(equalToConstant: 24),
            userIconView.heightAnchor.constraint(equalToConstant: 24),
            
            usernameLabel.leadingAnchor.constraint(equalTo: userIconView.trailingAnchor, constant: 8),
            usernameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            usernameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
        
        // Load the user avatar
        loadUserAvatar()
        
        // Add tap gesture to navigate to original message
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(replyTapped))
        addGestureRecognizer(tapGesture)
        isUserInteractionEnabled = true
    }
    
    private func getMemberForMessage() -> Member? {
        // Get the channel to determine server
        if let channel = viewState.channels[messageReply.message.channel],
           let serverId = channel.server {
            return viewState.members[serverId]?[messageReply.message.author]
        }
        return nil
    }
    
    private func loadUserAvatar() {
        // Try to get the author from ViewState
        guard let author = viewState.users[messageReply.message.author] else {
            // Set a default avatar if user not found
            userIconView.image = UIImage(systemName: "person.circle.fill")
            userIconView.tintColor = .systemGray
            return
        }
        
        // Get the member if in a server
        let member = getMemberForMessage()
        
        // Get the avatar URL
        let masquerade: Masquerade? = messageReply.message.masquerade
        let avatarInfo = viewState.resolveAvatarUrl(user: author, member: member, masquerade: masquerade)
        
        // MEMORY OPTIMIZATION: Use aggressive downsampling for avatars (target 60x60 display = 120x120 @2x)
        let avatarProcessor = DownsamplingImageProcessor(size: CGSize(width: 120, height: 120))
        let scale = UIScreen.main.scale
        
        // Load the avatar with Kingfisher
        userIconView.kf.setImage(
            with: avatarInfo.url,
            placeholder: UIImage(systemName: "person.circle.fill"),
            options: [
                .processor(avatarProcessor),
                .scaleFactor(scale),
                .transition(.fade(0.2)),
                .cacheOriginalImage // Keep original in disk cache
            ]
        )
        
        // Set background color if no avatar
        if !avatarInfo.isAvatarSet {
            // Get the display name for color generation (includes masquerade name)
            let displayName = messageReply.message.masquerade?.name ?? member?.nickname ?? author.display_name ?? author.username
            
            // Generate color based on display name
            userIconView.backgroundColor = UIColor(
                hue: CGFloat(displayName.hashValue % 100) / 100.0,
                saturation: 0.8,
                brightness: 0.8,
                alpha: 1.0
            )
        } else {
            userIconView.backgroundColor = UIColor.clear
        }
    }
    
    @objc private func closeButtonTapped() {
        delegate?.replyItemViewDidPressRemove(self, replyId: messageReply.messageId)
    }
    
    @objc private func replyTapped() {
        // Navigate to the original message
        print("🔗 REPLY_TAP: Reply tap detected!")
        print("🔗 REPLY_TAP: messageId=\(messageReply.message.id)")
        print("🔗 REPLY_TAP: channelId=\(messageReply.message.channel)")
        print("🔗 REPLY_TAP: delegate=\(delegate != nil ? "exists" : "nil")")
        
        delegate?.replyItemViewDidPressReply(self, messageId: messageReply.message.id, channelId: messageReply.message.channel)
    }
}

// MARK: - Legacy ReplyItemView for compatibility
extension ReplyItemView {
    func configure(with message: Message, mention: Bool, viewState: ViewState?) {
        guard let viewState = viewState else {
            usernameLabel.text = ""
            return
        }
        
        // Update the internal state
        self.messageReply = ReplyMessage(message: message, mention: mention)
        self.viewState = viewState
        
        // Get username from message using ViewState
        let authorName: String
        if let masqueradeName = message.masquerade?.name {
            authorName = masqueradeName
        } else if let author = viewState.users[message.author] {
            // Try to get member info for nickname
            let member: Member?
            if let channel = viewState.channels[message.channel],
               let serverId = channel.server {
                member = viewState.members[serverId]?[message.author]
            } else {
                member = nil
            }
            authorName = member?.nickname ?? author.display_name ?? author.username
        } else {
            authorName = ""
        }
        
        usernameLabel.text = "Replying to \(authorName)"
        
        // Reload avatar    
        loadUserAvatar()
    }
}

