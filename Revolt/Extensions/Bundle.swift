//
//  Bundle.swift
//  Revolt
//
//  Created by Angelo on 19/06/2024.
//

import SwiftUI

/// An extension to the `Bundle` class to provide easy access to the app's versioning information.
extension Bundle {
    
    /// A computed property that retrieves the release version number of the app.
    /// This corresponds to the `CFBundleShortVersionString` in the app's `Info.plist`.
    ///
    /// - Returns: A string representing the release version number, or `nil` if it cannot be found.
    ///
    /// - Usage:
    /// ```swift
    /// if let releaseVersion = Bundle.main.releaseVersionNumber {
    ///     print("Release Version: \(releaseVersion)")
    /// }
    /// ```
    var releaseVersionNumber: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
    }
    
    /// A computed property that retrieves the build version number of the app.
    /// This corresponds to the `CFBundleVersion` in the app's `Info.plist`.
    ///
    /// - Returns: A string representing the build version number, or `nil` if it cannot be found.
    ///
    /// - Usage:
    /// ```swift
    /// if let buildVersion = Bundle.main.buildVersionNumber {
    ///     print("Build Version: \(buildVersion)")
    /// }
    /// ```
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}
