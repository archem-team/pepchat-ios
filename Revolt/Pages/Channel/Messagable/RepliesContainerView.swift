import UIKit
import Types

// Protocol for the reply item view delegate
protocol ReplyItemViewDelegate: AnyObject {
    func replyItemViewDidPressRemove(_ view: ReplyItemView, replyId: String)
}

// Protocol for the replies container view delegate
protocol RepliesContainerViewDelegate: AnyObject {
    func repliesContainerView(_ view: RepliesContainerView, didRemoveReplyAt id: String)
    func getViewState() -> ViewState
}

// Reply model to hold message and mention state
struct MessageReply {
    let id: String
    let message: Message
    var mention: Bool
    
    init(message: Message, mention: Bool = true) {
        self.id = message.id
        self.message = message
        self.mention = mention
    }
}

// Container view for reply items
class RepliesContainerView: UIView {
    // MARK: - Properties
    
    weak var delegate: RepliesContainerViewDelegate?
    private var stackView: UIStackView!
    private var replyViews: [String: ReplyItemView] = [:]
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = UIColor(named: "bgDefaultPurple13")?.withAlphaComponent(0.95)
        
        // Create stack view for replies
        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(stackView)
        
        // Add constraints
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        
        // Add shadow to make it stand out
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 3
    }
    
    // MARK: - Public Methods
    
    func updateReplies(_ replies: [MessagesReply]) {
        // Clear existing reply views
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        replyViews.removeAll()
        
        // Add new reply views
        for reply in replies {
            let replyView = ReplyItemView(frame: .zero)
            replyView.delegate = self
            replyView.configure(with: reply.message, mention: reply.mention, viewState: delegate?.getViewState())
            stackView.addArrangedSubview(replyView)
            replyViews[reply.id] = replyView
        }
        
        // Update height based on number of replies
        invalidateIntrinsicContentSize()
    }
    
    // MARK: - Layout
    
    override var intrinsicContentSize: CGSize {
        let replyCount = stackView.arrangedSubviews.count
        let height = replyCount > 0 ? CGFloat(replyCount) * 44 + 16 : 0
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }
}

// MARK: - ReplyItemViewDelegate
extension RepliesContainerView: ReplyItemViewDelegate {
    func replyItemViewDidPressRemove(_ view: ReplyItemView, replyId: String) {
        delegate?.repliesContainerView(self, didRemoveReplyAt: replyId)
    }
}

// Individual reply item view
class ReplyItemView: UIView {
    // MARK: - Properties
    
    weak var delegate: ReplyItemViewDelegate?
    private var messageId: String = ""
    
    private let avatarImageView = UIImageView()
    private let usernameLabel = UILabel()
    private let contentLabel = UILabel()
    private let mentionSwitch = UISwitch()
    private let removeButton = UIButton()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = UIColor(named: "bgDefaultPurple15")
        layer.cornerRadius = 8
        clipsToBounds = true
        
        // Avatar image view
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 16
        avatarImageView.clipsToBounds = true
        avatarImageView.backgroundColor = UIColor(named: "bgDefaultPurple17")
        
        // Username label
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        usernameLabel.textColor = .white
        
        // Content label
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.font = UIFont.systemFont(ofSize: 12)
        contentLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        contentLabel.numberOfLines = 1
        
        // Mention switch
        mentionSwitch.translatesAutoresizingMaskIntoConstraints = false
        mentionSwitch.onTintColor = UIColor(named: "accentColor")
        mentionSwitch.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        
        // Remove button
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        
        // Add subviews
        addSubview(avatarImageView)
        addSubview(usernameLabel)
        addSubview(contentLabel)
        addSubview(mentionSwitch)
        addSubview(removeButton)
        
        // Add constraints
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            avatarImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            
            usernameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            usernameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            usernameLabel.trailingAnchor.constraint(lessThanOrEqualTo: mentionSwitch.leadingAnchor, constant: -8),
            
            contentLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            contentLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 2),
            contentLabel.trailingAnchor.constraint(lessThanOrEqualTo: mentionSwitch.leadingAnchor, constant: -8),
            contentLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
            
            mentionSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),
            mentionSwitch.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with message: Message, mention: Bool, viewState: ViewState?) {
        messageId = message.id
        
        // Set up mention switch
        mentionSwitch.isOn = mention
        
        // Get user from viewState
        if let user = viewState?.users[message.author] {
            usernameLabel.text = user.username
            
            // Set avatar if available
            if let avatarURL = user.avatar.flatMap({ URL(string: viewState?.formatUrl(fromId: $0, withTag: "avatars") ?? "") }) {
                URLSession.shared.dataTask(with: avatarURL) { [weak self] data, _, _ in
                    if let data = data, let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            self?.avatarImageView.image = image
                        }
                    }
                }.resume()
            }
        } else {
            usernameLabel.text = ""
        }
        
        // Set content text
        contentLabel.text = message.content ?? "[no content]"
    }
    
    // MARK: - Actions
    
    @objc private func removeButtonTapped() {
        delegate?.replyItemViewDidPressRemove(self, replyId: messageId)
    }
} 