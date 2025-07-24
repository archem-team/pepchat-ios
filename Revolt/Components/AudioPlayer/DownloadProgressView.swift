//
//  DownloadProgressView.swift
//  Revolt
//
//

import UIKit

class DownloadProgressView: UIView {
    private let trackLayer = CALayer()
    private let progressLayer = CALayer()
    private let bufferingLayer = CALayer()
    private let thumbView = UIView()
    private let thumbLayer = CALayer()
    private var _currentProgress: Float = 0.0
    
    // Public getter for current progress
    var currentProgress: Float {
        return _currentProgress
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        setupThumb()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupThumb()
    }
    
    private func setupLayers() {
        backgroundColor = UIColor.clear
        layer.masksToBounds = false
        
        // Background track layer
        trackLayer.backgroundColor = UIColor.systemGray5.cgColor
        trackLayer.cornerRadius = 2
        layer.addSublayer(trackLayer)
        
        // Buffering layer (blue overlay)
        bufferingLayer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
        bufferingLayer.cornerRadius = 2
        layer.addSublayer(bufferingLayer)
        
        // Progress layer (purple)
        progressLayer.backgroundColor = UIColor(red: 102/255.0, green: 45/255.0, blue: 145/255.0, alpha: 1.0).cgColor
        progressLayer.cornerRadius = 2
        layer.addSublayer(progressLayer)
    }
    
    private func setupThumb() {
        // Thumb container
        thumbView.backgroundColor = .clear
        thumbView.isUserInteractionEnabled = false
        
        // Shadow
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 1)
        thumbView.layer.shadowOpacity = 0.3
        thumbView.layer.shadowRadius = 2
        
        addSubview(thumbView)
        
        // Thumb circle
        thumbLayer.backgroundColor = UIColor(red: 102/255.0, green: 45/255.0, blue: 145/255.0, alpha: 1.0).cgColor
        thumbLayer.cornerRadius = 7 // Reduced from 8 to 7 (half of new thumb size 14)
        thumbLayer.borderWidth = 2
        thumbLayer.borderColor = UIColor.white.cgColor
        
        thumbView.layer.addSublayer(thumbLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let trackHeight: CGFloat = 4
        let trackY = (bounds.height - trackHeight) / 2
        
        // Update track layer
        trackLayer.frame = CGRect(x: 0, y: trackY, width: bounds.width, height: trackHeight)
        
        // Update other layers based on current progress
        updateLayerPositions()
    }
    
    private func updateLayerPositions() {
        let trackHeight: CGFloat = 4
        let trackY = (bounds.height - trackHeight) / 2
        
        // Update progress layer
        let progressWidth = bounds.width * CGFloat(_currentProgress)
        progressLayer.frame = CGRect(x: 0, y: trackY, width: progressWidth, height: trackHeight)
        
        // Update thumb position - reduced size from 16 to 14
        let thumbSize: CGFloat = 14
        let thumbX = progressWidth - thumbSize / 2
        let thumbY = (bounds.height - thumbSize) / 2
        
        thumbView.frame = CGRect(x: thumbX, y: thumbY, width: thumbSize, height: thumbSize)
        thumbLayer.frame = CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize)
    }
    
    // Update buffering progress (0.0 to 1.0)
    func updateBuffering(_ progress: Float) {
        let trackHeight: CGFloat = 4
        let trackY = (bounds.height - trackHeight) / 2
        let bufferedWidth = bounds.width * CGFloat(progress)
        
        bufferingLayer.frame = CGRect(x: 0, y: trackY, width: bufferedWidth, height: trackHeight)
    }
    
    // Update playback progress (0.0 to 1.0)
    func updateProgress(_ progress: Float) {
        _currentProgress = max(0.0, min(1.0, progress))
        updateLayerPositions()
    }
    
    // Highlight thumb for interaction
    func setThumbHighlighted(_ highlighted: Bool) {
        UIView.animate(withDuration: 0.1) {
            self.thumbView.transform = highlighted ? CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity
            self.thumbView.layer.shadowOpacity = highlighted ? 0.5 : 0.3
        }
    }
} 
