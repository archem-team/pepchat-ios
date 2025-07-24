//
//  RemoteImageTextAttachment.swift
//  Revolt
//
//  Created by Angelo on 15/10/2023.
//

import Foundation
import UIKit

class RemoteImageTextAttachment: NSTextAttachment {
    var contentURL: URL?
    var contentTask: Task<Void, Never>?
    
    convenience init(contents: @escaping () async -> URL) {
        self.init()
        
        // Start async task to fetch the URL
        contentTask = Task {
            do {
                let url = await contents()
                self.contentURL = url
                
                // Fetch image data from the URL
                let (data, _) = try await URLSession.shared.data(from: url)
                
                // Update the attachment image on the main thread
                await MainActor.run {
                    if let image = UIImage(data: data) {
                        // Resize image to appropriate size for inline display
                        let size = CGSize(width: 16, height: 16)
                        UIGraphicsBeginImageContextWithOptions(size, false, 0)
                        image.draw(in: CGRect(origin: .zero, size: size))
                        self.image = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                    }
                }
            } catch {
                print("Error loading remote image: \(error)")
            }
        }
    }
    
    deinit {
        contentTask?.cancel()
    }
}
