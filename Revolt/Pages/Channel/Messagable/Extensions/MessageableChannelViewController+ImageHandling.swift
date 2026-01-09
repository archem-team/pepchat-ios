//
//  MessageableChannelViewController+ImageHandling.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//

import UIKit

// MARK: - Image Handling
extension MessageableChannelViewController {
    
    func showFullScreenImage(_ image: UIImage) {
        let imageViewController = FullScreenImageViewController(image: image)
        imageViewController.modalPresentationStyle = .overFullScreen
        present(imageViewController, animated: true, completion: nil)
    }
}
