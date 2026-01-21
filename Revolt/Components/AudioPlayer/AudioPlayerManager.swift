//
//  AudioPlayerManager.swift
//  Revolt
//
//

import AVFoundation
import UIKit
import Combine
import OggDecoder

// MARK: - AudioPlayerManager
class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    // Published properties for UI updates
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = false
    @Published var currentlyPlayingURL: String?
    @Published var bufferingProgress: Float = 0.0 // Track download progress
    @Published var isBuffering = false // Track if we're waiting for more data
    @Published var isConvertingOgg = false // Track OGG conversion status
    
    // Playback rate (for speed control if needed)
    @Published var playbackRate: Float = 1.0
    
    // Track buffered ranges
    private var bufferedRanges: [CMTimeRange] = []
    
    // Cache for preloaded durations
    private var durationCache: [String: TimeInterval] = [:]
    
    // Session token for authenticated requests
    private var sessionToken: String?
    
    // Audio session setup
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth, .mixWithOthers])
            
            // DON'T activate the audio session here - only activate when actually playing
            // This prevents interrupting other apps' audio when the app initializes
            // try session.setActive(true)
            
            // Configure for better performance with converted files
            try session.setPreferredSampleRate(44100)
            try session.setPreferredIOBufferDuration(0.005) // 5ms buffer for low latency
            
            // print("✅ Audio session configured successfully (but not activated yet)")
        } catch {
            // print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Duration Preloading
    
    func preloadDuration(for urlString: String, fileSize: Int64? = nil, completion: @escaping (TimeInterval?) -> Void) {
        // print("📢 PRELOAD REQUEST RECEIVED!")
        // print("🎯 PRELOAD REQUEST: Starting for URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            // print("❌ PRELOAD ERROR: Invalid URL: \(urlString)")
            completion(nil)
            return
        }
        
        // Check if this is an OGG file - handle differently
        let filename = url.lastPathComponent.lowercased()
        if filename.contains("ogg") || urlString.lowercased().contains("oog") {
            // print("🎵 PRELOAD: OGG file detected - using file size estimation")
            if let size = fileSize {
                estimateDurationFromFileSize(urlString: urlString, knownFileSize: size, completion: completion)
            } else {
                // Try to get file size via HEAD request
                estimateDurationFromFileSize(urlString: urlString, knownFileSize: nil, completion: completion)
            }
            return
        }
        
        // Check if we already have this duration cached
        if let cachedDuration = durationCache[urlString] {
            // print("💾 CACHE HIT: Using cached duration \(String(format: "%.1f", cachedDuration))s for \(url.lastPathComponent)")
            completion(cachedDuration)
            return
        }
        
        // print("📡 PRELOAD START: Loading duration for \(url.lastPathComponent)")
        // print("  🌐 Full URL: \(urlString)")
        
        let asset = AVURLAsset(url: url)
        
        // Configure asset for better metadata loading
        let options = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
            AVURLAssetHTTPCookiesKey: [],
            "AVURLAssetOutOfBandMIMETypeKey": "audio/mpeg"
        ] as [String : Any]
        
        let configuredAsset = AVURLAsset(url: url, options: options)
        
        // Load multiple metadata keys for better results
        let metadataKeys = [
            "duration",
            "commonMetadata", 
            "availableMetadataFormats",
            "tracks"
        ]
        
        // print("📊 PRELOAD: Loading metadata keys: \(metadataKeys)")
        
        // Load metadata asynchronously
        let startTime = Date()
        configuredAsset.loadValuesAsynchronously(forKeys: metadataKeys) {
            let loadTime = Date().timeIntervalSince(startTime)
            
            DispatchQueue.main.async {
                // print("⏱️ PRELOAD RESULT: Load took \(String(format: "%.2f", loadTime))s for \(url.lastPathComponent)")
                
                // Check duration first
                var durationError: NSError?
                let durationStatus = configuredAsset.statusOfValue(forKey: "duration", error: &durationError)
                
                // print("  📊 Duration status: \(durationStatus.rawValue)")
                if let error = durationError {
                    // print("  ❌ Duration error: \(error.localizedDescription)")
                }
                
                // Try to get duration
                let duration = configuredAsset.duration
                // print("  📊 Raw duration: \(duration)")
                // print("  ✓ Valid: \(duration.isValid), Indefinite: \(duration.isIndefinite)")
                
                if duration.isValid && !duration.isIndefinite && duration.seconds > 0 {
                    // We have a valid duration
                    let durationSeconds = duration.seconds
                    // print("✅ PRELOAD SUCCESS: \(url.lastPathComponent) = \(String(format: "%.1f", durationSeconds))s")
                    
                    // Cache the duration
                    self.durationCache[urlString] = durationSeconds
                    // print("💾 CACHED: Total cache entries: \(self.durationCache.count)")
                    
                    completion(durationSeconds)
                    return
                }
                
                // Duration is indefinite or invalid - try alternative methods
                // print("⚠️ DURATION INDEFINITE: Trying alternative methods for \(url.lastPathComponent)")
                
                // Method 1: Check tracks
                var tracksError: NSError?
                let tracksStatus = configuredAsset.statusOfValue(forKey: "tracks", error: &tracksError)
                
                if tracksStatus == .loaded {
                    let tracks = configuredAsset.tracks
                    // print("  🎵 Found \(tracks.count) tracks")
                    
                    for track in tracks {
                        let trackDuration = track.timeRange.duration
                        // print("    Track duration: \(trackDuration)")
                        
                        if trackDuration.isValid && !trackDuration.isIndefinite && trackDuration.seconds > 0 {
                            let durationSeconds = trackDuration.seconds
                            // print("✅ PRELOAD SUCCESS (via tracks): \(url.lastPathComponent) = \(String(format: "%.1f", durationSeconds))s")
                            
                            // Cache the duration
                            self.durationCache[urlString] = durationSeconds
                            completion(durationSeconds)
                            return
                        }
                    }
                }
                
                // Method 2: Try creating a player item for better metadata
                // print("  🔄 FALLBACK: Creating player item for metadata")
                let playerItem = AVPlayerItem(url: url)
                
                var observer: NSKeyValueObservation?
                var hasCompleted = false
                
                // Observe the player item status
                observer = playerItem.observe(\.status, options: [.new]) { item, change in
                    DispatchQueue.main.async {
                        guard !hasCompleted else { return }
                        
                        switch item.status {
                        case .readyToPlay:
                            hasCompleted = true
                            observer?.invalidate()
                            
                            let itemDuration = item.duration
                            // print("    📊 PlayerItem duration: \(itemDuration)")
                            
                            if itemDuration.isValid && !itemDuration.isIndefinite && itemDuration.seconds > 0 {
                                let durationSeconds = itemDuration.seconds
                                // print("✅ PRELOAD SUCCESS (via PlayerItem): \(url.lastPathComponent) = \(String(format: "%.1f", durationSeconds))s")
                                
                                // Cache the duration
                                self.durationCache[urlString] = durationSeconds
                                completion(durationSeconds)
                            } else {
                                // print("❌ PRELOAD FAIL: PlayerItem duration also indefinite for \(url.lastPathComponent)")
                                // Try final fallback
                                self.estimateDurationFromFileSize(urlString: urlString, knownFileSize: fileSize, completion: completion)
                            }
                            
                        case .failed:
                            hasCompleted = true
                            observer?.invalidate()
                            // print("❌ PRELOAD FAIL: PlayerItem failed for \(url.lastPathComponent)")
                            // Try final fallback
                            self.estimateDurationFromFileSize(urlString: urlString, knownFileSize: fileSize, completion: completion)
                            
                        default:
                            break
                        }
                    }
                }
                
                // Clean up observer after a timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    observer?.invalidate()
                    // print("⏰ TIMEOUT: PlayerItem timeout for \(url.lastPathComponent)")
                    // Try final fallback
                    self.estimateDurationFromFileSize(urlString: urlString, knownFileSize: fileSize, completion: completion)
                }
            }
        }
    }
    
    // MARK: - Duration Estimation Fallback
    private func estimateDurationFromFileSize(urlString: String, knownFileSize: Int64? = nil, completion: @escaping (TimeInterval?) -> Void) {
        guard let url = URL(string: urlString) else {
            // print("❌ ESTIMATE: Invalid URL")
            completion(nil)
            return
        }
        
        // print("📏 ESTIMATE: Trying file size estimation for \(url.lastPathComponent)")
        
        // Use known file size if available
        if let bytes = knownFileSize {
            // print("📏 ESTIMATE: Using known file size: \(bytes) bytes")
            let estimatedDuration = calculateDurationFromBytes(bytes, filename: url.lastPathComponent)
            
            if let duration = estimatedDuration {
                // print("📏 ESTIMATE SUCCESS: \(url.lastPathComponent) ≈ \(String(format: "%.1f", duration))s (estimated from known size)")
                // print("📏 ESTIMATE DETAILS:")
                // print("  ↳ File size: \(bytes) bytes")
                // print("  ↳ Calculated duration: \(String(format: "%.2f", duration))s")
                
                // Cache the estimated duration
                durationCache[urlString] = duration
                completion(duration)
            } else {
                completion(nil)
            }
            return
        }
        
        // Fallback: Create a HEAD request to get file size
        // print("📏 ESTIMATE: Getting file size via HTTP HEAD")
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3.0
        
        // Add authentication header if available
        if let token = self.sessionToken {
            request.setValue(token, forHTTPHeaderField: "x-session-token")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse,
                   let contentLength = httpResponse.allHeaderFields["Content-Length"] as? String,
                   let bytes = Int64(contentLength) {
                    
                    // print("📏 ESTIMATE: File size from HTTP: \(bytes) bytes")
                    let estimatedDuration = self?.calculateDurationFromBytes(bytes, filename: url.lastPathComponent)
                    
                    if let duration = estimatedDuration {
                        // print("📏 ESTIMATE SUCCESS: \(url.lastPathComponent) ≈ \(String(format: "%.1f", duration))s (estimated from HTTP)")
                        
                        // Cache the estimated duration
                        self?.durationCache[urlString] = duration
                        completion(duration)
                    } else {
                        completion(nil)
                    }
                } else {
                    // print("❌ ESTIMATE: Could not get file size via HTTP")
                    completion(nil)
                }
            }
        }.resume()
    }
    
    private func calculateDurationFromBytes(_ bytes: Int64, filename: String) -> TimeInterval? {
        guard bytes > 0 else {
            // print("❌ ESTIMATE: Invalid file size: \(bytes)")
            return nil
        }
        
        // Estimate bitrate based on file extension
        let lowercaseFilename = filename.lowercased()
        let estimatedBitrate: Double
        
        if lowercaseFilename.hasSuffix(".mp3") {
            // Most MP3s today are higher quality - use 192 kbps as default
            estimatedBitrate = 192000 // 192 kbps for MP3
        } else if lowercaseFilename.hasSuffix(".m4a") || lowercaseFilename.hasSuffix(".aac") {
            estimatedBitrate = 256000 // 256 kbps for AAC (common for Apple Music)
        } else if lowercaseFilename.hasSuffix(".wav") || lowercaseFilename.hasSuffix(".flac") {
            estimatedBitrate = 1411000 // ~1411 kbps for uncompressed
        } else if lowercaseFilename.hasSuffix(".ogg") {
            estimatedBitrate = 192000 // 192 kbps for OGG
        } else {
            estimatedBitrate = 192000 // Default to 192 kbps
        }
        
        // print("📏 ESTIMATE: Using bitrate \(estimatedBitrate/1000)kbps for \(filename)")
        
        let bitsPerByte: Double = 8
        let estimatedSeconds = Double(bytes * Int64(bitsPerByte)) / estimatedBitrate
        
        // Also calculate with different bitrates to show range
        let minBitrate = 128000.0
        let maxBitrate = 320000.0
        let minSeconds = Double(bytes * Int64(bitsPerByte)) / maxBitrate
        let maxSeconds = Double(bytes * Int64(bitsPerByte)) / minBitrate
        
        // print("📏 ESTIMATE RANGE:")
        // print("  ↳ At 128kbps: \(String(format: "%.1f", maxSeconds))s")
        // print("  ↳ At \(Int(estimatedBitrate/1000))kbps: \(String(format: "%.1f", estimatedSeconds))s")
        // print("  ↳ At 320kbps: \(String(format: "%.1f", minSeconds))s")
        
        if estimatedSeconds > 0 && estimatedSeconds < 7200 { // Max 2 hours seems reasonable
            return estimatedSeconds
        } else {
            // print("❌ ESTIMATE: Unreasonable duration \(estimatedSeconds)s")
            return nil
        }
    }

    // MARK: - Session Token Management
    
    func setSessionToken(_ token: String?) {
        self.sessionToken = token
    }
    
    // MARK: - Playback Control
    
    func play(url: String, isOggFile: Bool = false) {
        // print("🎵 AudioPlayerManager.play() called for: \(url)")
        // print("🎵 Current playing URL: \(currentlyPlayingURL ?? "none")")
        // print("🎵 Current playing state: \(isPlaying)")
        // print("🔐 Session token available: \(sessionToken != nil ? "YES" : "NO")")
        // print("🎵 Is OGG file (from metadata): \(isOggFile)")
        
        guard let audioURL = URL(string: url) else {
            // print("❌ Invalid audio URL: \(url)")
            return
        }
        
        // Always stop current playback when play() is called
        // This ensures only one audio plays at a time
        if currentlyPlayingURL != nil {
            // print("🛑 Stopping current playback before starting new")
            stop()
        }
        
        // print("▶️ Starting new playback for: \(url)")
        isLoading = true
        currentlyPlayingURL = url
        
        // Check if we have a cached duration for this URL
        if let cachedDuration = durationCache[url] {
            // print("📋 PLAY: Using cached duration: \(cachedDuration)s")
            duration = cachedDuration
            // print("📋 PLAY: Set duration property to: \(duration)s")
        } else {
            // print("❌ PLAY: No cached duration found for this URL")
            duration = 0
        }
        
        // Check if this is an OGG file
        let filename = audioURL.lastPathComponent.lowercased()
        let urlLowercase = url.lowercased()
        
        // Check both filename and URL for OGG indicators, or use the passed parameter
        if isOggFile || filename.hasSuffix(".ogg") || urlLowercase.contains(".ogg") || urlLowercase.contains("oog") {
            // print("🎵 OGG file detected!")
            // print("🎵 Filename: \(filename)")
            // print("🎵 Full URL: \(url)")
            // print("🎵 Detection method: \(isOggFile ? "metadata flag" : "URL/filename detection")")
            playOggFile(url: url, audioURL: audioURL)
            return
        }
        
        // Create player item with authentication headers if needed
        let asset = AVURLAsset(url: audioURL)
        
        // Add authentication headers if available
        if let sessionToken = self.sessionToken {
            let headers = ["x-session-token": sessionToken]
            // print("🔐 Adding authentication headers to AVURLAsset")
            // print("🔐 Headers: \(headers.keys.joined(separator: ", "))")
            
            // Configure the asset with headers
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            let assetWithHeaders = AVURLAsset(url: audioURL, options: options)
            playerItem = AVPlayerItem(asset: assetWithHeaders)
        } else {
            // print("⚠️ No session token available - playing without authentication")
            playerItem = AVPlayerItem(asset: asset)
        }
        
        player = AVPlayer(playerItem: playerItem)
        
        // Set up observers
        setupPlayerObservers()
        
        // FIXED: Activate audio session only when we're actually starting playback
        // This ensures we don't interrupt other apps' audio unnecessarily
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
            // print("✅ Audio session activated for playback")
        } catch {
            // print("❌ Failed to activate audio session: \(error)")
        }
        
        // Start playback
        player?.play()
        isPlaying = true
        
        // print("✅ Playback started for: \(url)")
        
        // Update playback rate if needed
        player?.rate = playbackRate
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        
        // FIXED: Deactivate audio session when pausing
        // This allows other apps to resume their audio
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            // print("✅ Audio session deactivated on pause - other apps can resume")
        } catch {
            // print("❌ Failed to deactivate audio session on pause: \(error)")
        }
    }
    
    func resumePlayback() {
        // FIXED: Reactivate audio session when resuming playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
            // print("✅ Audio session reactivated for resume")
        } catch {
            // print("❌ Failed to reactivate audio session for resume: \(error)")
        }
        
        player?.play()
        isPlaying = true
    }
    
    func stop() {
        player?.pause()
        removeTimeObserver()
        removePlayerObservers()
        
        // FIXED: Deactivate audio session when stopping playback
        // This allows other apps to resume their audio
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            // print("✅ Audio session deactivated - other apps can resume")
        } catch {
            // print("❌ Failed to deactivate audio session: \(error)")
        }
        
        player = nil
        playerItem = nil
        currentlyPlayingURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        isLoading = false
        isConvertingOgg = false
    }
    
    func seek(to time: TimeInterval) {
        guard let player = player else {
            // print("❌ Cannot seek: player is nil")
            return
        }
        
        // Ensure time is within valid range
        let clampedTime = max(0, min(time, duration))
        
        // print("🎯 Seeking to: \(String(format: "%.1f", clampedTime))s")
        
        let targetTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        
        // Simple seek without tolerance for better accuracy
        player.seek(
            to: targetTime,
            toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600)
        ) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let actualSeconds = self.player?.currentTime().seconds ?? clampedTime
                self.currentTime = actualSeconds
                
                if !finished {
                    print("⚠️ Seek to \(clampedTime)s did not finish (finished=\(finished))")
                }
            }
        }
        
        // Update current time immediately for UI responsiveness
        currentTime = clampedTime
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }
    
    // MARK: - OGG File Support
    
    private func playOggFile(url: String, audioURL: URL) {
        // print("🎧 Handling OGG file playback with OggDecoder...")
        
        // OGG files need to be downloaded first, then decoded
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tempOggFileName = "temp_audio_\(UUID().uuidString).ogg"
        let tempOggFileURL = documentsPath.appendingPathComponent(tempOggFileName)
        
        let tempPCMFileName = "temp_audio_\(UUID().uuidString).wav"
        let tempPCMFileURL = documentsPath.appendingPathComponent(tempPCMFileName)
        
        // print("📁 Downloading OGG file to: \(tempOggFileURL.path)")
        
        // Create download task with authentication headers
        var request = URLRequest(url: audioURL)
        if let token = self.sessionToken {
            request.setValue(token, forHTTPHeaderField: "x-session-token")
            // print("🔐 OGG Download: Adding authentication header")
        } else {
            // print("⚠️ OGG Download: No session token - download may fail")
        }
        
        let session = URLSession.shared
        let downloadTask = session.downloadTask(with: request) { [weak self] (location, response, error) in
            guard let self = self else { return }
            
            if let error = error {
                // print("❌ Download error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.handleOggPlaybackError()
                }
                return
            }
            
            guard let location = location else {
                // print("❌ No download location")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.handleOggPlaybackError()
                }
                return
            }
            
            do {
                // Move downloaded file to temp location
                if FileManager.default.fileExists(atPath: tempOggFileURL.path) {
                    try FileManager.default.removeItem(at: tempOggFileURL)
                }
                try FileManager.default.moveItem(at: location, to: tempOggFileURL)
                
                // print("✅ OGG file downloaded successfully")
                // print("🔄 Converting OGG to PCM using OggDecoder...")
                
                // Update UI to show conversion in progress
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isConvertingOgg = true
                }
                
                // Use OggDecoder to decode the OGG file
                let decoder = OGGDecoder()
                
                DispatchQueue.global(qos: .userInitiated).async {
                    // OggDecoder might return a URL to the decoded file
                    if let decodedFileURL = decoder.decode(tempOggFileURL) {
                        // print("✅ OGG decoded successfully")
                        // print("📊 Decoded file URL: \(decodedFileURL)")
                        
                        // Play the decoded file directly
                        DispatchQueue.main.async {
                            self.isConvertingOgg = false
                            self.playLocalFile(at: decodedFileURL, originalURL: url)
                            
                            // Clean up OGG file after a delay to ensure it's not being used
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.cleanupTempFile(at: tempOggFileURL)
                            }
                        }
                    } else {
                        // print("❌ Failed to decode OGG file - decoder returned nil")
                        
                        // Try alternative - just play the OGG file directly
                        // iOS might be able to play it with AVPlayer in some cases
                        DispatchQueue.main.async {
                            // print("⚠️ Attempting to play OGG file directly...")
                            self.isConvertingOgg = false
                            self.playLocalFile(at: tempOggFileURL, originalURL: url)
                        }
                    }
                }
                
            } catch {
                // print("❌ File operation error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.handleOggPlaybackError()
                }
            }
        }
        
        downloadTask.resume()
    }
    
    private func playLocalFile(at fileURL: URL, originalURL: String) {
        // print("🎵 Attempting to play local file: \(fileURL.lastPathComponent)")
        
        // Create player item with local file
        playerItem = AVPlayerItem(url: fileURL)
        player = AVPlayer(playerItem: playerItem)
        
        // Set up observers
        setupPlayerObservers()
        
        // FIXED: Activate audio session for local file playback too
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
            // print("✅ Audio session activated for local file playback")
        } catch {
            // print("❌ Failed to activate audio session for local file: \(error)")
        }
        
        // Start playback
        player?.play()
        isPlaying = true
        
        // print("✅ Local playback started")
        
        // Update playback rate if needed
        player?.rate = playbackRate
        
        // Clean up temp file after playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupTempFile(at: fileURL)
        }
    }
    
    private func handleOggPlaybackError() {
        // print("❌ Unable to play OGG file")
        
        // Show alert to user
        if let window = UIApplication.shared.windows.first,
           let rootViewController = window.rootViewController {
            
            var topController = rootViewController
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            
            let alert = UIAlertController(
                title: "Playback Error",
                message: "Unable to play this OGG file. The file may be corrupted or in an unsupported format. Would you like to download it instead?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Download", style: .default) { _ in
                if let url = URL(string: self.currentlyPlayingURL ?? "") {
                    UIApplication.shared.open(url)
                }
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            topController.present(alert, animated: true)
        }
        
        // Reset state
        stop()
    }
    
    private func cleanupTempFile(at fileURL: URL) {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                // print("🧹 Cleaned up temp file: \(fileURL.lastPathComponent)")
            }
        } catch {
            // print("❌ Error cleaning up temp file: \(error.localizedDescription)")
        }
    }
    
    // Create WAV header and combine with PCM data
    private func createWAVFile(from pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcmData.count
        let fileSize = dataSize + 44 - 8 // 44 is the header size, -8 for RIFF header
        
        var wavData = Data()
        
        // RIFF header
        wavData.append(contentsOf: "RIFF".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: Int32(fileSize).littleEndian) { Data($0) })
        wavData.append(contentsOf: "WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append(contentsOf: "fmt ".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Data($0) }) // fmt chunk size
        wavData.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) }) // audio format (PCM)
        wavData.append(contentsOf: withUnsafeBytes(of: Int16(channels).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: Int32(byteRate).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: Int16(blockAlign).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: Int16(bitsPerSample).littleEndian) { Data($0) })
        
        // data chunk
        wavData.append(contentsOf: "data".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: Int32(dataSize).littleEndian) { Data($0) })
        wavData.append(pcmData)
        
        return wavData
    }
    
    // MARK: - Private Methods
    
    private func setupPlayerObservers() {
        guard let playerItem = playerItem else { return }
        
        // Time observer for progress updates
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            let newTime = time.seconds
            
            // Only update if time has actually changed significantly
            if abs(newTime - self.currentTime) > 0.05 {
                self.currentTime = newTime
            }
        }
        
        // Duration observer
        playerItem.publisher(for: \.duration)
            .sink { [weak self] duration in
                if duration.isValid && !duration.isIndefinite {
                    let durationSeconds = duration.seconds
                    // Only accept reasonable durations (more than 1 second)
                    if durationSeconds > 1.0 {
                        // Only update if we don't have a better cached duration or if the new duration is significantly different
                        if let currentCachedDuration = self?.durationCache[self?.currentlyPlayingURL ?? ""],
                           abs(currentCachedDuration - durationSeconds) < 1.0 {
                            // The cached duration is very similar, keep using it
                            // print("📋 Keeping cached duration: \(currentCachedDuration)s (received: \(durationSeconds)s)")
                        } else {
                            // Update with the new duration
                            let oldDuration = self?.duration ?? 0
                            self?.duration = durationSeconds
                            // print("✅ Valid duration received: \(durationSeconds)s")
                            // print("📊 DURATION CHANGE: \(String(format: "%.1f", oldDuration))s → \(String(format: "%.1f", durationSeconds))s")
                            
                            if abs(oldDuration - durationSeconds) > 10 {
                                // print("⚠️ LARGE DURATION CHANGE DETECTED!")
                                // print("  ↳ Old: \(String(format: "%.1f", oldDuration))s")
                                // print("  ↳ New: \(String(format: "%.1f", durationSeconds))s")
                                // print("  ↳ Difference: \(String(format: "%.1f", abs(oldDuration - durationSeconds)))s")
                            }
                            
                            // Update cache with the new duration
                            if let url = self?.currentlyPlayingURL {
                                self?.durationCache[url] = durationSeconds
                            }
                        }
                        
                        // Update buffering progress when duration becomes available
                        DispatchQueue.main.async {
                            self?.updateBufferingProgress()
                        }
                    } else {
                        // print("⚠️ Ignoring invalid duration: \(durationSeconds)s")
                    }
                }
            }
            .store(in: &cancellables)
        
        // Status observer
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                DispatchQueue.main.async {
                    switch status {
                    case .readyToPlay:
                        self?.isLoading = false
                        // Get initial duration - but respect cached values
                        if let playerItem = self?.playerItem {
                            let duration = playerItem.duration
                            if duration.isValid && !duration.isIndefinite {
                                let durationSeconds = duration.seconds
                                // Only accept reasonable durations
                                if durationSeconds > 1.0 {
                                    // Check if we have a cached duration
                                    if let currentCachedDuration = self?.durationCache[self?.currentlyPlayingURL ?? ""],
                                       abs(currentCachedDuration - durationSeconds) < 1.0 {
                                        // Use cached duration
                                        self?.duration = currentCachedDuration
                                        // print("📋 Using cached duration on ready: \(currentCachedDuration)s")
                                    } else {
                                        // Use the new duration
                                        self?.duration = durationSeconds
                                        // print("✅ Initial duration set: \(durationSeconds)s")
                                        
                                        // Update cache
                                        if let url = self?.currentlyPlayingURL {
                                            self?.durationCache[url] = durationSeconds
                                        }
                                    }
                                } else {
                                    // print("⚠️ Ignoring invalid initial duration: \(durationSeconds)s")
                                }
                            }
                        }
                        self?.updateBufferingProgress()
                    case .failed:
                        self?.isLoading = false
                        // print("Player item failed: \(String(describing: playerItem.error))")
                    case .unknown:
                        self?.isLoading = true
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
            
        // Buffering observer
        playerItem.publisher(for: \.loadedTimeRanges)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateBufferingProgress()
                }
            }
            .store(in: &cancellables)
            
        // Playback buffer empty observer
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .sink { [weak self] isEmpty in
                DispatchQueue.main.async {
                    self?.isBuffering = isEmpty
                    if !isEmpty {
                        self?.updateBufferingProgress()
                    }
                }
            }
            .store(in: &cancellables)
            
        // Initial buffering update
        DispatchQueue.main.async {
            // Try to get initial duration
            let duration = playerItem.duration
            if duration.isValid && !duration.isIndefinite {
                let durationSeconds = duration.seconds
                // Only accept reasonable durations
                if durationSeconds > 1.0 {
                    self.duration = durationSeconds
                    // print("✅ Initial async duration set: \(durationSeconds)s")
                } else {
                    // print("⚠️ Ignoring invalid initial async duration: \(durationSeconds)s")
                }
            }
            self.updateBufferingProgress()
        }
        
        // Playback finished observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Playback stalled observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: playerItem
        )
    }
    
    private func removePlayerObservers() {
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }
    
    private func removeTimeObserver() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
    
    private func cleanup() {
        stop()
        removePlayerObservers()
        // Clear duration cache periodically to prevent memory issues
        // Keep only the most recent 10 durations
        if durationCache.count > 10 {
            let sortedURLs = Array(durationCache.keys.prefix(10))
            let newCache = Dictionary(uniqueKeysWithValues: sortedURLs.map { ($0, durationCache[$0]!) })
            durationCache = newCache
            // print("🧹 Cleaned duration cache - kept \(newCache.count) entries")
        }
    }
    
    // Clear all cached durations (useful for memory management)
    func clearDurationCache() {
        durationCache.removeAll()
        // print("🧹 Cleared all cached durations")
    }
    
    // Get cache statistics for debugging
    func getCacheStats() -> (count: Int, urls: [String]) {
        let urls = Array(durationCache.keys).map { URL(string: $0)?.lastPathComponent ?? $0 }
        return (durationCache.count, urls)
    }
    
    // Print cache summary
    func printCacheSummary() {
        let stats = getCacheStats()
        // print("💾 CACHE SUMMARY: \(stats.count) durations cached")
        for (index, filename) in stats.urls.enumerated() {
            if let url = durationCache.keys.first(where: { URL(string: $0)?.lastPathComponent == filename }),
               let duration = durationCache[url] {
                // print("  [\(index + 1)] \(filename): \(String(format: "%.1f", duration))s")
            }
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = 0
        }
    }
    
    @objc private func playerStalled() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.isBuffering = true
        }
    }
    
    // MARK: - Buffering Methods
    
    private func updateBufferingProgress() {
        guard let playerItem = playerItem else { return }
        
        // Get all buffered ranges
        let loadedRanges = playerItem.loadedTimeRanges
        bufferedRanges = loadedRanges.map { $0.timeRangeValue }
        
        // Calculate total buffered duration
        var totalBufferedSeconds: TimeInterval = 0
        
        // Log each buffered range
        // print("\n🔄 Current buffered ranges:")
        for (index, range) in bufferedRanges.enumerated() {
            let startSeconds = range.start.seconds
            let durationSeconds = range.duration.seconds
            let endSeconds = startSeconds + durationSeconds
            totalBufferedSeconds += durationSeconds
            
            // print("  📍 Range \(index + 1): \(String(format: "%.1f", startSeconds))s → \(String(format: "%.1f", endSeconds))s (duration: \(String(format: "%.1f", durationSeconds))s)")
        }
        
        // Get the expected duration from the player item
        let expectedDuration: TimeInterval
        
        // First try to get duration from player item
        let itemDuration = playerItem.duration
        if itemDuration.isValid && !itemDuration.isIndefinite {
            expectedDuration = itemDuration.seconds
        } else {
            // If that fails, try to get cached duration
            if let cachedDuration = durationCache[currentlyPlayingURL ?? ""] {
                expectedDuration = cachedDuration
                // print("📋 Using cached duration for buffering: \(cachedDuration)s")
            } else {
                // If no cached duration, try to get duration from loaded ranges
                expectedDuration = totalBufferedSeconds
            }
        }
        
        // Update duration if we got a valid one (and it's reasonable)
        if expectedDuration > 1.0 && expectedDuration != self.duration {
            self.duration = expectedDuration
            // print("✅ Duration updated from buffering: \(expectedDuration)s")
        } else if expectedDuration <= 1.0 && expectedDuration > 0 {
            // print("⚠️ Ignoring unreasonable duration from buffering: \(expectedDuration)s")
        }
        
        // Use the larger value between expected and current duration
        let currentDuration = max(expectedDuration, self.duration)
        
        // print("\n📊 Duration Info:")
        if currentDuration > 0 {
            // print("  ↳ Expected Duration: \(String(format: "%.1f", expectedDuration))s")
            // print("  ↳ Current Duration: \(String(format: "%.1f", currentDuration))s")
            // print("  ↳ Buffered: \(String(format: "%.1f", totalBufferedSeconds))s")
        } else {
            // print("  ↳ Duration: Not available yet")
            // print("  ↳ Buffered: \(String(format: "%.1f", totalBufferedSeconds))s")
            
            // Try to estimate duration from buffered content
            if totalBufferedSeconds > 0 {
                // print("  ↳ Estimated minimum duration: \(String(format: "%.1f", totalBufferedSeconds))s")
            }
        }
        
        // Calculate progress as a percentage of total duration or buffered content
        let effectiveDuration = currentDuration > 0 ? currentDuration : totalBufferedSeconds
        if effectiveDuration > 0 {
            // Store old progress for comparison
            let oldProgress = bufferingProgress
            
            // Update progress
            bufferingProgress = Float(totalBufferedSeconds / effectiveDuration)
            
            // Always log download progress
            // print("\n📶 Download Progress:")
            // print("  ↳ Downloaded: \(String(format: "%.1f", totalBufferedSeconds))s")
            if currentDuration > 0 {
                // print("  ↳ Total Duration: \(String(format: "%.1f", currentDuration))s")
                // print("  ↳ Percentage: \(Int(bufferingProgress * 100))%")
                
                // Visual progress bar in console
                let barWidth = 30
                let safeProgress = min(max(bufferingProgress, 0), 1.0)
                let filledCount = Int(Float(barWidth) * safeProgress)
                let emptyCount = barWidth - filledCount
                let bar = String(repeating: "█", count: filledCount) + String(repeating: "▒", count: emptyCount)
                // print("  ↳ [\(bar)] \(Int(bufferingProgress * 100))%")
                
                // Log if there was a significant change
                if abs(oldProgress - bufferingProgress) > 0.01 {
                    // print("  ↳ Changed: \(Int(oldProgress * 100))% → \(Int(bufferingProgress * 100))%")
                }
            } else {
                // print("  ↳ (Duration unknown - showing buffered content only)")
            }
        }
        
        // Log buffering state
        if isBuffering {
            // print("\n⏳ Buffering in progress...")
        }
        
        // Add a separator for better readability
        // print("----------------------------------------")
    }
    
    private func isTimeBuffered(_ time: TimeInterval) -> Bool {
        // Convert time to CMTime for comparison
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        
        // Check if the time falls within any buffered range
        for range in bufferedRanges {
            if range.containsTime(targetTime) {
                return true
            }
        }
        
        return false
    }
} 
