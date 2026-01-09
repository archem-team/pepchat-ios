//
//  ToastView.swift
//  Revolt
//

import UIKit

class ToastView {
    private let containerView = UIView()
    private let messageLabel = UILabel()
    
    init(message: String) {
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        containerView.layer.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        messageLabel.text = message
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(messageLabel)
        
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
    }
    
    func show(duration: TimeInterval = 2.0) {
        guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return
        }
        
        keyWindow.addSubview(containerView)
        
        // Position at top center
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: keyWindow.safeAreaLayoutGuide.topAnchor, constant: 20),
            containerView.centerXAnchor.constraint(equalTo: keyWindow.centerXAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: keyWindow.widthAnchor, constant: -40)
        ])
        
        // Start with alpha 0
        containerView.alpha = 0.0
        
        // Animate in
        UIView.animate(withDuration: 0.3) {
            self.containerView.alpha = 1.0
        }
        
        // Auto dismiss after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(withDuration: 0.3, animations: {
                self.containerView.alpha = 0.0
            }) { _ in
                self.containerView.removeFromSuperview()
            }
        }
    }
    
    static func show(message: String, duration: TimeInterval = 2.0) {
        let toast = ToastView(message: message)
        toast.show(duration: duration)
    }
} 