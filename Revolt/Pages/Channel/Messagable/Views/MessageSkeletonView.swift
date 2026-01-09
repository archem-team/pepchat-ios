//
//  MessageSkeletonView.swift
//  Revolt
//
//

import UIKit

class MessageSkeletonView: UIView {
    
    private let numberOfSkeletons = 9
    private let skeletonRowHeight: CGFloat = 60
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSkeletonView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSkeletonView()
    }
    
    private func setupSkeletonView() {
        backgroundColor = .bgDefaultPurple13
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])
        
        // Create skeleton rows
        for _ in 0..<numberOfSkeletons {
            let skeletonRow = createSkeletonRow()
            stackView.addArrangedSubview(skeletonRow)
        }
    }
    
    private func createSkeletonRow() -> UIView {
        let rowContainer = UIView()
        rowContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Avatar placeholder
        let avatarView = UIView()
        avatarView.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.8)
        avatarView.layer.cornerRadius = 20
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        rowContainer.addSubview(avatarView)
        
        // Content container
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        rowContainer.addSubview(contentStack)
        
        // Username placeholder
        let usernameView = UIView()
        usernameView.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.7)
        usernameView.layer.cornerRadius = 4
        usernameView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(usernameView)
        
        // Message content placeholder
        let messageView = UIView()
        messageView.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.6)
        messageView.layer.cornerRadius = 4
        messageView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(messageView)
        
        NSLayoutConstraint.activate([
            rowContainer.heightAnchor.constraint(equalToConstant: skeletonRowHeight),
            
            // Avatar constraints
            avatarView.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
            avatarView.topAnchor.constraint(equalTo: rowContainer.topAnchor, constant: 8),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            
            // Content stack constraints
            contentStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: rowContainer.topAnchor, constant: 8),
            
            // Username placeholder constraints
            usernameView.heightAnchor.constraint(equalToConstant: 16),
            usernameView.widthAnchor.constraint(equalTo: contentStack.widthAnchor, multiplier: 0.5),
            
            // Message content placeholder constraints
            messageView.heightAnchor.constraint(equalToConstant: 20),
            messageView.widthAnchor.constraint(equalTo: contentStack.widthAnchor, multiplier: 0.85),
        ])
        
        return rowContainer
    }
}
