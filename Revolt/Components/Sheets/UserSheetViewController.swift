import UIKit
import Kingfisher
import Types

/// A view controller that presents a popup sheet with a user's profile matching the design in the app.
class UserSheetViewController: UIViewController {
    // MARK: - Properties
    private let displayName: String
    private let roleText: String
    private let userAvatar: URL?
    private let userId: String
    private var viewState: ViewState?
    private let relation: Relation?
    
    // Data properties
    private var mutualFriendsCount: Int = 0
    private var mutualGroupsCount: Int = 0
    private var profile: Profile?
    
    // MARK: - UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    // Profile sections
    private let avatarImageView = UIImageView()
    private let usernameLabel = UILabel()
    private let userIdLabel = UILabel()
    
    // Bottom action buttons
    private let bottomActionsView = UIView()
    private let messageButton = UIButton()
    private let unfriendButton = UIButton()
    private let reportButton = UIButton()
    
    // Mutual sections
    private let mutualsSectionView = UIView()
    private let mutualFriendsView = UIView()
    private let mutualGroupsView = UIView()
    
    // MARK: - Initializer
    init(displayName: String, role: String, avatar: URL? = nil, userId: String = "", viewState: ViewState? = nil, relation: Relation? = nil) {
        self.displayName = displayName
        self.roleText = role
        self.userAvatar = avatar
        self.userId = userId
        self.viewState = viewState
        self.relation = relation
        super.init(nibName: nil, bundle: nil)
        
        modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 24
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupScrollView()
        setupProfileSection()
        loadAvatar()
        setupBottomActions()
        setupMutualSections()
        
        // Fetch data from API
        fetchMutualData()
        fetchProfileData()
    }
    
    // MARK: - Setup Methods
    private func setupView() {
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.1, alpha: 1.0)
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupProfileSection() {
        // Set up avatar
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 36
        contentView.addSubview(avatarImageView)
        
        // Username label
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.text = displayName
        usernameLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        usernameLabel.textColor = .white
        usernameLabel.textAlignment = .center
        contentView.addSubview(usernameLabel)
        
        // User ID label
        userIdLabel.translatesAutoresizingMaskIntoConstraints = false
        userIdLabel.text = userId.isEmpty ? "" : userId + "#7978"
        userIdLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        userIdLabel.textColor = UIColor.lightGray
        userIdLabel.textAlignment = .center
        contentView.addSubview(userIdLabel)
        
        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            avatarImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 72),
            avatarImageView.heightAnchor.constraint(equalToConstant: 72),
            
            usernameLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 16),
            usernameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            usernameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            usernameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            userIdLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 4),
            userIdLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            userIdLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            userIdLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }
    
    private func loadAvatar() {
        if let avatarURL = userAvatar {
            avatarImageView.kf.setImage(
                with: avatarURL,
                placeholder: UIImage(systemName: "person.circle.fill"),
                options: [
                    .transition(.fade(0.2)),
                    .cacheOriginalImage
                ]
            )
        } else {
            // Default avatar with colorful background based on username
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = .white
            
            // Create colorful background based on display name
            let hash = displayName.hash
            avatarImageView.backgroundColor = UIColor(
                hue: CGFloat(abs(hash) % 100) / 100.0,
                saturation: 0.7,
                brightness: 0.8,
                alpha: 1.0
            )
        }
    }
    
    private func setupBottomActions() {
        bottomActionsView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomActionsView)
        
        // Configure action buttons in a row
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        bottomActionsView.addSubview(stackView)
        
        // Configure message button
        configureBottomButton(messageButton, title: "Message", icon: "message", tintColor: .white, target: self, action: #selector(messageButtonTapped))
        stackView.addArrangedSubview(messageButton)
        
        // Configure unfriend button based on relation
        configureUnfriendButton(stackView)
        
        // Configure report button
        configureBottomButton(reportButton, title: "Report", icon: "exclamationmark.triangle", tintColor: UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0), target: self, action: #selector(reportButtonTapped))
        stackView.addArrangedSubview(reportButton)
        
        NSLayoutConstraint.activate([
            bottomActionsView.topAnchor.constraint(equalTo: userIdLabel.bottomAnchor, constant: 32),
            bottomActionsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomActionsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomActionsView.heightAnchor.constraint(equalToConstant: 80),
            
            stackView.topAnchor.constraint(equalTo: bottomActionsView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: bottomActionsView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: bottomActionsView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomActionsView.bottomAnchor)
        ])
    }
    
    private func configureUnfriendButton(_ stackView: UIStackView) {
        // Show different button based on relation
        switch relation {
        case .Friend:
            configureBottomButton(unfriendButton, title: "Unfriend", icon: "person.badge.minus", tintColor: UIColor.lightGray, target: self, action: #selector(unfriendButtonTapped))
        case .None:
            configureBottomButton(unfriendButton, title: "Add Friend", icon: "person.badge.plus", tintColor: UIColor.lightGray, target: self, action: #selector(addFriendButtonTapped))
        case .Incoming:
            configureBottomButton(unfriendButton, title: "Accept", icon: "checkmark.circle", tintColor: UIColor.systemGreen, target: self, action: #selector(acceptFriendButtonTapped))
        case .Outgoing:
            configureBottomButton(unfriendButton, title: "Cancel", icon: "xmark.circle", tintColor: UIColor.lightGray, target: self, action: #selector(cancelRequestButtonTapped))
        case .Blocked:
            configureBottomButton(unfriendButton, title: "Unblock", icon: "person.fill.checkmark", tintColor: UIColor.lightGray, target: self, action: #selector(unblockButtonTapped))
        default:
            configureBottomButton(unfriendButton, title: "Block", icon: "slash.circle", tintColor: UIColor.lightGray, target: self, action: #selector(blockButtonTapped))
        }
        stackView.addArrangedSubview(unfriendButton)
    }
    
    private func configureBottomButton(_ button: UIButton, title: String, icon: String, tintColor: UIColor, target: Any, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        button.addSubview(stackView)
        
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = tintColor
        if let image = UIImage(systemName: icon) {
            iconView.image = image
        }
        stackView.addArrangedSubview(iconView)
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = tintColor
        stackView.addArrangedSubview(label)
        
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            stackView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        
        button.addTarget(target, action: action, for: .touchUpInside)
    }
    
    private func setupMutualSections() {
        mutualsSectionView.translatesAutoresizingMaskIntoConstraints = false
        mutualsSectionView.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)
        mutualsSectionView.layer.cornerRadius = 10
        contentView.addSubview(mutualsSectionView)
        
        // Setup mutual friends row
        setupMutualRow(
            parentView: mutualsSectionView,
            rowView: mutualFriendsView,
            icon: "person.2.fill",
            text: "0 Mutual Friends",
            topAnchor: mutualsSectionView.topAnchor
        )
        
        // Setup mutual groups row
        setupMutualRow(
            parentView: mutualsSectionView,
            rowView: mutualGroupsView,
            icon: "person.3.fill",
            text: "0 Mutual Groups",
            topAnchor: mutualFriendsView.bottomAnchor
        )
        
        NSLayoutConstraint.activate([
            mutualsSectionView.topAnchor.constraint(equalTo: bottomActionsView.bottomAnchor, constant: 32),
            mutualsSectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mutualsSectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mutualsSectionView.heightAnchor.constraint(equalToConstant: 110),
            mutualsSectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            
            mutualGroupsView.bottomAnchor.constraint(equalTo: mutualsSectionView.bottomAnchor)
        ])
    }
    
    private func setupMutualRow(parentView: UIView, rowView: UIView, icon: String, text: String, topAnchor: NSLayoutYAxisAnchor) {
        // Container view
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.backgroundColor = .clear
        parentView.addSubview(rowView)
        
        // Icon
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .white
        if let iconImage = UIImage(systemName: icon) {
            iconView.image = iconImage
        }
        rowView.addSubview(iconView)
        
        // Text label
        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.text = text
        textLabel.font = UIFont.systemFont(ofSize: 16)
        textLabel.textColor = .white
        rowView.addSubview(textLabel)
        
        // Chevron icon
        let chevronView = UIImageView()
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.image = UIImage(systemName: "chevron.right")
        chevronView.tintColor = UIColor.lightGray
        rowView.addSubview(chevronView)
        
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            rowView.topAnchor.constraint(equalTo: topAnchor),
            rowView.heightAnchor.constraint(equalToConstant: 55),
            
            iconView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            textLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            textLabel.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            
            chevronView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -16),
            chevronView.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(mutualRowTapped))
        rowView.addGestureRecognizer(tapGesture)
        rowView.isUserInteractionEnabled = true
    }
    
    // MARK: - Actions
    @objc private func messageButtonTapped() {
        dismiss(animated: true) {
            // Handle message action
            print("Message user: \(self.userId)")
        }
    }
    
    @objc private func unfriendButtonTapped() {
        dismiss(animated: true) {
            // Handle unfriend action
            print("Unfriend user: \(self.userId)")
        }
    }
    
    @objc private func addFriendButtonTapped() {
        dismiss(animated: true) {
            // Handle add friend action
            print("Add friend: \(self.userId)")
        }
    }
    
    @objc private func acceptFriendButtonTapped() {
        dismiss(animated: true) {
            // Handle accept friend request
            print("Accept friend request: \(self.userId)")
        }
    }
    
    @objc private func cancelRequestButtonTapped() {
        dismiss(animated: true) {
            // Handle cancel friend request
            print("Cancel friend request: \(self.userId)")
        }
    }
    
    @objc private func blockButtonTapped() {
        dismiss(animated: true) {
            // Handle block user
            print("Block user: \(self.userId)")
        }
    }
    
    @objc private func unblockButtonTapped() {
        dismiss(animated: true) {
            // Handle unblock user
            print("Unblock user: \(self.userId)")
        }
    }
    
    @objc private func reportButtonTapped() {
        let alert = UIAlertController(
            title: "Report User",
            message: "What would you like to report about this user?",
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Inappropriate Content", style: .default) { _ in
            self.dismiss(animated: true)
        })
        
        alert.addAction(UIAlertAction(title: "Harassment", style: .default) { _ in
            self.dismiss(animated: true)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    @objc private func mutualRowTapped(_ sender: UITapGestureRecognizer) {
        if sender.view == mutualFriendsView {
            print("Show mutual friends")
        } else if sender.view == mutualGroupsView {
            print("Show mutual groups")
        }
    }
    
    // MARK: - Data Fetching
    private func fetchMutualData() {
        guard let viewState = viewState, !userId.isEmpty else { return }
        
        // Check if we're not the current user
        if userId != viewState.currentUser?.id {
            Task {
                if let mutuals = try? await viewState.http.fetchMutuals(user: userId).get() {
                    // Update counts
                    let friendsCount = mutuals.users.count
                    let serversCount = mutuals.servers.count
                    
                    // Find mutual groups
                    let commonGroups = findCommonGroupDMChannels(
                        channels: viewState.dms,
                        currentUserId: viewState.currentUser?.id,
                        otherUserId: userId
                    )
                    let groupsCount = commonGroups.count
                    
                    // Update on main thread
                    DispatchQueue.main.async {
                        self.updateMutualUI(friendsCount: friendsCount, groupsCount: groupsCount)
                    }
                }
            }
        }
    }
    
    private func fetchProfileData() {
        guard let viewState = viewState, !userId.isEmpty else { return }
        
        Task {
            if let profile = try? await viewState.http.fetchProfile(user: userId).get() {
                DispatchQueue.main.async {
                    self.profile = profile
                    // You could update UI with profile data here if needed
                }
            }
        }
    }
    
    private func updateMutualUI(friendsCount: Int, groupsCount: Int) {
        // Update the mutual friends count
        for subview in mutualFriendsView.subviews {
            if let label = subview as? UILabel {
                let text = friendsCount == 1 ? "1 Mutual Friend" : "\(friendsCount) Mutual Friends"
                label.text = text
            }
        }
        
        // Update the mutual groups count
        for subview in mutualGroupsView.subviews {
            if let label = subview as? UILabel {
                let text = groupsCount == 1 ? "1 Mutual Group" : "\(groupsCount) Mutual Groups"
                label.text = text
            }
        }
        
        // Store the counts
        self.mutualFriendsCount = friendsCount
        self.mutualGroupsCount = groupsCount
    }
    
    private func findCommonGroupDMChannels(channels: [Channel], currentUserId: String?, otherUserId: String?) -> [GroupDMChannel] {
        guard let currentUserId = currentUserId, let otherUserId = otherUserId else {
            return []
        }
        
        return channels.compactMap { channel in
            if case let .group_dm_channel(groupChannel) = channel {
                let recipients = groupChannel.recipients
                if recipients.contains(currentUserId) && recipients.contains(otherUserId) {
                    return groupChannel
                }
            }
            return nil
        }
    }
}

// Usage Example:
// let sheetVC = UserSheetViewController(displayName: user.display_name ?? "", role: roleName, avatar: avatarURL, userId: user.id, viewState: viewState)
// present(sheetVC, animated: true) 
