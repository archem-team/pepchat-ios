//
//  LazyImage.swift
//  Revolt
//
//  Created by Angelo on 14/10/2023.
//

import Foundation
import SwiftUI
import Kingfisher
import Types

/// An enumeration representing different sources for loading images.
enum LazyImageSource {
    case url(URL)            // Loads an image from a URL.
    case file(File)         // Loads an image from a file.
    case emoji(String)      // Loads an image associated with an emoji ID.
    case local(Data)        // Loads an image from local data.
    case id(String, String) // Loads an image from a specified ID and tag.
}

/// A SwiftUI view that lazily loads and displays an image from various sources.
struct LazyImage<S: Shape>: View {
    
    // MARK: - Properties

    /// The current view state for the application, providing access to shared data.
    @EnvironmentObject private var viewState: ViewState

    /// The source from which to load the image.
    public var source: LazyImageSource
    
    /// The optional height of the image.
    public var height: CGFloat?
    
    /// The optional width of the image.
    public var width: CGFloat?
    
    /// The shape to which the image will be clipped.
    public var clipTo: S
    
    /// The content mode for the image.
    public var contentMode: SwiftUI.ContentMode = .fill

    // MARK: - Computed Properties

    /// The source for the image in a format compatible with the Kingfisher library.
    var _source: Source {
        switch source {
            case .url(let u):
                return .network(u)
            case .file(let file):
                return .network(URL(string: viewState.formatUrl(with: file))!)
            case .emoji(let id):
                return .network(URL(string: viewState.formatUrl(fromEmoji: id))!)
            case .local(let data):
                return .provider(RawImageDataProvider(data: data, cacheKey: String(data.hashValue)))
            case .id(let id, let tag):
                return .network(URL(string: viewState.formatUrl(fromId: id, withTag: tag))!)
        }
    }

    // MARK: - Computed Properties for Logging
    
    /// Description of the image source for logging
    private var sourceDescription: String {
        switch source {
        case .url(let u): return "URL(\(u.lastPathComponent))"
        case .file(let f): return "File(\(f.filename))"
        case .emoji(let id): return "Emoji(\(id))"
        case .local(_): return "Local"
        case .id(let id, let tag): return "ID(\(id), \(tag))"
        }
    }

    // MARK: - Body

    /// The main body of the `LazyImage` view.
    @ViewBuilder
    var body: some View {
        // MEMORY OPTIMIZATION: Calculate target size for downsampling
        // Default to 400x400 if no size specified, otherwise use provided size with 2x scale for retina
        let targetWidth = (width ?? 400) * 2
        let targetHeight = (height ?? 400) * 2
        let processor = DownsamplingImageProcessor(size: CGSize(width: targetWidth, height: targetHeight))
        let scale = UIScreen.main.scale
        
        // MEMORY OPTIMIZATION: Use KFImage which supports processors and handles both static and animated images
        KFImage(source: _source)
            .setProcessor(processor)
            .scaleFactor(scale)
            .placeholder { Color.bgGray11 }
            .aspectRatio(contentMode: contentMode)
            .frame(width: width, height: height)
            .clipped()
            .clipShape(clipTo)
            .onAppear {
                print("🖼️ [MEMORY] LazyImage loading: \(self.sourceDescription) with downsampling to \(Int(targetWidth))x\(Int(targetHeight)) @\(scale)x scale")
            }
    }
}
