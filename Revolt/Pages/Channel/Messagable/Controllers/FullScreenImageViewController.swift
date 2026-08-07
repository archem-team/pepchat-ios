//
//  FullScreenImageViewController.swift
//  Revolt
//
//

import UIKit
import Photos
import Kingfisher

struct FullScreenImageItem {
    let previewImage: UIImage?
    let originalImageURL: URL?
    let sessionToken: String?
}

enum FullScreenImageGalleryNavigation {
    static func destinationIndex(currentIndex: Int, itemCount: Int, step: Int) -> Int? {
        guard itemCount > 1, abs(step) == 1 else { return nil }
        let destination = currentIndex + step
        return (0..<itemCount).contains(destination) ? destination : nil
    }

    static func positionText(currentIndex: Int, itemCount: Int) -> String? {
        guard itemCount > 1, (0..<itemCount).contains(currentIndex) else { return nil }
        return "\(currentIndex + 1) of \(itemCount)"
    }
}

// MARK: - FullScreenImageViewController
class FullScreenImageViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    private let buttonStackView = UIStackView()
    private let positionLabel = UILabel()
    private let items: [FullScreenImageItem]
    private var currentIndex: Int
    private var originalImageDataByIndex: [Int: Data] = [:]
    private var originalImageDataTask: URLSessionDataTask?
    private var isTransitioningBetweenImages = false
    private lazy var swipeLeftGesture = UISwipeGestureRecognizer(
        target: self,
        action: #selector(handleGallerySwipe(_:))
    )
    private lazy var swipeRightGesture = UISwipeGestureRecognizer(
        target: self,
        action: #selector(handleGallerySwipe(_:))
    )
    
    // Zoom properties
    private var minZoomScale: CGFloat = 1.0
    private var maxZoomScale: CGFloat = 5.0
    private var hasSetInitialZoom = false

    init(items: [FullScreenImageItem], initialIndex: Int) {
        precondition(!items.isEmpty, "Full-screen image gallery requires at least one item")
        self.items = items
        self.currentIndex = min(max(0, initialIndex), items.count - 1)
        super.init(nibName: nil, bundle: nil)
        imageView.image = items[self.currentIndex].previewImage
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    convenience init(image: UIImage, originalImageURL: URL?, sessionToken: String?) {
        self.init(
            items: [
                FullScreenImageItem(
                    previewImage: image,
                    originalImageURL: originalImageURL,
                    sessionToken: sessionToken
                )
            ],
            initialIndex: 0
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        originalImageDataTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        setupScrollView()
        setupImageView()
        setupButtons()
        setupGestures()
        displayCurrentItem()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasSetInitialZoom {
            setInitialZoomScale()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Keep this as an observability point only; initial scale is set from setInitialZoomScale itself.
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
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInsetAdjustmentBehavior = .never
        
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

        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        positionLabel.textColor = .white
        positionLabel.textAlignment = .center
        positionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        positionLabel.layer.cornerRadius = 14
        positionLabel.layer.masksToBounds = true
        positionLabel.isAccessibilityElement = true
        view.addSubview(positionLabel)
        
        NSLayoutConstraint.activate([
            // Button size constraints
            downloadButton.widthAnchor.constraint(equalToConstant: 40),
            downloadButton.heightAnchor.constraint(equalToConstant: 40),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Stack view position
            buttonStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            buttonStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            positionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            positionLabel.centerYAnchor.constraint(equalTo: buttonStackView.centerYAnchor),
            positionLabel.heightAnchor.constraint(equalToConstant: 28),
            positionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54)
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

        swipeLeftGesture.direction = .left
        swipeRightGesture.direction = .right
        swipeLeftGesture.delegate = self
        swipeRightGesture.delegate = self
        scrollView.addGestureRecognizer(swipeLeftGesture)
        scrollView.addGestureRecognizer(swipeRightGesture)

        // Give gallery swipes first chance at the fitted scale. When zoomed in,
        // the swipe delegates decline and UIScrollView keeps normal image panning.
        scrollView.panGestureRecognizer.require(toFail: swipeLeftGesture)
        scrollView.panGestureRecognizer.require(toFail: swipeRightGesture)

    }
    
    private func setInitialZoomScale() {
        guard let image = imageView.image else { return }
        
        let scrollViewSize = scrollView.bounds.size
        guard scrollViewSize.width > 0 && scrollViewSize.height > 0 else { return }
        
        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else { return }

        hasSetInitialZoom = true

        // Clear the previous item's zoom transform before changing the image view's
        // geometry. Without this reset, assigning a new frame while UIScrollView is
        // still scaled can leave the next image thumbnail-sized or off screen.
        scrollView.minimumZoomScale = 0.01
        scrollView.maximumZoomScale = max(scrollView.maximumZoomScale, 1)
        scrollView.setZoomScale(1, animated: false)
        scrollView.contentInset = .zero
        scrollView.contentOffset = .zero
        
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
    }

    private func displayCurrentItem() {
        imageView.kf.cancelDownloadTask()
        originalImageDataTask?.cancel()
        originalImageDataTask = nil

        hasSetInitialZoom = false
        scrollView.minimumZoomScale = 0.01
        scrollView.maximumZoomScale = max(scrollView.maximumZoomScale, 1)
        scrollView.setZoomScale(1, animated: false)
        scrollView.contentInset = .zero

        let item = items[currentIndex]
        imageView.image = item.previewImage ?? UIImage(systemName: "photo")
        imageView.alpha = 1
        imageView.accessibilityLabel = "Image \(currentIndex + 1) of \(items.count)"

        positionLabel.text = FullScreenImageGalleryNavigation.positionText(
            currentIndex: currentIndex,
            itemCount: items.count
        )
        positionLabel.accessibilityLabel = positionLabel.text
        positionLabel.isHidden = items.count <= 1

        view.layoutIfNeeded()
        setInitialZoomScale()
        loadOriginalImageIfAvailable()
    }

    @objc private func handleGallerySwipe(_ gesture: UISwipeGestureRecognizer) {
        let step = gesture.direction == .left ? 1 : -1
        guard let destination = FullScreenImageGalleryNavigation.destinationIndex(
            currentIndex: currentIndex,
            itemCount: items.count,
            step: step
        ) else {
            return
        }

        transitionToImage(at: destination, step: step)
    }

    private func transitionToImage(at requestedIndex: Int, step: Int) {
        guard !isTransitioningBetweenImages else { return }
        guard let destination = FullScreenImageGalleryNavigation.destinationIndex(
            currentIndex: currentIndex,
            itemCount: items.count,
            step: step
        ), destination == requestedIndex else {
            restoreGalleryPosition()
            return
        }

        let travelDirection: CGFloat = step > 0 ? -1 : 1
        isTransitioningBetweenImages = true
        view.isUserInteractionEnabled = false

        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.curveEaseIn],
            animations: {
                self.scrollView.transform = CGAffineTransform(
                    translationX: travelDirection * self.view.bounds.width * 0.22,
                    y: 0
                )
                self.scrollView.alpha = 0
            },
            completion: { _ in
                self.currentIndex = destination
                self.scrollView.transform = CGAffineTransform(
                    translationX: -travelDirection * self.view.bounds.width * 0.22,
                    y: 0
                )
                self.displayCurrentItem()
                self.scrollView.alpha = 0

                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: [.curveEaseOut],
                    animations: {
                        self.scrollView.transform = .identity
                        self.scrollView.alpha = 1
                    },
                    completion: { _ in
                        self.isTransitioningBetweenImages = false
                        self.view.isUserInteractionEnabled = true
                    }
                )
            }
        )
    }

    private func restoreGalleryPosition() {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                self.scrollView.transform = .identity
            }
        )
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeLeftGesture || gestureRecognizer === swipeRightGesture else {
            return true
        }

        guard !isTransitioningBetweenImages,
              items.count > 1,
              abs(scrollView.zoomScale - minZoomScale) < 0.01 else {
            return false
        }

        let step = gestureRecognizer === swipeLeftGesture ? 1 : -1
        return FullScreenImageGalleryNavigation.destinationIndex(
            currentIndex: currentIndex,
            itemCount: items.count,
            step: step
        ) != nil
    }

    @objc private func handleSingleTap() {
        // Toggle buttons visibility
        UIView.animate(withDuration: 0.3) {
            let targetAlpha: CGFloat = self.buttonStackView.alpha == 0 ? 1 : 0
            self.buttonStackView.alpha = targetAlpha
            self.positionLabel.alpha = targetAlpha
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
        // Prefer original bytes from network for best quality.
        if let data = originalImageDataByIndex[currentIndex] {
            saveImageDataToPhotoLibrary(data)
            return
        }

        guard let image = imageView.image else {
            showAlert(title: "Error", message: "No image available for download")
            return
        }

        requestPhotoLibrarySaveAuthorization { [weak self] isAuthorized in
            guard let self else { return }
            if isAuthorized {
                self.saveImageToPhotoLibrary(image)
            } else {
                self.showPermissionDeniedAlert()
            }
        }
    }

    private func loadOriginalImageIfAvailable() {
        let loadingIndex = currentIndex
        let item = items[loadingIndex]
        guard let originalImageURL = item.originalImageURL else { return }
        fetchOriginalImageData(from: originalImageURL, itemIndex: loadingIndex)

        var options: KingfisherOptionsInfo = [
            .cacheOriginalImage,
            .transition(.fade(0.2))
        ]

        if let token = item.sessionToken, !token.isEmpty {
            let modifier = AnyModifier { request in
                var req = request
                req.setValue(token, forHTTPHeaderField: "x-session-token")
                return req
            }
            options.append(.requestModifier(modifier))
        }

        imageView.kf.setImage(
            with: originalImageURL,
            placeholder: imageView.image,
            options: options
        ) { [weak self] result in
            guard let self = self else { return }
            guard self.currentIndex == loadingIndex else { return }
            if case .success(let value) = result {
                // Keep fallback data even when raw-bytes fetch fails.
                if self.originalImageDataByIndex[loadingIndex] == nil {
                    self.originalImageDataByIndex[loadingIndex] = value.image.pngData()
                        ?? value.image.jpegData(compressionQuality: 1.0)
                }
                self.hasSetInitialZoom = false
                self.setInitialZoomScale()
            }
        }
    }

    private func fetchOriginalImageData(from url: URL, itemIndex: Int) {
        var request = URLRequest(url: url)
        if let token = items[itemIndex].sessionToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "x-session-token")
        }

        originalImageDataTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let data = data, !data.isEmpty else { return }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.originalImageDataByIndex[itemIndex] = data
            }
        }
        originalImageDataTask?.resume()
    }
    
    private func saveImageToPhotoLibrary(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    private func saveImageDataToPhotoLibrary(_ data: Data) {
        requestPhotoLibrarySaveAuthorization { [weak self] isAuthorized in
            guard let self else { return }
            if isAuthorized {
                self.performSaveImageDataToPhotoLibrary(data)
            } else {
                self.showPermissionDeniedAlert()
            }
        }
    }

    private func performSaveImageDataToPhotoLibrary(_ data: Data) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showAlert(title: "Error", message: "Failed to save image: \(error.localizedDescription)")
                } else if success {
                    self?.showSuccessMessage()
                } else {
                    self?.showAlert(title: "Error", message: "Failed to save image")
                }
            }
        }
    }

    private func requestPhotoLibrarySaveAuthorization(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        @unknown default:
            completion(false)
        }
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

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !isTransitioningBetweenImages,
              items.count > 1,
              abs(scrollView.zoomScale - minZoomScale) < 0.01 else {
            return
        }

        let translation = scrollView.panGestureRecognizer.translation(in: view)
        let velocity = scrollView.panGestureRecognizer.velocity(in: view)
        guard abs(translation.x) > abs(translation.y),
              abs(translation.x) > 60 || abs(velocity.x) > 500 else {
            return
        }

        let step = translation.x < 0 ? 1 : -1
        guard let destination = FullScreenImageGalleryNavigation.destinationIndex(
            currentIndex: currentIndex,
            itemCount: items.count,
            step: step
        ) else {
            return
        }

        transitionToImage(at: destination, step: step)
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Optional: Add any cleanup or additional behavior after zooming
    }
}
