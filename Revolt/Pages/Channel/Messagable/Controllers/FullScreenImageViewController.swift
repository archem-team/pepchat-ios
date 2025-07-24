//
//  FullScreenImageViewController.swift
//  Revolt
//
//

import UIKit
import Photos

// MARK: - FullScreenImageViewController
class FullScreenImageViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    private let buttonStackView = UIStackView()
    
    // Zoom properties
    private var minZoomScale: CGFloat = 1.0
    private var maxZoomScale: CGFloat = 5.0
    private var hasSetInitialZoom = false
    
    init(image: UIImage) {
        super.init(nibName: nil, bundle: nil)
        imageView.image = image
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        setupScrollView()
        setupImageView()
        setupButtons()
        setupGestures()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Set initial zoom scale when view appears
        if !hasSetInitialZoom {
            hasSetInitialZoom = true
            setInitialZoomScale()
        }
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.decelerationRate = UIScrollView.DecelerationRate.fast
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.contentInsetAdjustmentBehavior = .automatic
        
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    private func setupImageView() {
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        
        scrollView.addSubview(imageView)
    }
    
    private func setupButtons() {
        // Configure download button
        downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
        downloadButton.tintColor = .white
        downloadButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        downloadButton.layer.cornerRadius = 20
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.addTarget(self, action: #selector(downloadImage), for: .touchUpInside)
        
        // Configure close button
        closeButton.setTitle("✕", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .medium)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeButton.layer.cornerRadius = 20
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(dismissView), for: .touchUpInside)
        
        // Setup stack view for buttons
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fill
        buttonStackView.alignment = .center
        buttonStackView.spacing = 12
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        
        buttonStackView.addArrangedSubview(downloadButton)
        buttonStackView.addArrangedSubview(closeButton)
        
        view.addSubview(buttonStackView)
        
        NSLayoutConstraint.activate([
            // Button size constraints
            downloadButton.widthAnchor.constraint(equalToConstant: 40),
            downloadButton.heightAnchor.constraint(equalToConstant: 40),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Stack view position
            buttonStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            buttonStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }
    
    private func setupGestures() {
        // Single tap to toggle buttons visibility
        let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTapGesture.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTapGesture)
        
        // Double tap to zoom in/out
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
        
        // Make sure single tap doesn't interfere with double tap
        singleTapGesture.require(toFail: doubleTapGesture)
    }
    
    private func setInitialZoomScale() {
        guard let image = imageView.image else { return }
        
        let scrollViewSize = scrollView.bounds.size
        guard scrollViewSize.width > 0 && scrollViewSize.height > 0 else { return }
        
        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else { return }
        
        // Set imageView frame to match image size
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        
        // Set content size to match image size
        scrollView.contentSize = imageSize
        
        // Calculate the scale to fit the image within the scroll view
        let widthScale = scrollViewSize.width / imageSize.width
        let heightScale = scrollViewSize.height / imageSize.height
        let fitScale = min(widthScale, heightScale)
        
        // Set zoom scales
        minZoomScale = fitScale
        maxZoomScale = max(fitScale * 5.0, 3.0)
        
        scrollView.minimumZoomScale = minZoomScale
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.setZoomScale(minZoomScale, animated: false)
        
        // Center the image after zooming
        centerImageView()
    }
    
    private func centerImageView() {
        let scrollViewSize = scrollView.bounds.size
        let imageViewSize = imageView.frame.size
        
        // Calculate insets to center the image
        let verticalInset = max(0, (scrollViewSize.height - imageViewSize.height) / 2)
        let horizontalInset = max(0, (scrollViewSize.width - imageViewSize.width) / 2)
        
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
        
        // Debug logging
        print("🖼️ CenterImageView Debug:")
        print("   ScrollView size: \(scrollViewSize)")
        print("   ImageView size: \(imageViewSize)")
        print("   Vertical inset: \(verticalInset)")
        print("   Horizontal inset: \(horizontalInset)")
        print("   ContentOffset: \(scrollView.contentOffset)")
        print("   ContentSize: \(scrollView.contentSize)")
    }
    
    @objc private func handleSingleTap() {
        // Toggle buttons visibility
        UIView.animate(withDuration: 0.3) {
            self.buttonStackView.alpha = self.buttonStackView.alpha == 0 ? 1 : 0
        }
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale == minZoomScale {
            // Zoom in to the tapped location
            let location = gesture.location(in: imageView)
            let zoomScale = min(maxZoomScale, minZoomScale * 3.0) // Zoom to 3x or max scale
            let width = scrollView.bounds.width / zoomScale
            let height = scrollView.bounds.height / zoomScale
            let zoomRect = CGRect(
                x: location.x - width / 2,
                y: location.y - height / 2,
                width: width,
                height: height
            )
            scrollView.zoom(to: zoomRect, animated: true)
        } else {
            // Zoom out to fit
            scrollView.setZoomScale(minZoomScale, animated: true)
        }
    }
    
    @objc private func downloadImage() {
        guard let image = imageView.image else {
            showAlert(title: "Error", message: "No image available for download")
            return
        }
        
        // Check photo library access permission
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            saveImageToPhotoLibrary(image)
        case .denied, .restricted:
            showPermissionDeniedAlert()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self?.saveImageToPhotoLibrary(image)
                    } else {
                        self?.showPermissionDeniedAlert()
                    }
                }
            }
        @unknown default:
            showAlert(title: "Error", message: "Unknown permission status")
        }
    }
    
    private func saveImageToPhotoLibrary(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async {
            if let error = error {
                self.showAlert(title: "Error", message: "Failed to save image: \(error.localizedDescription)")
            } else {
                self.showSuccessMessage()
            }
        }
    }
    
    private func showSuccessMessage() {
        // Create a temporary success view
        let successView = UIView()
        successView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        successView.layer.cornerRadius = 8
        successView.translatesAutoresizingMaskIntoConstraints = false
        
        let successLabel = UILabel()
        successLabel.text = "✓ Image saved to Photos"
        successLabel.textColor = .white
        successLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        successLabel.textAlignment = .center
        successLabel.translatesAutoresizingMaskIntoConstraints = false
        
        successView.addSubview(successLabel)
        view.addSubview(successView)
        
        NSLayoutConstraint.activate([
            successLabel.centerXAnchor.constraint(equalTo: successView.centerXAnchor),
            successLabel.centerYAnchor.constraint(equalTo: successView.centerYAnchor),
            successLabel.leadingAnchor.constraint(equalTo: successView.leadingAnchor, constant: 16),
            successLabel.trailingAnchor.constraint(equalTo: successView.trailingAnchor, constant: -16),
            
            successView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            successView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            successView.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Animate in
        successView.alpha = 0
        successView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        UIView.animate(withDuration: 0.3, animations: {
            successView.alpha = 1
            successView.transform = .identity
        }) { _ in
            // Auto dismiss after 2 seconds
            UIView.animate(withDuration: 0.3, delay: 2.0, animations: {
                successView.alpha = 0
                successView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }) { _ in
                successView.removeFromSuperview()
            }
        }
    }
    
    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "Photo Library Access",
            message: "To save images, we need access to your photo library. Please enable access in Settings.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    // MARK: - UIScrollViewDelegate
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageView()
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Optional: Add any cleanup or additional behavior after zooming
    }
}

