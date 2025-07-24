//
//  MessageTableViewDataSource.swift
//  Revolt
//
//

import UIKit
import Types

// Add the data source class
class MessageTableViewDataSource: NSObject, UITableViewDataSource {
    private weak var viewModel: MessageableChannelViewModel?
    private weak var viewController: MessageableChannelViewController?
    
    init(viewModel: MessageableChannelViewModel, viewController: MessageableChannelViewController) {
        self.viewModel = viewModel
        self.viewController = viewController
        super.init()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = viewModel?.messages.count ?? 0
        print("📊 DATA SOURCE: Returning \(count) rows")
        return count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel,
              indexPath.row < viewModel.messages.count else {
            print("⚠️ Invalid index path: \(indexPath.row), messages count: \(viewModel?.messages.count ?? 0)")
            return UITableViewCell()
        }
        
        let messageId = viewModel.messages[indexPath.row]
        //print("📱 Configuring cell at row \(indexPath.row) with message ID: \(messageId)")
        
        if let message = viewModel.viewState.messages[messageId] {
            
            // Check if this is a system message
            if message.system != nil {
                guard let systemCell = tableView.dequeueReusableCell(withIdentifier: "SystemMessageCell", for: indexPath) as? SystemMessageCell else {
                    print("⚠️ Failed to dequeue SystemMessageCell")
                    return UITableViewCell()
                }
                
                systemCell.configure(with: message, viewState: viewModel.viewState)
                return systemCell
                
            } else {
                // Regular message - use MessageCell
                guard let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as? MessageCell else {
                    print("⚠️ Failed to dequeue MessageCell")
                    return UITableViewCell()
                }
                
                // Try to get author, or create a placeholder if not found
                let author: User
                if let foundAuthor = viewModel.viewState.users[message.author] {
                    author = foundAuthor
                } else {
                    print("⚠️ Could not find author for messageId: \(messageId), creating placeholder")
                    // Create a placeholder user to prevent black messages
                    author = User(
                        id: message.author,
                        username: "Unknown User",
                        discriminator: "0000",
                        avatar: nil,
                        relationship: .None
                    )
                }
                
                let member = viewModel.getMember(message: message).wrappedValue
                let isContinuation = viewController?.shouldGroupWithPreviousMessage(at: indexPath) ?? false
                
                cell.configure(with: message, 
                             author: author, 
                             member: member, 
                             viewState: viewModel.viewState, 
                             isContinuation: isContinuation)
                
                cell.onMessageAction = { [weak viewController] action, message in
                    viewController?.handleMessageAction(action, message: message)
                }
                
                cell.onImageTapped = { [weak viewController] image in
                    viewController?.showFullScreenImage(image)
                }
                
                if let viewController = viewController {
                    cell.textViewContent.delegate = viewController
                }
                
                return cell
            }
        } else {
            print("⚠️ Could not find message for messageId: \(messageId)")
            return UITableViewCell()
        }
    }
}

// Add a local messages data source subclass
class LocalMessagesDataSource: NSObject, UITableViewDataSource {
    private var localMessages: [String] = []
    private var viewModelRef: MessageableChannelViewModel
    private var viewControllerRef: MessageableChannelViewController
    
    init(viewModel: MessageableChannelViewModel, viewController: MessageableChannelViewController, localMessages: [String]) {
        self.localMessages = localMessages
        self.viewModelRef = viewModel
        self.viewControllerRef = viewController
        super.init()
    }
    
    // Method to update localMessages array
    func updateMessages(_ messages: [String]) {
        self.localMessages = messages
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = localMessages.count
        print("📊 LOCAL DATA SOURCE: Returning \(count) rows")
        
        // Update empty state visibility
        viewControllerRef.updateEmptyStateVisibility()
        
        return count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.row < localMessages.count else {
            print("⚠️ Invalid index path: \(indexPath.row), messages count: \(localMessages.count)")
            return UITableViewCell()
        }
        
        let messageId = localMessages[indexPath.row]
        //print("📱 Configuring cell at row \(indexPath.row) with message ID: \(messageId)")
        
        if let message = viewModelRef.viewState.messages[messageId] {
            
            // Check if this is a system message
            if message.system != nil {
                guard let systemCell = tableView.dequeueReusableCell(withIdentifier: "SystemMessageCell", for: indexPath) as? SystemMessageCell else {
                    print("⚠️ Failed to dequeue SystemMessageCell")
                    return UITableViewCell()
                }
                
                systemCell.configure(with: message, viewState: viewModelRef.viewState)
                return systemCell
                
            } else {
                // Regular message - use MessageCell
                guard let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as? MessageCell else {
                    print("⚠️ Failed to dequeue MessageCell")
                    return UITableViewCell()
                }
                
                // Try to get author, or create a placeholder if not found
                let author: User
                if let foundAuthor = viewModelRef.viewState.users[message.author] {
                    author = foundAuthor
                } else {
                    print("⚠️ Could not find author for messageId: \(messageId), creating placeholder")
                    // Create a placeholder user to prevent black messages
                    author = User(
                        id: message.author,
                        username: "Unknown User",
                        discriminator: "0000",
                        avatar: nil,
                        relationship: .None
                    )
                }
                
                let member = viewModelRef.getMember(message: message).wrappedValue
                let isContinuation = viewControllerRef.shouldGroupWithPreviousMessage(at: indexPath)
                
                cell.configure(with: message, 
                             author: author, 
                             member: member, 
                             viewState: viewModelRef.viewState, 
                             isContinuation: isContinuation)
                
                // Check if this is a pending message and set the state
                let channelQueuedMessages = viewModelRef.viewState.queuedMessages[message.channel] ?? []
                let isPending = channelQueuedMessages.contains { $0.nonce == message.id }
                cell.isPendingMessage = isPending
                
                cell.onMessageAction = { [weak viewController = viewControllerRef] action, message in
                    viewController?.handleMessageAction(action, message: message)
                }
                
                cell.onImageTapped = { [weak self] image in
                    self?.viewControllerRef.showFullScreenImage(image)
                }
                
                // Present user sheet on avatar tap
                cell.onAvatarTap = { [weak viewController = viewControllerRef] in
                    guard let viewController = viewController else { return }
                    // Use the SwiftUI UserSheet instead of UIKit version
                    viewController.viewModel.viewState.openUserSheet(user: author, member: member)
                }
                
                // Present user sheet on username tap
                cell.onUsernameTap = { [weak viewController = viewControllerRef] in
                    guard let viewController = viewController else { return }
                    // Use the SwiftUI UserSheet instead of UIKit version
                    viewController.viewModel.viewState.openUserSheet(user: author, member: member)
                }
                
                cell.textViewContent.delegate = viewControllerRef
                return cell
            }
        } else {
            print("⚠️ Could not find message for messageId: \(messageId)")
            return UITableViewCell()
        }
    }
}

