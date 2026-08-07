//
//  MessageCell+Attachments.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

struct ImageAttachmentPreviewLayout {
    static let singleMaxWidth: CGFloat = 280
    static let singleMaxHeight: CGFloat = 320
    static let galleryMaxTileWidth: CGFloat = 150
    static let gallerySpacing: CGFloat = 8

    static func singleSize(sourceSize: CGSize?, availableWidth: CGFloat) -> CGSize {
        let maxWidth = max(1, min(availableWidth, singleMaxWidth))
        let fallback = CGSize(width: maxWidth, height: maxWidth * 0.75)

        guard let sourceSize,
              sourceSize.width > 0,
              sourceSize.height > 0 else {
            return fallback
        }

        let scale = min(maxWidth / sourceSize.width, singleMaxHeight / sourceSize.height)
        return CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )
    }

    static func galleryTileSize(availableWidth: CGFloat) -> CGSize {
        let width = max(
            1,
            min((availableWidth - gallerySpacing) / 2, galleryMaxTileWidth)
        )
        return CGSize(width: width, height: width)
    }

    static func galleryHeight(imageCount: Int, tileHeight: CGFloat) -> CGFloat {
        guard imageCount > 0 else { return 0 }
        let rowCount = (imageCount + 1) / 2
        return CGFloat(rowCount) * tileHeight
            + CGFloat(max(0, rowCount - 1)) * gallerySpacing
    }

    static func galleryFrame(index: Int, imageCount: Int, tileSize: CGSize) -> CGRect {
        guard index >= 0, index < imageCount else { return .zero }

        if imageCount == 3 {
            switch index {
            case 0:
                return CGRect(
                    x: 0,
                    y: 0,
                    width: tileSize.width,
                    height: tileSize.height * 2 + gallerySpacing
                )
            case 1:
                return CGRect(
                    x: tileSize.width + gallerySpacing,
                    y: 0,
                    width: tileSize.width,
                    height: tileSize.height
                )
            default:
                return CGRect(
                    x: tileSize.width + gallerySpacing,
                    y: tileSize.height + gallerySpacing,
                    width: tileSize.width,
                    height: tileSize.height
                )
            }
        }

        let column = index % 2
        let row = index / 2
        return CGRect(
            x: CGFloat(column) * (tileSize.width + gallerySpacing),
            y: CGFloat(row) * (tileSize.height + gallerySpacing),
            width: tileSize.width,
            height: tileSize.height
        )
    }
}

extension MessageCell {
    internal func loadImageAttachments(attachments: [Types.File], viewState: ViewState) {
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
        NSLayoutConstraint.deactivate(imageAttachmentsContainer!.constraints)
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
        // Calculate available width based on actual layout constraints
        // Account for: avatar leading (16) + avatar width (40) + avatar spacing (10) + content trailing margin (16)
        let totalMargins: CGFloat = 16 + 40 + 10 + 16 // Total: 82px
        let measuredWidth = window?.bounds.width ?? UIScreen.main.bounds.width
        let availableWidth = measuredWidth - totalMargins
        
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
        
        let isGallery = attachments.count > 1
        let galleryTileSize = ImageAttachmentPreviewLayout.galleryTileSize(availableWidth: availableWidth)
        let singleSourceSize = attachments.first.flatMap {
            imageSourceSize(for: $0, viewState: viewState)
        }
        let singlePreviewSize = ImageAttachmentPreviewLayout.singleSize(
            sourceSize: singleSourceSize,
            availableWidth: availableWidth
        )
        let initialContainerHeight = isGallery
            ? ImageAttachmentPreviewLayout.galleryHeight(
                imageCount: attachments.count,
                tileHeight: galleryTileSize.height
            )
            : singlePreviewSize.height
        let containerHeightConstraint = imageAttachmentsContainer!.heightAnchor.constraint(
            equalToConstant: initialContainerHeight
        )
        containerHeightConstraint.priority = UILayoutPriority.defaultHigh
        containerHeightConstraint.isActive = true
        
        for (index, attachment) in attachments.enumerated() {
            let attachmentId = attachment.id
            // Create image view for this attachment
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 8
            imageView.backgroundColor = UIColor.gray.withAlphaComponent(0.1)
            imageView.isUserInteractionEnabled = true
            imageView.tag = index // Store index for tap handling
            imageView.accessibilityIdentifier = attachmentId
            
            // Add tap gesture recognizer for fullscreen view
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleImageCellTap(_:)))
            imageView.addGestureRecognizer(tapGesture)
            
            imageAttachmentsContainer!.addSubview(imageView)
            imageAttachmentViews.append(imageView)
            
            let previewFrame = isGallery
                ? ImageAttachmentPreviewLayout.galleryFrame(
                    index: index,
                    imageCount: attachments.count,
                    tileSize: galleryTileSize
                )
                : CGRect(origin: .zero, size: singlePreviewSize)
            let remainingWidth = availableWidth - previewFrame.minX
            let actualImageWidth = min(previewFrame.width, remainingWidth)
            
            // Create width constraint with lower priority to prevent conflicts
            let widthConstraint = imageView.widthAnchor.constraint(equalToConstant: actualImageWidth)
            widthConstraint.priority = UILayoutPriority(999) // High but not required
            let imageHeightConstraint = imageView.heightAnchor.constraint(
                equalToConstant: previewFrame.height
            )
            
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: imageAttachmentsContainer!.leadingAnchor, constant: previewFrame.minX),
                imageView.topAnchor.constraint(equalTo: imageAttachmentsContainer!.topAnchor, constant: previewFrame.minY),
                widthConstraint,
                imageHeightConstraint,
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
                    imageView.backgroundColor = .clear
                    imageView.contentMode = isGallery ? .scaleAspectFill : .scaleAspectFit
                    
                    // Add loading overlay to show upload progress
                    addLoadingOverlayToImageView(imageView, attachmentId: attachmentId, queuedMessage: queuedMessage)
                } else {
                    imageView.image = UIImage(systemName: "photo")
                }
                
            } else {
                // For real messages, load from server using Kingfisher
                if let url = URL(string: viewState.formatUrl(fromId: attachmentId, withTag: "attachments")) {
                    let downsampleSize = previewFrame.size
                    imageView.kf.setImage(
                        with: url,
                        placeholder: UIImage(systemName: "photo"),
                        options: [
                            .processor(DownsamplingImageProcessor(size: downsampleSize)),
                            .scaleFactor(UIScreen.main.scale),
                            .transition(.fade(0.3)),
                            .cacheOriginalImage,
                            .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))
                        ],
                        completionHandler: { [weak self] result in
                            switch result {
                            case .success(let value):
                                // Ensure cell hasn't been reused for a different message
                                if let currentAttachments = self?.currentMessage?.attachments,
                                   currentAttachments.contains(where: { $0.id == attachmentId }) {
                                    imageView.backgroundColor = .clear
                                    imageView.contentMode = isGallery ? .scaleAspectFill : .scaleAspectFit

                                    if !isGallery, singleSourceSize == nil {
                                        let fittedSize = ImageAttachmentPreviewLayout.singleSize(
                                            sourceSize: value.image.size,
                                            availableWidth: availableWidth
                                        )
                                        widthConstraint.constant = fittedSize.width
                                        imageHeightConstraint.constant = fittedSize.height
                                        containerHeightConstraint.constant = fittedSize.height
                                    }

                                    // Force layout update to ensure proper positioning
                                    self?.contentView.setNeedsLayout()
                                    self?.contentView.layoutIfNeeded()

                                    // Invalidate cached height — async image may have changed cell height
                                    if let messageId = self?.currentMessage?.id {
                                        self?.onAsyncContentLoaded?(messageId)
                                    }
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
            
        }
    }

    private func imageSourceSize(for attachment: Types.File, viewState: ViewState) -> CGSize? {
        if case .image(let metadata) = attachment.metadata,
           metadata.width > 0,
           metadata.height > 0 {
            return CGSize(width: CGFloat(metadata.width), height: CGFloat(metadata.height))
        }

        guard isPendingMessage,
              let currentMessage,
              let channelQueuedMessages = viewState.queuedMessages[currentMessage.channel],
              let queuedMessage = channelQueuedMessages.first(where: { $0.nonce == currentMessage.id }),
              let localImageData = queuedMessage.attachmentData.first(where: {
                  $0.1.contains(attachment.id.replacingOccurrences(of: "\(queuedMessage.nonce)_", with: ""))
              })?.0,
              let image = UIImage(data: localImageData) else {
            return nil
        }

        return image.size
    }
    
    internal func loadFileAttachments(attachments: [Types.File], viewState: ViewState) {
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
    
    internal func loadEmbeds(embeds: [Embed], viewState: ViewState) {
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
        // Link preview overlap fix: clip embed stack (docs/Fix/LinkPreviewImage.md)
        embedContainer.clipsToBounds = true

        // Add each embed
        for embed in embeds {
            let linkPreview = LinkPreviewView()
            linkPreview.translatesAutoresizingMaskIntoConstraints = false
            let callbackMessageId = currentMessage?.id
            let asyncCallback = onAsyncContentLoaded
            linkPreview.onAsyncLayoutAffectingContentLoaded = { [weak self] in
                guard let messageId = callbackMessageId else { return }
                if let asyncCallback {
                    asyncCallback(messageId)
                } else if let vc = self?.findParentViewController() as? MessageableChannelViewController {
                    vc.invalidateHeightForMessage(messageId)
                }
            }
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
            // Link preview overlap fix: layout now + draw embed behind header/text (docs/Fix/LinkPreviewImage.md)
            contentView.setNeedsLayout()
            contentView.layoutIfNeeded()
            embedContainer.layer.zPosition = -1
        }
    }
    
    // MARK: - File Attachments Support
    
    internal func isImageFile(_ file: Types.File) -> Bool {
        return file.content_type.hasPrefix("image/")
    }
    
    internal func isAudioFile(_ file: Types.File) -> Bool {
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
    
}
