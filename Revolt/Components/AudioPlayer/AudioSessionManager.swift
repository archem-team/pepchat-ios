//
//  AudioSessionManager.swift
//  Revolt
//
//

import AVFoundation
import UIKit

// MARK: - AudioSessionManager
class AudioSessionManager: NSObject {
    static let shared = AudioSessionManager()
    
    private let audioManager = AudioPlayerManager.shared
    
    private override init() {
        super.init()
        setupAudioSessionNotifications()
    }
    
    private func setupAudioSessionNotifications() {
        // Handle audio session interruptions (like phone calls)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        // Handle audio route changes (like unplugging headphones)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        // Handle app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Audio session was interrupted (phone call, alarm, etc.)
            print("🔊 Audio session interrupted - pausing playback")
            audioManager.pause()
            
        case .ended:
            // Audio session interruption ended
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // We can resume playback automatically
                print("🔊 Audio session interruption ended - can resume")
                // Don't auto-resume, let user manually resume for better UX
            } else {
                print("🔊 Audio session interruption ended - manual resume required")
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged or Bluetooth device disconnected
            print("🎧 Audio device disconnected - pausing playback")
            audioManager.pause()
            
        case .newDeviceAvailable:
            // New audio device connected
            print("🎧 Audio device connected")
            // Don't auto-resume, let user choose
            
        case .routeConfigurationChange:
            // Audio route configuration changed
            print("🔊 Audio route configuration changed")
            
        default:
            break
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Continue playing in background if audio is playing
        // iOS will automatically handle this for AVPlayer
        print("📱 App entered background - audio can continue playing")
    }
    
    @objc private func appWillEnterForeground() {
        // FIXED: Only activate audio session if we're actually playing audio
        // This prevents interrupting other apps like Spotify when our app enters foreground
        
        // Check if we have audio currently playing
        guard audioManager.isPlaying else {
            print("📱 App entering foreground - no audio playing, keeping audio session inactive to avoid interrupting other apps")
            return
        }
        
        // Only activate if we're actually playing audio
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Configure audio session to allow mixing with other apps
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth, .mixWithOthers])
            
            // Only activate if not already active
            if !session.isOtherAudioPlaying {
                try session.setActive(true)
                print("📱 App entering foreground - audio session reactivated (audio was playing)")
            } else {
                print("📱 App entering foreground - other audio is playing, keeping session inactive")
            }
            
        } catch {
            print("❌ Failed to configure/activate audio session: \(error)")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 
