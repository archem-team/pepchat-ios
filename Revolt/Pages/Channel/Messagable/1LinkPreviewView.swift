//
//  LinkPreviewView.swift
//  Revolt
//
//  Created by Assistant on $(date).
//

import UIKit
import Types
import Kingfisher
import WebKit

/// A UIView that renders different types of message embeds, such as website previews, images, videos, and text embeds.
class LinkPreviewView: UIView {
    
    // MARK: - UI Components
    private let containerView = UIView()
    private let leftBorderView = UIView()
    private let contentStackView = UIStackView()
    
    // Header components
    private let headerStackView = UIStackView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    
    // Content components  
    private let descriptionLabel = UILabel()
    private let previewImageView = UIImageView()
    private let videoView = UIView()
    private var webView: WKWebView?
    
    // MARK: - Properties
    private var embed: Embed = .none
    private var viewState: ViewState?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = .clear
        
        // Container view
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor(named: "bgGray12") ?? .systemGray6
        containerView.layer.cornerRadius = 8
        containerView.clipsToBounds = true
        addSubview(containerView)
        
        // Left border view  
        leftBorderView.translatesAutoresizingMaskIntoConstraints = false
        leftBorderView.backgroundColor = UIColor(named: "bgGray10") ?? .systemGray4
        containerView.addSubview(leftBorderView)
        
        // Content stack view
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.spacing = 0
        contentStackView.alignment = .leading
        containerView.addSubview(contentStackView)
        
        // Header stack view
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.axis = .horizontal
        headerStackView.spacing = 8
        headerStackView.alignment = .top
        
        // Icon image view
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 4
        
        // Title label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = UIColor(named: "textDefaultGray01") ?? .label
        titleLabel.numberOfLines = 2
        
        // Description label
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        descriptionLabel.textColor = UIColor(named: "textGray06") ?? .secondaryLabel
        descriptionLabel.numberOfLines = 3
        
        // Preview image view
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.layer.cornerRadius = 6
        previewImageView.isHidden = true
        
        // Setup constraints
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Left border
            leftBorderView.topAnchor.constraint(equalTo: containerView.topAnchor),
            leftBorderView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            leftBorderView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            leftBorderView.widthAnchor.constraint(equalToConstant: 3),
            
            // Content stack view
            contentStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            contentStackView.leadingAnchor.constraint(equalTo: leftBorderView.trailingAnchor, constant: 8),
            contentStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            contentStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            
            // Icon image view
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),
            
            // Preview image view
            previewImageView.heightAnchor.constraint(equalToConstant: 200),
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with embed: Embed, viewState: ViewState) {
        self.embed = embed
        self.viewState = viewState
        
        // Clear previous content
        clearContent()
        
        switch embed {
        case .website(let websiteEmbed):
            configureWebsiteEmbed(websiteEmbed)
        case .image(let imageEmbed):
            configureImageEmbed(imageEmbed)
        case .video(let videoEmbed):
            configureVideoEmbed(videoEmbed)
        case .text(let textEmbed):
            configureTextEmbed(textEmbed)
        case .none:
            isHidden = true
        }
    }
    
    private func clearContent() {
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        headerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        previewImageView.image = nil
        previewImageView.isHidden = true
        webView?.removeFromSuperview()
        webView = nil
        isHidden = false
    }
    
    // MARK: - Website Embed Configuration
    
    private func configureWebsiteEmbed(_ websiteEmbed: WebsiteEmbed) {
        var hasContent = false
        
        // Setup header with icon and title
        if let iconUrl = websiteEmbed.icon_url, let url = URL(string: iconUrl) {
            headerStackView.addArrangedSubview(iconImageView)
            iconImageView.kf.setImage(with: url, placeholder: UIImage(systemName: "globe"))
            hasContent = true
        }
        
        if let title = websiteEmbed.title, !title.isEmpty {
            titleLabel.text = title
            headerStackView.addArrangedSubview(titleLabel)
            hasContent = true
        }
        
        if hasContent {
            contentStackView.addArrangedSubview(headerStackView)
            contentStackView.setCustomSpacing(8, after: headerStackView)
        }
        
        // Description
        if let description = websiteEmbed.description, !description.isEmpty {
            descriptionLabel.text = description
            contentStackView.addArrangedSubview(descriptionLabel)
            contentStackView.setCustomSpacing(8, after: descriptionLabel)
        }
        
        // Handle special embeds (YouTube, Spotify, etc.)
        if let special = websiteEmbed.special, special != .none {
            configureSpecialEmbed(websiteEmbed, special: special)
        }
        // Handle video embeds
        else if let video = websiteEmbed.video {
            configureVideoPreview(video)
        }
        // Handle image embeds
        else if let image = websiteEmbed.image {
            configureImagePreview(image)
        }
    }
    
    // MARK: - Special Embed Configuration
    
    private func configureSpecialEmbed(_ websiteEmbed: WebsiteEmbed, special: WebsiteSpecial) {
        guard let embedUrl = getSpecialEmbedUrl(websiteEmbed, special: special) else { return }
        
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        
        let aspectRatio = getSpecialEmbedAspectRatio(special, websiteEmbed: websiteEmbed)
        
        contentStackView.addArrangedSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),
            webView.heightAnchor.constraint(equalTo: webView.widthAnchor, multiplier: 1.0 / aspectRatio)
        ])
        
        var request = URLRequest(url: embedUrl)
        request.timeoutInterval = 30.0
        request.cachePolicy = .returnCacheDataElseLoad
        webView.load(request)
        self.webView = webView
    }
    
    private func getSpecialEmbedUrl(_ websiteEmbed: WebsiteEmbed, special: WebsiteSpecial) -> URL? {
        let urlString: String?
        
        switch special {
        case .youtube(let special):
            let timestamp = special.timestamp != nil ? "&start=\(special.timestamp!)" : ""
            urlString = "https://www.youtube-nocookie.com/embed/\(special.id)?modestbranding=1\(timestamp)"
        case .twitch(let special):
            urlString = "https://player.twitch.tv/?\(special.content_type.rawValue.lowercased())=\(special.id)&autoplay=false"
        case .lightspeed(let special):
            urlString = "https://new.lightspeed.tv/embed/\(special.id)/stream"
        case .spotify(let special):
            urlString = "https://open.spotify.com/embed/\(special.content_type)/\(special.id)"
        case .soundcloud:
            guard let url = websiteEmbed.url?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
            urlString = "https://w.soundcloud.com/player/?url=\(url)&color=%23FF7F50&auto_play=false&hide_related=false&show_comments=true&show_user=true&show_reposts=false&show_teaser=true&visual=true"
        case .bandcamp(let special):
            urlString = "https://bandcamp.com/EmbeddedPlayer/\(special.content_type.rawValue.lowercased())=\(special.id)/size=large/bgcol=181a1b/linkcol=056cc4/tracklist=false/transparent=true/"
        case .streamable(let special):
            urlString = "https://streamable.com/e/\(special.id)?loop=0"
        default:
            urlString = nil
        }
        
        return urlString.flatMap { URL(string: $0) }
    }
    
    private func getSpecialEmbedAspectRatio(_ special: WebsiteSpecial, websiteEmbed: WebsiteEmbed) -> CGFloat {
        switch special {
        case .youtube:
            return CGFloat(websiteEmbed.video?.width ?? 16) / CGFloat(websiteEmbed.video?.height ?? 9)
        case .lightspeed, .twitch:
            return 16.0 / 9.0
        case .spotify(let special):
            switch special.content_type {
            case "artist", "playlist":
                return 400.0 / 200.0
            default:
                return 400.0 / 105.0
            }
        case .soundcloud:
            return 480.0 / 460.0
        case .bandcamp:
            return CGFloat(websiteEmbed.video?.width ?? 16) / CGFloat(websiteEmbed.video?.height ?? 9)
        default:
            return 16.0 / 9.0
        }
    }
    
    // MARK: - Image/Video Preview Configuration
    
    private func configureImagePreview(_ image: JanuaryImage) {
        guard let url = URL(string: image.url) else { return }
        
        previewImageView.isHidden = false
        previewImageView.kf.setImage(with: url)
        contentStackView.addArrangedSubview(previewImageView)
        
        let aspectRatio = CGFloat(image.width) / CGFloat(image.height)
        
        // Remove existing height constraints
        previewImageView.constraints.forEach { constraint in
            if constraint.firstAttribute == .height {
                previewImageView.removeConstraint(constraint)
            }
        }
        
        NSLayoutConstraint.activate([
            previewImageView.heightAnchor.constraint(equalTo: previewImageView.widthAnchor, multiplier: 1.0 / aspectRatio),
            previewImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
    }
    
    private func configureVideoPreview(_ video: JanuaryVideo) {
        guard let url = URL(string: video.url) else { return }
        
        previewImageView.isHidden = false
        // For video, you might want to show a thumbnail or use AVPlayerLayer
        // For now, we'll treat it like an image
        previewImageView.kf.setImage(with: url)
        contentStackView.addArrangedSubview(previewImageView)
        
        let aspectRatio = CGFloat(video.width) / CGFloat(video.height)
        
        // Remove existing height constraints
        previewImageView.constraints.forEach { constraint in
            if constraint.firstAttribute == .height {
                previewImageView.removeConstraint(constraint)
            }
        }
        
        NSLayoutConstraint.activate([
            previewImageView.heightAnchor.constraint(equalTo: previewImageView.widthAnchor, multiplier: 1.0 / aspectRatio),
            previewImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
    }
    
    // MARK: - Other Embed Types
    
    private func configureImageEmbed(_ imageEmbed: JanuaryImage) {
        configureImagePreview(imageEmbed)
    }
    
    private func configureVideoEmbed(_ videoEmbed: JanuaryVideo) {
        configureVideoPreview(videoEmbed)
    }
    
    private func configureTextEmbed(_ textEmbed: TextEmbed) {
        var hasContent = false
        
        // Setup header with icon and title
        if let iconUrl = textEmbed.icon_url, let url = URL(string: iconUrl) {
            headerStackView.addArrangedSubview(iconImageView)
            iconImageView.kf.setImage(with: url, placeholder: UIImage(systemName: "doc.text"))
            hasContent = true
        }
        
        if let title = textEmbed.title, !title.isEmpty {
            titleLabel.text = title
            headerStackView.addArrangedSubview(titleLabel)
            hasContent = true
        }
        
        if hasContent {
            contentStackView.addArrangedSubview(headerStackView)
            contentStackView.setCustomSpacing(8, after: headerStackView)
        }
        
        // Description
        if let description = textEmbed.description, !description.isEmpty {
            descriptionLabel.text = description
            contentStackView.addArrangedSubview(descriptionLabel)
        }
        
        // Set custom color if available
        if let colour = textEmbed.colour {
            leftBorderView.backgroundColor = parseColor(colour) ?? UIColor(named: "bgGray10")
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseColor(_ colorString: String) -> UIColor? {
        var hexString = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        
        guard hexString.count == 6 else { return nil }
        
        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)
        
        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0
        
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
} 