//
//  PermissionsManager.swift
//  Revolt
//


import UIKit
import Types

@MainActor
class PermissionsManager {
    weak var viewController: MessageableChannelViewController?
    private let viewModel: MessageableChannelViewModel
    
    // Property to hold no permission view
    private var noPermissionView: UIView?
    
    init(viewModel: MessageableChannelViewModel, viewController: MessageableChannelViewController) {
        self.viewModel = viewModel
        self.viewController = viewController
    }
    
    // MARK: - Permission Checks
    
    var sendMessagePermission: Bool {
        let viewState = viewModel.viewState
        guard let currentUser = viewState.currentUser else {
            return false
        }
        
        if case .dm_channel(let channel) = viewModel.channel {
            if let otherUser = channel.recipients.filter({ $0 != currentUser.id }).first {
                let relationship = viewState.users.first(where: { $0.value.id == otherUser })?.value.relationship
                return relationship != .Blocked && relationship != .BlockedOther
            }
        } else {
            let member = viewModel.server.flatMap {
                viewState.members[$0.id]?[currentUser.id]
            }
            
            let permissions = resolveChannelPermissions(
                from: currentUser,
                targettingUser: currentUser,
                targettingMember: member,
                channel: viewModel.channel,
                server: viewModel.server
            )
            
            return permissions.contains(Types.Permissions.sendMessages)
        }
        
        return true
    }
    
    func userHasPermission(_ permission: Types.Permissions) -> Bool {
        let viewState = viewModel.viewState
        guard let currentUser = viewState.currentUser else {
            return false
        }
        
        let member = viewModel.server.flatMap {
            viewState.members[$0.id]?[currentUser.id]
        }
        
        let permissions = resolveChannelPermissions(
            from: currentUser,
            targettingUser: currentUser,
            targettingMember: member,
            channel: viewModel.channel,
            server: viewModel.server
        )
        
        return permissions.contains(permission)
    }
    
    func userHasPermissions(_ permissions: Types.Permissions) -> Bool {
        let viewState = viewModel.viewState
        guard let currentUser = viewState.currentUser else {
            return false
        }
        
        let member = viewModel.server.flatMap {
            viewState.members[$0.id]?[currentUser.id]
        }
        
        let userPermissions = resolveChannelPermissions(
            from: currentUser,
            targettingUser: currentUser,
            targettingMember: member,
            channel: viewModel.channel,
            server: viewModel.server
        )
        
        return userPermissions.isSuperset(of: permissions)
    }
    
    // MARK: - UI Configuration
    
    func configureUIBasedOnPermissions() {
        guard let viewController = viewController else { return }
        
        // Handle message input visibility
        if sendMessagePermission {
            viewController.messageInputView.isHidden = false
            noPermissionView?.removeFromSuperview()
            noPermissionView = nil
        } else {
            viewController.messageInputView.isHidden = true
            createAndShowNoPermissionView()
        }
        
        // Configure file upload button in message input view
        viewController.messageInputView.uploadButtonEnabled = userHasPermission(Types.Permissions.uploadFiles)
        
        // Configure reaction button in message cells
        let canReact = userHasPermission(Types.Permissions.react)
        viewController.tableView.visibleCells.forEach { cell in
            if let messageCell = cell as? MessageCell {
                messageCell.reactionsEnabled = canReact
            }
        }
        
        // If this is a group DM, configure add members button visibility
        if viewModel.channel.isGroupDmChannel {
            let canInvite = userHasPermission(Types.Permissions.inviteOthers)
            // Future: addMembersButton.isHidden = !canInvite
        }
    }
    
    func createAndShowNoPermissionView() {
        guard let viewController = viewController else { return }
        
        // Remove any existing no permission view
        noPermissionView?.removeFromSuperview()
        
        // Create no permission view
        let containerView = UIView()
        containerView.backgroundColor = UIColor(named: "bgGray12")
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor(named: "borderGray11")?.cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add info icon
        let iconView = UIImageView(image: UIImage(named: "peptideInfo"))
        iconView.tintColor = UIColor(named: "iconGray04")
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add message label
        let label = UILabel()
        let isDm = viewModel.channel.isDM
        label.text = isDm ? 
            "You don't have permission to send message in this DM." :
            "You don't have permission to send messages in this channel."
        label.textColor = UIColor(named: "textGray07")
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        containerView.addSubview(iconView)
        containerView.addSubview(label)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12)
        ])
        
        // Add to main view
        viewController.view.addSubview(containerView)
        
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor, constant: -20)
        ])
        
        // Save reference
        noPermissionView = containerView
    }
}

