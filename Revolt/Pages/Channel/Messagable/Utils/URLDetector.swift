//
//  URLDetector.swift
//  Revolt
//
//  Created by Assistant on $(date).
//

import Foundation

/// A utility class for detecting and extracting URLs from text content
class URLDetector {
    
    // MARK: - URL Detection
    
    /// Detects URLs in the given text and returns them as an array
    /// - Parameter text: The text to search for URLs
    /// - Returns: An array of detected URLs
    static func detectURLs(in text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        guard let detector = detector else { return [] }
        
        let matches = detector.matches(in: text, options: [], range: range)
        
        return matches.compactMap { match in
            guard let url = match.url else { return nil }
            return url
        }
    }
    
    /// Checks if the given text contains any URLs
    /// - Parameter text: The text to check
    /// - Returns: True if the text contains URLs, false otherwise
    static func containsURL(_ text: String) -> Bool {
        return !detectURLs(in: text).isEmpty
    }
    
    /// Extracts URL information including title, description, and image from a URL
    /// - Parameter url: The URL to extract information from
    /// - Returns: A dictionary containing extracted information
    static func extractURLInfo(from url: URL) async -> [String: Any]? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            return parseHTMLForMetadata(html)
        } catch {
            print("Error fetching URL content: \(error)")
            return nil
        }
    }
    
    // MARK: - HTML Parsing
    
    /// Parses HTML content to extract Open Graph and meta tag information
    /// - Parameter html: The HTML content to parse
    /// - Returns: A dictionary containing extracted metadata
    private static func parseHTMLForMetadata(_ html: String) -> [String: Any] {
        var metadata: [String: Any] = [:]
        
        // Extract title
        if let title = extractHTMLTag(from: html, tag: "title") {
            metadata["title"] = title
        }
        
        // Extract Open Graph tags
        let ogTags = ["og:title", "og:description", "og:image", "og:url", "og:site_name"]
        for tag in ogTags {
            if let content = extractMetaContent(from: html, property: tag) {
                let key = String(tag.dropFirst(3)) // Remove "og:" prefix
                metadata[key] = content
            }
        }
        
        // Extract Twitter Card tags
        let twitterTags = ["twitter:title", "twitter:description", "twitter:image"]
        for tag in twitterTags {
            if let content = extractMetaContent(from: html, name: tag) {
                let key = String(tag.dropFirst(8)) // Remove "twitter:" prefix
                if metadata[key] == nil { // Only use if og: tag wasn't found
                    metadata[key] = content
                }
            }
        }
        
        // Extract description from meta description if not found in og:description
        if metadata["description"] == nil {
            if let description = extractMetaContent(from: html, name: "description") {
                metadata["description"] = description
            }
        }
        
        return metadata
    }
    
    /// Extracts content from HTML title tag
    /// - Parameters:
    ///   - html: The HTML content
    ///   - tag: The tag name to extract
    /// - Returns: The extracted title content
    private static func extractHTMLTag(from html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: html.utf16.count)
        
        if let match = regex?.firstMatch(in: html, options: [], range: range),
           let titleRange = Range(match.range(at: 1), in: html) {
            return String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    /// Extracts content from meta tag with property attribute
    /// - Parameters:
    ///   - html: The HTML content
    ///   - property: The property value to search for
    /// - Returns: The extracted content
    private static func extractMetaContent(from html: String, property: String) -> String? {
        let pattern = "<meta[^>]*property=\"\(property)\"[^>]*content=\"([^\"]+)\""
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: html.utf16.count)
        
        if let match = regex?.firstMatch(in: html, options: [], range: range),
           let contentRange = Range(match.range(at: 1), in: html) {
            return String(html[contentRange])
        }
        
        return nil
    }
    
    /// Extracts content from meta tag with name attribute
    /// - Parameters:
    ///   - html: The HTML content
    ///   - name: The name value to search for
    /// - Returns: The extracted content
    private static func extractMetaContent(from html: String, name: String) -> String? {
        let pattern = "<meta[^>]*name=\"\(name)\"[^>]*content=\"([^\"]+)\""
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: html.utf16.count)
        
        if let match = regex?.firstMatch(in: html, options: [], range: range),
           let contentRange = Range(match.range(at: 1), in: html) {
            return String(html[contentRange])
        }
        
        return nil
    }
    
    // MARK: - URL Validation
    
    /// Validates if a string is a valid URL
    /// - Parameter string: The string to validate
    /// - Returns: True if the string is a valid URL, false otherwise
    static func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    /// Normalizes a URL string by adding http:// if no scheme is present
    /// - Parameter urlString: The URL string to normalize
    /// - Returns: The normalized URL string
    static func normalizeURL(_ urlString: String) -> String {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return urlString
        }
        return "https://\(urlString)"
    }
    
    // MARK: - Domain Extraction
    
    /// Extracts the domain from a URL
    /// - Parameter url: The URL to extract domain from
    /// - Returns: The domain string or nil if unable to extract
    static func extractDomain(from url: URL) -> String? {
        return url.host
    }
    
    /// Checks if a URL is from a specific domain
    /// - Parameters:
    ///   - url: The URL to check
    ///   - domain: The domain to compare against
    /// - Returns: True if the URL is from the specified domain
    static func isFromDomain(_ url: URL, domain: String) -> Bool {
        guard let host = url.host else { return false }
        return host.lowercased().contains(domain.lowercased())
    }
    
    // MARK: - Social Media Detection
    
    /// Detects if a URL is from a social media platform
    /// - Parameter url: The URL to check
    /// - Returns: The social media platform name or nil
    static func detectSocialMediaPlatform(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return "YouTube"
        } else if host.contains("twitter.com") || host.contains("x.com") {
            return "Twitter"
        } else if host.contains("instagram.com") {
            return "Instagram"
        } else if host.contains("facebook.com") {
            return "Facebook"
        } else if host.contains("tiktok.com") {
            return "TikTok"
        } else if host.contains("linkedin.com") {
            return "LinkedIn"
        } else if host.contains("reddit.com") {
            return "Reddit"
        } else if host.contains("discord.com") || host.contains("discord.gg") {
            return "Discord"
        } else if host.contains("spotify.com") {
            return "Spotify"
        } else if host.contains("soundcloud.com") {
            return "SoundCloud"
        } else if host.contains("twitch.tv") {
            return "Twitch"
        }
        
        return nil
    }
}

// MARK: - URL Extension

extension URL {
    /// Extracts metadata from the URL asynchronously
    /// - Returns: A dictionary containing extracted metadata
    func extractMetadata() async -> [String: Any]? {
        return await URLDetector.extractURLInfo(from: self)
    }
    
    /// Gets the social media platform name if the URL is from a social media site
    /// - Returns: The platform name or nil
    var socialMediaPlatform: String? {
        return URLDetector.detectSocialMediaPlatform(from: self)
    }
    
    /// Gets the domain of the URL
    /// - Returns: The domain string
    var domain: String? {
        return URLDetector.extractDomain(from: self)
    }
} 