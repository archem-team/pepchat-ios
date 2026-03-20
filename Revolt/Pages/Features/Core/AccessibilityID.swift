//
//  AccessibilityID.swift
//  Revolt
//
//  Type-safe accessibility identifiers for UI testing.
//  Keys follow the pattern: feature.section.element
//

import SwiftUI

/// Type-safe accessibility identifiers with autocomplete support.
/// Usage: .accessibilityID(AccessibilityID.auth.login.emailField)
enum AccessibilityID {

    // MARK: - Intro

    /// Intro / platform selection screen
    enum intro {
        static func platformButton(_ name: String) -> String { "intro.platformButton.\(name)" }
        static let apiUrlField = "intro.apiUrlField"
        static let confirmButton = "intro.confirmButton"
    }

    // MARK: - Welcome

    /// Welcome screen (register / login choice)
    enum welcome {
        static let registerButton = "welcome.registerButton"
        static let loginButton = "welcome.loginButton"
        static let resendVerificationLink = "welcome.resendVerificationLink"
    }

    // MARK: - Auth

    /// Authentication screens (Login, SignUp, ForgotPassword)
    enum auth {
        enum login {
            static let emailField = "auth.login.emailField"
            static let passwordField = "auth.login.passwordField"
            static let loginButton = "auth.login.loginButton"
            static let forgotPasswordLink = "auth.login.forgotPasswordLink"
            static let registerLink = "auth.login.registerLink"
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies an accessibility identifier from the AccessibilityID enum
    func accessibilityID(_ identifier: String) -> some View {
        self.accessibilityIdentifier(identifier)
    }
}
