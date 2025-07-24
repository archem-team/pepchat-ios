//
//  TypingIndicatorManager.swift
//  Revolt
//
//

import UIKit
import Types

class TypingIndicatorManager {
    weak var viewController: MessageableChannelViewController?
    private let viewModel: MessageableChannelViewModel
    
    // Properties needed for typing indicator
    private var typingIndicatorView: TypingIndicatorView?
    private var currentlyTypingUsers: [(Types.User, Types.Member?)] = []
    
    init(viewModel: MessageableChannelViewModel, viewController: MessageableChannelViewController) {
        self.viewModel = viewModel
        self.viewController = viewController
        setupTypingIndicator()
        setupObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupTypingIndicator() {
        guard let viewController = viewController else { return }
        
        let typingIndicator = TypingIndicatorView()
        typingIndicator.translatesAutoresizingMaskIntoConstraints = false
        typingIndicator.isHidden = true
        viewController.view.addSubview(typingIndicator)
        
        NSLayoutConstraint.activate([
            typingIndicator.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            typingIndicator.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            typingIndicator.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor),
            typingIndicator.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        self.typingIndicatorView = typingIndicator
    }
    
    private func setupObservers() {
        // Setup observer for typing status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(typingStatusDidChange),
            name: NSNotification.Name("TypingStatusDidChange"),
            object: nil
        )
    }
    
    // MARK: - Typing Status Handling
    
    @objc private func typingStatusDidChange(notification: Notification) {
        if let users = notification.object as? [(Types.User, Types.Member?)] {
            updateTypingIndicator(users: users)
        }
    }
    
    private func updateTypingIndicator(users: [(Types.User, Types.Member?)]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentlyTypingUsers = users
            
            if users.isEmpty {
                self.typingIndicatorView?.isHidden = true
            } else {
                self.typingIndicatorView?.isHidden = false
                self.typingIndicatorView?.updateText(self.formatTypingIndicatorText(withUsers: users))
            }
        }
    }
    
    private func formatTypingIndicatorText(withUsers users: [(Types.User, Types.Member?)]) -> String {
        let usernames = users.map { (user, member) in
            return member?.nickname ?? user.display_name ?? user.username
        }
        
        if usernames.count == 1 {
            return "\(usernames[0]) is typing..."
        } else if usernames.count == 2 {
            return "\(usernames[0]) and \(usernames[1]) are typing..."
        } else {
            return "\(usernames.count) people are typing..."
        }
    }
    
    // MARK: - Public Methods
    
    func hideTypingIndicator() {
        typingIndicatorView?.isHidden = true
        currentlyTypingUsers.removeAll()
    }
    
    func showTypingIndicator(for users: [(Types.User, Types.Member?)]) {
        updateTypingIndicator(users: users)
    }
    
    var isVisible: Bool {
        return !(typingIndicatorView?.isHidden ?? true)
    }
    
    var typingUsers: [(Types.User, Types.Member?)] {
        return currentlyTypingUsers
    }
}

