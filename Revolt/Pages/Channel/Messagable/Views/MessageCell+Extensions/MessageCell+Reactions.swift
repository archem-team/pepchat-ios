//
//  MessageCell+Reactions.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

extension MessageCell {
    // MARK: - Reactions Management
    
    internal func updateReactions(for message: Message, viewState: ViewState) {
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
}
