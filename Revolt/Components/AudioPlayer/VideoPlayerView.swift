//
//  VideoPlayerView.swift
//  Revolt
//
//

import UIKit
import AVFoundation
import AVKit
import Kingfisher

// MARK: - VideoPlayerView
class VideoPlayerView: UIView {
    
    // MARK: - UI Components
    private let containerView = UIView()
    private let thumbnailImageView = UIImageView()
    private let playButton = UIButton(type: .custom)
    private let downloadButton = UIButton(type: .custom)
    private let durationLabel = UILabel()
    private let titleLabel = UILabel()
    private let fileSizeLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    
    // MARK: - Properties
    private var videoURL: String?
    private var filename: String?
    private var fileSize: Int64?
    private var authHeaders: [String: String] = [:]
    private var isDownloading = false
    private var videoAsset: AVAsset?
    private var assetLoadingTask: Task<Void, Never>?
    
    // Static cache for thumbnails with LRU tracking
    private static var thumbnailCache: [String: UIImage] = [:]
    private static var thumbnailCacheAccessOrder: [String] = [] // LRU tracking
    private static let maxThumbnailCacheEntries = 50
    
    // Static cache for durations with LRU tracking
    private static var durationCache: [String: TimeInterval] = [:]
    private static var durationCacheAccessOrder: [String] = [] // LRU tracking
    private static let maxDurationCacheEntries = 100
    
    /// Clear caches on memory warnings
    static func clearCachesOnMemoryWarning() {
        thumbnailCache.removeAll()
        thumbnailCacheAccessOrder.removeAll()
        durationCache.removeAll()
        durationCacheAccessOrder.removeAll()
    }
    
    // Callback for when play button is tapped
    var onPlayTapped: ((String) -> Void)?
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    deinit {
        // AVAsset cleanup: Release videoAsset and cancel loading operations
        assetLoadingTask?.cancel()
        videoAsset = nil
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = .clear
        
        // Container with rounded background
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.3)
        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = true
        containerView.isUserInteractionEnabled = true // Ensure it's interactive
        addSubview(containerView)
        
        // Thumbnail image view
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.backgroundColor = UIColor.black
        thumbnailImageView.layer.cornerRadius = 8
        containerView.addSubview(thumbnailImageView)
        
        // Play button overlay
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        playButton.tintColor = UIColor.white
        playButton.imageView?.contentMode = .scaleAspectFit
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        playButton.isUserInteractionEnabled = true // Ensure it's interactive
        
        // Add shadow to play button for better visibility
        playButton.layer.shadowColor = UIColor.black.cgColor
        playButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        playButton.layer.shadowRadius = 4
        playButton.layer.shadowOpacity = 0.5
        
        containerView.addSubview(playButton)
        
        // Download button (top right of thumbnail)
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
        downloadButton.tintColor = UIColor.white
        downloadButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        downloadButton.layer.cornerRadius = 15
        downloadButton.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
        
        // Add shadow to download button for better visibility
        downloadButton.layer.shadowColor = UIColor.black.cgColor
        downloadButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        downloadButton.layer.shadowRadius = 4
        downloadButton.layer.shadowOpacity = 0.5
        
        containerView.addSubview(downloadButton)
        
        // Duration label (bottom right of thumbnail)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = UIColor.white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        durationLabel.layer.cornerRadius = 4
        durationLabel.clipsToBounds = true
        durationLabel.textAlignment = .center
        durationLabel.text = "0:00"
        containerView.addSubview(durationLabel)
        
        // Title label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor.label
        titleLabel.text = "Video File"
        titleLabel.textAlignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
        containerView.addSubview(titleLabel)
        
        // File size label
        fileSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        fileSizeLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        fileSizeLabel.textColor = UIColor.secondaryLabel
        fileSizeLabel.text = ""
        fileSizeLabel.textAlignment = .left
        containerView.addSubview(fileSizeLabel)
        
        // Loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = UIColor.white
        containerView.addSubview(loadingIndicator)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Container
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 200), // Fixed height for video preview
            
            // Thumbnail - takes up top portion
            thumbnailImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            thumbnailImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            thumbnailImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 140),
            
            // Play button - centered on thumbnail
            playButton.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 60),
            playButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Loading indicator - same position as play button
            loadingIndicator.centerXAnchor.constraint(equalTo: playButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            
            // Download button - top right of thumbnail
            downloadButton.topAnchor.constraint(equalTo: thumbnailImageView.topAnchor, constant: 8),
            downloadButton.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: -8),
            downloadButton.widthAnchor.constraint(equalToConstant: 30),
            downloadButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Duration label - bottom right of thumbnail with padding
            durationLabel.bottomAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: -4),
            durationLabel.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: -4),
            durationLabel.heightAnchor.constraint(equalToConstant: 18),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 35),
            
            // Title label - below thumbnail
            titleLabel.topAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            
            // File size label - below title
            fileSizeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            fileSizeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            fileSizeLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            fileSizeLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -8)
        ])
        
        // Add padding to duration label
        durationLabel.layoutMargins = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    }
    
    // MARK: - Public Methods
    func configure(with videoURL: String, filename: String? = nil, fileSize: Int64? = nil, headers: [String: String] = [:]) {
        print("🎬 VideoPlayerView.configure called with:")
        print("  URL: \(videoURL)")
        print("  Filename: \(filename ?? "nil")")
        print("  FileSize: \(fileSize ?? 0)")
        print("  Headers: \(headers.keys.joined(separator: ", "))")
        
        self.videoURL = videoURL
        self.filename = filename
        self.fileSize = fileSize
        self.authHeaders = headers
        
        // Reset UI state
        thumbnailImageView.image = nil
        durationLabel.text = "0:00"
        playButton.isHidden = true
        loadingIndicator.startAnimating()
        
        // Set filename
        let fileName = filename ?? extractFileName(from: videoURL)
        titleLabel.text = fileName
        
        // Set file size
        if let fileSize = fileSize, fileSize > 0 {
            fileSizeLabel.text = formatFileSize(fileSize)
        } else {
            fileSizeLabel.text = ""
        }
        
        // Generate thumbnail and get duration
        generateThumbnail(from: videoURL)
    }
    
    // MARK: - Actions
    @objc private func downloadButtonTapped() {
        guard let videoURL = videoURL else {
            showAlert(title: "Error", message: "No video URL available for download")
            return
        }
        
        guard !isDownloading else {
            showAlert(title: "Download", message: "Download is already in progress")
            return
        }
        
        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        startVideoDownload()
    }
    
    @objc private func playButtonTapped() {
        print("🎬 Play button tapped")
        
        guard let videoURL = videoURL else {
            print("❌ No video URL available")
            return
        }
        
        print("🎬 Video URL: \(videoURL)")
        
        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Animate button press and add visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.playButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.playButton.alpha = 0.7
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.playButton.transform = .identity
                self.playButton.alpha = 1.0
            }
        }
        
        // Call the callback to handle video playback
        if let callback = onPlayTapped {
            print("🎬 Calling onPlayTapped callback...")
            callback(videoURL)
        } else {
            print("❌ No onPlayTapped callback set!")
        }
    }
    
    // MARK: - Helper Methods
    private func generateThumbnail(from urlString: String) {
        print("🎬 generateThumbnail called with: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ Failed to create URL from: \(urlString)")
            loadingIndicator.stopAnimating()
            playButton.isHidden = false
            return
        }
        
        // Check cache first
        if let cachedThumbnail = VideoPlayerView.thumbnailCache[urlString] {
            print("✅ Using cached thumbnail")
            thumbnailImageView.image = cachedThumbnail
            thumbnailImageView.contentMode = .scaleAspectFill
            
            // Update LRU access order (move to end = most recently used)
            if let index = VideoPlayerView.thumbnailCacheAccessOrder.firstIndex(of: urlString) {
                VideoPlayerView.thumbnailCacheAccessOrder.remove(at: index)
            }
            VideoPlayerView.thumbnailCacheAccessOrder.append(urlString)
            
            if let cachedDuration = VideoPlayerView.durationCache[urlString] {
                // Update LRU access order for duration cache
                if let index = VideoPlayerView.durationCacheAccessOrder.firstIndex(of: urlString) {
                    VideoPlayerView.durationCacheAccessOrder.remove(at: index)
                }
                VideoPlayerView.durationCacheAccessOrder.append(urlString)
                durationLabel.text = formatTime(cachedDuration)
            } else {
                durationLabel.text = "--:--"
            }
            
            loadingIndicator.stopAnimating()
            playButton.isHidden = false
            return
        }
        
        print("🎬 Starting thumbnail generation...")
        
        // Show placeholder first
        showPlaceholderThumbnail()
        loadingIndicator.stopAnimating()
        playButton.isHidden = false
        durationLabel.text = "--:--"
        
        // Try to generate thumbnail in background
        Task {
            do {
                // Download video to temp file
                let videoData = try await downloadVideoForThumbnail(from: urlString)
                
                // Save to temp file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("thumb_\(UUID().uuidString).mp4")
                try videoData.write(to: tempURL)
                
                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                // Extract thumbnail
                await generateThumbnailFromLocalFile(url: tempURL, cacheKey: urlString)
                
            } catch {
                print("❌ Thumbnail generation failed: \(error)")
                // Keep placeholder
            }
        }
    }
    
    private func showPlaceholderThumbnail() {
        thumbnailImageView.image = UIImage(systemName: "video.fill")
        thumbnailImageView.tintColor = .systemGray
        thumbnailImageView.contentMode = .scaleAspectFit
    }
    
    private func downloadVideoForThumbnail(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        
        // Add auth headers
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Try to get only first 2MB for thumbnail
        request.setValue("bytes=0-2097152", forHTTPHeaderField: "Range")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Accept partial content (206) or full content (200)
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
    
    private func generateThumbnailFromLocalFile(url: URL, cacheKey: String) async {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 400, height: 300)
        
        // Try multiple times to get a good frame
        let times = [
            CMTime(seconds: 0, preferredTimescale: 1),
            CMTime(seconds: 0.5, preferredTimescale: 1),
            CMTime(seconds: 1, preferredTimescale: 1)
        ]
        
        var thumbnailGenerated = false
        
        for time in times {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                
                // Cache the thumbnail
                VideoPlayerView.thumbnailCache[cacheKey] = thumbnail
                thumbnailGenerated = true
                
                await MainActor.run {
                    print("✅ Thumbnail generated successfully")
                    self.thumbnailImageView.image = thumbnail
                    self.thumbnailImageView.contentMode = .scaleAspectFill
                }
                
                // If we got a frame, stop trying
                break
            } catch {
                print("❌ Failed to generate thumbnail at time \(time.seconds): \(error)")
                continue
            }
        }
        
        // Also try to get duration
        let duration = asset.duration
        let durationSeconds = CMTimeGetSeconds(duration)
        
        if durationSeconds.isFinite && durationSeconds > 0 {
            // Cache the duration
            VideoPlayerView.durationCache[cacheKey] = durationSeconds
            
            await MainActor.run {
                self.durationLabel.text = self.formatTime(durationSeconds)
            }
        }
        
        // LRU eviction for thumbnail cache
        if VideoPlayerView.thumbnailCache.count > VideoPlayerView.maxThumbnailCacheEntries {
            let keysToRemove = VideoPlayerView.thumbnailCacheAccessOrder.prefix(VideoPlayerView.thumbnailCache.count - VideoPlayerView.maxThumbnailCacheEntries)
            for key in keysToRemove {
                VideoPlayerView.thumbnailCache.removeValue(forKey: key)
                VideoPlayerView.thumbnailCacheAccessOrder.removeAll { $0 == key }
            }
        }
        
        // LRU eviction for duration cache
        if VideoPlayerView.durationCache.count > VideoPlayerView.maxDurationCacheEntries {
            let keysToRemove = VideoPlayerView.durationCacheAccessOrder.prefix(VideoPlayerView.durationCache.count - VideoPlayerView.maxDurationCacheEntries)
            for key in keysToRemove {
                VideoPlayerView.durationCache.removeValue(forKey: key)
                VideoPlayerView.durationCacheAccessOrder.removeAll { $0 == key }
            }
        }
        
        // Update access order for LRU (move to end = most recently used)
        if let index = VideoPlayerView.thumbnailCacheAccessOrder.firstIndex(of: cacheKey) {
            VideoPlayerView.thumbnailCacheAccessOrder.remove(at: index)
        }
        VideoPlayerView.thumbnailCacheAccessOrder.append(cacheKey)
        
        if let index = VideoPlayerView.durationCacheAccessOrder.firstIndex(of: cacheKey) {
            VideoPlayerView.durationCacheAccessOrder.remove(at: index)
        }
        VideoPlayerView.durationCacheAccessOrder.append(cacheKey)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        guard !timeInterval.isNaN && timeInterval.isFinite else {
            return "0:00"
        }
        
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func extractFileName(from urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return "Video File"
        }
        
        let fileName = url.lastPathComponent
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension
        let decodedName = nameWithoutExtension.removingPercentEncoding ?? nameWithoutExtension
        
        if decodedName.isEmpty {
            return "Video File"
        }
        
        let maxLength = 30
        let cleanName = decodedName.count > maxLength ?
            String(decodedName.prefix(maxLength)) + "..." :
            decodedName
        
        return cleanName
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Download Functionality
    private func startVideoDownload() {
        guard let videoURL = videoURL else { return }
        
        isDownloading = true
        updateDownloadButtonState()
        
        // Get filename for saving
        let downloadFilename = getDownloadFilename()
        
        // Create download task
        guard let url = URL(string: videoURL) else {
            showAlert(title: "Error", message: "Invalid video URL")
            resetDownloadState()
            return
        }
        
        // Create request with authentication if available
        var request = URLRequest(url: url)
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let downloadTask = URLSession.shared.downloadTask(with: request) { [weak self] location, response, error in
            DispatchQueue.main.async {
                self?.handleDownloadCompletion(location: location, response: response, error: error, filename: downloadFilename)
            }
        }
        
        downloadTask.resume()
    }
    
    private func handleDownloadCompletion(location: URL?, response: URLResponse?, error: Error?, filename: String) {
        defer {
            resetDownloadState()
        }
        
        if let error = error {
            showAlert(title: "Download Failed", message: "Failed to download video: \(error.localizedDescription)")
            return
        }
        
        guard let location = location else {
            showAlert(title: "Download Failed", message: "Download location not found")
            return
        }
        
        // Save file to Documents directory
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documentsPath.appendingPathComponent(filename)
            
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Move downloaded file to destination
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            // Show success message with option to open in Files app
            showDownloadSuccessAlert(fileURL: destinationURL, filename: filename)
            
        } catch {
            showAlert(title: "Save Failed", message: "Failed to save video: \(error.localizedDescription)")
        }
    }
    
    private func getDownloadFilename() -> String {
        if let filename = filename, !filename.isEmpty {
            // Use provided filename, ensuring it has a video extension
            let cleanFilename = filename.replacingOccurrences(of: "/", with: "_")
                                       .replacingOccurrences(of: ":", with: "_")
            
            // Add .mp4 extension if no video extension exists
            let lowercased = cleanFilename.lowercased()
            if !lowercased.hasSuffix(".mp4") && !lowercased.hasSuffix(".mov") && !lowercased.hasSuffix(".m4v") && !lowercased.hasSuffix(".avi") && !lowercased.hasSuffix(".mkv") {
                return cleanFilename + ".mp4"
            }
            return cleanFilename
        } else if let videoURL = videoURL, let url = URL(string: videoURL) {
            // Extract from URL
            let urlFilename = url.lastPathComponent
            if !urlFilename.isEmpty && urlFilename != videoURL {
                let decodedFilename = urlFilename.removingPercentEncoding ?? urlFilename
                // Ensure video extension
                let lowercased = decodedFilename.lowercased()
                if !lowercased.hasSuffix(".mp4") && !lowercased.hasSuffix(".mov") && !lowercased.hasSuffix(".m4v") && !lowercased.hasSuffix(".avi") && !lowercased.hasSuffix(".mkv") {
                    return decodedFilename + ".mp4"
                }
                return decodedFilename
            }
        }
        
        // Fallback filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "video_\(timestamp).mp4"
    }
    
    private func updateDownloadButtonState() {
        if isDownloading {
            // Show downloading state
            downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
            downloadButton.tintColor = UIColor.systemOrange
            downloadButton.isEnabled = false
            
            // Add activity indicator
            let activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.tag = 999 // Tag to find and remove later
            activityIndicator.color = UIColor.white
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            downloadButton.addSubview(activityIndicator)
            
            NSLayoutConstraint.activate([
                activityIndicator.centerXAnchor.constraint(equalTo: downloadButton.centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: downloadButton.centerYAnchor)
            ])
            
            activityIndicator.startAnimating()
        } else {
            // Reset to normal state
            downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
            downloadButton.tintColor = UIColor.white
            downloadButton.isEnabled = true
            
            // Remove activity indicator
            if let activityIndicator = downloadButton.viewWithTag(999) as? UIActivityIndicatorView {
                activityIndicator.stopAnimating()
                activityIndicator.removeFromSuperview()
            }
        }
    }
    
    private func resetDownloadState() {
        isDownloading = false
        updateDownloadButtonState()
    }
    
    private func showDownloadSuccessAlert(fileURL: URL, filename: String) {
        let fileSize = getFileSize(at: fileURL)
        let message = "Video saved successfully!\n\nFile: \(filename)\nSize: \(fileSize)\nLocation: Documents folder"
        
        let alert = UIAlertController(title: "Download Complete", message: message, preferredStyle: .alert)
        
        // Add action to open in Files app
        alert.addAction(UIAlertAction(title: "Open in Files", style: .default) { _ in
            if UIApplication.shared.canOpenURL(fileURL) {
                UIApplication.shared.open(fileURL)
            }
        })
        
        // Add action to share file
        alert.addAction(UIAlertAction(title: "Share", style: .default) { _ in
            self.shareFile(at: fileURL)
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        
        // Present alert from the first available view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            var presentingViewController = rootViewController
            while let presentedViewController = presentingViewController.presentedViewController {
                presentingViewController = presentedViewController
            }
            
            presentingViewController.present(alert, animated: true)
        }
    }
    
    private func shareFile(at fileURL: URL) {
        let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        // Present from the first available view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            var presentingViewController = rootViewController
            while let presentedViewController = presentingViewController.presentedViewController {
                presentingViewController = presentedViewController
            }
            
            // For iPad
            if let popover = activityViewController.popoverPresentationController {
                popover.sourceView = downloadButton
                popover.sourceRect = downloadButton.bounds
            }
            
            presentingViewController.present(activityViewController, animated: true)
        }
    }
    
    private func getFileSize(at url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return formatFileSize(fileSize)
            }
        } catch {
            // Ignore error
        }
        return "Unknown size"
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Present alert from the first available view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            var presentingViewController = rootViewController
            while let presentedViewController = presentingViewController.presentedViewController {
                presentingViewController = presentedViewController
            }
            
            presentingViewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Layout
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 200)
    }
}

