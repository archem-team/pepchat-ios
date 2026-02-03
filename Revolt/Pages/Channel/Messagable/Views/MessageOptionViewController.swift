//
//  MessageOptionViewController.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit


// MARK: - Custom Message Option View Controller
class MessageOptionViewController: UIViewController {
    private let message: Message
    private let isMessageAuthor: Bool
    private let canDeleteMessage: Bool
    private let canReply: Bool
    private let onOptionSelected: (MessageCell.MessageAction) -> Void
    
    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    
    // Emoji reactions list (based on MessageEmojisReact.swift)
    private let emojiItems: [[Int]] = [[128077], [129315], [9786,65039], [10084,65039], [128559]]
    
    // Array to store button actions
    private var actions: [() -> Void] = []
    
    init(message: Message, isMessageAuthor: Bool, canDeleteMessage: Bool, canReply: Bool, onOptionSelected: @escaping (MessageCell.MessageAction) -> Void) {
        self.message = message
        self.isMessageAuthor = isMessageAuthor
        self.canDeleteMessage = canDeleteMessage
        self.canReply = canReply
        self.onOptionSelected = onOptionSelected
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupEmojiReactions()
        setupOptions()
    }
    
    private func setupUI() {
        // Set background color to match SwiftUI version (.bgGray12)
        view.backgroundColor = UIColor(named: "bgGray12") ?? UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
        
        // Set corner radius to view to ensure it's visible on the sheet
        if #available(iOS 15.0, *) {
            // iOS 15+ will handle this with sheet presentation controller
        } else {
            view.layer.cornerRadius = 16
            view.clipsToBounds = true
        }
        
        // Set up scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
        
        // Set up content stack view
        contentStackView.axis = .vertical
        contentStackView.spacing = 24
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStackView)
        
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupEmojiReactions() {
        // Create emoji container
        let emojiStack = UIStackView()
        emojiStack.axis = .horizontal
        emojiStack.spacing = 12
        emojiStack.distribution = .fillEqually
        emojiStack.translatesAutoresizingMaskIntoConstraints = false
        emojiStack.alignment = .center
        
        // Center the emojis horizontally
        let containerStack = UIStackView()
        containerStack.axis = .vertical
        containerStack.alignment = .center
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(containerStack)
        containerStack.addArrangedSubview(emojiStack)
        
        // Add emoji buttons
        for emojiCodes in emojiItems {
            let emojiButton = createEmojiButton(with: emojiCodes)
            emojiStack.addArrangedSubview(emojiButton)
        }
        
        // Add "Add custom emoji" button
        let customEmojiButton = createCustomEmojiButton()
        emojiStack.addArrangedSubview(customEmojiButton)
        
        // Set height constraint for the emoji stack
        NSLayoutConstraint.activate([
            emojiStack.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    
    private func createEmojiButton(with codePoints: [Int]) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create background circle
        let circleView = UIView()
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = UIColor(named: "bgGray11") ?? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0)
        circleView.layer.cornerRadius = 24
        containerView.addSubview(circleView)
        
        // Create emoji label
        let emojiLabel = UILabel()
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Convert code points to emoji string
        let emojiString = codePoints.compactMap { UnicodeScalar($0) }.reduce(into: "") { result, scalar in
            result.append(Character(scalar))
        }
        
        emojiLabel.text = emojiString
        emojiLabel.font = UIFont.systemFont(ofSize: 24)
        emojiLabel.textAlignment = .center
        circleView.addSubview(emojiLabel)
        
        // Add highlight effect on touch
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(emojiButtonTapped(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUpOutside(_:)), for: .touchUpOutside)
        
        // Store emoji string in button's accessibilityLabel for later retrieval
        button.accessibilityLabel = emojiString
        containerView.addSubview(button)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            containerView.widthAnchor.constraint(equalToConstant: 48),
            containerView.heightAnchor.constraint(equalToConstant: 48),
            
            circleView.widthAnchor.constraint(equalToConstant: 48),
            circleView.heightAnchor.constraint(equalToConstant: 48),
            circleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            emojiLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            
            button.topAnchor.constraint(equalTo: containerView.topAnchor),
            button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    private func createCustomEmojiButton() -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create background circle
        let circleView = UIView()
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = UIColor(named: "bgGray11") ?? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0)
        circleView.layer.cornerRadius = 24
        containerView.addSubview(circleView)
        
        // Create icon - try to use Peptide icon if available
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(named: "iconDefaultGray01") ?? .white
        
        if let peptideImage = UIImage(named: "peptideSmile") {
            iconView.image = peptideImage
        } else {
            iconView.image = UIImage(systemName: "face.smiling.fill")
        }
        
        circleView.addSubview(iconView)
        
        // Add highlight effect on touch
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(customEmojiButtonTapped), for: .touchUpInside)
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUpOutside(_:)), for: .touchUpOutside)
        containerView.addSubview(button)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            containerView.widthAnchor.constraint(equalToConstant: 48),
            containerView.heightAnchor.constraint(equalToConstant: 48),
            
            circleView.widthAnchor.constraint(equalToConstant: 48),
            circleView.heightAnchor.constraint(equalToConstant: 48),
            circleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            iconView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            button.topAnchor.constraint(equalTo: containerView.topAnchor),
            button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    @objc private func emojiButtonTapped(_ sender: UIButton) {
        guard let emojiString = sender.accessibilityLabel else { return }
        dismiss(animated: true) {
            // Send the emoji reaction
            // print("Selected emoji reaction: \(emojiString)")
            // Add handling for the emoji reaction (we'll need to add this action type)
            self.onOptionSelected(.react(emojiString))
        }
    }
    
    @objc private func customEmojiButtonTapped() {
        dismiss(animated: true) {
            // Request custom emoji selector
            // print("Open custom emoji selector")
            self.onOptionSelected(.react("-1")) // -1 is used to indicate custom emoji selection
        }
    }
    
    private func setupOptions() {
        // Author-specific options
        if isMessageAuthor {
            let authorOptionsStack = createOptionsGroup()
            
            // Edit option
            let editOption = createOptionButton(
                title: "Edit Message",
                iconName: "pencil",
                action: { [weak self] in
                    self?.onOptionSelected(.edit)
                    self?.dismiss(animated: true)
                }
            )
            authorOptionsStack.addArrangedSubview(editOption)
            
            // Add divider
            addDividerToGroup(group: authorOptionsStack)
            
            // Reply option (only if user has permission)
            if canReply {
                let replyOption = createOptionButton(
                    title: "Reply",
                    iconName: "arrowshape.turn.up.left",
                    action: { [weak self] in
                        self?.onOptionSelected(.reply)
                        self?.dismiss(animated: true)
                    }
                )
                authorOptionsStack.addArrangedSubview(replyOption)
            }
            
            contentStackView.addArrangedSubview(authorOptionsStack)
        } else {
            // Reply option for non-authors (only if user has permission)
            if canReply {
                let replyOption = createOptionButton(
                    title: "Reply",
                    iconName: "arrowshape.turn.up.left",
                    action: { [weak self] in
                        self?.onOptionSelected(.reply)
                        self?.dismiss(animated: true)
                    }
                )
                let replyContainer = createOptionsGroup()
                replyContainer.addArrangedSubview(replyOption)
                contentStackView.addArrangedSubview(replyContainer)
            }
        }
        
        // Common options group
        let commonOptionsStack = createOptionsGroup()
        
        // Mention option (only if not author)
//        if !isMessageAuthor {
//            let mentionOption = createOptionButton(
//                title: "Mention",
//                iconName: "at",
//                action: { [weak self] in
//                    self?.onOptionSelected(.mention)
//                    self?.dismiss(animated: true)
//                }
//            )
//            commonOptionsStack.addArrangedSubview(mentionOption)
//            addDividerToGroup(group: commonOptionsStack)
//        }
        
        // Mark unread option
        let markUnreadOption = createOptionButton(
            title: "Mark Unread",
            iconName: "eye.slash",
            action: { [weak self] in
                self?.onOptionSelected(.markUnread)
                self?.dismiss(animated: true)
            }
        )
        commonOptionsStack.addArrangedSubview(markUnreadOption)
        addDividerToGroup(group: commonOptionsStack)
        
        // Copy text option
        if let content = message.content, !content.isEmpty {
            let copyOption = createOptionButton(
                title: "Copy Text",
                iconName: "doc.on.doc",
                action: { [weak self] in
                    self?.onOptionSelected(.copy)
                    self?.dismiss(animated: true)
                }
            )
            commonOptionsStack.addArrangedSubview(copyOption)
            addDividerToGroup(group: commonOptionsStack)
        }
        
        // Copy link option
        let copyLinkOption = createOptionButton(
            title: "Copy Message Link",
            iconName: "link",
            action: { [weak self] in
                self?.onOptionSelected(.copyLink)
                self?.dismiss(animated: true)
            }
        )
        commonOptionsStack.addArrangedSubview(copyLinkOption)
        addDividerToGroup(group: commonOptionsStack)
        
        // Copy ID option
        let copyIdOption = createOptionButton(
            title: "Copy Message ID",
            iconName: "number",
            action: { [weak self] in
                self?.onOptionSelected(.copyId)
                self?.dismiss(animated: true)
            }
        )
        commonOptionsStack.addArrangedSubview(copyIdOption)
        
        contentStackView.addArrangedSubview(commonOptionsStack)
        
        // Delete message option (if user is author or has permissions)
        if canDeleteMessage {
            let deleteOption = createOptionButton(
                title: "Delete Message",
                iconName: "trash",
                titleColor: UIColor(named: "textRed07") ?? .systemRed,
                iconColor: UIColor(named: "iconRed07") ?? .systemRed,
                action: { [weak self] in
                    self?.onOptionSelected(.delete)
                    self?.dismiss(animated: true)
                }
            )
            let deleteContainer = createOptionsGroup()
            deleteContainer.addArrangedSubview(deleteOption)
            contentStackView.addArrangedSubview(deleteContainer)
        }
        
        // Report option (only if not author)
        if !isMessageAuthor {
            let reportOption = createOptionButton(
                title: "Report Message",
                iconName: "flag",
                titleColor: UIColor(named: "textRed07") ?? .systemRed,
                iconColor: UIColor(named: "iconRed07") ?? .systemRed,
                action: { [weak self] in
                    self?.onOptionSelected(.report)
                    self?.dismiss(animated: true)
                }
            )
            let reportContainer = createOptionsGroup()
            reportContainer.addArrangedSubview(reportOption)
            contentStackView.addArrangedSubview(reportContainer)
        }
    }
    
    private func createOptionsGroup() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        // Apply rounded background with padding
        stack.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.isLayoutMarginsRelativeArrangement = true
        
        // Apply bgGray11 background color with rounded corners
        stack.backgroundColor = UIColor(named: "bgGray11") ?? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0)
        stack.layer.cornerRadius = 8
        stack.clipsToBounds = true
        
        return stack
    }
    
    private func createDivider() -> UIView {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor(named: "borderGray10") ?? UIColor.gray.withAlphaComponent(0.3)
        
        // Just set the height - leading constraint will be set after adding to stackView
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        return divider
    }
    
    // Method to add divider to group with padding
    private func addDividerToGroup(group: UIStackView) {
        let divider = createDivider()
        group.addArrangedSubview(divider)
        
        // Now that divider is added to stackView, we can set its constraints safely
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 12)
        ])
    }
    
    private func createOptionButton(title: String, iconName: String, titleColor: UIColor = UIColor(named: "textDefaultGray01") ?? .white, iconColor: UIColor = UIColor(named: "iconDefaultGray01") ?? .white, action: @escaping () -> Void) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Button background
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(optionButtonTapped(_:)), for: .touchUpInside)
        // Add highlight effect
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUpOutside(_:)), for: .touchUpOutside)
        button.tag = actions.count // Use tag to identify button action
        actions.append(action)
        
        containerView.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: containerView.topAnchor),
            button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Icon view
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = iconColor
        
        // Map from plain icon names to SF Symbol names
        let sfSymbolName = mapToSFSymbol(iconName)
        iconView.image = UIImage(systemName: sfSymbolName)
        
        containerView.addSubview(iconView)
        
        // Label
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = titleColor
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        
        containerView.addSubview(label)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            containerView.heightAnchor.constraint(equalToConstant: 48),
            
            iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -12)
        ])
        
        return containerView
    }
    
    private func mapToSFSymbol(_ iconName: String) -> String {
        // Map PeptideIcon names to SF Symbols
        switch iconName {
        case "pencil": return "pencil"
        case "arrowshape.turn.up.left": return "arrowshape.turn.up.left.fill"
        case "at": return "at"
        case "eye.slash": return "eye.slash.fill"
        case "doc.on.doc": return "doc.on.doc"
        case "link": return "link"
        case "number": return "number"
        case "trash": return "trash.fill"
        case "flag": return "flag.fill"
        default: return iconName
        }
    }
    
    @objc private func buttonTouchDown(_ sender: UIButton) {
        // Highlight effect when button is pressed
        UIView.animate(withDuration: 0.1) {
            sender.superview?.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        }
    }
    
    @objc private func buttonTouchUpOutside(_ sender: UIButton) {
        // Remove highlight when touch is cancelled
        UIView.animate(withDuration: 0.1) {
            sender.superview?.backgroundColor = nil
        }
    }
    
    @objc private func optionButtonTapped(_ sender: UIButton) {
        // Restore original background
        UIView.animate(withDuration: 0.1) {
            sender.superview?.backgroundColor = nil
        }
        
        // Execute the action
        if let action = actions[safe: sender.tag] {
            action()
        }
    }
    

}
