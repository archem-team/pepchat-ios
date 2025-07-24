//
//  MentionInputView.swift
//  Revolt
//

import UIKit
import Types
import Kingfisher

// MARK: - Performance optimizations
private class UserCache {
    static let shared = UserCache()
    private var cachedUsers: [String: [(User, Member?)]] = [:]
    private var lastCacheTime: [String: Date] = [:]
    private let cacheTimeout: TimeInterval = 120 // 2 minutes - shorter timeout for better data freshness
    
    func getCachedUsers(for channelId: String) -> [(User, Member?)]? {
        guard let lastTime = lastCacheTime[channelId],
              Date().timeIntervalSince(lastTime) < cacheTimeout else {
            return nil
        }
        return cachedUsers[channelId]
    }
    
    func setCachedUsers(_ users: [(User, Member?)], for channelId: String) {
        cachedUsers[channelId] = users
        lastCacheTime[channelId] = Date()
    }
    
    func clearCache() {
        cachedUsers.removeAll()
        lastCacheTime.removeAll()
    }
}

protocol MentionInputViewDelegate: AnyObject {
    func mentionInputView(_ mentionView: MentionInputView, didSelectUser user: User, member: Member?)
    func mentionInputViewDidDismiss(_ mentionView: MentionInputView)
}

class MentionInputView: UIView {
    // MARK: - Properties
    private let tableView = UITableView()
    private let emptyStateLabel = UILabel()
    private let containerView = UIView()
    
    private var users: [(User, Member?)] = []
    private var filteredUsers: [(User, Member?)] = []
    private var searchText: String = ""
    
    weak var delegate: MentionInputViewDelegate?
    private var viewState: ViewState
    private var currentServer: Server?
    private var currentChannel: Channel?
    
    // Performance optimization: Only load users when needed
    private var usersLoaded = false
    private var isSearching = false
    
    // Debouncing for search
    private var searchWorkItem: DispatchWorkItem?
    
    // MARK: - Initialization
    init(viewState: ViewState) {
        self.viewState = viewState
        
        super.init(frame: .zero)
        
        // CRITICAL FIX: Set translatesAutoresizingMaskIntoConstraints to false
        translatesAutoresizingMaskIntoConstraints = false
        
        // Set clean background
        backgroundColor = UIColor.clear
        layer.cornerRadius = 12
        clipsToBounds = false
        
        // Add shadow for depth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.15
        
        // Ensure the view is displayed above everything
        layer.zPosition = 10000
        
        // Ensure the view is visible but initially transparent
        alpha = 0
        isHidden = true // Start hidden to avoid constraint conflicts
        
        setupViews()
        setupConstraints()
        
        // Don't load users immediately - wait for first search
        
        // Add a debug border to help with visualization
        // print("DEBUG: MentionInputView initialized with frame: \(frame)")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Methods
    func configure(channel: Channel?, server: Server?) {
        currentChannel = channel
        currentServer = server
        // Reset state when channel changes
        usersLoaded = false
        users.removeAll()
        filteredUsers.removeAll()
        searchText = ""
        
        // Hide the view until user starts typing @
        hidePopup()
    }
    
    func updateSearch(text: String) {
        print("DEBUG: MentionInputView.updateSearch called with text: '\(text)'")
        
        // Cancel previous search
        searchWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            print("DEBUG: Executing search workItem for text: '\(text)'")
            self?.performSearch(text: text)
        }
        
        searchWorkItem = workItem
        
        // Debounce search by 300ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    private func performSearch(text: String) {
        searchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("DEBUG: performSearch called with text: '\(text)', searchText: '\(searchText)'")
        print("DEBUG: usersLoaded: \(usersLoaded), total users loaded: \(users.count)")
        
        // Only load users when we actually need to search
        if !usersLoaded {
            print("DEBUG: Users not loaded, loading lazily...")
            loadUsersLazily()
        }
        
        filterUsers()
        // Note: showPopup() will be called from filterUsers() async block after UI updates
    }
    
    func reloadUsers() {
        // Clear cache and reload
        if let channelId = currentChannel?.id {
            UserCache.shared.clearCache()
        }
        usersLoaded = false
        loadUsersLazily()
    }
    
    // MARK: - Popup window functionality
    var popupWindow: UIWindow?
    private var heightConstraint: NSLayoutConstraint?
    
    private func showAsPopup() {
        guard filteredUsers.count > 0 else { 
            print("DEBUG: showAsPopup called but no filtered users, hiding instead")
            hidePopup()
            return 
        }
        
        // If already visible, just update the height
        if popupWindow != nil { 
            print("DEBUG: Popup already visible, updating height for \(filteredUsers.count) users")
            updatePopupHeight()
            return 
        }
        
        // Create window for the popup
        let window: UIWindow
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .first as? UIWindowScene {
                window = UIWindow(windowScene: windowScene)
            } else {
                window = UIWindow(frame: UIScreen.main.bounds)
            }
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        
        window.windowLevel = .alert
        window.backgroundColor = .clear
        window.isHidden = false
        
        // Create container for the mention view
        let containerViewController = UIViewController()
        containerViewController.view.backgroundColor = .clear
        
        // Make sure view is not hidden and properly configured
        self.isHidden = false
        self.translatesAutoresizingMaskIntoConstraints = false
        
        // Add this view to the container
        containerViewController.view.addSubview(self)
        
        // Calculate better height: maximum 8 users displayed for better UX  
        let maxVisibleUsers = min(filteredUsers.count, 8)
        let minHeight: CGFloat = 64 // Minimum height for 1 user
        let mentionHeight: CGFloat = max(minHeight, CGFloat(maxVisibleUsers * 48) + 16) // 8px padding top and bottom
        let margin: CGFloat = 20
        
        print("DEBUG: Creating new popup with height \(mentionHeight) for \(filteredUsers.count) users (maxVisible: \(maxVisibleUsers))")
        
        // Create height constraint and store it for later updates
        heightConstraint = self.heightAnchor.constraint(equalToConstant: mentionHeight)
        
        // Find actual MessageInputView position
        if let messageInputView = findMessageInputView() {
            print("DEBUG: Found MessageInputView, using its position")
            
            // Convert MessageInputView position to window coordinate system
            let inputFrame = messageInputView.convert(messageInputView.bounds, to: nil)
            print("DEBUG: MessageInputView frame in window: \(inputFrame)")
            
            NSLayoutConstraint.activate([
                self.leadingAnchor.constraint(equalTo: containerViewController.view.leadingAnchor, constant: margin),
                self.trailingAnchor.constraint(equalTo: containerViewController.view.trailingAnchor, constant: -margin),
                // Box position: above input field with 10px spacing
                self.bottomAnchor.constraint(equalTo: containerViewController.view.topAnchor, constant: inputFrame.minY - 10),
                heightConstraint!
            ])
        } else {
            print("DEBUG: Could not find MessageInputView, using keyboard-based positioning")
            
            // Fallback: use keyboard position
            let keyboardHeight: CGFloat = KeyboardHeightObserver.shared.currentKeyboardHeight > 0 ? 
                KeyboardHeightObserver.shared.currentKeyboardHeight : 300
            
            // Assume input field is about 60px height and 20px from bottom of keyboard
            let inputFieldHeight: CGFloat = 60
            let inputFieldBottomMargin: CGFloat = 20
            
            NSLayoutConstraint.activate([
                self.leadingAnchor.constraint(equalTo: containerViewController.view.leadingAnchor, constant: margin),
                self.trailingAnchor.constraint(equalTo: containerViewController.view.trailingAnchor, constant: -margin),
                // Box position: above input field with 10px spacing
                self.bottomAnchor.constraint(equalTo: containerViewController.view.bottomAnchor, constant: -(keyboardHeight + inputFieldBottomMargin + inputFieldHeight + 10)),
                heightConstraint!
            ])
        }
        
        window.rootViewController = containerViewController
        popupWindow = window
        
        // Animate in
        self.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1
        }
    }
    
    private func updatePopupHeight() {
        guard let heightConstraint = heightConstraint else { return }
        
        // Calculate new height based on current filtered users
        let maxVisibleUsers = min(filteredUsers.count, 8)
        let minHeight: CGFloat = 64 // Minimum height for 1 user
        let newHeight: CGFloat = max(minHeight, CGFloat(maxVisibleUsers * 48) + 16) // 8px padding top and bottom
        
        print("DEBUG: Updating popup height from \(heightConstraint.constant) to \(newHeight) for \(filteredUsers.count) users (maxVisible: \(maxVisibleUsers))")
        
        // Only animate if height actually changes
        if abs(heightConstraint.constant - newHeight) > 1.0 {
            heightConstraint.constant = newHeight
            
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: [.curveEaseInOut], animations: {
                self.layoutIfNeeded()
            }, completion: nil)
        }
    }
    
    func hidePopup() {
        guard let window = popupWindow else { return }
        
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }) { _ in
            window.isHidden = true
            self.popupWindow = nil
            self.heightConstraint = nil // Clear height constraint reference
            self.removeFromSuperview()
            self.isHidden = true
        }
    }
    
    // MARK: - Private Methods
    private func setupViews() {
        // Setup container view with modern styling
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.systemBackground
        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = true // Changed to true to prevent overflow
        
        // Add subtle modern border
        containerView.layer.borderWidth = 0.5
        containerView.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor
        
        // Add subtle shadow for depth
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowRadius = 8
        
        addSubview(containerView)
        
        // Setup table view with clean styling
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = UIColor.clear
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor.separator.withAlphaComponent(0.2)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.showsVerticalScrollIndicator = true
        tableView.bounces = true
        tableView.alwaysBounceVertical = false // Only bounce when content is larger than screen
        tableView.rowHeight = 48
        tableView.estimatedRowHeight = 48
        tableView.layer.cornerRadius = 8
        tableView.clipsToBounds = true
        tableView.contentInset = .zero
        tableView.scrollIndicatorInsets = .zero
        tableView.register(MentionUserCell.self, forCellReuseIdentifier: "MentionUserCell")
        containerView.addSubview(tableView)
        
        // Setup empty state label
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.text = "No users found"
        emptyStateLabel.textColor = UIColor.secondaryLabel
        emptyStateLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.isHidden = true
        containerView.addSubview(emptyStateLabel)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Container fills the entire view
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Table view with small padding inside container
            tableView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            
            // Empty state label centered
            emptyStateLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20)
        ])
    }
    
    // MARK: - Optimized User Loading
    private func loadUsersLazily() {
        guard let channel = currentChannel else { 
            print("DEBUG: loadUsersLazily - currentChannel is nil!")
            return 
        }
        
        print("DEBUG: loadUsersLazily called for channel: \(channel.id)")
        
        // Check cache first
        if let cachedUsers = UserCache.shared.getCachedUsers(for: channel.id) {
            print("DEBUG: Found \(cachedUsers.count) cached users")
            self.users = cachedUsers
            self.usersLoaded = true
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
            return
        }
        
        print("DEBUG: No cached users found, loading fresh...")
        
        // Load users based on channel type with performance optimizations
        var loadedUsers: [(User, Member?)] = []
        
        switch channel {
        case .saved_messages(_):
            if let currentUser = viewState.currentUser {
                loadedUsers = [(currentUser, nil)]
            }
            
        case .dm_channel(let dMChannel):
            loadedUsers = dMChannel.recipients.compactMap { userId in
                if let user = viewState.users[userId] {
                    return (user, nil)
                }
                return nil
            }
            
        case .group_dm_channel(let groupDMChannel):
            loadedUsers = groupDMChannel.recipients.compactMap { userId in
                if let user = viewState.users[userId] {
                    return (user, nil)
                }
                return nil
            }
            
        case .text_channel(_), .voice_channel(_):
            if let server = currentServer {
                let memberDict = viewState.members[server.id] ?? [:]
                
                print("DEBUG: Server \(server.name) memberDict has \(memberDict.count) entries")
                
                // Load ALL members instead of limiting to 200 for better search results
                loadedUsers = memberDict.values.compactMap { member in
                    if let user = viewState.users[member.id.user] {
                        return (user, member)
                    }
                    return nil
                }
                
                print("DEBUG: Successfully mapped \(loadedUsers.count) users from \(memberDict.count) members")
                
                // Sort by recent activity or alphabetically for better UX
                loadedUsers.sort { (user1, user2) in
                    let name1 = user1.1?.nickname ?? user1.0.display_name ?? user1.0.username
                    let name2 = user2.1?.nickname ?? user2.0.display_name ?? user2.0.username
                    return name1.lowercased() < name2.lowercased()
                }
            }
            
        default:
            break
        }
        
        self.users = loadedUsers
        self.usersLoaded = true
        
        print("DEBUG: Loaded \(loadedUsers.count) users for channel \(channel.id)")
        if let server = currentServer {
            print("DEBUG: Server \(server.name) has \(viewState.members[server.id]?.count ?? 0) total members")
        }
        
        // Cache the results
        UserCache.shared.setCachedUsers(loadedUsers, for: channel.id)
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    private func filterUsers() {
        if searchText.isEmpty {
            filteredUsers = Array(users.prefix(50)) // Show max 50 users when no search
        } else {
            let searchLower = searchText.lowercased()
            
            // PERFORMANCE: Use more efficient filtering with better matching
            var priorityMatches: [(User, Member?)] = []
            var secondaryMatches: [(User, Member?)] = []
            
            for (user, member) in users {
                let username = user.username.lowercased()
                let displayName = user.display_name?.lowercased() ?? ""
                let nickname = member?.nickname?.lowercased() ?? ""
                
                // Check if search term matches the beginning of any name (highest priority)
                let usernameMatch = username.hasPrefix(searchLower)
                let displayNameMatch = displayName.hasPrefix(searchLower)
                let nicknameMatch = nickname.hasPrefix(searchLower)
                
                if usernameMatch || displayNameMatch || nicknameMatch {
                    priorityMatches.append((user, member))
                    continue
                }
                
                // Also check contains for better UX (lower priority)
                let usernameContains = username.contains(searchLower)
                let displayNameContains = displayName.contains(searchLower)
                let nicknameContains = nickname.contains(searchLower)
                
                if usernameContains || displayNameContains || nicknameContains {
                    secondaryMatches.append((user, member))
                }
            }
            
            // Sort priority matches alphabetically
            priorityMatches.sort { (user1, user2) in
                let name1 = user1.1?.nickname ?? user1.0.display_name ?? user1.0.username
                let name2 = user2.1?.nickname ?? user2.0.display_name ?? user2.0.username
                return name1.lowercased() < name2.lowercased()
            }
            
            // Sort secondary matches alphabetically
            secondaryMatches.sort { (user1, user2) in
                let name1 = user1.1?.nickname ?? user1.0.display_name ?? user1.0.username
                let name2 = user2.1?.nickname ?? user2.0.display_name ?? user2.0.username
                return name1.lowercased() < name2.lowercased()
            }
            
            // Combine priority matches first, then secondary matches
            filteredUsers = priorityMatches + secondaryMatches
            
            print("DEBUG: Search '\(searchText)' found \(priorityMatches.count) priority matches and \(secondaryMatches.count) secondary matches")
            if priorityMatches.count > 0 {
                let sampleNames = priorityMatches.prefix(3).map { user, member in
                    member?.nickname ?? user.display_name ?? user.username
                }
                print("DEBUG: Priority match examples: \(sampleNames.joined(separator: ", "))")
            }
            
            // Debug: Check if the search term "axis" is in results
            if searchText.lowercased().contains("axis") {
                let axisUsers = filteredUsers.filter { user, member in
                    let username = user.username.lowercased()
                    let displayName = user.display_name?.lowercased() ?? ""
                    let nickname = member?.nickname?.lowercased() ?? ""
                    return username.contains("axis") || displayName.contains("axis") || nickname.contains("axis")
                }
                print("DEBUG: Found \(axisUsers.count) users matching 'axis'")
                axisUsers.forEach { user, member in
                    print("DEBUG: - User: \(user.username), Display: \(user.display_name ?? "nil"), Nickname: \(member?.nickname ?? "nil")")
                }
            }
            
            // Limit results for performance - increased limit for better user experience
            filteredUsers = Array(filteredUsers.prefix(50))
        }
        
        print("DEBUG: filteredUsers count after filtering: \(filteredUsers.count)")
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
            self.updateEmptyState()
            
            // Configure bounce behavior based on number of users
            let contentHeight = CGFloat(self.filteredUsers.count * 48)
            let tableHeight = self.tableView.frame.height
            self.tableView.alwaysBounceVertical = contentHeight > tableHeight
            self.tableView.bounces = contentHeight > tableHeight
            
            // Show or hide popup based on filtered results
            if !self.filteredUsers.isEmpty {
                print("DEBUG: Showing/updating popup with \(self.filteredUsers.count) users")
                self.showAsPopup()
            } else {
                print("DEBUG: No filtered users, hiding popup")
                self.hidePopup()
            }
        }
    }
    
    private func updateEmptyState() {
        DispatchQueue.main.async {
            self.emptyStateLabel.isHidden = !self.filteredUsers.isEmpty
            self.tableView.isHidden = self.filteredUsers.isEmpty
        }
    }
    
    private func insertMentionText(for user: User, member: Member?) {
        // print("DEBUG: insertMentionText for user: \(user.username)")
        
        // First try to use the delegate
        if let delegate = delegate {
            // print("DEBUG: Using delegate to insert mention")
            delegate.mentionInputView(self, didSelectUser: user, member: member)
            return
        }
        
        // Fallback: Try to find text view directly
        var inputTextField: UITextView?
        
        for window in UIApplication.shared.windows {
            for view in window.subviews {
                if let found = findTextView(in: view) {
                    inputTextField = found
                    break
                }
            }
            if inputTextField != nil { break }
        }
        
        // Check if we found the text view
        if let textView = inputTextField {
            // print("DEBUG: Found textView - inserting mention")
            
            // Get current text
            let currentText = textView.text ?? ""
            
            // Find the last @ symbol
            if let lastAtIndex = currentText.lastIndex(of: "@") {
                // Get the text from @ to the end
                let startIndex = lastAtIndex
                let endIndex = currentText.endIndex
                let range = startIndex..<endIndex
                
                // Replace the text from @ to the end with the mention
                let newText = currentText.replacingCharacters(in: range, with: "@\(user.username) ")
                textView.text = newText
                
                // Notify delegate about text change
                if let delegate = textView.delegate {
                    delegate.textViewDidChange?(textView)
                }
            } else {
                // No @ found, just append
                textView.text = currentText + " @\(user.username) "
                
                // Notify delegate about text change
                if let delegate = textView.delegate {
                    delegate.textViewDidChange?(textView)
                }
            }
        } else {
            print("ERROR: Could not find textView to insert mention")
        }
    }
    
    // Find MessageInputView in view hierarchy
    private func findMessageInputView() -> UIView? {
        for window in UIApplication.shared.windows {
            if let found = findViewOfType("MessageInputView", in: window) {
                return found
            }
        }
        return nil
    }
    
    // Find view with specific name
    private func findViewOfType(_ typeName: String, in view: UIView) -> UIView? {
        let currentClassName = NSStringFromClass(type(of: view))
        if currentClassName.contains(typeName) {
            return view
        }
        
        for subview in view.subviews {
            if let found = findViewOfType(typeName, in: subview) {
                return found
            }
        }
        
        return nil
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension MentionInputView: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        print("DEBUG: numberOfRowsInSection returning: \(filteredUsers.count)")
        return filteredUsers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "MentionUserCell", for: indexPath) as? MentionUserCell,
              indexPath.row < filteredUsers.count else {
            return UITableViewCell()
        }
        
        let (user, member) = filteredUsers[indexPath.row]
        cell.configure(with: user, member: member, viewState: viewState) { [weak self] selectedUser, selectedMember in
            // print("DEBUG: Cell onSelect called for user: \(selectedUser.username)")
            self?.tableView(tableView, didSelectRowAt: indexPath)
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Prevent excessive bounce
        scrollView.alwaysBounceVertical = false
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Restore bounce behavior
        scrollView.alwaysBounceVertical = false
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard indexPath.row < filteredUsers.count else { return }
        let (user, member) = filteredUsers[indexPath.row]
        
        // print("DEBUG: ==========================================")
        // print("DEBUG: USER SELECTED FROM MENTION LIST")
        // print("DEBUG: ==========================================")
        // print("DEBUG: Selected User Details:")
        // print("DEBUG: - Username: \(user.username)")
        // print("DEBUG: - Display Name: \(user.display_name ?? "nil")")
        // print("DEBUG: - Member Nickname: \(member?.nickname ?? "nil")")
        // print("DEBUG: - User ID: \(user.id)")
        // print("DEBUG: ==========================================")
        
        // Hide the popup window immediately
        popupWindow?.isHidden = true
        popupWindow = nil
        
        // print("DEBUG: User selected from popup: \(user.username)")
        
        // DIRECT IMPLEMENTATION: Insert the mention text directly
        insertMentionText(for: user, member: member)
    }
    
    // Recursive function to find a textView
    private func findTextView(in view: UIView) -> UITextView? {
        // Check if this view is a text view
        if let textView = view as? UITextView {
            return textView
        }
        
        // Check all subviews
        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }
        
        return nil
    }
}

// MARK: - MentionUserCell
class MentionUserCell: UITableViewCell {
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private var user: User?
    private var member: Member?
    private var viewState: ViewState?
    private var onSelect: ((User, Member?) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        backgroundColor = UIColor.clear
        selectionStyle = .none
        
        // Create modern selected background view with subtle highlight
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = UIColor.systemFill.withAlphaComponent(0.3)
        selectedBackgroundView.layer.cornerRadius = 8
        self.selectedBackgroundView = selectedBackgroundView
        
        // Configure avatar image view
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 16
        contentView.addSubview(avatarImageView)
        
        // Configure name label with modern styling
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        nameLabel.textColor = UIColor.label
        contentView.addSubview(nameLabel)
        
        // Configure username label with subtle secondary text
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        usernameLabel.textColor = UIColor.secondaryLabel
        contentView.addSubview(usernameLabel)
        
        // Setup constraints with proper spacing
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            usernameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            usernameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            usernameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tapGesture)
        contentView.isUserInteractionEnabled = true
    }
    
    @objc private func handleTap() {
                    // print("DEBUG: Cell tapped for user: \(user?.username ?? "unknown")")
        if let user = user {
            onSelect?(user, member)
        }
    }
    
    func configure(with user: User, member: Member?, viewState: ViewState, onSelect: @escaping (User, Member?) -> Void) {
        self.user = user
        self.member = member
        self.viewState = viewState
        self.onSelect = onSelect
        
        // Set username and display name
        nameLabel.text = member?.nickname ?? user.display_name ?? user.username
        usernameLabel.text = user.usernameWithDiscriminator()
        
        // Set avatar image
        let avatarInfo = viewState.resolveAvatarUrl(user: user, member: member, masquerade: nil)
        if avatarInfo.isAvatarSet {
            avatarImageView.kf.setImage(with: avatarInfo.url)
        } else {
            // Set default avatar if none is available
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = UIColor(named: "iconGray07")
        }
    }
}

// MARK: - UIView Extension for finding views
extension UIView {
    func recursiveSearchForView(ofType typeName: String) -> UIView? {
        // Check if the current view's class name contains the type name
        let currentClassName = NSStringFromClass(type(of: self))
        if currentClassName.contains(typeName) {
            return self
        }
        
        // Check all subviews recursively
        for subview in subviews {
            if let foundView = subview.recursiveSearchForView(ofType: typeName) {
                return foundView
            }
        }
        
        return nil
    }
}

// MARK: - Keyboard Height Observer
class KeyboardHeightObserver: NSObject {
    static let shared = KeyboardHeightObserver()
    
    var currentKeyboardHeight: CGFloat = 0
    
    override init() {
        super.init()
        setupKeyboardObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            currentKeyboardHeight = keyboardFrame.height
            // print("DEBUG: KeyboardObserver updated height to \(currentKeyboardHeight)")
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        currentKeyboardHeight = 0
    }
}

// Extension to add helper to UIViewController
extension UIViewController {
    static var keyboardHeightObserver: KeyboardHeightObserver? {
        return KeyboardHeightObserver.shared
    }
}

