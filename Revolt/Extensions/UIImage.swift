//
//  UIImage.swift
//  Revolt
//
//  Created by Angelo on 19/07/2024.
//

import UIKit

extension UIImage {
    
    /// Enumeration for different content modes used when resizing images.
    enum ContentMode {
        /// Scale the image to fill the target size, potentially altering the aspect ratio.
        case contentFill
        
        /// Scale the image to maintain its aspect ratio while fitting within the target size.
        case contentAspectFill
        
        /// Scale the image to maintain its aspect ratio while filling the target size.
        case contentAspectFit
    }
    
    /// Resizes the image to a new size using the specified content mode.
    ///
    /// This function computes the new dimensions based on the specified `ContentMode`.
    /// - Parameters:
    ///   - size: The desired size for the new image.
    ///   - contentMode: The content mode to apply when resizing.
    /// - Returns: A new resized `UIImage` or `nil` if the resizing fails.
    func imageWith(newSize size: CGSize, contentMode: ContentMode) -> UIImage? {
        let aspectWidth = size.width / self.size.width
        let aspectHeight = size.height / self.size.height
        
        switch contentMode {
            case .contentFill:
                return imageWith(newSize: size)
            case .contentAspectFit:
                let aspectRatio = min(aspectWidth, aspectHeight)
                return imageWith(newSize: CGSize(width: self.size.width * aspectRatio, height: self.size.height * aspectRatio))
            case .contentAspectFill:
                let aspectRatio = max(aspectWidth, aspectHeight)
                return imageWith(newSize: CGSize(width: self.size.width * aspectRatio, height: self.size.height * aspectRatio))
        }
    }
    
   
    func imageWith(newSize: CGSize) -> UIImage {
        let image = UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }

        return image.withRenderingMode(renderingMode)
    }

    func imageWith(targetSize: CGSize) -> UIImage {
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height

        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }

        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage!
    }
    
    /// Creates a rounded version of the image.
    ///
    /// This property generates a new image that has rounded corners. The corner radius
    /// is set to half the image's height, producing a circular image for square images.
    var roundedImage: UIImage {
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: self.size)
        UIGraphicsBeginImageContextWithOptions(self.size, false, 1)
        defer {
            // End context after returning to avoid memory leak
            UIGraphicsEndImageContext()
        }
        
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: self.size.height / 2 // Use half height for a circular image
        ).addClip()
        self.draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
}
