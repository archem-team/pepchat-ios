//
//  MessageInputHandler.swift
//  Revolt
//
import UIKit
import Types
import SwiftUI
import PhotosUI
import Network

class InternetMonitor: ObservableObject {
    static let shared = InternetMonitor()

    @Published private(set) var isConnected: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "InternetMonitor")

    private init() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isConnected = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}

@MainActor
class MessageInputHandler: NSObject, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
    weak var viewController: MessageableChannelViewController?
    private let viewModel: MessageableChannelViewModel
    private let repliesManager: RepliesManager
    
    init(viewModel: MessageableChannelViewModel, viewController: MessageableChannelViewController, repliesManager: RepliesManager) {
        self.viewModel = viewModel
        self.viewController = viewController
        self.repliesManager = repliesManager
        super.init()
    }
    
    func queueMessage(_ convertedText: String) {
        guard let currentUser = viewModel.viewState.currentUser else { return }

        let messageNonce = UUID().uuidString

        let queued = QueuedMessage(
            nonce: messageNonce,
            replies: [],
            content: convertedText,
            author: currentUser.id,
            channel: viewModel.channel.id,
            timestamp: Date(),
            hasAttachments: false
        )

        // Add to ViewState storage
        viewModel.viewState.queuedMessages[viewModel.channel.id, default: []].append(queued)

        // Also show in UI as pending message
        viewModel.viewState.channelMessages[viewModel.channel.id, default: []].append(messageNonce)
        viewModel.viewState.messages[messageNonce] = queued.toTemporaryMessage()
    }
    
    // MARK: - Message Sending
    
    func sendMessage(_ text: String) {
        guard let viewController = viewController else { return }
        
        // Convert mentions from display format (@username) to server format (<@USER_ID>)
        let convertedText = viewController.messageInputView.convertTextForSending()
        
        print("📝 MESSAGE_INPUT_HANDLER: User sent message: \"\(text)\"")
        print("📝 MESSAGE_INPUT_HANDLER: Converted message: \"\(convertedText)\"")
        
        if InternetMonitor.shared.isConnected {
            print("Internet Monitor: ❤️ ❤️ ❤️ ❤️ ❤️ Internet is available")
        } else {
            print("Internet Monitor: 😭 😭 😭 😭 😭 Internet not available")
            queueMessage(convertedText)
            print("Message sent to Queue: ✅ ✅ ✅ ✅ ✅")
            viewController.showErrorAlert(message: "You're offline. Will send when internet comes back.")
            print("Alert Sent to user: ⚠️ ⚠️ ⚠️ ⚠️ ⚠️")
            return
        }
        let socketConnnected = (viewModel.viewState.ws?.currentState == .connected)
        
        if !socketConnnected {
            print("Web Socket: 😭 😭 😭 😭 😭 Websocket is not connected")
        } else {
            print("Web Socket: ❤️ ❤️ ❤️ ❤️ ❤️ Websocket is connected")
        }
        // Create a queued message immediately for local display (no attachments)
        if let currentUser = viewModel.viewState.currentUser {
            let messageNonce = UUID().uuidString
            let apiReplies = repliesManager.getCurrentReplies().map { Revolt.ApiReply(id: $0.message.id, mention: $0.mention) }
            
            let queuedMessage = QueuedMessage(
                nonce: messageNonce,
                replies: apiReplies,
                content: convertedText,
                author: currentUser.id,
                channel: viewModel.channel.id,
                timestamp: Date(),
                hasAttachments: false
            )
            
            // Add to ViewState's queued messages for this channel
            if viewModel.viewState.queuedMessages[viewModel.channel.id] == nil {
                viewModel.viewState.queuedMessages[viewModel.channel.id] = []
            }
            viewModel.viewState.queuedMessages[viewModel.channel.id]?.append(queuedMessage)
            print("📝 MESSAGE_INPUT_HANDLER: Added to queued messages for channel \(viewModel.channel.id)")
            
            // Also add the temporary message ID to the channel messages list for immediate display
            if viewModel.viewState.channelMessages[viewModel.channel.id] == nil {
                viewModel.viewState.channelMessages[viewModel.channel.id] = []
            }
            viewModel.viewState.channelMessages[viewModel.channel.id]?.append(messageNonce)
            
            // Store the temporary message in the messages dictionary for rendering
            viewModel.viewState.messages[messageNonce] = queuedMessage.toTemporaryMessage()
            
            print("📝 MESSAGE_INPUT_HANDLER: Sending with \(apiReplies.count) replies")
            
            // Hide new message button when sending message
            if viewController.hasUnreadMessages {
                UIView.animate(withDuration: 0.3) {
                    viewController.newMessageButton.alpha = 0
                } completion: { _ in
                    viewController.newMessageButton.isHidden = true
                    viewController.hasUnreadMessages = false
                }
            }
            
            // IMPROVED: Handle new message sent with better keyboard coordination
            print("📝 MESSAGE_INPUT_HANDLER: Calling handleNewMessageSent()")
            viewController.handleNewMessageSent()
            
            // Reset lastManualScrollUpTime since user is sending a message and expects to see it
            viewController.lastManualScrollUpTime = nil
            
            // Note: scrollToBottom is now handled by handleNewMessageSent() method
            // which properly coordinates with keyboard state
            
            // Add notification for debugging - post MessagesDidChange notification without an object
            print("📝 MESSAGE_INPUT_HANDLER: Posting MessagesDidChange notification")
            // Only post notification if we actually have messages
            if !viewModel.messages.isEmpty {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NewMessagesReceived"),
                    object: ["channelId": viewModel.channel.id, "messageCount": viewModel.messages.count]
                )
            } else {
                print("📝 MESSAGE_INPUT_HANDLER: Skipping notification post because no messages exist")
            }
            
            // Send message to server with replies
            Task {
                print("📝 MESSAGE_INPUT_HANDLER: Starting async task to send message to server")
                do {
                    let result = try await viewModel.viewState.http.sendMessage(
                        channel: viewModel.channel.id,
                        replies: apiReplies,
                        content: convertedText,
                        attachments: [],
                        nonce: messageNonce
                    ).get()
                    print("📝 MESSAGE_INPUT_HANDLER: Successfully sent message to server: \(result)")
                    
                    // Clear mention data after successful send
                    DispatchQueue.main.async {
                        viewController.messageInputView.clearMentionData()
                    }
                    
                    // Post notification again after successful API response
                    DispatchQueue.main.async {
                        print("📝 MESSAGE_INPUT_HANDLER: Posting MessagesDidChange notification after API success")
                        NotificationCenter.default.post(name: NSNotification.Name("MessagesDidChange"), object: nil)
                        // Note: No additional scroll here - handleNewMessageSent() already handled it
                    }
                } catch {
                    print("❌ MESSAGE_INPUT_HANDLER: Error sending message: \(error)")
                    DispatchQueue.main.async {
                        // Use viewController's showError method instead
                        viewController.showErrorAlert(message: "Failed to send message: \(error.localizedDescription)")
                    }
                }
            }
            
            // Clear replies after sending
            repliesManager.clearReplies()
        } else {
            print("⚠️ MESSAGE_INPUT_HANDLER: currentUser is nil, can't send message")
        }
    }
    
    func sendMessageWithAttachments(_ text: String, attachments: [(Data, String)]) {
        guard let viewController = viewController else { return }
        
        // Convert mentions from display format (@username) to server format (<@USER_ID>)
        let convertedText = viewController.messageInputView.convertTextForSending()
        
        print("📝 MESSAGE_INPUT_HANDLER: User sent message with attachments: \"\(text)\", attachments count: \(attachments.count)")
        print("📝 MESSAGE_INPUT_HANDLER: Converted message: \"\(convertedText)\"")
        
        // For messages with attachments, show optimistic update with upload progress
        if let currentUser = viewModel.viewState.currentUser {
            let messageNonce = UUID().uuidString
            let apiReplies = repliesManager.getCurrentReplies().map { Revolt.ApiReply(id: $0.message.id, mention: $0.mention) }
            
            let queuedMessage = QueuedMessage(
                nonce: messageNonce,
                replies: apiReplies,
                content: convertedText,
                author: currentUser.id,
                channel: viewModel.channel.id,
                timestamp: Date(),
                hasAttachments: true,
                attachmentData: attachments
            )
            
            // Add to ViewState's queued messages for tracking
            if viewModel.viewState.queuedMessages[viewModel.channel.id] == nil {
                viewModel.viewState.queuedMessages[viewModel.channel.id] = []
            }
            viewModel.viewState.queuedMessages[viewModel.channel.id]?.append(queuedMessage)
            print("📝 MESSAGE_INPUT_HANDLER: Added attachment message with upload tracking")
            
            // NOW show in UI with upload progress
            if viewModel.viewState.channelMessages[viewModel.channel.id] == nil {
                viewModel.viewState.channelMessages[viewModel.channel.id] = []
            }
            viewModel.viewState.channelMessages[viewModel.channel.id]?.append(messageNonce)
            
            // Store the temporary message in the messages dictionary for rendering
            viewModel.viewState.messages[messageNonce] = queuedMessage.toTemporaryMessage()
            
            print("📝 MESSAGE_INPUT_HANDLER: Sending with \(apiReplies.count) replies")
            
            // Hide new message button when sending message
            if viewController.hasUnreadMessages {
                UIView.animate(withDuration: 0.3) {
                    viewController.newMessageButton.alpha = 0
                } completion: { _ in
                    viewController.newMessageButton.isHidden = true
                    viewController.hasUnreadMessages = false
                }
            }
            
            // IMPROVED: Handle new message sent with better keyboard coordination
            print("📝 MESSAGE_INPUT_HANDLER: Calling handleNewMessageSent()")
            viewController.handleNewMessageSent()
            
            // Reset lastManualScrollUpTime since user is sending a message and expects to see it
            viewController.lastManualScrollUpTime = nil
            
            // Note: scrollToBottom is now handled by handleNewMessageSent() method
            // which properly coordinates with keyboard state
            
            // Send message to server with attachments
            Task {
                print("📝 MESSAGE_INPUT_HANDLER: Starting async task to send message with attachments to server")
                do {
                    let result = try await viewModel.viewState.http.sendMessage(
                        channel: viewModel.channel.id,
                        replies: apiReplies,
                        content: convertedText,
                        attachments: attachments,
                        nonce: messageNonce,
                        progressCallback: { [weak self] filename, progress in
                            self?.updateUploadProgress(nonce: messageNonce, filename: filename, progress: progress)
                        }
                    ).get()
                    print("📝 MESSAGE_INPUT_HANDLER: Successfully sent message with attachments to server: \(result)")
                    
                    // Clear mention data after successful send
                    DispatchQueue.main.async {
                        viewController.messageInputView.clearMentionData()
                    }
                    
                    // Post notification again after successful API response
                    DispatchQueue.main.async {
                        print("📝 MESSAGE_INPUT_HANDLER: Posting MessagesDidChange notification after API success")
                        NotificationCenter.default.post(name: NSNotification.Name("MessagesDidChange"), object: nil)
                        // Note: No additional scroll here - handleNewMessageSent() already handled it
                        
                        // Clear attachments after successful upload
                        print("📝 MESSAGE_INPUT_HANDLER: viewController is \(viewController == nil ? "nil" : "not nil")")
                        
                        if let messageInputView = viewController.messageInputView {
                            print("📝 MESSAGE_INPUT_HANDLER: messageInputView found, calling onAttachmentsUploadComplete")
                            messageInputView.onAttachmentsUploadComplete()
                        } else {
                            print("❌ MESSAGE_INPUT_HANDLER: messageInputView is nil!")
                        }
                        
                        print("📝 MESSAGE_INPUT_HANDLER: Upload complete handler finished")
                    }
                } catch {
                    print("❌ MESSAGE_INPUT_HANDLER: Error sending message with attachments: \(error)")
                    DispatchQueue.main.async {
                        viewController.showErrorAlert(message: "Failed to send message: \(error.localizedDescription)")
                        
                        // Clear attachments even on failure
                        print("📝 MESSAGE_INPUT_HANDLER: viewController is \(viewController == nil ? "nil" : "not nil")")
                        
                        if let messageInputView = viewController.messageInputView {
                            print("📝 MESSAGE_INPUT_HANDLER: messageInputView found on error, calling onAttachmentsUploadComplete")
                            messageInputView.onAttachmentsUploadComplete()
                        } else {
                            print("❌ MESSAGE_INPUT_HANDLER: messageInputView is nil on error!")
                        }
                        
                        print("📝 MESSAGE_INPUT_HANDLER: Error handler finished")
                    }
                }
            }
            
            // Clear replies after sending
            repliesManager.clearReplies()
        } else {
            print("⚠️ MESSAGE_INPUT_HANDLER: currentUser is nil, can't send message")
        }
    }
    
    // MARK: - Message Editing
    
    func editMessage(_ message: Types.Message, newText: String) {
        guard let viewController = viewController else { return }
        
        print("📝 MESSAGE_INPUT_HANDLER: Editing message with ID: \(message.id), new text: \(newText)")
        
        // Only proceed if content has actually changed
        if message.content == newText {
            print("⚠️ MESSAGE_INPUT_HANDLER: Message content hasn't changed, no need to update")
            return
        }
        
        // Start a Task to edit the message
        Task {
            do {
                // Call the API to edit the message
                let _ = try await viewModel.viewState.http.editMessage(
                    channel: viewModel.channel.id,
                    message: message.id,
                    edits: Revolt.MessageEdit(content: newText)
                ).get()
                
                print("✅ MESSAGE_INPUT_HANDLER: Successfully edited message")
                
                // Update the local copy of the message with the new content
                await MainActor.run {
                    if var updatedMessage = viewModel.viewState.messages[message.id] {
                        updatedMessage.content = newText
                        viewModel.viewState.messages[message.id] = updatedMessage
                        
                        // Reload the table view to show the updated message
                        viewController.tableView.reloadData()
                    }
                }
            } catch {
                print("❌ MESSAGE_INPUT_HANDLER: Failed to edit message: \(error)")
                // Show an error alert or notification to the user
                DispatchQueue.main.async {
                    viewController.showErrorAlert(message: "Failed to edit message: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Reply Handling
    
    func replyToMessage(_ message: Types.Message, withText text: String) {
        print("📝 MESSAGE_INPUT_HANDLER: Replying to message with ID: \(message.id), text: \(text)")
        
        // The reply should already be set in the RepliesManager when this method is called
        // Just send the message - the sendMessage method will handle the replies
        sendMessage(text)
    }
    
    // MARK: - Attachment Handling
    
    func handleAttachmentTap() {
        guard let viewController = viewController else { return }
        
        // Present AttachmentsSheet using SwiftUI
        let attachmentsSheet = AttachmentsSheet(isPresented: .constant(true)) { [weak self] attachmentType in
            // Dismiss the sheet first, then handle the selection after a short delay
            viewController.dismiss(animated: true) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.handleAttachmentSelection(attachmentType)
                }
            }
        }
        
        let hostingController = UIHostingController(rootView: attachmentsSheet)
        hostingController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = hostingController.sheetPresentationController {
                sheet.prefersGrabberVisible = true
                sheet.detents = [.custom { _ in 120 }]
                sheet.preferredCornerRadius = 16
            }
        }
        
        viewController.present(hostingController, animated: true)
    }
    
    private func handleAttachmentSelection(_ attachmentType: Attachments) {
        guard let viewController = viewController else { return }
        
        switch attachmentType {
        case .gallery:
            presentPhotoPicker()
        case .camera:
            presentImagePicker(sourceType: .camera)
        case .file:
            presentDocumentPicker()
        }
    }
    
    private func presentImagePicker(sourceType: UIImagePickerController.SourceType) {
        guard let viewController = viewController else { return }
        
        // Check if the source type is available
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            let alertTitle = sourceType == .camera ? "Camera Not Available" : "Photo Library Not Available"
            let alertMessage = sourceType == .camera ? "Camera is not available on this device." : "Photo library is not available on this device."
            
            let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
            return
        }
        
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = sourceType
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        imagePicker.mediaTypes = ["public.image", "public.movie"]
        
        // CRITICAL FIX: Always use overCurrentContext to prevent navigation interference
        imagePicker.modalPresentationStyle = .overCurrentContext
        imagePicker.modalTransitionStyle = .coverVertical
        
        // For camera, we need to ensure it covers full screen
        if sourceType == .camera {
            imagePicker.modalPresentationStyle = .overFullScreen
        }
        
        // CRITICAL: Find the root window to present from to avoid navigation stack issues
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            // Find the top-most view controller
            var topController = window.rootViewController
            while let presentedController = topController?.presentedViewController {
                topController = presentedController
            }
            
            // Present from the top-most controller
            topController?.present(imagePicker, animated: true)
        } else {
            // Fallback to normal presentation
            viewController.present(imagePicker, animated: true)
        }
    }
    
    private func presentDocumentPicker() {
        guard let viewController = viewController else { return }
        
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .item, // All file types
            .data,
            .content,
            .text,
            .pdf,
            .rtf,
            .spreadsheet,
            .presentation,
            .archive,
            .audio,
            .movie,
            .image
        ])
        
        documentPicker.delegate = self // Set delegate to self instead of viewController
        documentPicker.allowsMultipleSelection = false
        documentPicker.modalPresentationStyle = .pageSheet
        
        viewController.present(documentPicker, animated: true)
    }
    
    // New: Use PHPickerViewController for multi-media selection from gallery
    private func presentPhotoPicker() {
        guard let viewController = viewController else { return }
        var config = PHPickerConfiguration()
        config.selectionLimit = 10 // You can adjust the max number of images/videos
        config.filter = .any(of: [.images, .videos]) // Allow both images and videos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        viewController.present(picker, animated: true)
    }
    
    // MARK: - UIDocumentPickerDelegate Implementation
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true)
        
        guard let fileURL = urls.first else { return }
        
        // Start accessing the security-scoped resource
        guard fileURL.startAccessingSecurityScopedResource() else {
            viewController?.showErrorAlert(message: "Unable to access the selected file.")
            return
        }
        
        defer {
            fileURL.stopAccessingSecurityScopedResource()
        }
        
        do {
            // Read the file data
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            
            // Add document to pending attachments instead of sending immediately
            if let messageInputView = viewController?.messageInputView {
                let success = messageInputView.addDocument(data: fileData, fileName: fileName)
                if !success {
                    // Show error if couldn't add (file too large or too many attachments)
                    DispatchQueue.main.async { [weak self] in
                        let manager = messageInputView.pendingAttachmentsManager
                        if !manager.canAddMoreAttachments() {
                            self?.viewController?.showErrorAlert(message: "Maximum number of attachments reached.")
                        } else {
                            self?.viewController?.showErrorAlert(message: "File size exceeds the maximum limit of \(manager.getMaxFileSizeString()).")
                        }
                    }
                }
            }
        } catch {
            print("❌ Error reading file: \(error)")
            viewController?.showErrorAlert(message: "Failed to read the selected file: \(error.localizedDescription)")
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }
    
    // MARK: - UIImagePickerControllerDelegate Implementation
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        // CRITICAL FIX: Store the media first, then dismiss to prevent navigation issues
        var capturedImage: UIImage? = nil
        var capturedVideoURL: URL? = nil
        
        // Check if it's an image
        if let image = info[.originalImage] as? UIImage {
            capturedImage = image
        }
        // Check if it's a video
        else if let videoURL = info[.mediaURL] as? URL {
            capturedVideoURL = videoURL
        }
        
        // Dismiss picker immediately without animation to prevent navigation corruption
        picker.dismiss(animated: false) { [weak self] in
            // Process the media after dismissal is complete
            if let image = capturedImage {
                // Handle image
                DispatchQueue.main.async {
                    if let messageInputView = self?.viewController?.messageInputView {
                        let success = messageInputView.addImage(image)
                        if !success {
                            // Show error if couldn't add (file too large or too many attachments)
                            let manager = messageInputView.pendingAttachmentsManager
                            if !manager.canAddMoreAttachments() {
                                self?.viewController?.showErrorAlert(message: "Maximum number of attachments reached.")
                            } else {
                                self?.viewController?.showErrorAlert(message: "File size exceeds the maximum limit of \(manager.getMaxFileSizeString()).")
                            }
                        }
                    }
                }
            } else if let videoURL = capturedVideoURL {
                // Handle video
                DispatchQueue.main.async {
                    do {
                        let videoData = try Data(contentsOf: videoURL)
                        let fileName = videoURL.lastPathComponent
                        
                        if let messageInputView = self?.viewController?.messageInputView {
                            let success = messageInputView.addVideo(data: videoData, fileName: fileName)
                            if !success {
                                // Show error if couldn't add (file too large or too many attachments)
                                let manager = messageInputView.pendingAttachmentsManager
                                if !manager.canAddMoreAttachments() {
                                    self?.viewController?.showErrorAlert(message: "Maximum number of attachments reached.")
                                } else {
                                    self?.viewController?.showErrorAlert(message: "File size exceeds the maximum limit of \(manager.getMaxFileSizeString()).")
                                }
                            }
                        }
                    } catch {
                        print("❌ Error reading video file: \(error)")
                        self?.viewController?.showErrorAlert(message: "Failed to read the selected video: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        // CRITICAL FIX: Dismiss without animation to prevent navigation stack corruption
        picker.dismiss(animated: false, completion: nil)
    }
    
    // MARK: - PHPickerViewControllerDelegate Implementation
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let viewController = viewController else { return }
        guard let messageInputView = viewController.messageInputView else { return }
        
        for result in results {
            // Check if it's an image
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async {
                            let success = messageInputView.addImage(image)
                            if !success {
                                // Show error if couldn't add (file too large or too many attachments)
                                let manager = messageInputView.pendingAttachmentsManager
                                if !manager.canAddMoreAttachments() {
                                    viewController.showErrorAlert(message: "Maximum number of attachments reached.")
                                } else {
                                    viewController.showErrorAlert(message: "File size exceeds the maximum limit of \(manager.getMaxFileSizeString()).")
                                }
                            }
                        }
                    }
                }
            }
            // Check if it's a video
            else if result.itemProvider.hasItemConformingToTypeIdentifier("public.movie") {
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                    if let videoURL = url, error == nil {
                        do {
                            let videoData = try Data(contentsOf: videoURL)
                            let fileName = videoURL.lastPathComponent
                            
                            DispatchQueue.main.async {
                                let success = messageInputView.addVideo(data: videoData, fileName: fileName)
                                if !success {
                                    // Show error if couldn't add (file too large or too many attachments)
                                    let manager = messageInputView.pendingAttachmentsManager
                                    if !manager.canAddMoreAttachments() {
                                        viewController.showErrorAlert(message: "Maximum number of attachments reached.")
                                    } else {
                                        viewController.showErrorAlert(message: "File size exceeds the maximum limit of \(manager.getMaxFileSizeString()).")
                                    }
                                }
                            }
                        } catch {
                            DispatchQueue.main.async {
                                print("❌ Error reading video file from picker: \(error)")
                                viewController.showErrorAlert(message: "Failed to read the selected video: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Error Handling
    
    func showError(_ message: String) {
        DispatchQueue.main.async {
            // Use viewController's showError method instead
            self.viewController?.showErrorAlert(message: message)
        }
    }
}

// MARK: - MessageInputViewDelegate Implementation
extension MessageInputHandler: MessageInputViewDelegate {
    func messageInputView(_ inputView: MessageInputView, didSendMessage text: String) {
        sendMessage(text)
    }
    
    func messageInputView(_ inputView: MessageInputView, didSendMessageWithAttachments text: String, attachments: [(Data, String)]) {
        sendMessageWithAttachments(text, attachments: attachments)
    }
    
    func messageInputView(_ inputView: MessageInputView, didEditMessage message: Types.Message, newText: String) {
        editMessage(message, newText: newText)
    }
    
    func messageInputView(_ inputView: MessageInputView, didReplyToMessage message: Types.Message, withText text: String) {
        replyToMessage(message, withText: text)
    }
    
    func messageInputViewDidTapAttach(_ inputView: MessageInputView) {
        handleAttachmentTap()
    }
    
    func showFullScreenImage(_ image: UIImage) {
        // Delegate to view controller
        // viewController?.showFullScreenImage(image)
        print("📝 MESSAGE_INPUT_HANDLER: showFullScreenImage called")
    }
    
    func dismissFullscreenImage(_ gesture: UITapGestureRecognizer) {
        // Delegate to view controller
        print("📝 MESSAGE_INPUT_HANDLER: dismissFullscreenImage called")
    }
    
    func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        // Delegate to view controller
        print("📝 MESSAGE_INPUT_HANDLER: handlePinch called")
    }
    
    // Update upload progress for a specific file
    private func updateUploadProgress(nonce: String, filename: String, progress: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let channelId = self.viewModel.channel.id
            guard let queuedMessages = self.viewModel.viewState.queuedMessages[channelId],
                  let queuedMessage = queuedMessages.first(where: { $0.nonce == nonce }) else {
                return
            }
            
            // Update progress directly on the observable object
            queuedMessage.uploadProgress[filename] = progress
            
            print("📤 UPLOAD_PROGRESS: \(filename) = \(Int(progress * 100))%")
            
            // Update the temporary message in messages dictionary to trigger UI refresh
            self.viewModel.viewState.messages[nonce] = queuedMessage.toTemporaryMessage()
            
            // Post notification to refresh UI
            NotificationCenter.default.post(name: NSNotification.Name("MessagesDidChange"), object: nil)
        }
    }
}

