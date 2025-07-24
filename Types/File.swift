//
//  File.swift
//  Types
//
//  Created by Angelo on 20/05/2024.
//

import Foundation

/// A structure representing metadata for a file with specified dimensions.
public struct SizedMetadata: Codable, Equatable, Hashable {
    /// The height of the file.
    public var height: Int
    
    /// The width of the file.
    public var width: Int
    
    public init(height: Int, width: Int) {
            self.height = height
            self.width = width
        }
}

/// A structure representing simple metadata without additional properties.
public struct SimpleMetadata: Codable, Equatable, Hashable {
    // Currently empty, can be expanded in the future if needed.
    
    public init() {
        // Default initializer for empty struct
    }
}

/// An enumeration representing the type of file metadata.
/// Each case can hold different types of metadata.
public enum FileMetadata: Equatable, Hashable {
    case image(SizedMetadata)       // Metadata for an image file.
    case video(SizedMetadata)       // Metadata for a video file.
    case file(SimpleMetadata)       // Metadata for a generic file.
    case text(SimpleMetadata)       // Metadata for a text file.
    case audio(SimpleMetadata)      // Metadata for an audio file.
}

// MARK: - Codable Conformance for FileMetadata
extension FileMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case type // The type of the file (image, video, etc.).
    }
    
    enum Tag: String, Codable {
        case Image, Video, File, Text, Audio // Tags for each file type.
    }
    
    /// Initializes a `FileMetadata` instance from a decoder.
    /// - Parameter decoder: The decoder to read data from.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        // Decode the type of file metadata.
        switch try container.decode(Tag.self, forKey: .type) {
            case .Image:
                self = .image(try singleValueContainer.decode(SizedMetadata.self))
            case .Video:
                self = .video(try singleValueContainer.decode(SizedMetadata.self))
            case .File:
                self = .file(try singleValueContainer.decode(SimpleMetadata.self))
            case .Text:
                self = .text(try singleValueContainer.decode(SimpleMetadata.self))
            case .Audio:
                self = .audio(try singleValueContainer.decode(SimpleMetadata.self))
        }
    }
    
    /// Encodes the `FileMetadata` instance into the provided encoder.
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var tagContainer = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode the type of file metadata.
        switch self {
            case .image(let m):
                try tagContainer.encode(Tag.Image, forKey: .type)
                try m.encode(to: encoder)
            case .video(let m):
                try tagContainer.encode(Tag.Video, forKey: .type)
                try m.encode(to: encoder)
            case .file(let m):
                try tagContainer.encode(Tag.File, forKey: .type)
                try m.encode(to: encoder)
            case .text(let m):
                try tagContainer.encode(Tag.Text, forKey: .type)
                try m.encode(to: encoder)
            case .audio(let m):
                try tagContainer.encode(Tag.Audio, forKey: .type)
                try m.encode(to: encoder)
        }
    }
}

/// A structure representing a file with its metadata and other attributes.
public struct File: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier for the file.
    public var id: String
    
    /// A tag associated with the file (e.g., a category or type).
    public var tag: String
    
    /// The size of the file in bytes.
    public var size: Int64
    
    /// The name of the file, including its extension.
    public var filename: String
    
    /// Metadata associated with the file.
    public var metadata: FileMetadata
    
    /// The content type of the file (e.g., "image/png", "video/mp4").
    public var content_type: String
    
    /// Coding keys for encoding/decoding the `File` structure.
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case tag, size, filename, metadata, content_type
    }
    
    
    public init(id: String, tag: String, size: Int64, filename: String, metadata: FileMetadata, content_type: String) {
            self.id = id
            self.tag = tag
            self.size = size
            self.filename = filename
            self.metadata = metadata
            self.content_type = content_type
        }
    
}
