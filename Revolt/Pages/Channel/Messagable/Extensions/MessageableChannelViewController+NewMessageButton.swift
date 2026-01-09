//
//  MessageableChannelViewController+NewMessageButton.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//

import UIKit

// MARK: - New Message Button
extension MessageableChannelViewController {
    
    func setupNewMessageButton() {
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
        newMessageButton.addTarget(self, action: #selector(newMessageButtonTapped), for: .touchUpInside)
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
            imageView.leadingAnchor.constraint(equalTo: newMessageButton.leadingAnchor, constant: 10),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16)
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
            newMessageButton.bottomAnchor.constraint(equalTo: messageInputView.topAnchor, constant: -16),
            newMessageButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    @objc private func newMessageButtonTapped() {
        // Function to scroll to new message and hide the button
        scrollToBottom(animated: true)
        
        // Hide the button with animation
        UIView.animate(withDuration: 0.3) {
            self.newMessageButton.alpha = 0
        } completion: { _ in
            self.newMessageButton.isHidden = true
            self.hasUnreadMessages = false
        }
    }
    
    func showNewMessageButton() {
        // If the button is already displayed, do nothing
        if !newMessageButton.isHidden && newMessageButton.alpha > 0 {
            return
        }
        
        // Show button with animation
        newMessageButton.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.newMessageButton.alpha = 1
        }
        
        hasUnreadMessages = true
        
        // If no click on the button for a few seconds, automatically hide it
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.hasUnreadMessages {
                UIView.animate(withDuration: 0.3) {
                    self.newMessageButton.alpha = 0
                } completion: { _ in
                    self.newMessageButton.isHidden = true
                    self.hasUnreadMessages = false
                }
            }
        }
    }
}
