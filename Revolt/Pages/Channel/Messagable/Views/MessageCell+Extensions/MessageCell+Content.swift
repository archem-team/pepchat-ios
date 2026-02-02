//
//  MessageCell+Content.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

extension MessageCell {
    /// Removes empty Markdown links from the given text
    /// Empty links are defined as links with no visible text content in the label
    /// Examples: [](url), [ ](url), [  ](url) will be removed
    /// Valid links like [profile](url) will remain untouched
    internal func removeEmptyMarkdownLinks(from text: String) -> String {
        // Regular expression to match markdown links: [label](url)
        // This pattern captures:
        // - Group 1: The entire link [label](url)
        // - Group 2: The label content between [ and ]
        // - Group 3: The URL content between ( and )
        let pattern = #"(\[([^\]]*)\]\([^)]+\))"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: text.utf16.count)
            
            // Find all matches and process them in reverse order to avoid index issues
            let matches = regex.matches(in: text, range: range)
            var result = text
            
            for match in matches.reversed() {
                // Extract the label content (group 2)
                if let labelRange = Range(match.range(at: 2), in: text) {
                    let label = String(text[labelRange])
                    
                    // Check if label is empty or contains only whitespace
                    if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Remove the entire link (group 1) from the text
                        if let linkRange = Range(match.range(at: 1), in: result) {
                            result.removeSubrange(linkRange)
                        }
                    }
                }
            }
            
            return result
        } catch {
            // print("Error processing markdown links: \(error)")
            return text // Return original text if regex fails
        }
    }
    
    // MARK: - Audio Duration Preloading
    internal func preloadAudioDurations(for message: Message, viewState: ViewState) {
        // print("🎯 PRELOAD FUNCTION CALLED for message \(message.id)")
        
        guard let attachments = message.attachments else {
            // print("🎵 PRELOAD: No attachments for message \(message.id)")
            return
        }
        
        // print("🎵 PRELOAD: Checking \(attachments.count) attachments for message \(message.id)")
        
        // Filter audio attachments
        let audioAttachments = attachments.filter { isAudioFile($0) }
        
        if audioAttachments.isEmpty {
            // print("🎵 PRELOAD: No audio files found in \(attachments.count) attachments")
            for attachment in attachments {
                // print("  📄 Non-audio: \(attachment.filename) (type: \(attachment.content_type))")
            }
            return
        }
        
        // print("🎵 PRELOAD: Found \(audioAttachments.count) audio files in message \(message.id)")
        
        let audioManager = AudioPlayerManager.shared
        
        // Set session token in audio manager
        if let token = viewState.sessionToken {
            audioManager.setSessionToken(token)
            // print("🔐 PRELOAD: Set session token in AudioManager")
        }
        
        // Preload duration for each audio file
        for (index, attachment) in audioAttachments.enumerated() {
            let audioURL = viewState.formatUrl(fromId: attachment.id, withTag: "attachments")
            
            // print("🔍 PRELOAD [\(index + 1)/\(audioAttachments.count)]: Starting for \(attachment.filename)")
            // print("  📋 URL: \(audioURL)")
            // print("  📊 Size: \(attachment.size) bytes")
            // print("  🏷️ Type: \(attachment.content_type)")
            
            // Pass file size for better estimation
            audioManager.preloadDuration(for: audioURL, fileSize: attachment.size) { duration in
                if let duration = duration {
                    // print("✅ PRELOAD SUCCESS [\(index + 1)/\(audioAttachments.count)]: \(attachment.filename) = \(String(format: "%.1f", duration))s")
                } else {
                    // print("❌ PRELOAD FAILED [\(index + 1)/\(audioAttachments.count)]: \(attachment.filename)")
                }
            }
        }
        
        // print("🎵 PRELOAD: Initiated for all \(audioAttachments.count) audio files in message \(message.id)")
    }
    
    // MARK: - Emoji Processing
    internal func processCustomEmojis(in attributedString: NSMutableAttributedString, textView: UITextView) {
        // Process custom emoji with IDs like :01J6GCN9DDDRJV1R0STZYB8432:
        let customEmojiPattern = ":([A-Za-z0-9]{26}):"
        
        do {
            let regex = try NSRegularExpression(pattern: customEmojiPattern)
            let text = attributedString.string
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
            
            // Process matches in reverse to avoid index issues
            for match in matches.reversed() {
                if let emojiIdRange = Range(match.range(at: 1), in: text) {
                    let emojiId = String(text[emojiIdRange])
                    let fullMatchRange = match.range
                    
                    // Create text attachment for the emoji
                    let attachment = NSTextAttachment()
                    let emojiSize = CGSize(width: 20, height: 20)
                    attachment.bounds = CGRect(x: 0, y: -4, width: emojiSize.width, height: emojiSize.height)
                    
                    // Load the emoji from the URL using dynamic API endpoint
                    if let apiInfo = viewState?.apiInfo,
                       let url = URL(string: "\(apiInfo.features.autumn.url)/emojis/\(emojiId)") {
                        // Use Kingfisher to load and set the image
                        KF.url(url)
                            .placeholder(.none)
                            .appendProcessor(ResizingImageProcessor(referenceSize: emojiSize, mode: .aspectFit))
                            .set(to: attachment, attributedView: textView)
                    }
                    
                    // Replace the emoji code with the attachment
                    let attachmentString = NSAttributedString(attachment: attachment)
                    attributedString.replaceCharacters(in: fullMatchRange, with: attachmentString)
                }
            }
        } catch {
            print("Error processing custom emojis with IDs: \(error)")
        }
        
        // Process named emoji shortcodes like :smile:, :1234:, etc.
        let namedEmojiPattern = ":([a-zA-Z0-9_+-]+):"
        
        do {
            let regex = try NSRegularExpression(pattern: namedEmojiPattern)
            let text = attributedString.string
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
            
            // Process matches in reverse to avoid index issues
            for match in matches.reversed() {
                if let shortcodeRange = Range(match.range(at: 1), in: text) {
                    let shortcode = String(text[shortcodeRange])
                    let fullMatchRange = match.range
                    print("🔍 MessageCell: Processing shortcode: '\(shortcode)'")
                    
                    // Check if this is an emoji shortcode using EmojiParser
                    if let emoji = EmojiParser.findEmojiByShortcode(shortcode) {
                        if emoji.hasPrefix("custom:") {
                            // Handle custom emoji with image attachment
                            let attachment = NSTextAttachment()
                            let emojiSize = CGSize(width: 20, height: 20)
                            attachment.bounds = CGRect(x: 0, y: -4, width: emojiSize.width, height: emojiSize.height)
                            
                            let customEmojiURL = EmojiParser.parseEmoji(emoji, apiInfo: viewState?.apiInfo)
                            if let url = URL(string: customEmojiURL) {
                                KF.url(url)
                                    .placeholder(.none)
                                    .appendProcessor(ResizingImageProcessor(referenceSize: emojiSize, mode: .aspectFit))
                                    .set(to: attachment, attributedView: textView)
                            }
                            
                            let attachmentString = NSAttributedString(attachment: attachment)
                            attributedString.replaceCharacters(in: fullMatchRange, with: attachmentString)
                        } else {
                            // Handle Unicode emoji - replace with the actual emoji character
                            let emojiAttributedString = NSAttributedString(string: emoji)
                            attributedString.replaceCharacters(in: fullMatchRange, with: emojiAttributedString)
                        }
                    } else {
                        // CRITICAL FIX: If EmojiParser fails, try fallback with viewState
                        if let viewState = viewState {
                            let emojiBase = viewState.findEmojiBase(by: shortcode)
                            if !emojiBase.isEmpty {
                                let emojiString = String(String.UnicodeScalarView(emojiBase.compactMap(Unicode.Scalar.init)))
                                if !emojiString.isEmpty {
                                    let emojiAttributedString = NSAttributedString(string: emojiString)
                                    attributedString.replaceCharacters(in: fullMatchRange, with: emojiAttributedString)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error processing named emoji shortcodes: \(error)")
        }
    }
    
}
