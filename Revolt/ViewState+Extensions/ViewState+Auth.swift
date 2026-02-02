//
//  ViewState+Auth.swift
//  Revolt
//
//  Created by Akshat Srivastava on 31/01/26.
//

import Foundation
import Combine
import SwiftUI
import Alamofire
import ULID
import Collections
import Sentry
@preconcurrency import Types
import UserNotifications
import KeychainAccess
import Darwin
import Network

extension ViewState {
    
    func signIn(mfa_ticket: String, mfa_response: [String: String], callback: @escaping((LoginState) -> ())) async {
        let body = ["mfa_ticket": mfa_ticket, "mfa_response": mfa_response, "friendly_name": "Revolt iOS"] as [String : Any]
        
        await innerSignIn(body, callback)
    }
    
    func signIn(email: String, password: String, callback: @escaping((LoginState) -> ())) async {
        let body = ["email": email, "password":  password, "friendly_name": "Revolt IOS"]
        
        await innerSignIn(body, callback)
    }
    
    /// A successful result here means pending (the session has been destroyed but the client still has data cached)
    func signOut(afterRemoveSession : Bool = false) async -> Result<(), UserStateError>  {
        
        if !afterRemoveSession {
            let status = try? await http.signout().get()
            guard let status = status else { return .failure(.signOutError)}
        }
        
        self.ws?.stop()
        /*withAnimation {
         state = .signedOut
         }*/
        // IMPORTANT: do not destroy the cache/session here. It'll cause the app to crash before it can transition to the welcome screen.
        // The cache is destroyed in RevoltApp.swift:ApplicationSwitcher
        
        state = .signedOut
        return .success(())
    }
    
    private func innerSignIn(_ body: [String: Any], _ callback: @escaping((LoginState) -> ())) async {
        AF.request("\(http.baseURL)/auth/session/login", method: .post, parameters: body, encoding: JSONEncoding.default)
            .responseData { response in
                
                switch response.result {
                case .success(let data):
                    if [401, 403, 500].contains(response.response!.statusCode) {
                        return callback(.Invalid)
                    }
                    if let result = try? JSONDecoder().decode(LoginResponse.self, from: data){
                        switch result {
                        case .Success(let success):
                            Task {
                                self.isOnboarding = true
                                self.currentSessionId = success._id
                                self.sessionToken = success.token
                                self.http.token = success.token
                                
                                await self.promptForNotifications()
                                
                                // If we already have a device notification token, try to upload it
                                if let existingToken = self.deviceNotificationToken {
                                    // print("📱 LOGIN_SUCCESS: Found existing device token, uploading...")
                                    Task {
                                        let response = await self.http.uploadNotificationToken(token: existingToken)
                                        switch response {
                                            case .success:
                                                print("✅ LOGIN_SUCCESS: Successfully uploaded existing token")
                                            case .failure(let error):
                                                print("❌ LOGIN_SUCCESS: Failed to upload existing token: \(error)")
                                                self.storePendingNotificationToken(existingToken)
                                        }
                                    }
                                }
                                
                                do {
                                    let onboardingState = try await self.http.checkOnboarding().get()
                                    if onboardingState.onboarding {
                                        self.isOnboarding = true
                                        callback(.Onboarding)
                                    } else {
                                        self.isOnboarding = false
                                        callback(.Success)
                                        self.state = .connecting
                                    }
                                } catch {
                                    self.isOnboarding = false
                                    self.state = .connecting
                                    return callback(.Success) // if the onboard check dies, just try to go for it
                                }
                            }
                            
                        case .Mfa(let mfa):
                            return callback(.Mfa(ticket: mfa.ticket, methods: mfa.allowed_methods))
                            
                        case .Disabled:
                            return callback(.Disabled)
                        }
                    } else {
                        return callback(.Invalid)
                    }
                    
                case .failure(_):
                    ()
                }
            }
    }
    
    /// A workaround for the UserSettingStore finding out we're not authenticated, since not a main actor.
    func setSignedOutState() {
        withAnimation {
            state = .signedOut
        }
    }
    
    func destroyCache() {
        // In future this'll need to delete files too
        path = []
        
        // MEMORY MANAGEMENT: Stop cleanup timer
        memoryCleanupTimer?.invalidate()
        memoryCleanupTimer = nil
        
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
        
        // Cancel all pending saves
        for workItem in saveWorkItems.values {
            workItem.cancel()
        }
        saveWorkItems.removeAll()
        
        users.removeAll()
        servers.removeAll()
        channels.removeAll()
        messages.removeAll()
        members.removeAll()
        emojis.removeAll()
        dms.removeAll()
        currentlyTyping.removeAll()
        channelMessages.removeAll()
        preloadedChannels.removeAll()
        
        currentUser = nil
        currentSelection = .discover
        currentChannel = .home
        currentSessionId = nil
        
        userSettingsStore.isLoggingOut()
        self.ws = nil
    }
}
