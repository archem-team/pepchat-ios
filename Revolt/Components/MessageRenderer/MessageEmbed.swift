//
//  MessageEmbed.swift
//  Revolt
//
//  Created by Angelo on 08/07/2024.
//

import SwiftUI
import Types
import AVKit
import WebKit

/// A view that renders different types of message embeds, such as images, videos, text, websites, and special embeds.
struct MessageEmbed: View {
    @EnvironmentObject var viewState: ViewState  // Access to global state and theming
    @Binding var embed: Embed  // Binding to the embed data
    
    /// Parses a color string to return a corresponding shape style.
    /// - Parameter color: The color string to parse.
    /// - Returns: An AnyShapeStyle based on the input color or a default color.
    func parseEmbedColor(color: String?) -> AnyShapeStyle {
        if let color {
            return parseCSSColor(currentTheme: viewState.theme, input: color)
        } else {
            return AnyShapeStyle(viewState.theme.foreground3)
        }
    }
    
    /// Checks if the embed is a GIF based on its properties.
    var isGif: Bool {
        switch embed {
        case .website(let website):
            switch website.special {
            case .gif:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    var body: some View {
        switch embed {
        case .image(let image):
            // Render an image embed
            LazyImage(source: .url(URL(string: image.url)!), clipTo: Rectangle())
        case .video(let video):
            // Render a video embed using AVPlayer
            if let url = URL(string: video.url) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: CGFloat(integerLiteral: video.width), height: CGFloat(integerLiteral: video.height))
            }
        case .text(let embed):
            // Render a text embed with a custom shape and styling
            HStack(spacing: 0) {
                UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6)
                    .fill(parseEmbedColor(color: embed.colour))
                    .frame(width: 4)  // Color bar on the left
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        // Icon
                        if let icon_url = embed.icon_url, let url = URL(string: icon_url) {
                            LazyImage(source: .url(url), height: 14, width: 14, clipTo: Rectangle())
                        }
                        
                        // Title
                        if let title = embed.title {
                            Contents(text: .constant(title), fontSize: 13, foregroundColor: viewState.theme.foreground2.uiColor)
                        }
                    }
                    
                    // Description
                    if let description = embed.description {
                        Contents(text: .constant(description), fontSize: 17, foregroundColor: viewState.theme.foreground.uiColor)
                    }
                    
                    // Media
                    if let media = embed.media {
                        LazyImage(source: .file(media), clipTo: Rectangle())
                    }
                }
                .padding(12)
                .background(viewState.theme.background2)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6))
            }
        case .website(let embed):
            // Render a website embed
            HStack(spacing: .zero) {
                UnevenRoundedRectangle(topLeadingRadius: .radius8, bottomLeadingRadius: .radius8)
                //.fill(parseEmbedColor(color: embed.colour))
                    .fill(Color.bgGray10)
                    .frame(width: .size3)  // Color bar on the left
                
                VStack(alignment: .leading, spacing: .zero) {
                    HStack(alignment: .top, spacing: .padding8) {
                        
                        VStack(alignment: .leading, spacing: .zero){
                            if let title = embed.title {
                                Contents(text: .constant(title),
                                         fontSize: PeptideFont.peptideBody3.fontSize,
                                         font: PeptideFont.peptideBody3.getFontData().font,
                                         foregroundColor: .textDefaultGray01)
                                .padding(.top, .padding4)
                            }
                            
                            if let description = embed.description {
                                Contents(text: .constant(description),
                                         fontSize: PeptideFont.peptideBody4.fontSize,
                                         font: PeptideFont.peptideBody4.getFontData().font,
                                         foregroundColor: .textGray06)
                            }
                        }

                        Spacer(minLength: .zero)
                        
                        VStack(alignment: .trailing, spacing: .zero){
                            
                            // Icon and site name
                            if let icon_url = embed.icon_url, embed.site_name != nil, let url = URL(string: icon_url) {
                                LazyImage(source: .url(url), height: .size64, width: .size64, clipTo: Rectangle())
                                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: .radiusXSmall, bottomLeadingRadius: .radiusXSmall, bottomTrailingRadius: .radiusXSmall, topTrailingRadius: .radiusXSmall))
                                    .padding(.top, .padding8)
                            }
                            
                            /*if let site_name = embed.site_name {
                                Contents(text: .constant("Google Tractor"), fontSize: 13, foregroundColor: .textGray04)
                                        .padding(.top, .padding4)
                            }*/
                        }
                       
                    }
                    
                  
                    
                    // Special embeds or media
                    if let special = embed.special, special != .none {
                        SpecialEmbed(embed: embed)
                    } else if let video = embed.video, let url = URL(string: video.url) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .aspectRatio(CGSize(width: video.width, height: video.height), contentMode: .fit)
                            .frame(maxWidth: CGFloat(integerLiteral: video.width), maxHeight: CGFloat(integerLiteral: video.height))
                    } else if let image = embed.image, image.size == JanuaryImage.Size.large, let url = URL(string: image.url) {
                            LazyImage(source: .url(url), clipTo: Rectangle())
                            .clipShape(RoundedRectangle(cornerRadius: .radiusXSmall))
                            .padding(.top, .padding8)
                        }
                    
                    // Preview image for smaller embeds
                    if let image = embed.image, embed.special == nil || embed.special == WebsiteSpecial.none, embed.video == nil {
                        if image.size == JanuaryImage.Size.preview, let url = URL(string: image.url) {
                            LazyImage(source: .url(url), clipTo: Rectangle())
                                .clipShape(RoundedRectangle(cornerRadius: .radiusXSmall))
                                .padding(.top, .padding8)
                        }
                    }
                }
                .padding(top: .zero, bottom: .padding8, leading: .padding8, trailing: .padding8)
               
            }
            .background(Color.bgGray12)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: .radius8, bottomLeadingRadius: .radius8, bottomTrailingRadius: .radius8, topTrailingRadius: .radius8))
            
        case .none:
            // Render an empty view if no embed is provided
            EmptyView()
        }
    }
}

#if os(iOS)
// A UIViewRepresentable struct to display a WKWebView for iOS.
fileprivate struct WebView: UIViewRepresentable {
    let url: URL  // The URL to load
    let webview: WKWebView  // The WKWebView instance
    
    init(url: URL) {
        self.url = url
        self.webview = WKWebView(frame: .zero)
        self.webview.isOpaque = false
        self.webview.backgroundColor = .clear
    }
    
    func makeUIView(context: Context) -> WKWebView {
        return webview
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        var request = URLRequest(url: url)  // Load the URL request
        request.timeoutInterval = 30.0
        request.cachePolicy = .returnCacheDataElseLoad
        webView.load(request)
    }
}
#elseif os(macOS)
// A NSViewRepresentable struct to display a WKWebView for macOS.
fileprivate struct WebView: NSViewRepresentable {
    let url: URL  // The URL to load
    let webview: WKWebView  // The WKWebView instance
    
    init(url: URL) {
        self.url = url
        self.webview = WKWebView(frame: .zero)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        return webview
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        var request = URLRequest(url: url)  // Load the URL request
        request.timeoutInterval = 30.0
        request.cachePolicy = .returnCacheDataElseLoad
        webView.load(request)
    }
}
#endif

/// A view for displaying special embeds from websites such as YouTube, Spotify, etc.
struct SpecialEmbed: View {
    var embed: WebsiteEmbed  // The website embed data
    
    /// Determines the aspect ratio size for the special embed.
    var size: CGFloat {
        switch embed.special! {
        case .youtube:
            return CGFloat(embed.video?.width ?? 16) / CGFloat(embed.video?.height ?? 9)
        case .lightspeed:
            return 16 / 9
        case .twitch:
            return 16 / 9
        case .spotify(let special):
            switch special.content_type {
            case "artist", "playlist":
                return 400 / 200
            default:
                return 400 / 105
            }
        case .soundcloud:
            return 480 / 460
        case .bandcamp:
            return CGFloat(embed.video?.width ?? 16) / CGFloat(embed.video?.height ?? 9)
        default:
            return 0
        }
    }
    
    /// Generates the URL for the special embed based on its type and properties.
    var url: String? {
        switch embed.special! {
        case .youtube(let special):
            let timestamp = special.timestamp != nil ? "&start=\(special.timestamp!)" : ""
            return "https://www.youtube-nocookie.com/embed/\(special.id)?modestbranding=1\(timestamp)"
        case .twitch(let special):
            return "https://player.twitch.tv/?\(special.content_type.rawValue.lowercased())=\(special.id)&autoplay=false"
        case .lightspeed(let special):
            return "https://new.lightspeed.tv/embed/\(special.id)/stream"
        case .spotify(let special):
            return "https://open.spotify.com/embed/\(special.content_type)/\(special.id)"
        case .soundcloud:
            let url = embed.url!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            return "https://w.soundcloud.com/player/?url=\(url)&color=%23FF7F50&auto_play=false&hide_related=false&show_comments=true&show_user=true&show_reposts=false&show_teaser=true&visual=true"
        case .bandcamp(let special):
            return "https://bandcamp.com/EmbeddedPlayer/\(special.content_type.rawValue.lowercased())=\(special.id)/size=large/bgcol=181a1b/linkcol=056cc4/tracklist=false/transparent=true/"
        case .streamable(let special):
            return "https://streamable.com/e/\(special.id)?loop=0"
        default:
            return nil
        }
    }
    
    var body: some View {
        // Render a WebView for the special embed if a valid URL is generated
        if let string = url, let url = URL(string: string) {
            WebView(url: url)
                .aspectRatio(size, contentMode: .fit)
        }
    }
}
