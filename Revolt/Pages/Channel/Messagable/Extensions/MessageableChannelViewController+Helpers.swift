//
//  MessageableChannelViewController+Helpers.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//

import Foundation
import Types

// MARK: - Helper Functions
extension MessageableChannelViewController {
    /// Generates a dynamic message link based on the current domain
    func generateMessageLink(serverId: String?, channelId: String, messageId: String, viewState: ViewState) async -> String {
        // Get the current base URL and determine the web domain
        let baseURL = await viewState.baseURL ?? viewState.defaultBaseURL
        let webDomain: String
        
        if baseURL.contains("peptide.chat") {
            webDomain = "https://peptide.chat"
        } else if baseURL.contains("app.revolt.chat") {
            webDomain = "https://app.revolt.chat"
        } else {
            // Fallback for other instances - extract domain from API URL
            if let url = URL(string: baseURL),
               let host = url.host {
                webDomain = "https://\(host)"
            } else {
                webDomain = "https://app.revolt.chat" // Ultimate fallback
            }
        }
        
        // Generate proper URL based on channel type
        if let serverId = serverId, !serverId.isEmpty {
            // Server channel
            return "\(webDomain)/server/\(serverId)/channel/\(channelId)/\(messageId)"
        } else {
            // DM channel
            return "\(webDomain)/channel/\(channelId)/\(messageId)"
        }
    }
}
