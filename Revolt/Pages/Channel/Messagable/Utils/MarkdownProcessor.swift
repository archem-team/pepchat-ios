//
//  MarkdownProcessor.swift
//  Revolt
//
//

import UIKit

// PERFORMANCE: Cache for processed markdown to avoid reprocessing same content
private var markdownCache: [String: NSAttributedString] = [:]
private let maxCacheSize = 100

// PERFORMANCE: Main function to process markdown with caching
func processMarkdownOptimized(_ text: String) -> NSAttributedString {
    // Check cache first
    if let cached = markdownCache[text] {
        return cached
    }
    
    // For very long text, limit processing to prevent UI lag
    let shouldLimitProcessing = text.count > 1500
    
    let mutableAttributedString = NSMutableAttributedString(string: text)
    
    // Apply default font and color
    mutableAttributedString.addAttributes([
        .font: UIFont.systemFont(ofSize: 15, weight: .light),
        .foregroundColor: UIColor.textDefaultGray01
    ], range: NSRange(location: 0, length: mutableAttributedString.length))
    
    if !shouldLimitProcessing {
        // Only apply heavy processing for shorter messages
        processMarkdownLists(mutableAttributedString)
        processMarkdownEmphasis(mutableAttributedString)
        processMarkdownCodeBlocks(mutableAttributedString)
        processMarkdownHeaders(mutableAttributedString)
        processMarkdownLineBreaks(mutableAttributedString)
    } else {
        // For long messages, only apply lightweight formatting
        processLightweightMarkdown(mutableAttributedString)
    }
    
    // Cache the result
    if markdownCache.count >= maxCacheSize {
        // Clear half the cache to prevent memory issues
        let keysToRemove = Array(markdownCache.keys.prefix(maxCacheSize / 2))
        keysToRemove.forEach { markdownCache.removeValue(forKey: $0) }
    }
    markdownCache[text] = mutableAttributedString
    
    return mutableAttributedString
}

// PERFORMANCE: Lightweight markdown processing for long messages
func processLightweightMarkdown(_ attributedString: NSMutableAttributedString) {
    // Only process bold and links for long messages
    processBoldMarkdown(attributedString)
    processMarkdownLinks(attributedString)
    processPlainURLs(attributedString)
}

func processMarkdownLists(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    let listItemPattern = "(?m)^(\\s*[\\*\\-\\+•]\\s+)(.+)$"  // Pattern for bullet list items
    
    if let regex = try? NSRegularExpression(pattern: listItemPattern, options: []) {
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches.reversed() {
            let fullRange = match.range
            let bulletRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            
            // Get the content text without the bullet
            let contentText = (attributedString.string as NSString).substring(with: contentRange)
            
            // Create bullet symbol (use a proper bullet point)
            let bulletText = "• "
            
            // Create the full formatted text
            let fullText = bulletText + contentText
            
            // Content formatting
            let contentAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: UIColor.textDefaultGray01
            ]
            
            // Create paragraph style for list item
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = 0.0 // No indent for first line (bullet line)
            paragraphStyle.headIndent = 12.0 // Indent for wrapped lines to align with text content
            paragraphStyle.paragraphSpacing = 2.0 // Space between list items
            paragraphStyle.lineSpacing = 1.0
            
            // Combine attributes
            var combinedAttributes = contentAttributes
            combinedAttributes[.paragraphStyle] = paragraphStyle
            
            // Create attributed string for the entire list item
            let listItemAttributedString = NSMutableAttributedString(string: fullText, attributes: combinedAttributes)
            
            // Make the bullet point a different color
            let bulletAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: UIColor.textGray06
            ]
            
            listItemAttributedString.addAttributes(bulletAttributes, range: NSRange(location: 0, length: bulletText.count))
            
            // Replace the original list item with the formatted version
            attributedString.replaceCharacters(in: fullRange, with: listItemAttributedString)
        }
    }
}

// Process markdown headers
func processMarkdownHeaders(_ attributedString: NSMutableAttributedString) {
    // Find and process headers using regular expressions
    let text = attributedString.string
    let headerPattern = "(?m)^(#{1,6})\\s+(.+)$"  // Pattern for headers with #
    
    
    do {
        let regex = try NSRegularExpression(pattern: headerPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        
        for match in matches.reversed() {
            // Full match range
            let fullRange = match.range
            
            // First group: # symbols
            let hashmarkRange = match.range(at: 1)
            
            // Second group: header text
            let contentRange = match.range(at: 2)
            
            // Number of # symbols determines header size
            let hashmarkLength = hashmarkRange.length
            let fontSize: CGFloat
            
            switch hashmarkLength {
            case 1: fontSize = 22.0 // H1 - Large but not too big
            case 2: fontSize = 20.0 // H2 - Medium-large  
            case 3: fontSize = 18.0 // H3 - Medium
            case 4: fontSize = 17.0 // H4 - Slightly larger than normal
            case 5: fontSize = 16.0 // H5 - Small
            case 6: fontSize = 15.5 // H6 - Just slightly larger than normal text
            default: fontSize = 15.0
            }
            
            let hashmarkText = (attributedString.string as NSString).substring(with: hashmarkRange)
            
            
            // Get the existing content from the attributed string (preserving any formatting)
            let headerContentAttributedString = attributedString.attributedSubstring(from: contentRange).mutableCopy() as! NSMutableAttributedString
            
            // Update fonts in the header content to the header size
            headerContentAttributedString.enumerateAttributes(in: NSRange(location: 0, length: headerContentAttributedString.length), options: []) { attributes, range, _ in
                var newAttributes = attributes
                
                // Preserve bold/italic but update size
                if let currentFont = attributes[.font] as? UIFont {
                    if currentFont.fontDescriptor.symbolicTraits.contains(.traitBold) {
                        newAttributes[.font] = UIFont.boldSystemFont(ofSize: fontSize)
                    } else if currentFont.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                        newAttributes[.font] = UIFont.italicSystemFont(ofSize: fontSize)
                    } else {
                        newAttributes[.font] = UIFont.boldSystemFont(ofSize: fontSize) // Headers are bold by default
                    }
                } else {
                    newAttributes[.font] = UIFont.boldSystemFont(ofSize: fontSize)
                }
                
                // Only set header color if this text doesn't have a link attribute
                if attributes[.link] == nil {
                    newAttributes[.foregroundColor] = UIColor.textDefaultGray01
                }
                // If it has a link, preserve the existing foreground color
                
                // Add paragraph style
                newAttributes[.paragraphStyle] = createHeaderParagraphStyle()
                
                headerContentAttributedString.setAttributes(newAttributes, range: range)
            }
            
            // Replace the entire header (including # symbols) with the formatted content
            attributedString.replaceCharacters(in: fullRange, with: headerContentAttributedString)
        }
    } catch {
        print("Error processing markdown headers: \(error)")
    }
}

// Process emphasis in markdown (bold, italic, code, links)
func processMarkdownEmphasis(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    
    // Process in the correct order for nested markdown:
    
    // 1. Code first (to protect code from other formatting)
    processInlineCodeMarkdown(attributedString)
    
    // 2. Bold and Italic (process these before links to avoid conflicts)
    processBoldMarkdown(attributedString)
    processItalicMarkdown(attributedString)
    
    // 3. Strikethrough
    processStrikethroughMarkdown(attributedString)
    
    // 4. Links last (to ensure they don't get broken by other formatting)
    processMarkdownLinks(attributedString)
    processPlainURLs(attributedString)
}

// Process bold markdown
func processBoldMarkdown(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    let boldPattern = "\\*\\*(.*?)\\*\\*|__(.*?)__"
    
    
    do {
        let regex = try NSRegularExpression(pattern: boldPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        
        for match in matches.reversed() {
            let fullRange = match.range
            
            // Check if this range overlaps with any existing links
            var hasLinkInRange = false
            attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, _, _ in
                if attributes[.link] != nil {
                    hasLinkInRange = true
                }
            }
            
            // Skip processing if this range contains a link
            if hasLinkInRange {
                continue
            }
            
            // Find the content (first non-empty capture group)
            var contentText = ""
            for i in 1..<match.numberOfRanges {
                let captureRange = match.range(at: i)
                if captureRange.location != NSNotFound && captureRange.length > 0 {
                    contentText = (attributedString.string as NSString).substring(with: captureRange)
                    break
                }
            }
            
            if !contentText.isEmpty {
                let fullText = (attributedString.string as NSString).substring(with: fullRange)
                
                let boldAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 15),
                    .foregroundColor: UIColor.textDefaultGray01
                ]
                
                let boldAttributedString = NSAttributedString(string: contentText, attributes: boldAttributes)
                attributedString.replaceCharacters(in: fullRange, with: boldAttributedString)
            }
        }
    } catch {
        print("Error processing bold markdown: \(error)")
    }
}

// Process italic markdown
func processItalicMarkdown(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    // CRITICAL FIX: Modified regex to avoid matching underscores inside emoji shortcodes
    // This pattern excludes underscores that are inside :emoji_name: patterns
    let italicPattern = "(?<!\\*)\\*((?!\\*)[^*]+?)\\*(?!\\*)|(?<!:)(?<!_)_((?!_)(?![a-zA-Z0-9_]*:)[^_]+?)_(?!_)(?!:)"
    
    do {
        let regex = try NSRegularExpression(pattern: italicPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches.reversed() {
            let fullRange = match.range
            
            // Check if this range overlaps with any existing links
            var hasLinkInRange = false
            attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, _, _ in
                if attributes[.link] != nil {
                    hasLinkInRange = true
                }
            }
            
            // Skip processing if this range contains a link
            if hasLinkInRange {
                continue
            }
            
            // Find the content (first non-empty capture group)
            var contentText = ""
            for i in 1..<match.numberOfRanges {
                let captureRange = match.range(at: i)
                if captureRange.location != NSNotFound && captureRange.length > 0 {
                    contentText = (attributedString.string as NSString).substring(with: captureRange)
                    break
                }
            }
            
            if !contentText.isEmpty {
                let italicAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.italicSystemFont(ofSize: 15),
                    .foregroundColor: UIColor.textDefaultGray01
                ]
                
                let italicAttributedString = NSAttributedString(string: contentText, attributes: italicAttributes)
                attributedString.replaceCharacters(in: fullRange, with: italicAttributedString)
            }
        }
    } catch {
        print("Error processing italic markdown: \(error)")
    }
}

// Process inline code markdown
func processInlineCodeMarkdown(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    let codePattern = "`(.*?)`"
    
    do {
        let regex = try NSRegularExpression(pattern: codePattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches.reversed() {
            let fullRange = match.range
            let contentRange = match.range(at: 1)
            
            if contentRange.location != NSNotFound {
                let contentText = (attributedString.string as NSString).substring(with: contentRange)
                
                let codeAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: UIColor.systemOrange,
                    .backgroundColor: UIColor.darkGray.withAlphaComponent(0.15)
                ]
                
                let codeAttributedString = NSAttributedString(string: contentText, attributes: codeAttributes)
                attributedString.replaceCharacters(in: fullRange, with: codeAttributedString)
            }
        }
    } catch {
        print("Error processing inline code markdown: \(error)")
    }
}

// Process strikethrough markdown
func processStrikethroughMarkdown(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    let strikethroughPattern = "~~(.*?)~~"
    
    do {
        let regex = try NSRegularExpression(pattern: strikethroughPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches.reversed() {
            let fullRange = match.range
            let contentRange = match.range(at: 1)
            
            if contentRange.location != NSNotFound {
                let contentText = (attributedString.string as NSString).substring(with: contentRange)
                
                let strikethroughAttributes: [NSAttributedString.Key: Any] = [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: UIColor.textGray06,
                    .foregroundColor: UIColor.textGray06
                ]
                
                let strikethroughAttributedString = NSAttributedString(string: contentText, attributes: strikethroughAttributes)
                attributedString.replaceCharacters(in: fullRange, with: strikethroughAttributedString)
            }
        }
    } catch {
        print("Error processing strikethrough markdown: \(error)")
    }
}

// Process markdown links
func processMarkdownLinks(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    let linkPattern = "\\[(.*?)\\]\\((.*?)\\)"
    
    do {
        let regex = try NSRegularExpression(pattern: linkPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches.reversed() {
            if match.numberOfRanges >= 3 {
                let fullRange = match.range
                let titleRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                
                if titleRange.location != NSNotFound && urlRange.location != NSNotFound {
                    let titleText = (attributedString.string as NSString).substring(with: titleRange)
                    let urlString = (attributedString.string as NSString).substring(with: urlRange)
                    
                    if let url = URL(string: urlString) {
                        let linkAttributes: [NSAttributedString.Key: Any] = [
                            .link: url,
                            .foregroundColor: UIColor.systemBlue,
                            .font: UIFont.systemFont(ofSize: 15) // Ensure consistent font
                        ]
                        
                        let linkAttributedString = NSAttributedString(string: titleText, attributes: linkAttributes)
                        attributedString.replaceCharacters(in: fullRange, with: linkAttributedString)
                    }
                }
            }
        }
    } catch {
        print("Error processing markdown links: \(error)")
    }
}

// Process plain URLs using a simpler approach
func processPlainURLs(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    
    // Find all potential URLs manually
    var searchRange = text.startIndex
    var urlRanges: [(range: NSRange, url: String)] = []
    
    while searchRange < text.endIndex {
        // Look for http:// or https://
        if let httpRange = text.range(of: "http://", range: searchRange..<text.endIndex) {
            let urlStart = httpRange.lowerBound
            let urlEnd = findUrlEnd(in: text, from: urlStart)
            let urlString = String(text[urlStart..<urlEnd])
            
            let nsRange = NSRange(urlStart..<urlEnd, in: text)
            urlRanges.append((range: nsRange, url: urlString))
            
            searchRange = urlEnd
        } else if let httpsRange = text.range(of: "https://", range: searchRange..<text.endIndex) {
            let urlStart = httpsRange.lowerBound
            let urlEnd = findUrlEnd(in: text, from: urlStart)
            let urlString = String(text[urlStart..<urlEnd])
            
            let nsRange = NSRange(urlStart..<urlEnd, in: text)
            urlRanges.append((range: nsRange, url: urlString))
            
            searchRange = urlEnd
        } else {
            break
        }
    }
    
    // Process URLs in reverse order to avoid index shifting
    for urlInfo in urlRanges.reversed() {
        let urlRange = urlInfo.range
        let urlString = urlInfo.url
        
        // Check if this text already has a link attribute
        var alreadyHasLink = false
        if urlRange.location + urlRange.length <= attributedString.length {
            attributedString.enumerateAttributes(in: urlRange, options: []) { attributes, _, _ in
                if attributes[.link] != nil {
                    alreadyHasLink = true
                }
            }
        }
        
        // Only process if it doesn't already have a link and it's not part of a markdown link
        if !alreadyHasLink && !isPartOfMarkdownLink(text: text, range: urlRange) {
            if let url = URL(string: urlString) {
                let linkAttributes: [NSAttributedString.Key: Any] = [
                    .link: url,
                    .foregroundColor: UIColor.systemBlue,
                    .font: UIFont.systemFont(ofSize: 15)
                ]
                
                // Apply attributes to the URL range
                attributedString.addAttributes(linkAttributes, range: urlRange)
            }
        }
    }
}

// Helper function to find the end of a URL starting from a given position
private func findUrlEnd(in text: String, from start: String.Index) -> String.Index {
    var current = start
    
    while current < text.endIndex {
        let char = text[current]
        
        // Stop at whitespace or newline
        if char.isWhitespace || char.isNewline {
            break
        }
        
        // Stop at common sentence-ending punctuation if it's at the end or followed by whitespace
        // But allow underscores, hyphens, and other URL-safe characters
        if ".,;!?)]}>'\"".contains(char) {
            let nextIndex = text.index(after: current)
            if nextIndex >= text.endIndex || text[nextIndex].isWhitespace || text[nextIndex].isNewline {
                break
            }
        }
        
        current = text.index(after: current)
    }
    
    return current
}

// Process code blocks in markdown
func processMarkdownCodeBlocks(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    
    // Pattern for code blocks with three backticks (```)
    let codeBlockPattern = "```(?:[a-zA-Z0-9]+)?\\s*\\n([\\s\\S]*?)\\n```"
    
    do {
        let regex = try NSRegularExpression(pattern: codeBlockPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches.reversed() {
            // Full code block range including backticks
            let fullRange = match.range
            
            // Inner text range (without backticks)
            if match.numberOfRanges > 1 {
                let codeContentRange = match.range(at: 1)
                let codeText = (attributedString.string as NSString).substring(with: codeContentRange)
                
                // Code block formatting
                let codeBlockAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: UIColor.systemGreen,
                    .backgroundColor: UIColor.darkGray.withAlphaComponent(0.2)
                ]
                
                // Create paragraph style for code block
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.firstLineHeadIndent = 8.0
                paragraphStyle.headIndent = 8.0
                paragraphStyle.tailIndent = -8.0 // Negative for right indent
                paragraphStyle.paragraphSpacing = 4.0
                paragraphStyle.paragraphSpacingBefore = 4.0
                paragraphStyle.lineSpacing = 1.0
                
                // Combine attributes
                var combinedAttributes = codeBlockAttributes
                combinedAttributes[.paragraphStyle] = paragraphStyle
                
                // Replace the entire code block (including backticks) with formatted text
                let codeAttributedString = NSAttributedString(string: codeText, attributes: combinedAttributes)
                attributedString.replaceCharacters(in: fullRange, with: codeAttributedString)
            }
        }
    } catch {
        print("Error processing code blocks: \(error)")
    }
}

// Process line breaks and paragraphs in markdown
func processMarkdownLineBreaks(_ attributedString: NSMutableAttributedString) {
    let text = attributedString.string
    
    // 1. Ensure support for line breaks
    let brPattern = "(\\n)"
    
    do {
        let regex = try NSRegularExpression(pattern: brPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches.reversed() {
            let lineBreakRange = match.range
            
            // Apply paragraph spacing to new line
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 1.0 // Line spacing
            paragraphStyle.paragraphSpacing = 2.0 // Paragraph spacing
            paragraphStyle.firstLineHeadIndent = 0.0 // No indentation for first line
            paragraphStyle.headIndent = 0.0 // No indentation for subsequent lines
            
            attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineBreakRange)
        }
    } catch {
        print("Error processing line breaks: \(error)")
    }
    
    // 2. Explicitly process new line with two spaces at the end of the line
    let hardBreakPattern = "  \\n"
    
    do {
        let regex = try NSRegularExpression(pattern: hardBreakPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches.reversed() {
            let hardBreakRange = match.range
            
            // Increase emphasis on explicit new line processing
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2.0 // More spacing for explicit new line
            paragraphStyle.paragraphSpacing = 4.0
            paragraphStyle.firstLineHeadIndent = 0.0 // No indentation for first line
            paragraphStyle.headIndent = 0.0 // No indentation for subsequent lines
            
            attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: hardBreakRange)
        }
    } catch {
        print("Error processing hard line breaks: \(error)")
    }
}

// Helper function to check if a URL is part of a markdown link [text](url)
func isPartOfMarkdownLink(text: String, range: NSRange) -> Bool {
    // Look for markdown link pattern around this URL
    let linkPattern = "\\[([^\\]]+)\\]\\(([^\\)]+)\\)"
    
    do {
        let regex = try NSRegularExpression(pattern: linkPattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches {
            if match.numberOfRanges >= 3 {
                let fullLinkRange = match.range // The entire [text](url) range
                let urlRangeInLink = match.range(at: 2) // The URL part of the markdown link
                
                // Check if our URL range is contained within or overlaps with the markdown link
                if NSIntersectionRange(range, fullLinkRange).length > 0 ||
                   NSIntersectionRange(range, urlRangeInLink).length > 0 {
                    return true
                }
            }
        }
    } catch {
        print("Error checking markdown link pattern: \(error)")
    }
    
    return false
}

// Function to create a uniform paragraph style for headers
func createHeaderParagraphStyle() -> NSParagraphStyle {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacing = 6.0 // Reduced spacing after header
    paragraphStyle.paragraphSpacingBefore = 4.0 // Reduced spacing before header
    paragraphStyle.lineSpacing = 1.0 // Reduced line spacing
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.firstLineHeadIndent = 0.0 // No indentation for first line
    paragraphStyle.headIndent = 0.0 // No indentation for subsequent lines
    return paragraphStyle
}

