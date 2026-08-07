//
//  MessageInputView.swift
//  Revolt
//

import UIKit
import Types
import Combine

struct MentionReplacement {
    let text: String
    let replacedRange: NSRange
    let insertedRange: NSRange
    let selectedRange: NSRange
}

enum MentionInputUtilities {
    static func isValid(range: NSRange, inUTF16Length length: Int) -> Bool {
        range.location != NSNotFound
            && range.location <= length
            && range.length <= length - range.location
    }

    static func activeMentionRange(in text: String, selectedRange: NSRange) -> NSRange? {
        let nsText = text as NSString
        guard selectedRange.length == 0,
              isValid(range: selectedRange, inUTF16Length: nsText.length) else {
            return nil
        }

        let prefixRange = NSRange(location: 0, length: selectedRange.location)
        let atRange = nsText.range(of: "@", options: .backwards, range: prefixRange)
        guard atRange.location != NSNotFound else { return nil }

        let mentionRange = NSRange(
            location: atRange.location,
            length: selectedRange.location - atRange.location
        )
        let candidate = nsText.substring(with: mentionRange)
        guard !candidate.contains(where: { $0.isWhitespace }) else { return nil }
        return mentionRange
    }

    static func searchText(in text: String, selectedRange: NSRange) -> String? {
        guard let range = activeMentionRange(in: text, selectedRange: selectedRange) else {
            return nil
        }
        let nsText = text as NSString
        return nsText.substring(with: NSRange(
            location: range.location + 1,
            length: max(0, range.length - 1)
        ))
    }

    static func replacingActiveMention(
        in text: String,
        selectedRange: NSRange,
        with replacement: String
    ) -> MentionReplacement? {
        guard let activeRange = activeMentionRange(in: text, selectedRange: selectedRange) else {
            return nil
        }

        let nsText = text as NSString
        var replacedRange = activeRange
        if replacement.last?.isWhitespace == true,
           NSMaxRange(replacedRange) < nsText.length,
           nsText.character(at: NSMaxRange(replacedRange)) == 32 {
            replacedRange.length += 1
        }

        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: replacedRange, with: replacement)
        let insertedRange = NSRange(
            location: replacedRange.location,
            length: (replacement as NSString).length
        )
        return MentionReplacement(
            text: mutable as String,
            replacedRange: replacedRange,
            insertedRange: insertedRange,
            selectedRange: NSRange(location: NSMaxRange(insertedRange), length: 0)
        )
    }

    static func shouldIncludeEveryone(searchText: String, canMentionEveryone: Bool) -> Bool {
        canMentionEveryone
            && (searchText.isEmpty || "everyone".hasPrefix(searchText.lowercased()))
    }

    @MainActor
    static func canMentionEveryone(
        in channel: Channel?,
        server: Server?,
        viewState: ViewState?
    ) -> Bool {
        guard let channel else { return false }

        switch channel {
        case .group_dm_channel:
            return true
        case .text_channel:
            guard let server,
                  let viewState,
                  let currentUser = viewState.currentUser else {
                return false
            }
            let member = viewState.members[server.id]?[currentUser.id]
            let permissions = resolveChannelPermissions(
                from: currentUser,
                targettingUser: currentUser,
                targettingMember: member,
                channel: channel,
                server: server
            )
            return permissions.contains(.mentionEveryone)
        default:
            return false
        }
    }

    static func requiresPlainTextEveryoneConfirmation(
        text: String,
        canMentionEveryone: Bool
    ) -> Bool {
        !canMentionEveryone && !everyoneMentionRanges(in: text).isEmpty
    }

    /// Finds literal mass mentions while excluding escaped text and inline/fenced code.
    static func everyoneMentionRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        let mention = "@everyone" as NSString
        var ranges: [NSRange] = []
        var codeDelimiterLength: Int?
        var index = 0

        while index < nsText.length {
            let character = nsText.character(at: index)

            if character == 92 { // Backslash escapes the next UTF-16 code unit.
                index += min(2, nsText.length - index)
                continue
            }

            if character == 96 { // Backtick.
                var delimiterLength = 1
                while index + delimiterLength < nsText.length,
                      nsText.character(at: index + delimiterLength) == 96 {
                    delimiterLength += 1
                }

                let normalizedLength = min(delimiterLength, 3)
                if let activeLength = codeDelimiterLength {
                    if normalizedLength == activeLength {
                        codeDelimiterLength = nil
                    }
                } else {
                    codeDelimiterLength = normalizedLength
                }
                index += delimiterLength
                continue
            }

            if codeDelimiterLength == nil,
               index + mention.length <= nsText.length,
               nsText.substring(with: NSRange(location: index, length: mention.length)) == mention as String {
                ranges.append(NSRange(location: index, length: mention.length))
                index += mention.length
                continue
            }

            index += 1
        }

        return ranges
    }
}

// MARK: - MentionData structure for storing mention information
public struct MentionData {
    let userId: String
    let username: String
    let displayText: String
}

// MARK: - Associated Objects Keys for mention functionality
private struct MentionKeys {
    static var mentionView = "mentionView"
    static var mentionDataList = "mentionDataList"
}

// MARK: - PendingAttachment Model
public struct PendingAttachment {
    public let id: String
    public let image: UIImage
    public let data: Data
    public let fileName: String
    public let type: AttachmentType
    
    public enum AttachmentType {
        case image
        case video
        case document
    }
    
    public init(image: UIImage, fileName: String? = nil) {
        self.id = UUID().uuidString
        self.image = image
        self.data = image.jpegData(compressionQuality: 0.7) ?? Data()
        self.fileName = fileName ?? "\(UUID().uuidString).jpg"
        self.type = .image
    }
    
    public init(data: Data, fileName: String, type: AttachmentType) {
        self.id = UUID().uuidString
        self.image = UIImage(data: data) ?? UIImage()
        self.data = data
        self.fileName = fileName
        self.type = type
    }
}

// MARK: - PendingAttachmentsManager (Inline)
@MainActor
class PendingAttachmentsManager: ObservableObject {
    @Published var pendingAttachments: [PendingAttachment] = []
    
    // Maximum number of attachments allowed
    private let maxAttachments = 10
    
    // Maximum file size (8MB)
    private let maxFileSize = 8 * 1024 * 1024
    
    var hasPendingAttachments: Bool {
        return !pendingAttachments.isEmpty
    }
    
    var attachmentCount: Int {
        return pendingAttachments.count
    }
    
    // MARK: - Add Attachments
    
    func addImage(_ image: UIImage, fileName: String? = nil) -> Bool {
        guard pendingAttachments.count < maxAttachments else {
            return false
        }
        
        let attachment = PendingAttachment(image: image, fileName: fileName)
        
        // Check file size
        guard attachment.data.count <= maxFileSize else {
            return false
        }
        
        pendingAttachments.append(attachment)
        return true
    }
    
    func addDocument(data: Data, fileName: String) -> Bool {
        guard pendingAttachments.count < maxAttachments else {
            return false
        }
        
        // Check file size
        guard data.count <= maxFileSize else {
            return false
        }
        
        let attachment = PendingAttachment(data: data, fileName: fileName, type: .document)
        pendingAttachments.append(attachment)
        return true
    }
    
    func addVideo(data: Data, fileName: String) -> Bool {
        guard pendingAttachments.count < maxAttachments else {
            return false
        }
        
        // Check file size
        guard data.count <= maxFileSize else {
            return false
        }
        
        let attachment = PendingAttachment(data: data, fileName: fileName, type: .video)
        pendingAttachments.append(attachment)
        return true
    }
    
    // MARK: - Remove Attachments
    
    func removeAttachment(withId id: String) {
        pendingAttachments.removeAll { $0.id == id }
    }
    
    func removeAttachment(at index: Int) {
        guard index >= 0 && index < pendingAttachments.count else { return }
        pendingAttachments.remove(at: index)
    }
    
    func clearAllAttachments() {
        pendingAttachments.removeAll()
    }
    
    // MARK: - Get Attachments for Sending
    
    func getAttachmentsForSending() -> [(Data, String)] {
        return pendingAttachments.map { ($0.data, $0.fileName) }
    }
    
    // MARK: - Validation
    
    func canAddMoreAttachments() -> Bool {
        return pendingAttachments.count < maxAttachments
    }
    
    func validateFileSize(_ data: Data) -> Bool {
        return data.count <= maxFileSize
    }
    
    func getMaxFileSizeString() -> String {
        return "8MB"
    }
}

// MARK: - MessageInputViewDelegate Protocol
protocol MessageInputViewDelegate: AnyObject {
    func messageInputView(_ inputView: MessageInputView, didSendMessage text: String)
    func messageInputView(_ inputView: MessageInputView, didSendMessageWithAttachments text: String, attachments: [(Data, String)])
    func messageInputView(_ inputView: MessageInputView, didEditMessage message: Types.Message, newText: String)
    func messageInputView(_ inputView: MessageInputView, didReplyToMessage message: Types.Message, withText text: String)
    func messageInputViewDidTapAttach(_ inputView: MessageInputView)
    func showFullScreenImage(_ image: UIImage)
    func dismissFullscreenImage(_ gesture: UITapGestureRecognizer)
    func handlePinch(_ gesture: UIPinchGestureRecognizer)
}

// MARK: - MessageInputView Class
class MessageInputView: UIView {
    private struct MentionToken {
        let userId: String
        let displayText: String
        var range: NSRange
    }

    // Making textView internal instead of private so extensions can access it
    let textView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    
    // Add properties for message editing
    private var editingMessage: Types.Message?
    private let editingIndicator = UIView()
    private let editingLabel = UILabel()
    private let cancelEditButton = UIButton(type: .system)
    
    // Add properties for message reply
    private var replyingToMessage: Types.Message?
    private let replyIndicator = UIView()
    private let replyLabel = UILabel()
    private let cancelReplyButton = UIButton(type: .system)
    
    // Add properties for attachment preview
    private let attachmentPreviewView = AttachmentPreviewView()
    let pendingAttachmentsManager = PendingAttachmentsManager()
    private var isSendingAttachments = false
    
    weak var delegate: MessageInputViewDelegate?
    
    // MARK: - Mention functionality properties
    private var mentionInputView: MentionInputView?
    private var currentChannel: Channel?
    private var currentServer: Server?
    private var currentViewState: ViewState?
    private var mentionTokens: [MentionToken] = []
    private let mentionTextColor = UIColor.systemYellow
    private var isApplyingMentionStyle = false
    private(set) var isProgrammaticallySettingText = false
    
    private var normalTextViewTopConstraint: NSLayoutConstraint!
    private var editingTextViewTopConstraint: NSLayoutConstraint!
    private var replyTextViewTopConstraint: NSLayoutConstraint!
    private var attachmentTextViewTopConstraint: NSLayoutConstraint!
    private var textViewHeightConstraint: NSLayoutConstraint!
    
    private let maxHeight: CGFloat = 200
    private let minHeight: CGFloat = 40
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupAttachmentPreview()
    }
    
    convenience init(channel: Types.Channel, server: Types.Server?, viewState: ViewState) {
        self.init(frame: .zero)
        // You can use these parameters to configure the view if needed
        // This is the initializer that's being used in MessageableChannelViewController
        setupAttachmentPreview()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Methods
    
    // Setup mention functionality
    func setupMentionFunctionality(viewState: ViewState, channel: Channel, server: Server?) {
        currentViewState = viewState
        currentChannel = channel
        currentServer = server

        mentionInputView?.cleanup()
        
        // Create mention input view
        mentionInputView = MentionInputView(viewState: viewState)
        mentionInputView?.configure(channel: channel, server: server)
        mentionInputView?.delegate = self
        
        // print("DEBUG: Mention functionality setup complete for channel: \(channel.id)")
    }
    
    // Check for mention in text
    func checkForMention(in text: String) {
        if let searchText = MentionInputUtilities.searchText(
            in: text,
            selectedRange: textView.selectedRange
        ) {
            mentionInputView?.updateSearch(text: searchText)
        } else {
            hideMentionView()
        }
    }
    
    // Hide mention view
    func hideMentionView() {
        // print("DEBUG: hideMentionView called")
        mentionInputView?.dismissSearch()
    }

    func hideMentionViewImmediately() {
        mentionInputView?.dismissSearch(animated: false)
    }

    func refreshMentionStylingAfterTextChange() {
        let text = textView.text ?? ""
        let nsText = text as NSString

        mentionTokens = mentionTokens.filter { token in
            guard MentionInputUtilities.isValid(
                range: token.range,
                inUTF16Length: nsText.length
            ) else { return false }
            return nsText.substring(with: token.range) == token.displayText
        }
        removeMentionDataNotPresent(in: text)

        applyMentionStyling()
    }

    private func applyMentionStyling() {
        guard !isApplyingMentionStyle else { return }
        isApplyingMentionStyle = true
        defer { isApplyingMentionStyle = false }

        let raw = textView.text ?? ""
        let selected = textView.selectedRange
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: textView.font ?? UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor(named: "textDefaultGray01") ?? UIColor.label
        ]

        let attributed = NSMutableAttributedString(string: raw, attributes: baseAttrs)
        for token in mentionTokens {
            guard MentionInputUtilities.isValid(
                range: token.range,
                inUTF16Length: (raw as NSString).length
            ) else { continue }
            attributed.addAttribute(.foregroundColor, value: mentionTextColor, range: token.range)
        }
        for range in MentionInputUtilities.everyoneMentionRanges(in: raw) {
            attributed.addAttribute(.foregroundColor, value: mentionTextColor, range: range)
        }

        textView.attributedText = attributed
        textView.selectedRange = selected
        textView.typingAttributes = baseAttrs
    }

    private func adjustMentionTokens(for replacement: MentionReplacement) {
        let replacedEnd = NSMaxRange(replacement.replacedRange)
        let delta = replacement.insertedRange.length - replacement.replacedRange.length

        mentionTokens = mentionTokens.compactMap { token in
            if token.range.location >= replacedEnd {
                var shifted = token
                shifted.range.location += delta
                return shifted
            }

            if NSIntersectionRange(token.range, replacement.replacedRange).length > 0 {
                return nil
            }

            return token
        }
    }
    
    // MARK: - Cleanup Methods
    
    // CRITICAL FIX: Cleanup method to clear strong references and prevent memory leaks
    func cleanup() {
        // print("DEBUG: MessageInputView cleanup called")
        
        NotificationCenter.default.removeObserver(self, name: UITextView.textDidChangeNotification, object: nil)
        
        // Hide and cleanup mention view
        mentionInputView?.hidePopup(animated: false)
        mentionInputView?.cleanup()
        mentionInputView = nil
        
        // Clear strong references to prevent memory leaks
        currentViewState = nil
        currentChannel = nil
        currentServer = nil
        
        // Clear delegate to break any potential retain cycles
        delegate = nil
        
        // Clear mention data
        clearMentionData()
        mentionTokens.removeAll()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UITextView.textDidChangeNotification, object: nil)
    }
    
    // Set text in the input field
    func setText(_ text: String?) {
        // UITextView does not reliably update contentSize when isScrollEnabled is false (e.g. restored draft).
        isProgrammaticallySettingText = true
        defer { isProgrammaticallySettingText = false }
        textView.isScrollEnabled = true
        textView.text = text
        updateTextViewHeight()
        // Run again after layout so we get correct height/scroll when the first run had effectiveWidth == 0 (draft restore).
        DispatchQueue.main.async { [weak self] in
            self?.updateTextViewHeight()
        }
        updateSendButtonState()
        refreshMentionStylingAfterTextChange()
        mentionInputView?.dismissSearch(animated: false)
        NotificationCenter.default.post(name: UITextView.textDidChangeNotification, object: textView)
    }
    
    func insertText(_ text: String) {
        if let selectedRange = textView.selectedTextRange {
            textView.replace(selectedRange, withText: text)
        } else {
            textView.text = (textView.text ?? "") + text
        }
        updateTextViewHeight()
    }
    
    // Focus the text field
    func focusTextField() {
        textView.becomeFirstResponder()
    }
    
    // Add attachment methods
    func addImage(_ image: UIImage, fileName: String? = nil) -> Bool {
        let success = pendingAttachmentsManager.addImage(image, fileName: fileName)
        if success {
            updateAttachmentPreview()
            updateSendButtonState()
        }
        return success
    }
    
    func addDocument(data: Data, fileName: String) -> Bool {
        let success = pendingAttachmentsManager.addDocument(data: data, fileName: fileName)
        if success {
            updateAttachmentPreview()
            updateSendButtonState()
        }
        return success
    }
    
    func addVideo(data: Data, fileName: String) -> Bool {
        let success = pendingAttachmentsManager.addVideo(data: data, fileName: fileName)
        if success {
            updateAttachmentPreview()
            updateSendButtonState()
        }
        return success
    }
    
    func clearAllAttachments() {
        pendingAttachmentsManager.clearAllAttachments()
        updateAttachmentPreview()
        updateSendButtonState()
    }
    
    // Clear attachments
    func clearAttachments() {
        pendingAttachmentsManager.clearAllAttachments()
        updateAttachmentPreview()
        updateSendButtonState()
    }
    
    // Clear only text input (keep attachments during upload)
    func clearTextInput() {
        textView.text = ""
        updateSendButtonState()
        // Trigger text change notification to update placeholder
        NotificationCenter.default.post(name: UITextView.textDidChangeNotification, object: textView)
    }
    
    // Call this when upload completes (success or failure)
    func onAttachmentsUploadComplete() {
        // print("🎯 onAttachmentsUploadComplete CALLED")
        
        // IMPORTANT: Clear upload state BEFORE clearing attachments
        // Otherwise the views will be removed and we can't update their state
        // print("🎯 Calling attachmentPreviewView.hideAllLoadingOverlays()")
        attachmentPreviewView.hideAllLoadingOverlays()
        // print("🎯 hideAllLoadingOverlays() completed")
        
        // Clear attachments immediately (no delay) to hide preview box
        // print("🎯 Clearing pending attachments immediately")
        pendingAttachmentsManager.clearAllAttachments()
        updateAttachmentPreview()
        // print("🎯 Attachments cleared and preview updated")
        
        // Re-enable interactions
        plusButton.isEnabled = true
        isSendingAttachments = false
        // print("🎯 Plus button re-enabled")
        
        updateSendButtonState()
        // print("🎯 onAttachmentsUploadComplete COMPLETED")
    }
    
    // Set the editing state
    func setEditingMessage(_ message: Types.Message?) {
        // Reset replying state if setting edit mode
        if message != nil {
            setReplyingToMessage(nil)
        }
        
        // Update the editing message
        editingMessage = message
        
        if message != nil {
            // Show editing indicator when message is not nil
            editingIndicator.isHidden = false
            
            // Set text for editing
            if let content = message?.content {
                textView.text = content
                NotificationCenter.default.post(name: UITextView.textDidChangeNotification, object: textView)
                // Make sure send button is enabled
                updateSendButtonState()
                updateTextViewHeight()
            }
            
            // Update height to accommodate editing indicator
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            layoutIfNeeded()
            
            // If parent view exists, notify it of layout changes
            if let superview = self.superview {
                superview.setNeedsLayout()
                superview.layoutIfNeeded()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.focusTextField()
            }
        } else {
            // Hide editing indicator when message is nil
            editingIndicator.isHidden = true
            textView.text = nil
            updateTextViewHeight()
            
            // Update height to remove editing indicator space
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            layoutIfNeeded()
            
            // If parent view exists, notify it of layout changes
            if let superview = self.superview {
                superview.setNeedsLayout()
                superview.layoutIfNeeded()
            }
        }
        
        // Update text view position based on editing state
        updateTextViewPosition()
    }
    
    // Set the replying state
    func setReplyingToMessage(_ message: Types.Message?) {
        // Reset editing state if setting reply mode
        if message != nil {
            setEditingMessage(nil)
        }
        
        // Update the replying message
        replyingToMessage = message
        
        if message != nil {
            // Show reply indicator when message is not nil
            replyIndicator.isHidden = false
            
            // Update UI to show replying state
            // Set reply label text if we have user info
            if let author = message?.author {
                replyLabel.text = "Replying to message"
            } else {
                replyLabel.text = "Replying to message"
            }
            
            // Update height to accommodate reply indicator
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            layoutIfNeeded()
            
            // If parent view exists, notify it of layout changes
            if let superview = self.superview {
                superview.setNeedsLayout()
                superview.layoutIfNeeded()
            }
            
            // Focus text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.focusTextField()
            }
        } else {
            // Hide reply indicator when message is nil
            replyIndicator.isHidden = true
            
            // Update height to remove reply indicator space
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            layoutIfNeeded()
            
            // If parent view exists, notify it of layout changes
            if let superview = self.superview {
                superview.setNeedsLayout()
                superview.layoutIfNeeded()
            }
        }
        
        // Update text view position based on replying state
        updateTextViewPosition()
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        backgroundColor = UIColor(named: "bgGray13") ?? .systemBackground
        
        // Setup text view
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.placeholder = "Message..."  // We'll add this extension below
        textView.backgroundColor = UIColor(named: "bgGray11") ?? .systemGray6
        textView.textColor = UIColor(named: "textDefaultGray01") ?? .label
        textView.layer.cornerRadius = 20
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 14, right: 14)
        textView.isScrollEnabled = false
        textView.delegate = self
        
        // Setup editing indicator view
        setupEditingIndicator()
        
        // Setup reply indicator view
        setupReplyIndicator()
        
        // Setup attachment preview view
        attachmentPreviewView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewView.isHidden = true // Hidden by default
        addSubview(attachmentPreviewView)
        
        // Setup send button
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        let sendIcon = UIImage(systemName: "arrow.up.circle.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .medium))
        sendButton.setImage(sendIcon, for: .normal)
        sendButton.tintColor = UIColor(named: "iconDefaultPurple05") ?? .systemBlue
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 15, left: 5, bottom: 0, right: 5)
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        
        // Setup plus button
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        plusButton.setImage(UIImage(systemName: "plus"), for: .normal)
        plusButton.tintColor = UIColor(named: "iconGray07") ?? .systemGray
        plusButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        plusButton.addTarget(self, action: #selector(plusButtonTapped), for: .touchUpInside)
        
        // Add views
        addSubview(textView)
        addSubview(sendButton)
        addSubview(plusButton)
        addSubview(editingIndicator)
        addSubview(replyIndicator)
        addSubview(attachmentPreviewView)
        
        // Hide indicators initially
        editingIndicator.isHidden = true
        replyIndicator.isHidden = true
        attachmentPreviewView.isHidden = true
        
        // Create constraints
        let textViewLeadingConstraint = textView.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 10)
        let textViewTrailingConstraint = textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10)
        let textViewBottomConstraint = textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: minHeight)
        
        // Create different top constraints for different states
        normalTextViewTopConstraint = textView.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        editingTextViewTopConstraint = textView.topAnchor.constraint(equalTo: editingIndicator.bottomAnchor, constant: 5)
        replyTextViewTopConstraint = textView.topAnchor.constraint(equalTo: replyIndicator.bottomAnchor, constant: 5)
        attachmentTextViewTopConstraint = textView.topAnchor.constraint(equalTo: attachmentPreviewView.bottomAnchor, constant: 5)
        
        // Activate the appropriate top constraint
        normalTextViewTopConstraint.isActive = true
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Editing indicator
            editingIndicator.topAnchor.constraint(equalTo: topAnchor),
            editingIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            editingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            editingIndicator.heightAnchor.constraint(equalToConstant: 40),
            
            // Reply indicator
            replyIndicator.topAnchor.constraint(equalTo: topAnchor),
            replyIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            replyIndicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            replyIndicator.heightAnchor.constraint(equalToConstant: 40),
            
            // Attachment preview
            attachmentPreviewView.topAnchor.constraint(equalTo: topAnchor),
            attachmentPreviewView.leadingAnchor.constraint(equalTo: leadingAnchor),
            attachmentPreviewView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            // Text view - activate the shared constraints
            textViewLeadingConstraint,
            textViewTrailingConstraint,
            textViewBottomConstraint,
            textViewHeightConstraint,
            
            // Send button
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: -4),
            sendButton.widthAnchor.constraint(equalToConstant: 48),
            sendButton.heightAnchor.constraint(equalToConstant: 48),
            
            // Plus button
            plusButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            plusButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: -4),
            plusButton.widthAnchor.constraint(equalToConstant: 40),
            plusButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Initialize with empty state
        updateSendButtonState()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        // Make sure text view position is updated whenever layout changes
        updateTextViewPosition()

        // Recompute text view height when we have content (e.g. after draft restore) so multiline height uses real width once laid out
        if let text = textView.text, !text.isEmpty {
            updateTextViewHeight()
        }

        // Make sure our bounds height is updated correctly
        invalidateIntrinsicContentSize()
    }
    
    override var intrinsicContentSize: CGSize {
        let textViewHeight = min(textView.contentSize.height, maxHeight)
        var totalHeight: CGFloat = textViewHeight + 20 // Base text view + padding
        
        if !editingIndicator.isHidden {
            totalHeight += 40 + 5 // Edit indicator + spacing
        } else if !replyIndicator.isHidden {
            totalHeight += 40 + 5 // Reply indicator + spacing
        }
        
        if !attachmentPreviewView.isHidden {
            totalHeight += 76 + 5 // Attachment preview + spacing
        }
        
        return CGSize(width: UIView.noIntrinsicMetric, height: totalHeight)
    }
    
    private func setupEditingIndicator() {
        editingIndicator.translatesAutoresizingMaskIntoConstraints = false
        editingIndicator.backgroundColor = UIColor(named: "bgDefaultPurple13") ?? .systemBackground
        
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        editingIndicator.addSubview(separator)
        
        editingLabel.translatesAutoresizingMaskIntoConstraints = false
        editingLabel.text = "Editing Message"
        editingLabel.textColor = UIColor(named: "textGray04") ?? .systemGray
        editingLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        
        cancelEditButton.translatesAutoresizingMaskIntoConstraints = false
        cancelEditButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancelEditButton.tintColor = UIColor(named: "iconGray07") ?? .systemGray
        cancelEditButton.addTarget(self, action: #selector(cancelEditButtonTapped), for: .touchUpInside)
        
        editingIndicator.addSubview(editingLabel)
        editingIndicator.addSubview(cancelEditButton)
        
        NSLayoutConstraint.activate([
            cancelEditButton.leadingAnchor.constraint(equalTo: editingIndicator.leadingAnchor, constant: 12),
            cancelEditButton.centerYAnchor.constraint(equalTo: editingIndicator.centerYAnchor),
            cancelEditButton.widthAnchor.constraint(equalToConstant: 24),
            cancelEditButton.heightAnchor.constraint(equalToConstant: 24),
            
            editingLabel.leadingAnchor.constraint(equalTo: cancelEditButton.trailingAnchor, constant: 8),
            editingLabel.centerYAnchor.constraint(equalTo: editingIndicator.centerYAnchor),
            editingLabel.trailingAnchor.constraint(lessThanOrEqualTo: editingIndicator.trailingAnchor, constant: -12),
            
            separator.leadingAnchor.constraint(equalTo: editingIndicator.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: editingIndicator.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: editingIndicator.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    private func setupReplyIndicator() {
        replyIndicator.translatesAutoresizingMaskIntoConstraints = false
        replyIndicator.backgroundColor = UIColor(named: "bgDefaultBlue13") ?? .systemBackground
        
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        replyIndicator.addSubview(separator)
        
        replyLabel.translatesAutoresizingMaskIntoConstraints = false
        replyLabel.text = "Replying to message"
        replyLabel.textColor = UIColor(named: "textGray04") ?? .systemGray
        replyLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        
        cancelReplyButton.translatesAutoresizingMaskIntoConstraints = false
        cancelReplyButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancelReplyButton.tintColor = UIColor(named: "iconGray07") ?? .systemGray
        cancelReplyButton.addTarget(self, action: #selector(cancelReplyButtonTapped), for: .touchUpInside)
        
        replyIndicator.addSubview(replyLabel)
        replyIndicator.addSubview(cancelReplyButton)
        
        NSLayoutConstraint.activate([
            cancelReplyButton.leadingAnchor.constraint(equalTo: replyIndicator.leadingAnchor, constant: 12),
            cancelReplyButton.centerYAnchor.constraint(equalTo: replyIndicator.centerYAnchor),
            cancelReplyButton.widthAnchor.constraint(equalToConstant: 24),
            cancelReplyButton.heightAnchor.constraint(equalToConstant: 24),
            
            replyLabel.leadingAnchor.constraint(equalTo: cancelReplyButton.trailingAnchor, constant: 8),
            replyLabel.centerYAnchor.constraint(equalTo: replyIndicator.centerYAnchor),
            replyLabel.trailingAnchor.constraint(lessThanOrEqualTo: replyIndicator.trailingAnchor, constant: -12),
            
            separator.leadingAnchor.constraint(equalTo: replyIndicator.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: replyIndicator.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: replyIndicator.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    private func setupAttachmentPreview() {
        attachmentPreviewView.onRemoveAttachment = { [weak self] (attachmentId: String) in
            self?.pendingAttachmentsManager.removeAttachment(withId: attachmentId)
            self?.updateAttachmentPreview()
            self?.updateSendButtonState()
        }
    }
    
    private func updateAttachmentPreview() {
        attachmentPreviewView.updateAttachments(pendingAttachmentsManager.pendingAttachments)
        attachmentPreviewView.isHidden = !pendingAttachmentsManager.hasPendingAttachments
        updateTextViewPosition()
        invalidateIntrinsicContentSize()
        
        // If parent view exists, notify it of layout changes
        if let superview = self.superview {
            superview.setNeedsLayout()
            superview.layoutIfNeeded()
        }
    }
    
    // Update text view height based on content
    private func updateTextViewHeight() {
        // When text is set before layout (e.g. draft restore in viewWillAppear), textView.frame.width can be 0,
        // causing sizeThatFits to return single-line height. Use container width minus siblings (plus 10+40+10, send 10+48+10).
        let effectiveWidth: CGFloat = {
            let w = textView.frame.width
            if w > 0 { return w }
            let margin: CGFloat = 10 + 40 + 10 + 10 + 48 + 10 // leading, plus, gap, gap, send, trailing
            return max(0, bounds.width - margin)
        }()
        guard effectiveWidth > 0 else { return }
        let size = textView.sizeThatFits(CGSize(width: effectiveWidth, height: CGFloat.greatestFiniteMagnitude))
        let newHeight = min(max(size.height, minHeight), maxHeight)
        
        // Enable scrolling when content exceeds visible area. Once we're at maxHeight, keep scrolling on so a later layout
        // pass with a wrong width (e.g. from layoutSubviews) can't turn it off—restored long drafts otherwise lose scrolling.
        if textViewHeightConstraint.constant >= maxHeight {
            textView.isScrollEnabled = true
        } else {
            textView.isScrollEnabled = (newHeight >= maxHeight)
        }
        if textViewHeightConstraint.constant != newHeight {
            textViewHeightConstraint.constant = newHeight
            invalidateIntrinsicContentSize()

            // If parent view exists, notify it of layout changes
            if let superview = self.superview {
                superview.setNeedsLayout()
                superview.layoutIfNeeded()
            }
        }

        textView.layoutIfNeeded()
        // Force UITextView to recompute contentSize for the new frame (it can stay stale when text was set with a smaller frame).
        if newHeight >= maxHeight {
            textView.isScrollEnabled = false
            textView.isScrollEnabled = true
        }
        if textView.contentSize.height > textView.bounds.height + 1 {
            textView.isScrollEnabled = true
        }
    }
    
    // MARK: - Action Handlers
    
    @objc private func sendButtonTapped() {
        let text = textView.text ?? ""
        let hasAttachments = pendingAttachmentsManager.hasPendingAttachments
        
        // Must have at least one non-whitespace character or attachments
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments else { return }

        let canMentionEveryone = MentionInputUtilities.canMentionEveryone(
            in: currentChannel,
            server: currentServer,
            viewState: currentViewState
        )
        if MentionInputUtilities.requiresPlainTextEveryoneConfirmation(
            text: text,
            canMentionEveryone: canMentionEveryone
        ) {
            presentPlainTextEveryoneConfirmation(text: text, hasAttachments: hasAttachments)
            return
        }

        performSend(text: text, hasAttachments: hasAttachments)
    }

    private func presentPlainTextEveryoneConfirmation(
        text: String,
        hasAttachments: Bool
    ) {
        guard let presenter = findViewController() else { return }

        let alert = UIAlertController(
            title: "You can’t mention @everyone",
            message: "You don’t have permission to mention @everyone in this channel. Please contact the server owner if you believe this is incorrect.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Edit Message", style: .cancel) { [weak self] _ in
            self?.textView.becomeFirstResponder()
        })
        alert.addAction(UIAlertAction(title: "Send as Plain Text", style: .default) { [weak self] _ in
            self?.performSend(text: text, hasAttachments: hasAttachments)
        })
        presenter.present(alert, animated: true)
    }

    private func performSend(text: String, hasAttachments: Bool) {
        
        if let editingMessage = editingMessage {
            // Handle edit message (attachments not supported for editing)
            delegate?.messageInputView(self, didEditMessage: editingMessage, newText: text)
            
            // Reset editing state
            setEditingMessage(nil)
        } else if let replyingToMessage = replyingToMessage {
            // Handle reply message
            if hasAttachments {
                // Set uploading state for all attachments
                let attachmentIds = pendingAttachmentsManager.pendingAttachments.map { $0.id }
                attachmentPreviewView.setUploadingState(for: attachmentIds)
                
                // Disable interactions during upload
                plusButton.isEnabled = false
                isSendingAttachments = true
                
                let attachments = pendingAttachmentsManager.getAttachmentsForSending()
                delegate?.messageInputView(self, didSendMessageWithAttachments: text, attachments: attachments)
                
                // Don't clear attachments yet - they'll be cleared when upload completes
            } else {
            delegate?.messageInputView(self, didReplyToMessage: replyingToMessage, withText: text)
            }
            
            // Reset reply state
            setReplyingToMessage(nil)
        } else {
            // Handle new message
            if hasAttachments {
                // Set uploading state for all attachments
                let attachmentIds = pendingAttachmentsManager.pendingAttachments.map { $0.id }
                attachmentPreviewView.setUploadingState(for: attachmentIds)
                
                // Disable interactions during upload
                plusButton.isEnabled = false
                isSendingAttachments = true
                
                let attachments = pendingAttachmentsManager.getAttachmentsForSending()
                delegate?.messageInputView(self, didSendMessageWithAttachments: text, attachments: attachments)
                
                // Don't clear attachments yet - they'll be cleared when upload completes
            } else {
            delegate?.messageInputView(self, didSendMessage: text)
            }
        }
        
        // Clear text field
        textView.text = nil
        updateSendButtonState()
        updateTextViewHeight()
    }
    
    @objc private func plusButtonTapped() {
        delegate?.messageInputViewDidTapAttach(self)
    }
    
    @objc private func cancelEditButtonTapped() {
        // Reset editing state
        setEditingMessage(nil)
        textView.text = nil
        updateSendButtonState()
        updateTextViewHeight()
    }
    
    @objc private func cancelReplyButtonTapped() {
        // Reset reply state
        setReplyingToMessage(nil)
    }
    
    private func updateSendButtonState() {
        let trimmed = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasText = !trimmed.isEmpty
        let hasAttachments = pendingAttachmentsManager.hasPendingAttachments
        let canSend = hasText || hasAttachments
        
        sendButton.isEnabled = canSend && !isSendingAttachments
        if !sendButton.isEnabled {
            sendButton.tintColor = UIColor(named: "iconGray07") ?? .systemGray
        } else {
            sendButton.tintColor = UIColor(named: "iconDefaultPurple05") ?? .systemBlue
        }
    }
    
    private func updateTextViewPosition() {
        // Deactivate all constraints first
        normalTextViewTopConstraint.isActive = false
        editingTextViewTopConstraint.isActive = false
        replyTextViewTopConstraint.isActive = false
        attachmentTextViewTopConstraint.isActive = false
        
        // Activate the appropriate constraint based on visible indicators
        if !editingIndicator.isHidden {
            editingTextViewTopConstraint.isActive = true
        } else if !replyIndicator.isHidden {
            replyTextViewTopConstraint.isActive = true
        } else if !attachmentPreviewView.isHidden {
            attachmentTextViewTopConstraint.isActive = true
        } else {
            normalTextViewTopConstraint.isActive = true
        }
    }
}

// MARK: - UITextViewDelegate
extension MessageInputView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateSendButtonState()
        updateTextViewHeight()
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Safety check for range bounds (use UTF-16 length to handle emoji correctly)
        guard let textViewText = textView.text else { return true }
        let nsText = textViewText as NSString
        guard range.location >= 0,
              range.location + range.length <= nsText.length else {
            return false
        }
        
        // Handle Enter key (new line)
        if text == "\n" {
            // Always allow new lines - don't send message on Enter
            return true
        }
        return true
    }
}

// MARK: - UITextView Placeholder Extension
extension UITextView {
    private struct AssociatedKeys {
        static var placeholder = "placeholder"
        static var placeholderLabel = "placeholderLabel"
    }
    
    var placeholder: String? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.placeholder) as? String
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.placeholder, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            setupPlaceholderIfNeeded()
        }
    }
    
    private var placeholderLabel: UILabel? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.placeholderLabel) as? UILabel
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.placeholderLabel, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private func setupPlaceholderIfNeeded() {
        if placeholderLabel == nil {
            placeholderLabel = UILabel()
            placeholderLabel?.font = self.font
            placeholderLabel?.textColor = UIColor.lightGray
            placeholderLabel?.numberOfLines = 0
            placeholderLabel?.translatesAutoresizingMaskIntoConstraints = false
            
            if let placeholderLabel = placeholderLabel {
                self.addSubview(placeholderLabel)
                NSLayoutConstraint.activate([
                    placeholderLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 14),
                    placeholderLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -14),
                    placeholderLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 10),
                    placeholderLabel.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor, constant: -14)
                ])
            }
            
            NotificationCenter.default.addObserver(self, selector: #selector(textDidChange), name: UITextView.textDidChangeNotification, object: nil)
        }
        
        placeholderLabel?.text = placeholder
        placeholderLabel?.isHidden = !self.text.isEmpty
    }
    
    @objc private func textDidChange() {
        placeholderLabel?.isHidden = !self.text.isEmpty
    }
}

// MARK: - MessageInputView Mention Extension
extension MessageInputView: MentionInputViewDelegate {
    func mentionInputView(_ mentionView: MentionInputView, didSelectUser user: User, member: Member?) {
        // print("DEBUG: User selected from mention: \(user.username)")
        
        // Get current text
        let currentText = textView.text ?? ""
        
        if let replacement = MentionInputUtilities.replacingActiveMention(
            in: currentText,
            selectedRange: textView.selectedRange,
            with: "@\(user.username) "
        ) {
            // Create the mention data
            let displayText = "@\(user.username)"
            let mentionData = MentionData(
                userId: user.id,
                username: user.username,
                displayText: displayText
            )
            
            // Store the mention data
            storeMentionData(mentionData)
            
            adjustMentionTokens(for: replacement)
            textView.text = replacement.text
            textView.selectedRange = replacement.selectedRange
            mentionTokens.append(MentionToken(
                userId: user.id,
                displayText: displayText,
                range: NSRange(location: replacement.insertedRange.location, length: (displayText as NSString).length)
            ))
            
            // Update UI
            updateSendButtonState()
            updateTextViewHeight()
            applyMentionStyling()
            
            // Notify delegate about text change
            if let delegate = textView.delegate {
                delegate.textViewDidChange?(textView)
            }
        }
        
        // Hide the mention view
        hideMentionView()
    }

    func mentionInputViewDidSelectEveryone(_ mentionView: MentionInputView) {
        guard let replacement = MentionInputUtilities.replacingActiveMention(
            in: textView.text ?? "",
            selectedRange: textView.selectedRange,
            with: "@everyone "
        ) else {
            hideMentionView()
            return
        }

        adjustMentionTokens(for: replacement)
        textView.text = replacement.text
        textView.selectedRange = replacement.selectedRange
        updateSendButtonState()
        updateTextViewHeight()
        applyMentionStyling()
        textView.delegate?.textViewDidChange?(textView)
        hideMentionView()
    }
    
    func mentionInputViewDidDismiss(_ mentionView: MentionInputView) {
        // print("DEBUG: Mention view dismissed")
    }
    
    // MARK: - Mention Data Management
    
    // Store mention data using associated objects
    private func storeMentionData(_ mentionData: MentionData) {
        var mentionDataList = getMentionDataList()
        
        // Remove any existing mention for the same user to avoid duplicates
        mentionDataList.removeAll { $0.userId == mentionData.userId }
        
        // Add the new mention data
        mentionDataList.append(mentionData)
        
        // Store back to associated object
        objc_setAssociatedObject(
            self,
            &MentionKeys.mentionDataList,
            mentionDataList,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        
        // print("DEBUG: Stored mention data for user: \(mentionData.username)")
    }
    
    // Get mention data list
    private func getMentionDataList() -> [MentionData] {
        return objc_getAssociatedObject(self, &MentionKeys.mentionDataList) as? [MentionData] ?? []
    }

    private func removeMentionDataNotPresent(in text: String) {
        let validMentionData = getMentionDataList().filter { text.contains($0.displayText) }
        objc_setAssociatedObject(
            self,
            &MentionKeys.mentionDataList,
            validMentionData.isEmpty ? nil : validMentionData,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
    
    // Convert text for sending (replace @username with <@USER_ID>)
    func convertTextForSending() -> String {
        let originalText = textView.text ?? ""
        let mutable = NSMutableString(string: originalText)
        let validTokens = mentionTokens
            .filter { token in
                MentionInputUtilities.isValid(
                    range: token.range,
                    inUTF16Length: mutable.length
                )
                    && mutable.substring(with: token.range) == token.displayText
            }
            .sorted { $0.range.location > $1.range.location }

        if !validTokens.isEmpty {
            for token in validTokens {
                mutable.replaceCharacters(in: token.range, with: "<@\(token.userId)>")
            }
            return mutable as String
        }

        var convertedText = originalText
        let mentionDataList = getMentionDataList()
        for mentionData in mentionDataList {
            convertedText = convertedText.replacingOccurrences(
                of: mentionData.displayText,
                with: "<@\(mentionData.userId)>"
            )
        }
        
        // print("DEBUG: Converted text from '\(originalText)' to '\(convertedText)'")
        return convertedText
    }
    
    // Clear mention data
    func clearMentionData() {
        objc_setAssociatedObject(
            self,
            &MentionKeys.mentionDataList,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        mentionTokens.removeAll()
        // print("DEBUG: Cleared mention data")
    }
}
