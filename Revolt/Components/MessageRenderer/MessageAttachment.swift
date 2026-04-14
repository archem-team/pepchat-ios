//
//  MessageAttachment.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI
import UIKit
import AVFoundation
import AVKit
import Types

// Formatter to convert byte counts into human-readable strings
var fmt = ByteCountFormatter()

/// Same UIKit `VideoPlayerView` as the main chat (thumbnail, play, download, duration) with identical tap-to-play flow.
struct ChannelVideoAttachmentPlayerView: UIViewRepresentable {
    var videoURL: String
    var filename: String
    var fileSize: Int64
    var sessionToken: String?

    final class Coordinator {
        var lastVideoURL: String?
        var lastFilename: String?
        var lastFileSize: Int64?
        var lastToken: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> VideoPlayerView {
        let view = VideoPlayerView()
        applyConfiguration(to: view, context: context, force: true)
        return view
    }

    func updateUIView(_ uiView: VideoPlayerView, context: Context) {
        applyConfiguration(to: uiView, context: context, force: false)
    }

    private func applyConfiguration(to view: VideoPlayerView, context: Context, force: Bool) {
        let c = context.coordinator
        if !force,
           c.lastVideoURL == videoURL,
           c.lastFilename == filename,
           c.lastFileSize == fileSize,
           c.lastToken == sessionToken {
            return
        }
        c.lastVideoURL = videoURL
        c.lastFilename = filename
        c.lastFileSize = fileSize
        c.lastToken = sessionToken

        var headers: [String: String] = [:]
        if let token = sessionToken, !token.isEmpty {
            headers["x-session-token"] = token
        }
        view.configure(with: videoURL, filename: filename, fileSize: fileSize, headers: headers)
        let tokenForPlayback = sessionToken
        view.onPlayTapped = { url in
            AttachmentVideoPlayback.play(from: view, urlString: url, sessionToken: tokenForPlayback)
        }
    }
}

/// A view that represents an attachment in a message, supporting various file types.
struct MessageAttachment: View {
    @EnvironmentObject var viewState: ViewState  // Access to the global state for theming and ...
    @State var isPresented: Bool = false
    var attachment: File  // The file attachment to be displayed
    var height : CGFloat = 0
    
    
    var body: some View {
        // Switch statement to determine how to display the attachment based on its metadata
        
        Group {
            switch attachment.metadata {
            case .image(_):  // Handle image attachments
                
                
                /*Button {
                    self.isPresented.toggle()
                } label: {*/
                    Color.clear
                        .overlay {
                            LazyImage(source: .file(attachment),
                                      clipTo: RoundedRectangle(cornerRadius: .radiusXSmall))  // Load the image with rounded corners
                            .aspectRatio(contentMode: .fill)  // Maintain aspect ratio
                            //.frame(maxHeight: 298)  // Set a maximum height for the image
                            .clipShape(RoundedRectangle(cornerRadius: .radiusXSmall))
                            .scaledToFill()
                        }
                        .clipped()
                        .frame(height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture{
                            self.isPresented.toggle()
                        }
               // }
                
                
                
                
                
            case .video(_):  // Handle video attachments (same UIKit player as chat)
                let videoURL = viewState.formatUrl(fromId: attachment.id, withTag: "attachments")
                ChannelVideoAttachmentPlayerView(
                    videoURL: videoURL,
                    filename: attachment.filename,
                    fileSize: attachment.size,
                    sessionToken: viewState.sessionToken
                )
                .id(attachment.id)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: .radiusXSmall))
                
            case .file(_), .text(_), .audio(_):  // Handle general file types, text files, and audio files
                HStack(alignment: .center) {
                    
                    
                    PeptideIcon(iconName: .peptideDoc,
                                size: .size32,
                                color: .iconGray07)
                    .padding(.padding4)
                    
                    
                    VStack(alignment: .leading, spacing: .zero) {
                        
                        PeptideText(textVerbatim: attachment.filename,
                                    font: .peptideBody3,
                                    textColor: .textBlue07,
                                    lineLimit: 1)
                        
                        PeptideText(textVerbatim: fmt.string(fromByteCount: attachment.size),
                                    font: .peptideSubhead,
                                    textColor: .textGray07,
                                    lineLimit: 1)
                        
                        
                    }
                    //.padding(.vertical, 8)
                    
                    Spacer()  // Pushes the following button to the right
                    
                    // Button for downloading the attachment
                    /*Button {
                     print("todo")  // Placeholder action for the button
                     } label: {
                     Image(systemName: "square.and.arrow.down")  // Download icon
                     }
                     .padding(.trailing, 16)  // Right padding for the button
                     .padding(.vertical, 8)  // Vertical padding for the button
                     */
                }
                .onTapGesture {
                    UIApplication.shared.open(URL(string: viewState.formatUrl(with: attachment))!)
                }
                //.background(viewState.theme.background2.color)  // Background color based on the current theme
                //.clipShape(RoundedRectangle(cornerRadius: radius8))  // Round the corners of the background
                
            default:
                EmptyView()
            }
            
        }
        .fullScreenCover(isPresented: $isPresented){
            ZoomableMessageAttachment(isPresented: $isPresented, attachment: attachment)
        }
        
    }
}


struct ZoomableMessageAttachment : View {
    
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool
    var attachment: File
    
    
    var body: some View {
        
        VStack(spacing: .zero){
            
            HStack(spacing: .spacing8){
                
                Button {
                    self.isPresented.toggle()
                } label: {
                    PeptideIcon(iconName: .peptideCloseLiner,
                                color: .iconDefaultGray01)
                }
                
                Spacer(minLength: .zero)
                
            }
            .padding(.horizontal, .padding16)
            .frame(height: .size48)
            
            RoundedRectangle(cornerRadius: .zero)
                .foregroundStyle(.borderGray11)
                .frame(height: .size1)
            
            Spacer(minLength: .zero)
            
            ZStack {
                switch attachment.metadata {
                case .image(_):  // Handle image attachments
                    
                    ZoomableScrollView {
                        LazyImage(source: .file(attachment),
                                  clipTo: RoundedRectangle(cornerRadius: .radiusXSmall),
                                  contentMode: .fit)  // Load the image with rounded corners
                        .aspectRatio(contentMode: .fit)  // Maintain aspect ratio
                        .frame(maxHeight: 295)  // Set a maximum height for the image
                    }
                    
                    
                   
                    
                    
                case .video(_):  // Handle video attachments (same UIKit player as chat)
                    let videoURL = viewState.formatUrl(fromId: attachment.id, withTag: "attachments")
                    ChannelVideoAttachmentPlayerView(
                        videoURL: videoURL,
                        filename: attachment.filename,
                        fileSize: attachment.size,
                        sessionToken: viewState.sessionToken
                    )
                    .id(attachment.id)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: .radius8))
                    
                case .file(_), .text(_), .audio(_):  // Handle general file types, text files, and audio files
                    HStack(alignment: .center) {
                        
                        
                        PeptideIcon(iconName: .peptideDoc,
                                    size: .size32,
                                    color: .iconGray07)
                        .padding(.padding4)
                        
                        
                        VStack(alignment: .leading, spacing: .zero) {
                            
                            PeptideText(textVerbatim: attachment.filename,
                                        font: .peptideBody3,
                                        textColor: .textBlue07,
                                        lineLimit: 1)
                            
                            PeptideText(textVerbatim: fmt.string(fromByteCount: attachment.size),
                                        font: .peptideSubhead,
                                        textColor: .textGray07,
                                        lineLimit: 1)
                            
                            
                        }
                        //.padding(.vertical, 8)
                        
                        Spacer()  // Pushes the following button to the right
                        
                        // Button for downloading the attachment
                        /*Button {
                         print("todo")  // Placeholder action for the button
                         } label: {
                         Image(systemName: "square.and.arrow.down")  // Download icon
                         }
                         .padding(.trailing, 16)  // Right padding for the button
                         .padding(.vertical, 8)  // Vertical padding for the button
                         */
                    }
                    //.background(viewState.theme.background2.color)  // Background color based on the current theme
                    //.clipShape(RoundedRectangle(cornerRadius: radius8))  // Round the corners of the background
                default:
                    EmptyView()
                }
                
            }
            
            Spacer(minLength: .zero)
            
        }
        
        
        
    }
}


struct ZoomableScrollView<Content: View>: UIViewRepresentable {
  private var content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  func makeUIView(context: Context) -> UIScrollView {
    // set up the UIScrollView
    let scrollView = UIScrollView()
    scrollView.delegate = context.coordinator  // for viewForZooming(in:)
    scrollView.maximumZoomScale = 20
    scrollView.minimumZoomScale = 1
    scrollView.bouncesZoom = true

    // create a UIHostingController to hold our SwiftUI content
    let hostedView = context.coordinator.hostingController.view!
    hostedView.translatesAutoresizingMaskIntoConstraints = true
    hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    hostedView.frame = scrollView.bounds
    scrollView.addSubview(hostedView)

    return scrollView
  }

  func makeCoordinator() -> Coordinator {
    return Coordinator(hostingController: UIHostingController(rootView: self.content))
  }

  func updateUIView(_ uiView: UIScrollView, context: Context) {
    // update the hosting controller's SwiftUI content
    context.coordinator.hostingController.rootView = self.content
    assert(context.coordinator.hostingController.view.superview == uiView)
  }

  // MARK: - Coordinator

  class Coordinator: NSObject, UIScrollViewDelegate {
    var hostingController: UIHostingController<Content>

    init(hostingController: UIHostingController<Content>) {
      self.hostingController = hostingController
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      return hostingController.view
    }
  }
}

// MARK: - Attachment video playback (shared with MessageCell)

extension UIView {
    /// Walks the responder chain to find the hosting view controller (same idea as `MessageCell.findParentViewController()`).
    fileprivate func parentViewControllerForPlayback() -> UIViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            responder = responder?.next
            if let viewController = responder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
}

enum AttachmentVideoPlayback {

    private static let loadingViewTag = 99_999

    /// Temp files written before handing a local URL to `AVPlayer` (cleaned up when the player dismisses).
    static var tempVideoURLs: Set<URL> = []

    /// Strong ref while fullscreen playback is active (owns `AVPlayerViewControllerDelegate`).
    private static var activeSession: Session?

    static func cleanupTempVideos() {
        for url in tempVideoURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        tempVideoURLs.removeAll()
    }

    /// Entry point used by chat cells and SwiftUI-hosted `VideoPlayerView` (pinned list, etc.).
    static func play(from anchorView: UIView, urlString: String, sessionToken: String?) {
        guard URL(string: urlString) != nil else { return }
        guard let hostVC = anchorView.parentViewControllerForPlayback() else { return }

        let loadingView = createLoadingView()
        loadingView.tag = loadingViewTag
        guard let targetView = hostVC.view else { return }
        targetView.addSubview(loadingView)

        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: targetView.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: targetView.centerYAnchor),
            loadingView.widthAnchor.constraint(equalToConstant: 120),
            loadingView.heightAnchor.constraint(equalToConstant: 120),
        ])

        Task {
            do {
                let videoData = try await downloadVideo(from: urlString, sessionToken: sessionToken)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("temp_video_\(UUID().uuidString).mp4")
                try videoData.write(to: tempURL)

                await MainActor.run {
                    tempVideoURLs.insert(tempURL)
                    removeLoadingView(from: hostVC)

                    let session = Session(weakAnchor: anchorView)
                    activeSession = session
                    session.playLocalVideo(at: tempURL)
                }
            } catch {
                await MainActor.run {
                    removeLoadingView(from: hostVC)
                    let alert = UIAlertController(
                        title: "Error",
                        message: "Failed to load video: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    hostVC.present(alert, animated: true)
                }
            }
        }
    }

    private static func createLoadingView() -> UIView {
        let loadingView = UIView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        loadingView.layer.cornerRadius = 10

        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        activityIndicator.startAnimating()

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Loading video..."
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14)

        loadingView.addSubview(activityIndicator)
        loadingView.addSubview(label)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor, constant: -15),
            label.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            label.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 10),
        ])

        return loadingView
    }

    private static func removeLoadingView(from viewController: UIViewController) {
        if let loadingView = viewController.view.viewWithTag(loadingViewTag) {
            loadingView.removeFromSuperview()
        }
        if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.viewWithTag(loadingViewTag)?.removeFromSuperview()
                    }
                }
            }
        }
    }

    private static func downloadVideo(from urlString: String, sessionToken: String?) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        if let token = sessionToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "x-session-token")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private final class Session: NSObject, AVPlayerViewControllerDelegate {

        private weak var weakAnchor: UIView?

        init(weakAnchor: UIView) {
            self.weakAnchor = weakAnchor
        }

        func playLocalVideo(at url: URL) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }

            let player = AVPlayer(url: url)
            let playerViewController = AVPlayerViewController()
            playerViewController.player = player
            playerViewController.delegate = self
            playerViewController.modalPresentationStyle = .fullScreen
            playerViewController.showsPlaybackControls = true
            playerViewController.allowsPictureInPicturePlayback = false
            playerViewController.entersFullScreenWhenPlaybackBegins = true
            playerViewController.exitsFullScreenWhenPlaybackEnds = true

            let window: UIWindow
            if #available(iOS 13.0, *) {
                if let windowScene = UIApplication.shared.connectedScenes
                    .filter({ $0.activationState == .foregroundActive })
                    .first as? UIWindowScene {
                    window = UIWindow(windowScene: windowScene)
                } else {
                    window = UIWindow(frame: UIScreen.main.bounds)
                }
            } else {
                window = UIWindow(frame: UIScreen.main.bounds)
            }

            window.windowLevel = .statusBar + 1
            let rootVC = UIViewController()
            rootVC.view.backgroundColor = .black
            window.rootViewController = rootVC
            MessageCell.videoWindow = window
            window.makeKeyAndVisible()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                rootVC.present(playerViewController, animated: true) {
                    player.play()
                }
            }
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            AttachmentVideoPlayback.cleanupTempVideos()
        }

        func playerViewControllerWillDismiss(_ playerViewController: AVPlayerViewController) {
            AttachmentVideoPlayback.cleanupTempVideos()
            playerViewController.player?.pause()
            playerViewController.player?.replaceCurrentItem(with: nil)
        }

        func playerViewControllerDidDismiss(_ playerViewController: AVPlayerViewController) {
            AttachmentVideoPlayback.cleanupTempVideos()
            DispatchQueue.main.async {
                MessageCell.videoWindow?.isHidden = true
                MessageCell.videoWindow?.resignKey()
                MessageCell.videoWindow = nil
                NotificationCenter.default.post(name: NSNotification.Name("VideoPlayerDidDismiss"), object: nil)

                if let viewController = self.weakAnchor?.parentViewControllerForPlayback(),
                   viewController is MessageableChannelViewController {
                    viewController.navigationController?.setNavigationBarHidden(true, animated: false)
                    viewController.view.setNeedsLayout()
                    viewController.view.layoutIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewController.navigationController?.setNavigationBarHidden(true, animated: false)
                    }
                }
                AttachmentVideoPlayback.activeSession = nil
            }
        }

        func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            AttachmentVideoPlayback.cleanupTempVideos()
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            AttachmentVideoPlayback.cleanupTempVideos()
            coordinator.animate(alongsideTransition: nil) { _ in
                DispatchQueue.main.async {
                    MessageCell.videoWindow?.isHidden = true
                    MessageCell.videoWindow?.resignKey()
                    MessageCell.videoWindow = nil
                }
            }
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState = ViewState.preview()
    let file = File(
        id: "_KtufRtot6HbJ6sUxlC52c2arOlVNvewQUAkgXA62f",
        tag: "attachments",
        size: 51413,
        filename: "ai-generated-autumn-leaves-in-the-forest-nature-background-photo.jpg",
        metadata: .image(.init(height: 200, width: 200)),
        content_type: "image/jpeg"
    )
    
    
    ZoomableMessageAttachment(isPresented: .constant(true), attachment: file)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
