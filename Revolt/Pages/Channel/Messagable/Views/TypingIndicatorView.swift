//
//  TypingIndicatorView.swift
//  Revolt
//
//

import UIKit

// MARK: - TypingIndicatorView
class TypingIndicatorView: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.text = "Someone is typing..."
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .textGray06
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let dotAnimation: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        backgroundColor = .bgDefaultPurple13
        
        addSubview(label)
        addSubview(dotAnimation)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            dotAnimation.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            dotAnimation.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotAnimation.widthAnchor.constraint(equalToConstant: 30),
            dotAnimation.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        setupDotAnimation()
    }
    
    private func setupDotAnimation() {
        // A placeholder for a dot animation implementation
        // This would be replaced with an actual animation in a real implementation
    }
    
    func updateText(_ text: String) {
        label.text = text
    }
}

