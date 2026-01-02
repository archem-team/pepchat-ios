//
//  AudioPlayerView.swift
//  Revolt
//
//

import UIKit
import AVFoundation
import Combine

// MARK: - AudioPlayerView
class AudioPlayerView: UIView {
    
    // MARK: - UI Components
    private let containerView = UIView()
    private let playPauseButton = UIButton(type: .custom)
    private let downloadButton = UIButton(type: .custom)
    private let progressView = DownloadProgressView()
    private let currentTimeLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel() // For audio file name
    private let fileSizeLabel = UILabel() // For file size
    private let seekLimitLabel = UILabel() // Shows "Can't seek here" message
    
    // MARK: - Properties
    private let audioManager = AudioPlayerManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var audioURL: String?
    private var filename: String?
    private var fileSize: Int64?
    private var sessionToken: String?
    private var isUserDragging = false // Simple flag for drag state
    private var isDownloading = false
    
    // Callback for when player starts/stops
    var onPlaybackStateChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupBindings()
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupBindings()
        setupGestures()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = .clear
        
        // Container with rounded background
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.8)
        containerView.layer.cornerRadius = 42 // Much more rounded corners
        containerView.layer.masksToBounds = true
        addSubview(containerView)
        
        // Play/Pause button - Medium circular button
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playPauseButton.tintColor = UIColor.white
        playPauseButton.backgroundColor = UIColor(red: 102/255.0, green: 45/255.0, blue: 145/255.0, alpha: 1.0) // Revolt purple
        playPauseButton.layer.cornerRadius = 25 // Will be 50x50 button
        playPauseButton.imageView?.contentMode = .scaleAspectFit
        playPauseButton.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        containerView.addSubview(playPauseButton)
        
        // Loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = UIColor(red: 102/255.0, green: 45/255.0, blue: 145/255.0, alpha: 1.0) // Revolt purple
        containerView.addSubview(loadingIndicator)
        
        // Progress view
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isUserInteractionEnabled = true
        progressView.backgroundColor = UIColor.clear // Remove debug background
        containerView.addSubview(progressView)
        

        
        // Download button
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
        downloadButton.tintColor = UIColor.systemBlue
        downloadButton.backgroundColor = UIColor.clear
        downloadButton.layer.cornerRadius = 15
        downloadButton.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
        containerView.addSubview(downloadButton)
        
        // Current time label (shows playback position)
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular) // Even smaller
        currentTimeLabel.textColor = UIColor.label
        currentTimeLabel.text = "0:00"
        currentTimeLabel.textAlignment = .right // Right align for cleaner look
        containerView.addSubview(currentTimeLabel)
        
        // Title label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium) // Slightly larger font
        titleLabel.textColor = UIColor.label
        titleLabel.text = "Audio File"
        titleLabel.textAlignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = false
        titleLabel.backgroundColor = UIColor.clear
        titleLabel.baselineAdjustment = .alignCenters // Better text alignment
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        containerView.addSubview(titleLabel)
        
        // File size label
        fileSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        fileSizeLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        fileSizeLabel.textColor = UIColor.secondaryLabel
        fileSizeLabel.text = ""
        fileSizeLabel.textAlignment = .left
        fileSizeLabel.backgroundColor = UIColor.clear
        fileSizeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fileSizeLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        containerView.addSubview(fileSizeLabel)
        
        // Seek limit label (hidden by default)
        seekLimitLabel.translatesAutoresizingMaskIntoConstraints = false
        seekLimitLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        seekLimitLabel.textColor = UIColor.systemOrange
        seekLimitLabel.text = "⚠️ Not buffered yet"
        seekLimitLabel.textAlignment = .center
        seekLimitLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        seekLimitLabel.layer.cornerRadius = 8
        seekLimitLabel.layer.masksToBounds = true
        seekLimitLabel.layer.borderWidth = 1
        seekLimitLabel.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.3).cgColor
        seekLimitLabel.isHidden = true
        seekLimitLabel.alpha = 0
        containerView.addSubview(seekLimitLabel)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Container
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 85), // Increased from 80 to 85
            
            // Play/Pause button - Larger circular
            playPauseButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            playPauseButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 50),
            playPauseButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Loading indicator (same position as play button)
            loadingIndicator.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            
            // Download button - positioned on the right side
            downloadButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            downloadButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            downloadButton.widthAnchor.constraint(equalToConstant: 30),
            downloadButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Current time label - positioned next to download button
            currentTimeLabel.trailingAnchor.constraint(equalTo: downloadButton.leadingAnchor, constant: -8),
            currentTimeLabel.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 36), // Smaller width for more progress space
            
            // Title label - aligned with progress view with proper height
            titleLabel.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: currentTimeLabel.leadingAnchor, constant: -8),
            titleLabel.heightAnchor.constraint(equalToConstant: 18), // Fixed height for proper text display
            
            // File size label - aligned with title and progress
            fileSizeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            fileSizeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            fileSizeLabel.trailingAnchor.constraint(lessThanOrEqualTo: currentTimeLabel.leadingAnchor, constant: -8),
            fileSizeLabel.heightAnchor.constraint(equalToConstant: 14), // Reduced from 16 to 14
            
            // Progress view - aligned with title and file size labels
            progressView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressView.topAnchor.constraint(equalTo: fileSizeLabel.bottomAnchor, constant: 5), // Reduced from 6 to 5
            progressView.trailingAnchor.constraint(equalTo: currentTimeLabel.leadingAnchor, constant: -8),
            progressView.heightAnchor.constraint(equalToConstant: 18), // Reduced from 20 to 18
            progressView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -8), // Reduced from -10 to -8
            
            // Seek limit label - positioned above progress bar
            seekLimitLabel.centerXAnchor.constraint(equalTo: progressView.centerXAnchor),
            seekLimitLabel.bottomAnchor.constraint(equalTo: progressView.topAnchor, constant: -4),
            seekLimitLabel.widthAnchor.constraint(equalToConstant: 120),
            seekLimitLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Debug layout after it's complete - only log occasionally to reduce noise
        if Int.random(in: 0...50) == 0 { // 2% chance
            // print("🎨 LAYOUT COMPLETE:")
            // print("  ↳ AudioPlayerView frame: \(frame)")
            // print("  ↳ ContainerView frame: \(containerView.frame)")
            // print("  ↳ ProgressView frame: \(progressView.frame)")
            // print("  ↳ ProgressView bounds: \(progressView.bounds)")
            // print("  ↳ PlayButton frame: \(playPauseButton.frame)")
            // print("  ↳ TimeLabel frame: \(currentTimeLabel.frame)")
            
            // Calculate usable width
            let totalWidth = frame.width
            let playButtonEnd = playPauseButton.frame.maxX
            let timeLabelStart = currentTimeLabel.frame.minX
            let availableWidth = timeLabelStart - playButtonEnd - 20 // 20 for margins
            
            // print("  ↳ Total width: \(totalWidth)")
            // print("  ↳ Available for progress: \(availableWidth)")
            // print("  ↳ Actual progress width: \(progressView.frame.width)")
            
            if progressView.frame.width < 100 {
                // print("  ⚠️ WARNING: Progress view is very narrow!")
            }
        }
    }
    
    private func setupBindings() {
        // Bind to audio manager state - only update if this is the active player
        audioManager.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                
                // Only update play button if this is the currently playing audio
                let isThisPlayerActive = self.audioManager.currentlyPlayingURL == self.audioURL
                let shouldShowPlaying = isThisPlayerActive && isPlaying
                
                self.updatePlayPauseButton(isPlaying: shouldShowPlaying)
                
                // Only call callback for active player
                if isThisPlayerActive {
                    self.onPlaybackStateChanged?(isPlaying)
                }
            }
            .store(in: &cancellables)
        
        audioManager.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime in
                self?.updateCurrentTime(currentTime)
            }
            .store(in: &cancellables)
        
        // Duration binding removed - we only show current time now
        
        audioManager.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                guard let self = self else { return }
                
                // Only show loading if this is the currently loading/playing audio
                let isThisPlayerActive = self.audioManager.currentlyPlayingURL == self.audioURL
                let shouldShowLoading = isThisPlayerActive && isLoading
                
                self.updateLoadingState(shouldShowLoading)
            }
            .store(in: &cancellables)
        
        audioManager.$isConvertingOgg
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConverting in
                guard let self = self else { return }
                
                // Only show converting if this is the current audio
                let isThisPlayerActive = self.audioManager.currentlyPlayingURL == self.audioURL
                let shouldShowConverting = isThisPlayerActive && isConverting
                
                if shouldShowConverting {
                    self.showOggConversionMessage()
                } else {
                    self.hideOggConversionMessage()
                }
            }
            .store(in: &cancellables)
        
        audioManager.$currentlyPlayingURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playingURL in
                guard let self = self else { return }
                
                self.updatePlayingState(playingURL)
                
                // Also update play button when currently playing URL changes
                let isThisPlayerActive = playingURL == self.audioURL
                let shouldShowPlaying = isThisPlayerActive && self.audioManager.isPlaying
                self.updatePlayPauseButton(isPlaying: shouldShowPlaying)
                
                // Stop loading for inactive players immediately
                if !isThisPlayerActive {
                    self.loadingIndicator.stopAnimating()
                    self.playPauseButton.isHidden = false
                }
            }
            .store(in: &cancellables)
            
        audioManager.$bufferingProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView.updateBuffering(progress)
            }
            .store(in: &cancellables)
            
        audioManager.$isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isBuffering in
                guard let self = self else { return }
                
                // Only show buffering if this is the currently playing audio
                let isThisPlayerActive = self.audioManager.currentlyPlayingURL == self.audioURL
                let shouldShowBuffering = isThisPlayerActive && isBuffering
                
                if shouldShowBuffering {
                    self.loadingIndicator.startAnimating()
                } else {
                    self.loadingIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupGestures() {
        // Add pan gesture to progress view for seeking
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        progressView.addGestureRecognizer(panGesture)
        progressView.isUserInteractionEnabled = true
        
        // Add tap gesture to progress view for direct seeking
        let progressTapGesture = UITapGestureRecognizer(target: self, action: #selector(progressTapped(_:)))
        progressView.addGestureRecognizer(progressTapGesture)
    }
    
    // MARK: - Public Methods
    
    // PERFORMANCE: Stop playback immediately for cell reuse
    func stopPlayback() {
        // Stop audio if this is the currently playing audio
        if let audioURL = audioURL, audioManager.currentlyPlayingURL == audioURL {
            audioManager.stop()
        }
        
        // Reset UI state
        progressView.updateProgress(0)
        progressView.updateBuffering(0)
        currentTimeLabel.text = "0:00"
        updatePlayPauseButton(isPlaying: false)
        loadingIndicator.stopAnimating()
        playPauseButton.isHidden = false
        
        // Clear audio URL reference
        self.audioURL = nil
    }
    
    func configure(with audioURL: String, filename: String? = nil, fileSize: Int64? = nil, sessionToken: String? = nil) {
        self.audioURL = audioURL
        self.filename = filename
        self.fileSize = fileSize
        self.sessionToken = sessionToken
        
        // Check if it's an OGG file based on filename
        if let filename = filename {
            let isOggFile = filename.lowercased().hasSuffix(".ogg") || 
                           filename.lowercased().contains(".oog")
            if isOggFile && self.tag != 7777 {
                self.tag = 7777 // Mark as OGG file
                // print("🎵 Marked as OGG file based on filename: \(filename)")
            }
        }
        
        // Set session token in audio manager if provided
        if let token = sessionToken {
            // print("🔐 AudioPlayerView: Setting session token in AudioManager")
            audioManager.setSessionToken(token)
        } else {
            // print("⚠️ AudioPlayerView: No session token provided")
        }
        
        // Reset UI state properly
        progressView.updateProgress(0)
        progressView.updateBuffering(0)
        currentTimeLabel.text = "0:00"
        
        // Use provided filename or extract from URL
        let fileName = filename ?? extractFileName(from: audioURL)
        
        // Log filename information
        // print("🎵 AudioPlayer Configure:")
        // print("  ↳ Audio URL: \(audioURL)")
        // print("  ↳ Provided filename: \(filename ?? "nil")")
        // print("  ↳ Final filename: \(fileName)")
        
        titleLabel.text = fileName
        
        // Pass session token to audio manager before preloading
        if let token = sessionToken {
            audioManager.setSessionToken(token)
        }
        
        // Preload duration for better UX
        audioManager.preloadDuration(for: audioURL) { [weak self] duration in
            guard let self = self, let duration = duration else { return }
            // print("✅ Duration preloaded for UI: \(duration)s")
            
            // Store the preloaded duration in the audio manager if it doesn't have one yet
            if self.audioManager.duration <= 0 {
                // We can't directly set the duration in AudioPlayerManager, but we can log it
                // print("📋 Preloaded duration available: \(duration)s")
            }
        }
        
        // Debug UI state
        // print("🎨 UI Debug:")
        // print("  ↳ titleLabel.text: \(titleLabel.text ?? "nil")")
        // print("  ↳ titleLabel.frame: \(titleLabel.frame)")
        // print("  ↳ titleLabel.isHidden: \(titleLabel.isHidden)")
        // print("  ↳ titleLabel.alpha: \(titleLabel.alpha)")
        // print("  ↳ fileSizeLabel.text: \(fileSizeLabel.text ?? "nil")")
        // print("  ↳ fileSizeLabel.frame: \(fileSizeLabel.frame)")
        // print("  ↳ fileSizeLabel.isHidden: \(fileSizeLabel.isHidden)")
        // print("  ↳ fileSizeLabel.alpha: \(fileSizeLabel.alpha)")
        // print("  ↳ containerView.frame: \(containerView.frame)")
        
        // Force layout update and debug after layout
        setNeedsLayout()
        layoutIfNeeded()
        
        DispatchQueue.main.async {
            // print("🎨 UI Debug AFTER layout:")
            // print("  ↳ titleLabel.frame: \(self.titleLabel.frame)")
            // print("  ↳ titleLabel.text: '\(self.titleLabel.text ?? "nil")'")
            // print("  ↳ fileSizeLabel.frame: \(self.fileSizeLabel.frame)")
            // print("  ↳ fileSizeLabel.text: '\(self.fileSizeLabel.text ?? "nil")'")
            // print("  ↳ fileSizeLabel.textColor: \(self.fileSizeLabel.textColor?.description ?? "nil")")
            // print("  ↳ fileSizeLabel.font: \(self.fileSizeLabel.font?.description ?? "nil")")
            // print("  ↳ containerView.frame: \(self.containerView.frame)")
            // print("  ↳ self.frame: \(self.frame)")
            // print("  ↳ self.bounds: \(self.bounds)")
            
            // Force another layout cycle
            self.setNeedsLayout()
            self.layoutIfNeeded()
            
            // print("🎨 After SECOND layout:")
            // print("  ↳ fileSizeLabel.frame: \(self.fileSizeLabel.frame)")
            // print("  ↳ titleLabel.frame: \(self.titleLabel.frame)")
            // print("  ↳ progressView.frame: \(self.progressView.frame)")
            // print("  ↳ playPauseButton.frame: \(self.playPauseButton.frame)")
            // print("  ↳ currentTimeLabel.frame: \(self.currentTimeLabel.frame)")
            
            // Check alignment
            let titleLeading = self.titleLabel.frame.minX
            let progressLeading = self.progressView.frame.minX
            // print("🎯 Alignment check:")
            // print("  ↳ titleLabel leading: \(titleLeading)")
            // print("  ↳ progressView leading: \(progressLeading)")
            // print("  ↳ Difference: \(abs(titleLeading - progressLeading))")
        }
        
        // Set file size from parameter
        // print("🔍 File size debug:")
        // print("  ↳ fileSize parameter: \(fileSize ?? -1)")
        // print("  ↳ fileSize is nil: \(fileSize == nil)")
        
        // Force show with test data first
        fileSizeLabel.text = "TEST 5.9 MB"
        fileSizeLabel.isHidden = false
        fileSizeLabel.backgroundColor = UIColor.yellow.withAlphaComponent(0.5)
        // print("  ↳ Set TEST text and yellow background")
        
        // Then set actual data
        if let fileSize = fileSize, fileSize > 0 {
            let formattedSize = formatFileSize(fileSize)
            // print("  ↳ Formatted size: \(formattedSize) from \(fileSize) bytes")
            
            // Set the actual size text
            fileSizeLabel.text = formattedSize
            fileSizeLabel.backgroundColor = UIColor.clear
            
            // print("  ↳ Set fileSizeLabel.text to: '\(fileSizeLabel.text ?? "nil")'")
            // print("  ↳ fileSizeLabel.isHidden: \(fileSizeLabel.isHidden)")
        } else {
            // print("  ↳ No valid file size - keeping test text")
            fileSizeLabel.backgroundColor = UIColor.red.withAlphaComponent(0.3) // Red for error
        }
        
        // Thumb will be positioned correctly when progress updates
        
        // Update play button state based on current player state
        let isThisPlayerActive = audioManager.currentlyPlayingURL == audioURL
        let shouldShowPlaying = isThisPlayerActive && audioManager.isPlaying
        updatePlayPauseButton(isPlaying: shouldShowPlaying)
        
        // Update visual state based on current playback
        updatePlayingState(audioManager.currentlyPlayingURL)
        
        // If this is the currently playing URL, update buffering progress
        if audioManager.currentlyPlayingURL == audioURL {
            progressView.updateBuffering(audioManager.bufferingProgress)
            
            // Update current time if available
            if audioManager.currentTime > 0 {
                updateCurrentTime(audioManager.currentTime)
            }
        } else {
            // Reset state for non-active players
            progressView.updateProgress(0)
            progressView.updateBuffering(0)
            currentTimeLabel.text = "0:00"
            
            // Ensure loading is stopped for inactive players
            loadingIndicator.stopAnimating()
            playPauseButton.isHidden = false
        }
    }
    
    // MARK: - Actions
    @objc private func downloadButtonTapped() {
        guard let audioURL = audioURL else {
            showAlert(title: "Error", message: "No file URL available for download")
            return
        }
        
        guard !isDownloading else {
            showAlert(title: "Download", message: "Download is already in progress")
            return
        }
        
        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        startDownload()
    }
    
    @objc private func playPauseButtonTapped() {
        guard let audioURL = audioURL else { 
            // print("❌ No audio URL available")
            return 
        }
        
        // print("🎵 Play button tapped for: \(audioURL)")
        // print("🎵 Current playing URL: \(audioManager.currentlyPlayingURL ?? "none")")
        // print("🎵 Current playing state: \(audioManager.isPlaying)")
        
        if audioManager.currentlyPlayingURL == audioURL {
            // Same audio file - toggle play/pause
            if audioManager.isPlaying {
                // print("⏸️ Pausing current audio")
                audioManager.pause()
            } else {
                // print("▶️ Resuming current audio")
                audioManager.resumePlayback()
            }
        } else {
            // Different audio file - stop current and play new
            if audioManager.isPlaying {
                // print("⏹️ Stopping current audio and playing new")
                audioManager.stop()
            }
            // print("▶️ Playing new audio: \(audioURL)")
            
            // Check if the filename (from title) indicates an OGG file
            // First check the tag, then fall back to filename check
            let isOggFile = self.tag == 7777 || 
                           titleLabel.text?.lowercased().contains(".ogg") ?? false || 
                           titleLabel.text?.lowercased().contains("(ogg)") ?? false
            
            // print("🎵 OGG detection: tag=\(self.tag), filename=\(titleLabel.text ?? ""), isOgg=\(isOggFile)")
            
            audioManager.play(url: audioURL, isOggFile: isOggFile)
        }
        
        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let audioURL = audioURL,
              audioManager.currentlyPlayingURL == audioURL,
              audioManager.duration > 0 else {
            return
        }
        
        let location = gesture.location(in: progressView)
        let progress = Float(location.x / progressView.bounds.width)
        let clampedProgress = max(0, min(1, progress))
        
        switch gesture.state {
        case .began:
            isUserDragging = true
            progressView.setThumbHighlighted(true)
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
        case .changed:
            // Update progress bar while dragging
            progressView.updateProgress(clampedProgress)
            
            // Update time label to show where we're dragging to
            let dragTime = Double(clampedProgress) * audioManager.duration
            currentTimeLabel.text = formatTime(dragTime)
            
        case .ended, .cancelled:
            isUserDragging = false
            progressView.setThumbHighlighted(false)
            
            // Perform seek
            let targetTime = Double(clampedProgress) * audioManager.duration
            audioManager.seek(to: targetTime)
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
        default:
            break
        }
    }
    
    @objc private func progressTapped(_ gesture: UITapGestureRecognizer) {
        guard let audioURL = audioURL,
              audioManager.currentlyPlayingURL == audioURL,
              audioManager.duration > 0 else {
            return
        }
        
        let location = gesture.location(in: progressView)
        let progress = Float(location.x / progressView.bounds.width)
        let clampedProgress = max(0, min(1, progress))
        
        // Update progress bar
        progressView.updateProgress(clampedProgress)
        
        // Perform seek
        let targetTime = Double(clampedProgress) * audioManager.duration
        audioManager.seek(to: targetTime)
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Brief thumb highlight
        progressView.setThumbHighlighted(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.progressView.setThumbHighlighted(false)
        }
    }
    
    // MARK: - Update Methods
    private func updatePlayPauseButton(isPlaying: Bool) {
        let imageName = isPlaying ? "pause.fill" : "play.fill"
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let image = UIImage(systemName: imageName, withConfiguration: config)
        playPauseButton.setImage(image, for: .normal)
        
        // Debug logging
        // print("🔄 UpdatePlayPauseButton for \(audioURL ?? "unknown"): \(isPlaying ? "PAUSE" : "PLAY")")
    }
    
    private func updateCurrentTime(_ currentTime: TimeInterval) {
        // Only update if this is the currently playing audio
        guard audioManager.currentlyPlayingURL == audioURL else {
            return
        }
        
        // Update time label
        currentTimeLabel.text = formatTime(currentTime)
        
        // Only update progress bar if user is not dragging
        if !isUserDragging && audioManager.duration > 0 {
            let progress = Float(currentTime / audioManager.duration)
            progressView.updateProgress(progress)
        }
    }
    
    private func updateLoadingState(_ isLoading: Bool) {
        // print("🔄 UpdateLoadingState for \(audioURL ?? "unknown"): \(isLoading)")
        
        if isLoading {
            loadingIndicator.startAnimating()
            playPauseButton.isHidden = true
        } else {
            loadingIndicator.stopAnimating()
            playPauseButton.isHidden = false
        }
    }
    
    private func updatePlayingState(_ playingURL: String?) {
        let isThisPlayerActive = playingURL == audioURL
        
        // print("🎵 UpdatePlayingState for \(audioURL ?? "unknown")")
        // print("🎵 Currently playing: \(playingURL ?? "none")")
        // print("🎵 Is this player active: \(isThisPlayerActive)")
        
        // Update play button state - this will be handled by the isPlaying binding
        // updatePlayPauseButton is now handled in setupBindings()
        
        // Update visual state based on whether this player is active
        UIView.animate(withDuration: 0.2) {
            self.containerView.backgroundColor = isThisPlayerActive ?
                UIColor(red: 102/255.0, green: 45/255.0, blue: 145/255.0, alpha: 0.1) :
                UIColor.systemGray6.withAlphaComponent(0.8)
        }
        
        // Reset state for inactive players
        if !isThisPlayerActive {
            progressView.updateProgress(0)
            progressView.updateBuffering(0)
            currentTimeLabel.text = "0:00"
            
            // Stop loading indicator for inactive players
            loadingIndicator.stopAnimating()
            playPauseButton.isHidden = false
        }
    }
    
    // MARK: - Helper Methods
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        guard !timeInterval.isNaN && timeInterval.isFinite else {
            return "0:00"
        }
        
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func extractFileName(from urlString: String) -> String {
        // Extract filename from URL
        guard let url = URL(string: urlString) else {
            // print("🚫 extractFileName: Invalid URL")
            return "Audio File"
        }
        
        let fileName = url.lastPathComponent
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        
        // Remove file extension and decode URL encoding
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension
        let decodedName = nameWithoutExtension.removingPercentEncoding ?? nameWithoutExtension
        
        // print("📂 extractFileName process:")
        // print("  ↳ Original URL: \(urlString)")
        // print("  ↳ Last path component: \(fileName)")
        // print("  ↳ Without extension: \(nameWithoutExtension)")
        // print("  ↳ Decoded name: \(decodedName)")
        // print("  ↳ File extension: \(fileExtension)")
        
        // If the name is empty or too generic, return a default
        if decodedName.isEmpty || decodedName.lowercased().contains("audio") {
            // print("  ↳ Using default name (empty or generic)")
            return "Audio File"
        }
        
        // Limit length and clean up
        let maxLength = 25 // Reduced to make room for OGG indicator
        let cleanName = decodedName.count > maxLength ? 
            String(decodedName.prefix(maxLength)) + "..." : 
            decodedName
        
        // Add OGG indicator if it's an OGG file
        let finalName = fileExtension == "ogg" ? "\(cleanName) (OGG)" : cleanName
        
        // print("  ↳ Final clean name: \(finalName)")
        return finalName
    }
    
    private func fetchFileSize(for urlString: String) {
        guard let url = URL(string: urlString) else {
            fileSizeLabel.text = "Unknown size"
            return
        }
        
        // Create a HEAD request to get file size without downloading
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let httpResponse = response as? HTTPURLResponse,
                   let contentLength = httpResponse.allHeaderFields["Content-Length"] as? String,
                   let bytes = Int64(contentLength) {
                    
                    let sizeText = self.formatFileSize(bytes)
                    self.fileSizeLabel.text = sizeText
                } else {
                    // Fallback - estimate based on duration when available
                    self.fileSizeLabel.text = "Unknown size"
                }
            }
        }.resume()
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes <= 0 {
            return ""
        }
        
        let bytesDouble = Double(bytes)
        let kb = bytesDouble / 1024.0
        let mb = kb / 1024.0
        
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }
    
    // MARK: - Layout
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 80)
    }
    
    // MARK: - Warning UI
    private func showSeekLimitWarning() {
        // Cancel any existing hide timer
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideSeekLimitWarning), object: nil)
        
        // Show the warning
        seekLimitLabel.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.seekLimitLabel.alpha = 1.0
        }
        
        // Hide after 2 seconds
        perform(#selector(hideSeekLimitWarning), with: nil, afterDelay: 2.0)
    }
    
    @objc private func hideSeekLimitWarning() {
        UIView.animate(withDuration: 0.3, animations: {
            self.seekLimitLabel.alpha = 0.0
        }) { _ in
            self.seekLimitLabel.isHidden = true
        }
    }
    
    // MARK: - OGG Conversion UI
    private func showOggConversionMessage() {
        // Update the current time label to show conversion message
        currentTimeLabel.text = "Converting..."
        currentTimeLabel.textColor = UIColor.systemOrange
        
        // Show loading indicator
        loadingIndicator.startAnimating()
        playPauseButton.isHidden = true
    }
    
    private func hideOggConversionMessage() {
        // Reset the time label
        currentTimeLabel.textColor = UIColor.label
        currentTimeLabel.text = formatTime(audioManager.currentTime)
        
        // Hide loading indicator
        loadingIndicator.stopAnimating()
        playPauseButton.isHidden = false
    }
    
    // MARK: - Download Functionality
    private func startDownload() {
        guard let audioURL = audioURL else { return }
        
        isDownloading = true
        updateDownloadButtonState()
        
        // Get filename for saving
        let downloadFilename = getDownloadFilename()
        
        // Create download task
        guard let url = URL(string: audioURL) else {
            showAlert(title: "Error", message: "Invalid file URL")
            resetDownloadState()
            return
        }
        
        // Create request with authentication if available
        var request = URLRequest(url: url)
        if let token = sessionToken {
            request.setValue(token, forHTTPHeaderField: "x-session-token")
        }
        
        let downloadTask = URLSession.shared.downloadTask(with: request) { [weak self] location, response, error in
            var preservedLocation: URL? = nil

            if let location = location {
                let fm = FileManager.default
                let tempDir = fm.temporaryDirectory
                let uniqueTemp = tempDir.appendingPathComponent(UUID().uuidString + "_" + location.lastPathComponent)

                do {
                    try fm.moveItem(at: location, to: uniqueTemp)
                    preservedLocation = uniqueTemp
                } catch {
                    // Move might fail for cross-volume or other reasons, fall back to copy
                    do {
                        let data = try Data(contentsOf: location)
                        try data.write(to: uniqueTemp, options: .atomic)
                        preservedLocation = uniqueTemp
                    } catch {
                        print("⚠️ [AudioPlayer] Failed to preserve download temp file: \(error)")
                        preservedLocation = location
                    }
                }
            }

            DispatchQueue.main.async {
                self?.handleDownloadCompletion(location: preservedLocation, response: response, error: error, filename: downloadFilename)
            }
        }

        downloadTask.resume()
    }
    
    private func handleDownloadCompletion(location: URL?, response: URLResponse?, error: Error?, filename: String) {
        defer {
            resetDownloadState()
        }

        if let error = error {
            showAlert(title: "Download Failed", message: "Failed to download file: \(error.localizedDescription)")
            return
        }

        guard let location = location else {
            showAlert(title: "Download Failed", message: "Download location not found")
            return
        }

        // Robust save: ensure Documents exists, try move, fallback to copy, and generate a unique filename if needed
        do {
            let fm = FileManager.default
            let documentsPath = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

            // Ensure the Documents directory exists
            try fm.createDirectory(at: documentsPath, withIntermediateDirectories: true)

            var destinationURL = documentsPath.appendingPathComponent(filename)

            // If destination exists try to remove it
            if fm.fileExists(atPath: destinationURL.path) {
                do {
                    try fm.removeItem(at: destinationURL)
                } catch {
                    let base = destinationURL.deletingPathExtension().lastPathComponent
                    let ext = destinationURL.pathExtension
                    var counter = 1
                    var newURL = destinationURL
                    repeat {
                        let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
                        newURL = documentsPath.appendingPathComponent(newName)
                        counter += 1
                    } while fm.fileExists(atPath: newURL.path)
                    destinationURL = newURL
                }
            }

            // First attempt to move
            do {
                try fm.moveItem(at: location, to: destinationURL)
            } catch let moveError {
                print("⚠️ [AudioPlayer] moveItem failed: \(moveError)")

                do {
                    let data = try Data(contentsOf: location)
                    try data.write(to: destinationURL, options: .atomic)

                    // Attempt to remove the temporary file if it still exists
                    try? fm.removeItem(at: location)
                } catch let copyError {
                    print("❌ [AudioPlayer] Copy fallback failed: \(copyError)")
                    throw copyError
                }
            }

            showDownloadSuccessAlert(fileURL: destinationURL, filename: destinationURL.lastPathComponent)

        } catch {
            showAlert(title: "Save Failed", message: "Failed to save file: \(error.localizedDescription)")
            print("❌ [AudioPlayer] Save failed: \(error)")
        }
    }
    
    private func getDownloadFilename() -> String {
        if let filename = filename, !filename.isEmpty {
            // Use provided filename
            let cleanFilename = filename.replacingOccurrences(of: "/", with: "_")
                                       .replacingOccurrences(of: ":", with: "_")
            return cleanFilename
        } else if let audioURL = audioURL, let url = URL(string: audioURL) {
            // Extract from URL
            let urlFilename = url.lastPathComponent
            if !urlFilename.isEmpty && urlFilename != audioURL {
                return urlFilename.removingPercentEncoding ?? urlFilename
            }
        }
        
        // Fallback filename
        let timestamp = DateFormatter().string(from: Date())
        return "audio_file_\(timestamp)"
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
            activityIndicator.color = UIColor.systemOrange
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            downloadButton.addSubview(activityIndicator)
            
            NSLayoutConstraint.activate([
                activityIndicator.centerXAnchor.constraint(equalTo: downloadButton.centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: downloadButton.centerYAnchor)
            ])
            
            activityIndicator.startAnimating()
        } else {
            // Reset to normal state
            downloadButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
            downloadButton.tintColor = UIColor.systemBlue
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
        let message = "File saved successfully!\n\nFile: \(filename)\nSize: \(fileSize)\nLocation: Documents folder"
        
        let alert = UIAlertController(title: "Download Complete", message: message, preferredStyle: .alert)
        
        // Add action to open in Files app
        alert.addAction(UIAlertAction(title: "Open in Files", style: .default) { _ in
            self.openInFiles(at: fileURL)
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
    
    private func openInFiles(at fileURL: URL) {
        DispatchQueue.main.async {
            let picker = UIDocumentPickerViewController(forExporting: [fileURL])
            picker.modalPresentationStyle = .formSheet
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               var root = window.rootViewController {
                while let presented = root.presentedViewController { root = presented }
                root.present(picker, animated: true)
            }
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
    
    // MARK: - Cleanup
    deinit {
        cancellables.removeAll()
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }
} 
