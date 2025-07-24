//
//  AttachmentPreviewView.swift
//  Revolt
//
//  Created by Assistant on 1/15/2025.
//

import UIKit
import Foundation

// MARK: - AttachmentPreviewView
class AttachmentPreviewView: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    
    var onRemoveAttachment: ((String) -> Void)?
    // Add property to track upload state
    private var uploadingAttachmentIds: Set<String> = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = UIColor(named: "bgGray13") ?? .systemBackground
        
        // Setup scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        
        // Setup stack view
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        scrollView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            // Scroll view constraints
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            
            // Stack view constraints
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
    
    func updateAttachments(_ attachments: [PendingAttachment]) {
        // Clear existing views
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add new attachment previews
        for attachment in attachments {
            let previewView = createAttachmentPreview(for: attachment)
            stackView.addArrangedSubview(previewView)
        }
        
        // Update visibility
        isHidden = attachments.isEmpty
    }
    
    private func createAttachmentPreview(for attachment: PendingAttachment) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // For images, use clear background so image is visible, for files use gray background
        if attachment.type == PendingAttachment.AttachmentType.image {
            containerView.backgroundColor = UIColor.clear
        } else {
            containerView.backgroundColor = UIColor(named: "bgGray11") ?? .systemGray6
        }
        
        containerView.layer.cornerRadius = 8
        containerView.clipsToBounds = true
        containerView.tag = attachment.id.hashValue // Store ID in tag for later identification
        
        // Image view
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.image = attachment.image
        
        // Debug: Check if image is nil or empty
        if attachment.image.size.width == 0 || attachment.image.size.height == 0 {
            print("🔴 DEBUG: attachment.image is empty for type: \(attachment.type), fileName: \(attachment.fileName)")
            // Set a placeholder for debugging
            imageView.backgroundColor = .red
        }
        
        containerView.addSubview(imageView)
        
        // For images, bring imageView to front to ensure it's visible above any other views
        if attachment.type == PendingAttachment.AttachmentType.image {
            containerView.bringSubviewToFront(imageView)
        }
        
        // Loading overlay - initially hidden
        let loadingOverlay = UIView()
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        loadingOverlay.isHidden = true
        loadingOverlay.tag = 100 // Tag to identify loading overlay
        containerView.addSubview(loadingOverlay)
        
        // Circular progress container
        let progressContainer = UIView()
        progressContainer.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        progressContainer.layer.cornerRadius = 18
        loadingOverlay.addSubview(progressContainer)
        
        // Progress circle background
        let circleBackgroundLayer = CAShapeLayer()
        let center = CGPoint(x: 18, y: 18)
        let radius: CGFloat = 14
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -CGFloat.pi / 2, endAngle: CGFloat.pi * 1.5, clockwise: true)
        
        circleBackgroundLayer.path = path.cgPath
        circleBackgroundLayer.fillColor = UIColor.clear.cgColor
        circleBackgroundLayer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
        circleBackgroundLayer.lineWidth = 3
        progressContainer.layer.addSublayer(circleBackgroundLayer)
        
        // Progress circle
        let progressLayer = CAShapeLayer()
        progressLayer.path = path.cgPath
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.cgColor
        progressLayer.lineWidth = 3
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        progressLayer.name = "progressLayer" // Use name property instead of accessibilityIdentifier
        progressContainer.layer.addSublayer(progressLayer)
        
        // Animate progress indefinitely
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 2.0
        animation.repeatCount = .infinity
        progressLayer.add(animation, forKey: "progressAnimation")
        
        // Upload icon in center
        let uploadIcon = UIImageView()
        uploadIcon.translatesAutoresizingMaskIntoConstraints = false
        uploadIcon.image = UIImage(systemName: "arrow.up")
        uploadIcon.tintColor = .white
        uploadIcon.contentMode = .scaleAspectFit
        progressContainer.addSubview(uploadIcon)
        
        // Remove button
        let removeButton = UIButton(type: .custom)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = .white
        removeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        removeButton.layer.cornerRadius = 12
        removeButton.clipsToBounds = true
        
        // Store attachment ID in button tag for removal
        removeButton.accessibilityIdentifier = attachment.id
        removeButton.addTarget(self, action: #selector(removeButtonTapped(_:)), for: .touchUpInside)
        
        containerView.addSubview(removeButton)
        
        // File type indicator for non-images
        if attachment.type != PendingAttachment.AttachmentType.image {
            let typeLabel = UILabel()
            typeLabel.translatesAutoresizingMaskIntoConstraints = false
            typeLabel.text = getFileTypeText(for: attachment)
            typeLabel.textColor = .white
            typeLabel.font = UIFont.boldSystemFont(ofSize: 10)
            typeLabel.textAlignment = .center
            typeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            typeLabel.layer.cornerRadius = 4
            typeLabel.clipsToBounds = true
            containerView.addSubview(typeLabel)
            
            NSLayoutConstraint.activate([
                typeLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
                typeLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
                typeLabel.heightAnchor.constraint(equalToConstant: 16),
                typeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30)
            ])
        }
        
        NSLayoutConstraint.activate([
            // Container size
            containerView.widthAnchor.constraint(equalToConstant: 60),
            containerView.heightAnchor.constraint(equalToConstant: 60),
            
            // Image view fills container
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            // Loading overlay fills container
            loadingOverlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            // Progress container centered
            progressContainer.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            progressContainer.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
            progressContainer.widthAnchor.constraint(equalToConstant: 36),
            progressContainer.heightAnchor.constraint(equalToConstant: 36),
            
            // Upload icon centered in progress container
            uploadIcon.centerXAnchor.constraint(equalTo: progressContainer.centerXAnchor),
            uploadIcon.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            uploadIcon.widthAnchor.constraint(equalToConstant: 16),
            uploadIcon.heightAnchor.constraint(equalToConstant: 16),
            
            // Remove button in top-right corner (adjusted spacing)
            removeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        // Check if this attachment is currently uploading
        if uploadingAttachmentIds.contains(attachment.id) {
            showUploadingState(for: containerView)
        }
        
        return containerView
    }
    
    private func getFileTypeText(for attachment: PendingAttachment) -> String {
        switch attachment.type {
        case PendingAttachment.AttachmentType.image:
            return "IMG"
        case PendingAttachment.AttachmentType.video:
            return "VID"
        case PendingAttachment.AttachmentType.document:
            let fileExtension = (attachment.fileName as NSString).pathExtension.uppercased()
            return fileExtension.isEmpty ? "FILE" : fileExtension
        }
    }
    
    @objc private func removeButtonTapped(_ sender: UIButton) {
        guard let attachmentId = sender.accessibilityIdentifier else { return }
        onRemoveAttachment?(attachmentId)
    }
    
    // MARK: - Upload State Management
    
    func setUploadingState(for attachmentIds: [String]) {
        print("🔴 setUploadingState called with \(attachmentIds.count) IDs: \(attachmentIds)")
        uploadingAttachmentIds = Set(attachmentIds)
        updateUploadingStates()
    }
    
    func clearUploadingState() {
        print("🔴 clearUploadingState called - current uploading IDs: \(uploadingAttachmentIds)")
        
        // First update the UI to hide loading states BEFORE clearing attachments
        updateUploadingStates()
        
        // Then clear the uploading IDs
        uploadingAttachmentIds.removeAll()
        
        print("🔴 clearUploadingState completed - uploading IDs should be empty: \(uploadingAttachmentIds)")
    }
    
    // New method: Clear all loading overlays directly
    func hideAllLoadingOverlays() {
        print("🔴 hideAllLoadingOverlays called - hiding all loading states")
        
        // Go through all arranged subviews and hide their loading overlays
        for view in stackView.arrangedSubviews {
            if let loadingOverlay = view.viewWithTag(100) {
                print("🔴 Hiding loading overlay for view")
                loadingOverlay.isHidden = true
            }
            
            // Re-enable all buttons
            view.subviews.forEach { subview in
                if let button = subview as? UIButton {
                    button.isEnabled = true
                    button.alpha = 1.0
                }
            }
        }
        
        // Clear the uploading IDs
        uploadingAttachmentIds.removeAll()
        
        print("🔴 hideAllLoadingOverlays completed")
    }
    
    private func updateUploadingStates() {
        print("🔴 updateUploadingStates called - uploading IDs: \(uploadingAttachmentIds)")
        print("🔴 Stack view has \(stackView.arrangedSubviews.count) arranged subviews")
        
        for view in stackView.arrangedSubviews {
            guard let attachmentId = findAttachmentId(for: view) else {
                print("🔴 Could not find attachment ID for view")
                continue
            }
            
            print("🔴 Processing attachment ID: \(attachmentId)")
            
            if uploadingAttachmentIds.contains(attachmentId) {
                print("🔴 Showing upload state for ID: \(attachmentId)")
                showUploadingState(for: view)
            } else {
                print("🔴 Hiding upload state for ID: \(attachmentId)")
                hideUploadingState(for: view)
            }
        }
    }
    
    private func showUploadingState(for containerView: UIView) {
        // Show loading overlay
        if let loadingOverlay = containerView.viewWithTag(100) {
            loadingOverlay.isHidden = false
            
            // Progress animation is already set up in createAttachmentPreview
        }
        
        // Disable remove button during upload
        containerView.subviews.forEach { subview in
            if let button = subview as? UIButton {
                button.isEnabled = false
                button.alpha = 0.5
            }
        }
    }
    
    private func hideUploadingState(for containerView: UIView) {
        // Hide loading overlay
        if let loadingOverlay = containerView.viewWithTag(100) {
            loadingOverlay.isHidden = true
        }
        
        // Re-enable remove button
        containerView.subviews.forEach { subview in
            if let button = subview as? UIButton {
                button.isEnabled = true
                button.alpha = 1.0
            }
        }
    }
    
    private func findAttachmentId(for view: UIView) -> String? {
        // Try to find attachment ID from remove button's accessibilityIdentifier
        for subview in view.subviews {
            if let button = subview as? UIButton,
               let attachmentId = button.accessibilityIdentifier,
               !attachmentId.isEmpty {
                return attachmentId
            }
        }
        return nil
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 76) // 60 + 16 padding
    }
}
