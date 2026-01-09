//
//  MessageAttachment.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI
import AVKit
import Types
import UIKit

// Formatter to convert byte counts into human-readable strings
var fmt = ByteCountFormatter()

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
                
                
                
                
                
            case .video(_):  // Handle video attachments
                // MEMORY OPTIMIZATION: Use VideoPlayerView which shows thumbnail instead of creating AVPlayer immediately
                VideoPlayerViewWrapper(
                    videoURL: viewState.formatUrl(with: attachment),
                    filename: attachment.filename,
                    fileSize: attachment.size,
                    headers: {
                        var headers: [String: String] = [:]
                        if let token = viewState.sessionToken {
                            headers["x-session-token"] = token
                        }
                        return headers
                    }(),
                    onPlayTapped: {
                        self.isPresented.toggle()
                    }
                )
                .frame(maxHeight: 298)
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
                    
                    
                   
                    
                    
                case .video(_):  // Handle video attachments
                    VideoPlayer(player: AVPlayer(url: URL(string: viewState.formatUrl(with: attachment))!))  // Play the video using AVPlayer
                        .aspectRatio(contentMode: .fit)  // Maintain aspect ratio
                        .frame(maxHeight: 400)  // Set a maximum height for the video player
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


// MARK: - VideoPlayerViewWrapper
/// SwiftUI wrapper for VideoPlayerView to avoid immediate AVPlayer creation
struct VideoPlayerViewWrapper: UIViewRepresentable {
    let videoURL: String
    let filename: String?
    let fileSize: Int64?
    let headers: [String: String]
    let onPlayTapped: () -> Void
    
    func makeUIView(context: Context) -> VideoPlayerView {
        let videoPlayerView = VideoPlayerView()
        videoPlayerView.configure(
            with: videoURL,
            filename: filename,
            fileSize: fileSize,
            headers: headers
        )
        videoPlayerView.onPlayTapped = { _ in
            onPlayTapped()
        }
        return videoPlayerView
    }
    
    func updateUIView(_ uiView: VideoPlayerView, context: Context) {
        // Update if needed (e.g., if URL changes)
        // For now, configuration happens in makeUIView
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
