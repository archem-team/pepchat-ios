//
//  MessageableChannelConstants.swift
//  Revolt
//
//

import Foundation
import UIKit

enum MessageableChannelConstants {
    // Loading and API constants
    static let minimumAPICallInterval: TimeInterval = 3.0
    static let networkErrorCooldown: TimeInterval = 5.0
    static let scrollDebounceInterval: TimeInterval = 2.0
    static let maxLogMessages = 20
    
    // UI constants
    static let nearBottomThreshold: CGFloat = 50.0  // Reduced from 100 to 50 pixels
    static let scrollProtectionInterval: TimeInterval = 1.0
    
    // Animation constants
    static let fadeAnimationDuration: TimeInterval = 0.3
    static let pulseAnimationDuration: TimeInterval = 0.5
    
    // Toast constants
    static let toastDefaultDuration: TimeInterval = 2.0
    static let toastTopMargin: CGFloat = 20.0
    static let toastSideMargin: CGFloat = 40.0
    
    // Message loading constants
    static let messageLoadLimit = 50
    static let retryMaxAttempts = 3
    static let retryBaseDelay: TimeInterval = 1.0
    static let maxMessagesInMemory = 100
}
