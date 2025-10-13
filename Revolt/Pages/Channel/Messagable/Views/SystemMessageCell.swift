//
//  SystemMessageCell.swift
//  Revolt
//
//  Created by AI Assistant.
//

import UIKit
import Types

class SystemMessageCell: UITableViewCell {
    private let containerView = UIView()
    private let messageLabel = UILabel()
    private let dateLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        
        self.transform = CGAffineTransform(scaleX: 1, y: -1)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup message label - centered and styled
        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = UIColor.secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup date label - hide it
        dateLabel.isHidden = true
        
        // Add only message label to container
        containerView.addSubview(messageLabel)
        
        // Setup constraints - center everything
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            messageLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Reset message label
        messageLabel.text = nil
        messageLabel.attributedText = nil
        messageLabel.textAlignment = .center
        messageLabel.textColor = UIColor.secondaryLabel
        messageLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
    }
    
    func configure(with message: Message, viewState: ViewState) {
        guard let systemContent = message.system else { return }
        
        let messageDate = createdAt(id: message.id)
        dateLabel.text = formattedMessageDate(from: messageDate)
        
        switch systemContent {
        case .user_joined(let content):
            configureUserJoined(content: content, viewState: viewState)
            
        case .user_left(let content):
            configureUserLeft(content: content, viewState: viewState)
            
        case .user_added(let content):
            configureUserAdded(content: content, viewState: viewState, message: message)
            
        case .user_removed(let content):
            configureUserRemoved(content: content, viewState: viewState, message: message)
            
        case .user_kicked(let content):
            configureUserKicked(content: content, viewState: viewState, message: message)
            
        case .user_banned(let content):
            configureUserBanned(content: content, viewState: viewState, message: message)
            
        case .channel_renamed(let content):
            configureChannelRenamed(content: content, viewState: viewState, message: message)
            
        case .channel_description_changed(let content):
            configureChannelDescriptionChanged(content: content, viewState: viewState, message: message)
            
        case .channel_icon_changed(let content):
            configureChannelIconChanged(content: content, viewState: viewState, message: message)
            
        case .channel_ownership_changed(let content):
            configureChannelOwnershipChanged(content: content, viewState: viewState, message: message)
            
        case .message_pinned(let content):
            configureMessagePinned(content: content, isPinned: true)
            
        case .message_unpinned(let content):
            configureMessagePinned(content: content, isPinned: false)
            
        case .text(let content):
            configureTextSystemMessage(content: content)
        }
    }
    
    private func configureUserJoined(content: UserJoinedSystemContent, viewState: ViewState) {
        guard let user = viewState.users[content.id] else { return }
        setSimpleMessage("\(getUserDisplayName(user: user, viewState: viewState)) joined the group.")
    }
    
    private func configureUserLeft(content: UserLeftSystemContent, viewState: ViewState) {
        guard let user = viewState.users[content.id] else { return }
        setSimpleMessage("\(getUserDisplayName(user: user, viewState: viewState)) left the group.")
    }
    
    private func configureUserAdded(content: UserAddedSystemContent, viewState: ViewState, message: Message) {
        guard let addedUser = viewState.users[content.id],
              let byUser = viewState.users[content.by] else { return }
        setSimpleMessage("\(getUserDisplayName(user: addedUser, viewState: viewState)) was added by \(getUserDisplayName(user: byUser, viewState: viewState))")
    }
    
    private func configureUserRemoved(content: UserRemovedSystemContent, viewState: ViewState, message: Message) {
        guard let removedUser = viewState.users[content.id],
              let byUser = viewState.users[content.by] else { return }
        setSimpleMessage("\(getUserDisplayName(user: removedUser, viewState: viewState)) was removed by \(getUserDisplayName(user: byUser, viewState: viewState))")
    }
    
    private func configureUserKicked(content: UserKickedSystemContent, viewState: ViewState, message: Message) {
        guard let kickedUser = viewState.users[content.id] else { return }
        setSimpleMessage("\(getUserDisplayName(user: kickedUser, viewState: viewState)) was kicked.")
    }
    
    private func configureUserBanned(content: UserBannedSystemContent, viewState: ViewState, message: Message) {
        guard let bannedUser = viewState.users[content.id] else { return }
        setSimpleMessage("\(getUserDisplayName(user: bannedUser, viewState: viewState)) was banned.")
    }
    
    private func configureChannelRenamed(content: ChannelRenamedSystemContent, viewState: ViewState, message: Message) {
        guard let user = viewState.users[content.by] else { return }
        setSimpleMessage("\(getUserDisplayName(user: user, viewState: viewState)) renamed the channel to: \(content.name)")
    }
    
    private func configureChannelDescriptionChanged(content: ChannelDescriptionChangedSystemContent, viewState: ViewState, message: Message) {
        guard let user = viewState.users[content.by] else { return }
        setSimpleMessage("\(getUserDisplayName(user: user, viewState: viewState)) changed the group description.")
    }
    
    private func configureChannelIconChanged(content: ChannelIconChangedSystemContent, viewState: ViewState, message: Message) {
        guard let user = viewState.users[content.by] else { return }
        setSimpleMessage("\(getUserDisplayName(user: user, viewState: viewState)) changed the group icon.")
    }
    
    private func configureChannelOwnershipChanged(content: ChannelOwnershipChangedSystemContent, viewState: ViewState, message: Message) {
        guard let fromUser = viewState.users[content.from],
              let toUser = viewState.users[content.to] else { return }
        setSimpleMessage("\(getUserDisplayName(user: fromUser, viewState: viewState)) gave \(getUserDisplayName(user: toUser, viewState: viewState)) group ownership")
    }
    
    private func configureMessagePinned(content: MessagePinnedSystemContent, isPinned: Bool) {
        let action = isPinned ? "pinned" : "unpinned"
        setSimpleMessage("Message \(action) by \(content.by_username)")
    }
    
    private func configureTextSystemMessage(content: TextSystemMessageContent) {
        setSimpleMessage(content.content)
    }
    
    private func setSimpleMessage(_ text: String) {
        messageLabel.attributedText = createAttributedText(text)
    }
    
    private func getUserDisplayName(user: User, viewState: ViewState) -> String {
        return user.display_name ?? user.username
    }
    

    
    private func createAttributedText(_ text: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        
        // Set default attributes for centered system message
        attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 13, weight: .medium), range: NSRange(location: 0, length: text.count))
        attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: NSRange(location: 0, length: text.count))
        
        // Find and bold usernames for better readability
        do {
            // Simple pattern to match any word that could be a username (not common words)
            let commonWords = ["was", "added", "by", "the", "to", "a", "an", "and", "or", "but", "joined", "left", "kicked", "banned", "removed", "changed", "renamed", "gave", "ownership", "group", "channel", "description", "icon", "message", "pinned", "unpinned"]
            
            let words = text.components(separatedBy: " ")
            for word in words {
                let cleanWord = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
                if !commonWords.contains(cleanWord.lowercased()) && cleanWord.count > 1 {
                    let wordRange = (text as NSString).range(of: word)
                    if wordRange.location != NSNotFound {
                        attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 13, weight: .semibold), range: wordRange)
                        attributedString.addAttribute(.foregroundColor, value: UIColor.label.withAlphaComponent(0.8), range: wordRange)
                    }
                }
            }
        }
        
        return attributedString
    }
} 
