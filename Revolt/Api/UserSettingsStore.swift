//
//  UserSettingsStore.swift
//  Revolt
//
//  Created by Angelo on 2024-02-23.
//

import Foundation
import Observation
import OSLog
import Sentry
import Types

// Logger for tracking events in the settings store.
let logger = Logger(subsystem: "chat.peptide.app", category: "settingsStore")

// MARK: - Discardable caches

/// Represents the multi-factor authentication (MFA) status of an account.
struct AccountSettingsMFAStatus: Codable {
    var email_otp: Bool // Email OTP MFA enabled status.
    var trusted_handover: Bool // Trusted handover MFA enabled status.
    var email_mfa: Bool // Email-based MFA enabled status.
    var totp_mfa: Bool // Time-based one-time password MFA enabled status.
    var security_key_mfa: Bool // Security key-based MFA enabled status.
    var recovery_active: Bool // Indicates if recovery is active.
    
    /// Checks if any MFA method is active.
    var anyMFA: Bool {
        return email_otp || totp_mfa || recovery_active || email_mfa || security_key_mfa || trusted_handover
    }
}

/// Represents user account data.
struct UserSettingsAccountData: Codable {
    var email: String // User's email address.
    var mfaStatus: AccountSettingsMFAStatus // MFA status for the account.
}

enum NotificationState: String, Encodable {
    case  useDefault, all, mention, muted, none
}

extension NotificationState: Decodable {
    enum Inner: String, Decodable {
        case all, mention, muted, none
    }
    
    init(from decoder: any Decoder) throws {
        do {
            switch try decoder.singleValueContainer().decode(Inner.self) {
            case .all: self = .all
            case .mention: self = .mention
            case .muted: self = .muted
            case .none: self = .none
            }
        } catch {
            self = .all
        }
    }
}


struct UserSettingsNotificationsData: Codable {
    var server: [String: NotificationState]
    var channel: [String: NotificationState]
}


struct OrderingSettings : Codable {
    var servers: [String] = []
}


@Observable
class DiscardableUserStore: Codable {
    var user: Types.User? // Current user data.
    var accountData: UserSettingsAccountData? // User account data.
    var notificationSettings: UserSettingsNotificationsData = .init(server: [:], channel: [:])
    var orderSettings : OrderingSettings = .init(servers: [])
    
    /// Clears the user and account data.
    fileprivate func clear() {
        user = nil
        accountData = nil
        notificationSettings = .init(server: [:], channel: [:])
    }
    
    enum CodingKeys: String, CodingKey {
        case _user = "user"
        case _accountData = "accountData"
        case _notificationSettings = "notificationSettings"
    }
}

// MARK: - Persistent settings

@Observable
class NotificationOptionsData: Codable {
    var keyWasSet: () -> Void = {} // Callback when a key is set.
    
    // Indicates if remote notifications were rejected.
    var rejectedRemoteNotifications: Bool {
        didSet(newSetting) {
            keyWasSet() // Notify when changed.
        }
    }
    
    // Indicates if notifications should be allowed while the app is running.
    var wantsNotificationsWhileAppRunning: Bool {
        didSet(newSetting) {
            keyWasSet() // Notify when changed.
        }
    }
    
    // Initializer with specified settings.
    init(keyWasSet: @escaping () -> Void, rejectedRemoteNotifications: Bool, wantsNotificationsWhileAppRunning: Bool) {
        self.rejectedRemoteNotifications = rejectedRemoteNotifications
        self.wantsNotificationsWhileAppRunning = wantsNotificationsWhileAppRunning
        self.keyWasSet = keyWasSet
    }
    
    // Default initializer.
    init(keyWasSet: @escaping () -> Void) {
        self.rejectedRemoteNotifications = true
        self.wantsNotificationsWhileAppRunning = true
        self.keyWasSet = keyWasSet
    }
    
    init() {
        self.rejectedRemoteNotifications = true
        self.wantsNotificationsWhileAppRunning = true
    }
    
    enum CodingKeys: String, CodingKey {
        case _rejectedRemoteNotifications = "rejectedRemoteNotifications"
        case _wantsNotificationsWhileAppRunning = "wantsNotificationsWhileAppRunning"
    }
}

@Observable
class ExperimentOptionsData: Codable {
    var keyWasSet: () -> Void = {} // Callback when a key is set.
    
    // Indicates if custom markdown formatting is enabled.
    var customMarkdown: Bool {
        didSet(newSetting) {
            keyWasSet() // Notify when changed.
        }
    }
    
    // Initializers for experiment options data.
    init(keyWasSet: @escaping () -> Void, customMarkdown: Bool) {
        self.customMarkdown = customMarkdown
        self.keyWasSet = keyWasSet
    }
    
    init(keyWasSet: @escaping () -> Void) {
        customMarkdown = false
        self.keyWasSet = keyWasSet
    }
    
    init() {
        self.customMarkdown = true
    }
    
    enum CodingKeys: String, CodingKey {
        case _customMarkdown = "customMarkdown"
    }
}

@Observable
class PersistentUserSettingsStore: Codable {
    var keyWasSet: () -> Void = {} // Callback when a key is set.
    
    var notifications: NotificationOptionsData // Notification settings.
    
    // Stores the last open channels by identifier.
    var lastOpenChannels: [String: String] {
        didSet {
            keyWasSet() // Notify when changed.
        }
    }
    
    // Stores the closed categories and their corresponding channels.
    var closedCategories: [String: Set<String>] {
        didSet {
            keyWasSet() // Notify when changed.
        }
    }
    
    var experiments: ExperimentOptionsData // Experiment settings.
    
    // Initializer with specified settings.
    init(keyWasSet: @escaping () -> Void, notifications: NotificationOptionsData, lastOpenChannels: [String: String], closedCategories: [String: Set<String>], experiments: ExperimentOptionsData) {
        self.notifications = notifications
        self.lastOpenChannels = lastOpenChannels
        self.closedCategories = closedCategories
        self.experiments = experiments
        self.keyWasSet = keyWasSet
    }
    
    // Default initializer.
    init() {
        self.notifications = NotificationOptionsData()
        self.lastOpenChannels = [:]
        self.closedCategories = [:]
        self.experiments = ExperimentOptionsData()
    }
    
    // Updates the keyWasSet callback for notifications and experiments.
    fileprivate func updateDecodeWithCallback(keyWasSet: @escaping () -> Void) {
        self._notifications.keyWasSet = keyWasSet
        self._experiments.keyWasSet = keyWasSet
        self.keyWasSet = keyWasSet
    }
    
    enum CodingKeys: String, CodingKey {
        case _notifications = "notifications"
        case _lastOpenChannels = "lastOpenChannels"
        case _closedCategories = "closedCategories"
        case _experiments = "experiments"
    }
}

class UserSettingsData {
    enum SettingsFetchState {
        case fetching, failed, cached // Different states for settings fetching.
    }
    
    var viewState: ViewState? // Current state of the view.
    
    var cache: DiscardableUserStore // Temporary user data cache.
    var cacheState: SettingsFetchState // Current state of the cache.
    
    var store: PersistentUserSettingsStore // Persistent user settings storage.
    
    // File URL for the cache file.
    static var cacheFile: URL? {
        if let caches = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let revoltDir = caches.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
            let resp = revoltDir.appendingPathComponent("userInfoCache", conformingTo: .json)
            return resp
        }
        return nil
    }
    
    // File URL for the settings store file.
    static var storeFile: URL? {
        if let caches = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let revoltDir = caches.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
            let resp = revoltDir.appendingPathComponent("userSettings", conformingTo: .json)
            return resp
        }
        return nil
    }
    
    // Initializer for UserSettingsData with specified cache and store.
    init(viewState: ViewState?, cache: DiscardableUserStore, store: PersistentUserSettingsStore, isLoginUser : Bool) {
        self.viewState = viewState
        self.cache = cache
        self.cacheState = .cached
        self.store = store
        self.store.updateDecodeWithCallback(keyWasSet: storeKeyWasSet)
        
        if isLoginUser {
            createFetchTask() // Start fetching settings from API.
        }
    }
    
    // Initializer for UserSettingsData with specified store.
    init(viewState: ViewState?, store: PersistentUserSettingsStore, isLoginUser : Bool) {
        self.viewState = viewState
        self.cache = DiscardableUserStore()
        self.cacheState = .fetching
        
        self.store = store
        self.store.updateDecodeWithCallback(keyWasSet: storeKeyWasSet)
        
        if isLoginUser {
            createFetchTask() // Start fetching settings from API.
        }
    }
    
    // Default initializer for UserSettingsData.
    init(viewState: ViewState?, isLoginUser : Bool) {
        self.viewState = viewState
        self.cache = DiscardableUserStore()
        self.cacheState = .fetching
        
        self.store = PersistentUserSettingsStore()
        self.store.updateDecodeWithCallback(keyWasSet: storeKeyWasSet)
        
        if isLoginUser {
            createFetchTask() // Start fetching settings from API.
        }
    }
    
    // Attempts to read cached and persistent settings data.
    class func maybeRead(viewState: ViewState?, isLoginUser : Bool) -> UserSettingsData {
        var cache: DiscardableUserStore? = nil
        var store: PersistentUserSettingsStore? = nil
        
        var fileContents: Data?
        do {
            let filePath = UserSettingsData.cacheFile!
            fileContents = try Data(contentsOf: filePath) // Read cache file.
        } catch {
            logger.debug("settingsCache file does not exist, will rebuild. \(error.localizedDescription)")
        }
        
        do {
            if fileContents != nil {
                cache = try JSONDecoder().decode(DiscardableUserStore.self, from: fileContents!) // Decode cache.
            }
        } catch {
            logger.warning("Failed to parse the existing cache file. Will discard cache and rebuild. \(error.localizedDescription)")
        }
        
        var storefileContents: Data? = nil
        do {
            let filePath = UserSettingsData.storeFile!
            storefileContents = try Data(contentsOf: filePath) // Read store file.
        } catch {
            logger.warning("User settings have been removed. Will rebuild from scratch. \(error.localizedDescription)")
        }
        
        do {
            if storefileContents != nil {
                store = try JSONDecoder().decode(PersistentUserSettingsStore.self, from: storefileContents!) // Decode store.
            }
        } catch {
            logger.warning("Failed to parse the existing settings store file. Settings may have been lost. \(error.localizedDescription)")
        }
        
        // Return UserSettingsData based on available cache/store.
        if store != nil && cache != nil {
            return UserSettingsData(viewState: viewState, cache: cache!, store: store!, isLoginUser: isLoginUser)
        } else if store != nil {
            return UserSettingsData(viewState: viewState, store: store!, isLoginUser: isLoginUser)
        } else {
            return UserSettingsData(viewState: viewState, isLoginUser: isLoginUser) // Default initialization.
        }
    }
    
    // Callback when a key is set in the store.
    private func storeKeyWasSet() {
        DispatchQueue.main.async(qos: .utility) {
            self.writeStoreToFile() // Write updated store to file.
        }
    }
    
    // Creates a fetch task to retrieve settings from the API.
    func createFetchTask() {
        Task(priority: .medium, operation: self.fetchFromApi)
    }
    
    // Fetches user settings from the API asynchronously.
    func fetchFromApi() async {
        while viewState == nil {
            do {
                try await Task.sleep(for: .seconds(0.1))
            } catch {
                logger.error("Failed to sleep: \(error.localizedDescription)")
                return // Exit if Task.sleep fails.
            }
        }
        
        let state = viewState!
        if await state.state == .signedOut {
            return // No need to fetch if signed out.
        }
        
        do {
            // Fetch user data and account information.
            self.cache.user = try await state.http.fetchSelf().get()
            self.cache.accountData = UserSettingsAccountData(
                email: try await state.http.fetchAccount().get().email,
                mfaStatus: try await state.http.fetchMFAStatus().get()
            )
            
            // Fetch settings
            let settingsValues = try await state.http
                .fetchSettings(keys: ["theme", "appearance", "locale", "notifications", "ordering", "changelog"])
                .get()
            
            
            storeFetchData(settingsValues: settingsValues)
            
            
            
            
            
        } catch let revoltError as RevoltError {
            self.cacheState = .failed // Update cache state to failed.
            switch revoltError {
            case .Alamofire(let afErr):
                if afErr.responseCode == 401 {
                    await state.setSignedOutState() // Handle unauthorized access.
                } else {
                    SentrySDK.capture(error: revoltError) // Capture the error.
                }
            case .HTTPError(_, let status):
                if status == 401 {
                    await state.setSignedOutState() // Handle unauthorized access.
                } else {
                    SentrySDK.capture(error: revoltError) // Capture the error.
                }
            default:
                logger.error("An error occurred while fetching user settings: \(revoltError.localizedDescription)")
                SentrySDK.capture(error: revoltError) // Capture the error.
            }
        } catch {
            self.cacheState = .failed // Update cache state to failed.
            logger.error("An unexpected error occurred: \(error.localizedDescription)")
            SentrySDK.capture(error: error) // Capture the error.
        }
    }
    
    // Writes the current cache to file asynchronously.
    /*func writeCacheToFile() {
     DispatchQueue.main.async(qos: .utility) {
     if let caches = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
     let revoltDir = caches.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
     do {
     try FileManager.default.createDirectory(at: revoltDir, withIntermediateDirectories: false) // Create directory if it doesn't exist.
     } catch {} // Ignore error if it already exists
     
     do {
     let encoded = try JSONEncoder().encode(self.cache) // Encode cache data.
     let filePath = UserSettingsData.cacheFile!
     logger.debug("will write cache to: \(filePath.absoluteString)")
     try encoded.write(to: filePath) // Write encoded cache to file.
     } catch {
     logger.error("Failed to serialize the cache: \(error.localizedDescription)") // Log error.
     }
     } else {
     logger.warning("Caches are not accessible. Skipping cache write") // Log warning.
     }
     }
     }*/
    
    
    func storeFetchData(settingsValues : SettingsResponse) {
        if let notificationEntry = settingsValues["notifications"] {
            
            // Attempt to parse notification settings
            do {
                let notificationValue = notificationEntry.b.replacingOccurrences(of: #"\""#, with: #"""#)
                if let notificationData = notificationValue.data(using: .utf8) {
                    self.cache.notificationSettings = try JSONDecoder()
                        .decode(UserSettingsNotificationsData.self, from: notificationData)
                } else {
                    logger.warning("Failed to convert notification value to Data.")
                    self.cache.notificationSettings = .init(server: [:], channel: [:])
                }
            } catch {
                logger.error("Failed to decode notification settings: \(error.localizedDescription)")
                self.cache.notificationSettings = .init(server: [:], channel: [:])
            }
        } else {
            // Set default notification settings if "notifications" doesn't exist
            self.cache.notificationSettings = .init(server: [:], channel: [:])
        }
        
    
        
        if let orderingEntry = settingsValues["ordering"] {
            
            // Attempt to parse notification settings
            do {
                let orderingValue = orderingEntry.b.replacingOccurrences(of: #"\""#, with: #"""#)
                if let orderingData = orderingValue.data(using: .utf8) {
                    
                    self.cache.orderSettings = try JSONDecoder()
                        .decode(OrderingSettings.self, from: orderingData)
                } else {
                    logger.warning("Failed to convert ordering value to Data.")
                    self.cache.orderSettings = .init()
                }
            } catch {
                logger.error("Failed to decode ordering settings: \(error.localizedDescription)")
                self.cache.orderSettings = .init()
            }
        } else {
            // Set default notification settings if "notifications" doesn't exist
            self.cache.orderSettings = .init()
        }
        
        
        
        self.cacheState = .cached // Update cache state to cached.
        writeCacheToFile() // Write updated cache to file.
        
    }
    
    
    
    /// Updates the notification state for a specific channel in the cache.
    /// - Parameters:
    ///   - channelId: The ID of the channel to update.
    ///   - newState: The new notification state to set.
    /// - Returns: The updated `UserSettingsNotificationsData`.
    func updateNotificationState(forChannel channelId: String?,
                                 forServer serverId: String?,
                                 with newState: NotificationState) {
        var updatedSettings = self.cache.notificationSettings
        
        if let channelId = channelId {
            if newState == .useDefault {
                updatedSettings.channel.removeValue(forKey: channelId)
            } else {
                updatedSettings.channel[channelId] = newState
            }
        }
        else if let serverId = serverId {
            if newState == .useDefault {
                updatedSettings.server.removeValue(forKey: serverId)
            } else {
                updatedSettings.server[serverId] = newState
            }
        }

        self.cache.notificationSettings = updatedSettings

        writeCacheToFile()
    }
    
    /// Prepares notification settings and sends them to the server.
    /// - Returns: A dictionary representing the JSON payload for server.
    func prepareNotificationSettings() -> [String: String] {
        // Convert `notificationSettings` to a JSON string
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            let jsonData = try encoder.encode(self.cache.notificationSettings)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return ["notifications": jsonString]
            } else {
                print("Error: Failed to convert JSON data to string.")
                return [:]
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            return [:]
        }
    }
    
    
    func updateServerOrdering(orders : [String]){
        self.cache.orderSettings.servers = orders
        writeCacheToFile()
    }
    
    
    func prepareOrderingSettings() -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            let jsonData = try encoder.encode(self.cache.orderSettings)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return ["ordering": jsonString]
            } else {
                print("Error: Failed to convert ordering JSON data to string.")
                return [:]
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            return [:]
        }
    }
    
    
    func writeCacheToFile() {
        DispatchQueue.global(qos: .utility).async {
            if let caches = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let revoltDir = caches.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
                do {
                    // Create directory if it doesn't exist
                    try FileManager.default.createDirectory(at: revoltDir, withIntermediateDirectories: true)
                    
                    // Get file path
                    guard let filePath = UserSettingsData.cacheFile else {
                        logger.error("Cache file URL is nil.")
                        return
                    }
                    
                    // Create file if it doesn't exist
                    if !FileManager.default.fileExists(atPath: filePath.path) {
                        FileManager.default.createFile(atPath: filePath.path, contents: nil)
                    }
                    
                    // Write data to file
                    let encoded = try JSONEncoder().encode(self.cache)
                    try encoded.write(to: filePath)
                    logger.debug("Cache written to: \(filePath.absoluteString)")
                } catch {
                    logger.error("Failed to write cache: \(error.localizedDescription)")
                }
            } else {
                logger.warning("Caches are not accessible. Skipping cache write")
            }
        }
    }
    
    
    
    // Writes the current settings store to file asynchronously.
    /*func writeStoreToFile() {
     DispatchQueue.main.async(qos: .utility) {
     if let caches = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
     let revoltDir = caches.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
     do {
     try FileManager.default.createDirectory(at: revoltDir, withIntermediateDirectories: false) // Create directory if it doesn't exist.
     } catch {} // Ignore error if it already exists
     }
     do {
     let encoded = try JSONEncoder().encode(self.store) // Encode store data.
     let filePath = UserSettingsData.storeFile!
     logger.debug("will write settings store to: \(filePath.absoluteString)")
     try encoded.write(to: filePath) // Write encoded store to file.
     } catch {
     logger.error("Failed to serialize the settings store: \(error.localizedDescription)") // Log error.
     }
     }
     }*/
    
    // Writes the current settings store to file asynchronously.
    func writeStoreToFile() {
        DispatchQueue.global(qos: .utility).async {
            if let caches = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let revoltDir = caches.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
                do {
                    // Create directory if it doesn't exist
                    try FileManager.default.createDirectory(at: revoltDir, withIntermediateDirectories: true)
                    
                    // Get file path
                    guard let filePath = UserSettingsData.storeFile else {
                        logger.error("Store file URL is nil.")
                        return
                    }
                    
                    // Create file if it doesn't exist
                    if !FileManager.default.fileExists(atPath: filePath.path) {
                        FileManager.default.createFile(atPath: filePath.path, contents: nil)
                    }
                    
                    // Write data to file
                    let encoded = try JSONEncoder().encode(self.store)
                    try encoded.write(to: filePath)
                    logger.debug("Settings store written to: \(filePath.absoluteString)")
                } catch {
                    logger.error("Failed to write settings store: \(error.localizedDescription)")
                }
            } else {
                logger.warning("Caches are not accessible. Skipping store write")
            }
        }
    }
    
    // Clears the cache and deletes the cache file.
    func destroyCache() {
        DispatchQueue.main.async(qos: .utility, execute: deleteCacheFile) // Schedule cache file deletion.
        self.cache.clear() // Clear cache from memory.
        logger.debug("Queued cache file deletion, evicted from memory") // Log cache deletion.
    }
    
    // Deletes the cache file from the file system.
    private func deleteCacheFile() {
        let file = UserSettingsData.cacheFile!
        try? FileManager.default.removeItem(at: file) // Attempt to remove the cache file.
    }
    
    /// Called when logging out of the app
    func isLoggingOut() {
        destroyCache() // Clear cache.
        let file = UserSettingsData.storeFile!
        try? FileManager.default.removeItem(at: file) // Remove settings store file.
        self.store = .init() // Reset settings store to default.
        self.store.updateDecodeWithCallback(keyWasSet: storeKeyWasSet) // Update callback for the store.
    }
}
