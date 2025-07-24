//
//  NSFWOverlayView.swift
//  Revolt
//

import UIKit

protocol NSFWOverlayViewDelegate: AnyObject {
    func nsfwOverlayViewDidConfirm(_ view: NSFWOverlayView)
}

class NSFWOverlayView: UIView {
    weak var delegate: NSFWOverlayViewDelegate?
    
    private let channelName: String
    
    // UI Components
    private let overlayView = UIView()
    private let stackView = UIStackView()
    private let warningSymbol = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let confirmButton = UIButton(type: .system)
    
    init(channelName: String) {
        self.channelName = channelName
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        setupOverlay()
        setupStackView()
        setupWarningSymbol()
        setupLabels()
        setupConfirmButton()
        setupConstraints()
    }
    
    private func setupOverlay() {
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlayView)
    }
    
    private func setupStackView() {
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(stackView)
    }
    
    private func setupWarningSymbol() {
        warningSymbol.image = UIImage(systemName: "exclamationmark.triangle.fill")
        warningSymbol.contentMode = .scaleAspectFit
        warningSymbol.tintColor = .textDefaultGray01
        warningSymbol.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupLabels() {
        // Title label
        titleLabel.text = channelName
        titleLabel.textColor = .textDefaultGray01
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.numberOfLines = 0
        
        // Message label
        messageLabel.text = "This channel is marked as NSFW"
        messageLabel.textColor = .textGray06
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 14)
        messageLabel.numberOfLines = 0
    }
    
    private func setupConfirmButton() {
        confirmButton.setTitle("I confirm that I am at least 18 years old", for: .normal)
        confirmButton.setTitleColor(.textDefaultGray01, for: .normal)
        confirmButton.backgroundColor = UIColor.systemBlue
        confirmButton.layer.cornerRadius = 8
        confirmButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        confirmButton.addTarget(self, action: #selector(confirmButtonTapped), for: .touchUpInside)
        confirmButton.titleLabel?.numberOfLines = 0
        confirmButton.titleLabel?.textAlignment = .center
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Overlay fills entire view
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Stack view centered in overlay
            stackView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: overlayView.widthAnchor, multiplier: 0.8),
            
            // Warning symbol size
            warningSymbol.heightAnchor.constraint(equalToConstant: 100),
            warningSymbol.widthAnchor.constraint(equalToConstant: 100)
        ])
        
        // Add arranged subviews
        stackView.addArrangedSubview(warningSymbol)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(confirmButton)
    }
    
    // MARK: - Actions
    
    @objc private func confirmButtonTapped() {
        delegate?.nsfwOverlayViewDidConfirm(self)
    }
    
    // MARK: - Public Methods
    
    func show(in parentView: UIView, animated: Bool = true) {
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            topAnchor.constraint(equalTo: parentView.topAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        
        if animated {
            alpha = 0
            UIView.animate(withDuration: 0.3) {
                self.alpha = 1
            }
        }
    }
    
    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                self.alpha = 0
            }) { _ in
                self.removeFromSuperview()
                completion?()
            }
        } else {
            removeFromSuperview()
            completion?()
        }
    }
    
    // MARK: - Static Convenience Method
    
    static func show(in parentView: UIView, channelName: String, delegate: NSFWOverlayViewDelegate?) -> NSFWOverlayView {
        let overlay = NSFWOverlayView(channelName: channelName)
        overlay.delegate = delegate
        overlay.show(in: parentView, animated: true)
        return overlay
    }
} 