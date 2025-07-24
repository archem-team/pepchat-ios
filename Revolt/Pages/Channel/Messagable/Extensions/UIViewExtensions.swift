//
//  UIViewExtensions.swift
//  Revolt
//
//

import UIKit

// Extension to find parent view controller from a UIView
extension UIView {
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let viewController = nextResponder as? UIViewController {
                return viewController
            }
            responder = nextResponder
        }
        return nil
    }
    
    // Spring animation helper
    static func animate(withSpring animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.2,
            options: .curveEaseOut,
            animations: animations,
            completion: completion
        )
    }
}

