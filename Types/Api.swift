//
//  Api.swift
//  Revolt
//
//  Created by Zomatree on 21/04/2023.
//

import Foundation

// MARK: - CaptchaFeature Structure

/// Represents the configuration for captcha features in the API.
public struct CaptchaFeature: Codable {
    /// Initializes a new instance of `CaptchaFeature`.
    /// - Parameters:
    ///   - enabled: A boolean indicating whether the captcha feature is enabled.
    ///   - key: Client key used for solving captcha.
    public init(enabled: Bool, key: String) {
        self.enabled = enabled
        self.key = key
    }
    
    public var enabled: Bool // Indicates if captcha is enabled.
    public var key: String // The key for the captcha service.
}

// MARK: - RevoltFeature Structure

/// Represents a general feature configuration in the Revolt API.
public struct RevoltFeature: Codable {
    /// Initializes a new instance of `RevoltFeature`.
    /// - Parameters:
    ///   - enabled: A boolean indicating whether the feature is enabled.
    ///   - url: URL pointing to the service.
    public init(enabled: Bool, url: String) {
        self.enabled = enabled
        self.url = url
    }
    
    public var enabled: Bool // Indicates if the feature is enabled.
    public var url: String // The URL for the feature.
}

// MARK: - VortexFeature Structure

/// Represents the configuration for the Vortex feature in the API.
public struct VortexFeature: Codable {
    /// Initializes a new instance of `VortexFeature`.
    /// - Parameters:
    ///   - enabled: Whether voice is enabled.
    ///   - url: URL pointing to the voice API.
    ///   - ws: URL pointing to the voice WebSocket server.
    public init(enabled: Bool, url: String, ws: String) {
        self.enabled = enabled
        self.url = url
        self.ws = ws
    }
    
    public var enabled: Bool // Whether voice is enabled.
    public var url: String  //URL pointing to the voice API.
    public var ws: String //URL pointing to the voice WebSocket server.
}

// MARK: - ApiFeatures Structure

/// Represents the collection of features available in the API.
public struct ApiFeatures: Codable {
    /// Initializes a new instance of `ApiFeatures`.
    /// - Parameters:
    ///   - captcha: Configuration for the captcha feature.
    ///   - email: A boolean indicating if email feature is enabled (Whether email verification is enabled).
    ///   - invite_only: A boolean indicating if the API is invite-only.
    ///   - autumn: File server service configuration.
    ///   - january: Proxy service configuration..
    ///   - voso: Voice server configuration..
    public init(captcha: CaptchaFeature, email: Bool, invite_only: Bool, autumn: RevoltFeature, january: RevoltFeature, voso: VortexFeature) {
        self.captcha = captcha
        self.email = email
        self.invite_only = invite_only
        self.autumn = autumn
        self.january = january
        self.voso = voso
    }
    
    public var captcha: CaptchaFeature // Configuration for the captcha feature.
    public var email: Bool // Indicates if email feature is enabled.
    public var invite_only: Bool // Indicates if the API is invite-only.
    public var autumn: RevoltFeature // Configuration for the autumn feature.
    public var january: RevoltFeature // Configuration for the January feature.
    public var voso: VortexFeature // Configuration for the Vortex feature.
}

// MARK: - ApiInfo Structure

/// Represents information about the API and its features.
public struct ApiInfo: Codable {
    /// Initializes a new instance of `ApiInfo`.
    /// - Parameters:
    ///   - revolt: The Revolt API version or identifier.
    ///   - features: Features enabled on this Revolt node.
    ///   - ws: The WebSocket URL for the API.
    ///   - app: URL pointing to the client serving this node.
    ///   - vapid: Web Push VAPID public key
    public init(revolt: String, features: ApiFeatures, ws: String, app: String, vapid: String) {
        self.revolt = revolt
        self.features = features
        self.ws = ws
        self.app = app
        self.vapid = vapid
    }
    
    public var revolt: String // The Revolt API version or identifier.
    public var features: ApiFeatures // Features available in the API.
    public var ws: String // WebSocket URL for the API.
    public var app: String // The application name or identifier.
    public var vapid: String // The VAPID key for Web Push notifications.
}

// MARK: - Session Structure

/// Represents a user session in the API.
public struct Session: Codable, Identifiable {
    /// Initializes a new instance of `Session`.
    /// - Parameters:
    ///   - id: Unique identifier for the session.
    ///   - name: Name associated with the session.
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
    
    public var id: String // Unique identifier for the session.
    public var name: String // Name associated with the session.
    
    enum CodingKeys: String, CodingKey { case id = "_id", name } // Custom coding keys for JSON encoding/decoding.
}
