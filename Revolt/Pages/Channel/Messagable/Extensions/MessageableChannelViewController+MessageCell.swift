//
//  MessageableChannelViewController+MessageCell.swift
//  Revolt
//
//  Created by Akshat Srivastava on 20/01/26.
//

import Foundation
import Combine
import Kingfisher
import ObjectiveC
import SwiftUI
import Types
import UIKit
import ULID

// Replace the existing extension for MessageCell with this one
extension MessageCell {
    private struct AssociatedKeys {
        static var reactionsEnabledKey = "reactionsEnabled"
    }

    // Add this property to MessageCell to control reaction button visibility
    var reactionsEnabled: Bool {
        get {
            // Get associated object or return default value
            return objc_getAssociatedObject(self, &AssociatedKeys.reactionsEnabledKey) as? Bool
                ?? true
        }
        set {
            // Store new value using associated object
            objc_setAssociatedObject(
                self,
                &AssociatedKeys.reactionsEnabledKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            // Update UI based on the new value
            updateReactionsVisibility()
        }
    }

    // Update the visibility of reaction buttons
    private func updateReactionsVisibility() {
        // Update any reaction buttons based on the enabled state
        reactionButton?.isHidden = !reactionsEnabled
    }

    // Add a property for the reaction button - you'll need to implement this
    private var reactionButton: UIButton? {
        // Return the actual reaction button from your view hierarchy
        return subviews.compactMap { $0 as? UIButton }.first(where: {
            $0.accessibilityIdentifier == "reactionButton"
        })
    }
}


// Add the uploadButtonEnabled property to MessageInputView class
extension MessageInputView {
    private struct AssociatedKeys {
        static var uploadButtonEnabledKey = "uploadButtonEnabled"
    }

    // Add this property to control upload button visibility
    var uploadButtonEnabled: Bool {
        get {
            // Return stored value or default
            return objc_getAssociatedObject(self, &AssociatedKeys.uploadButtonEnabledKey) as? Bool
                ?? true
        }
        set {
            // Store the value
            objc_setAssociatedObject(
                self,
                &AssociatedKeys.uploadButtonEnabledKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            // Update the upload button visibility
            uploadButton?.isHidden = !newValue
        }
    }

    // Optional upload button reference - implement as needed
    var uploadButton: UIButton? {
        // Return the actual upload button from your view hierarchy
        return subviews.compactMap { $0 as? UIButton }.first(where: {
            $0.accessibilityIdentifier == "uploadButton"
        })
    }
}
