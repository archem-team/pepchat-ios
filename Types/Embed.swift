//
//  Embed.swift
//  Revolt
//
//  Created by Angelo on 08/07/2024.
//

import Foundation

// MARK: - Special Content Structures

/// Represents a YouTube special embed.
public struct YoutubeSpecial: Codable, Hashable {
    public var id: String // Unique identifier for the YouTube content.
    public var timestamp: String? // Optional timestamp for the video.
}

/// Represents a Twitch special embed.
public struct TwitchSpecial: Codable, Hashable {
    public enum ContentType: String, Codable, Hashable {
        case channel = "Channel" // Twitch channel content.
        case video = "Video" // Twitch video content.
        case clip = "Clip" // Twitch clip content.
    }
    
    public var content_type: ContentType // Type of Twitch content.
    public var id: String // Unique identifier for the Twitch content.
}

/// Represents a Spotify special embed.
public struct SpotifySpecial: Codable, Hashable {
    public var content_type: String // Type of Spotify content.
    public var id: String // Unique identifier for the Spotify content.
}

/// Represents a Soundcloud special embed.
public struct SoundcloudSpecial: Codable, Hashable {
    // Currently no properties defined for SoundcloudSpecial.
}

/// Represents a Bandcamp special embed.
public struct BandcampSpecial: Codable, Hashable {
    public enum ContentType: String, Codable, Hashable {
        case album = "Album" // Bandcamp album content.
        case track = "Track" // Bandcamp track content.
    }
    
    public var content_type: ContentType // Type of Bandcamp content.
    public var id: String // Unique identifier for the Bandcamp content.
}

/// Represents a Lightspeed special embed.
public struct LightspeedSpecial: Codable, Hashable {
    public enum ContentType: String, Codable, Hashable {
        case channel = "Channel" // Lightspeed channel content.
    }
    
    public var content_type: ContentType // Type of Lightspeed content.
    public var id: String // Unique identifier for the Lightspeed content.
}

/// Represents a Streamable special embed.
public struct StreamableSpecial: Codable, Hashable {
    public var id: String // Unique identifier for the Streamable content.
}

/// Enum to represent different types of special website embeds.
public enum WebsiteSpecial: Hashable, Equatable {
    case none // No special content.
    case gif // GIF content.
    case youtube(YoutubeSpecial) // YouTube special content.
    case lightspeed(LightspeedSpecial) // Lightspeed special content.
    case twitch(TwitchSpecial) // Twitch special content.
    case spotify(SpotifySpecial) // Spotify special content.
    case soundcloud(SoundcloudSpecial) // Soundcloud special content.
    case bandcamp(BandcampSpecial) // Bandcamp special content.
    case streamable(StreamableSpecial) // Streamable special content.
}

// MARK: - Codable Conformance for WebsiteSpecial

extension WebsiteSpecial: Codable {
    enum CodingKeys: String, CodingKey { case type } // Key for the type.
    enum Tag: String, Codable { case None, GIF, YouTube, Lightspeed, Twitch, Spotify, Soundcloud, Bandcamp, Streamable } // Tags for different types of content.
    
    // Custom decoding for WebsiteSpecial.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .type) {
            case .None:
                self = .none
            case .GIF:
                self = .gif
            case .YouTube:
                self = .youtube(try singleValueContainer.decode(YoutubeSpecial.self))
            case .Lightspeed:
                self = .lightspeed(try singleValueContainer.decode(LightspeedSpecial.self))
            case .Twitch:
                self = .twitch(try singleValueContainer.decode(TwitchSpecial.self))
            case .Spotify:
                self = .spotify(try singleValueContainer.decode(SpotifySpecial.self))
            case .Soundcloud:
                self = .soundcloud(try singleValueContainer.decode(SoundcloudSpecial.self))
            case .Bandcamp:
                self = .bandcamp(try singleValueContainer.decode(BandcampSpecial.self))
            case .Streamable:
                self = .streamable(try singleValueContainer.decode(StreamableSpecial.self))
        }
    }
    
    // Custom encoding for WebsiteSpecial.
    public func encode(to encoder: any Encoder) throws {
        var tagContainer = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
            case .none:
                try tagContainer.encode(Tag.None, forKey: .type)
            case .gif:
                try tagContainer.encode(Tag.GIF, forKey: .type)
            case .youtube(let e):
                try tagContainer.encode(Tag.YouTube, forKey: .type)
                try e.encode(to: encoder)
            case .lightspeed(let e):
                try tagContainer.encode(Tag.Lightspeed, forKey: .type)
                try e.encode(to: encoder)
            case .twitch(let e):
                try tagContainer.encode(Tag.Twitch, forKey: .type)
                try e.encode(to: encoder)
            case .spotify(let e):
                try tagContainer.encode(Tag.Spotify, forKey: .type)
                try e.encode(to: encoder)
            case .soundcloud(let e):
                try tagContainer.encode(Tag.Soundcloud, forKey: .type)
                try e.encode(to: encoder)
            case .bandcamp(let e):
                try tagContainer.encode(Tag.Bandcamp, forKey: .type)
                try e.encode(to: encoder)
            case .streamable(let e):
                try tagContainer.encode(Tag.Streamable, forKey: .type)
                try e.encode(to: encoder)
        }
    }
}

// MARK: - January Media Structures

/// Represents an image from January.
public struct JanuaryImage: Codable, Hashable {
    public enum Size: String, Codable, Hashable {
        case large = "Large" // Large image size.
        case preview = "Preview" // Preview image size.
    }
    
    public var url: String // URL of the image.
    public var width: Int // Width of the image.
    public var height: Int // Height of the image.
    public var size: Size // Size of the image.
}

/// Represents a video from January.
public struct JanuaryVideo: Codable, Hashable {
    public var url: String // URL of the video.
    public var width: Int // Width of the video.
    public var height: Int // Height of the video.
}

/// Represents an embedded website content.
public struct WebsiteEmbed: Codable, Hashable {
    public var url: String? // URL of the embedded website.
    public var special: WebsiteSpecial? // Special content if any.
    public var title: String? // Title of the embedded content.
    public var description: String? // Description of the embedded content.
    public var image: JanuaryImage? // Associated image.
    public var video: JanuaryVideo? // Associated video.
    public var site_name: String? // Name of the site.
    public var icon_url: String? // URL of the site's icon.
    public var colour: String? // Color associated with the site.
}

/// Represents an embedded text content.
public struct TextEmbed: Codable, Hashable {
    public var icon_url: String? // URL of the icon.
    public var url: String? // URL of the text content.
    public var title: String? // Title of the text content.
    public var description: String? // Description of the text content.
    public var media: File? // Associated media file.
    public var colour: String? // Color associated with the text content.
}

// MARK: - Embed Enum

/// An enumeration representing different types of embeds.
public enum Embed: Hashable {
    case website(WebsiteEmbed) // Website embed type.
    case image(JanuaryImage) // Image embed type.
    case video(JanuaryVideo) // Video embed type.
    case text(TextEmbed) // Text embed type.
    case none // No embed.
}

// MARK: - Codable Conformance for Embed

extension Embed: Codable {
    enum CodingKeys: String, CodingKey { case type } // Key for the type.
    enum Tag: String, Codable { case Website, Image, Video, Text, None } // Tags for different types of embeds.
    
    // Custom decoding for Embed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .type) {
            case .Website:
                self = .website(try singleValueContainer.decode(WebsiteEmbed.self))
            case .Image:
                self = .image(try singleValueContainer.decode(JanuaryImage.self))
            case .Video:
                self = .video(try singleValueContainer.decode(JanuaryVideo.self))
            case .Text:
                self = .text(try singleValueContainer.decode(TextEmbed.self))
            case .None:
                self = .none
        }
    }
    
    // Custom encoding for Embed.
    public func encode(to encoder: any Encoder) throws {
        var tagContainer = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
            case .website(let e):
                try tagContainer.encode(Tag.Website, forKey: .type)
                try e.encode(to: encoder)
            case .image(let e):
                try tagContainer.encode(Tag.Image, forKey: .type)
                try e.encode(to: encoder)
            case .video(let e):
                try tagContainer.encode(Tag.Video, forKey: .type)
                try e.encode(to: encoder)
            case .text(let e):
                try tagContainer.encode(Tag.Text, forKey: .type)
                try e.encode(to: encoder)
            case .none:
                try tagContainer.encode(Tag.None, forKey: .type)
        }
    }
}
