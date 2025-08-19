//
//  Discovery.swift
//  Revolt
//
//  Created by Angelo on 18/11/2023.
//

import Foundation
import SwiftUI
import WebKit
import Types

// WebView implementation for macOS using NSViewRepresentable.
#if os(macOS)
/// `WebView` is a custom view that wraps a `WKWebView` for macOS.
/// It loads a given URL and presents it inside a native macOS view.
/// The `viewState` is used to access the app's global state, including theme data.
fileprivate struct WebView: NSViewRepresentable {
    @EnvironmentObject var viewState: ViewState  // Global state, including theme information.
    
    let url: URL  // The URL to be loaded in the WebView.
    
    /// Creates the initial `WKWebView` for macOS.
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        // You could customize the appearance here, like setting background color.
        // view.backgroundColor = .init(viewState.theme.background.color)
        view.navigationDelegate = context.coordinator
        return view
    }
    
    /// Updates the content of the `WKWebView` with the provided URL.
    func updateNSView(_ webView: WKWebView, context: Context) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        request.cachePolicy = .returnCacheDataElseLoad
        webView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                print("🌐 [Discovery macOS] Navigation to URL: \(url.absoluteString)")
                print("🌐 [Discovery macOS] Navigation type: \(navigationAction.navigationType)")
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url {
                print("🌐 [Discovery macOS] Started loading: \(url.absoluteString)")
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                print("✅ [Discovery macOS] Finished loading: \(url.absoluteString)")
            }
        }
    }
}

#else

// WebView implementation for iOS and other platforms using UIViewRepresentable.
/// `WebView` is a custom view that wraps a `WKWebView` for iOS and other platforms.
/// It injects custom CSS based on the current theme from `viewState` and loads the given URL.
fileprivate struct WebView: UIViewRepresentable {
    @EnvironmentObject var viewState: ViewState  // Global state, including theme information.

    let url: URL  // The URL to be loaded in the WebView.
    
    /// Creates the initial `WKWebView` for iOS, injecting CSS for theming based on the app's theme.
    func makeUIView(context: Context) -> WKWebView {
        // Define custom CSS based on the app's theme.
        let css = """
            :root {
                --accent: \(viewState.theme.accent.hex)!important;
                --background: \(viewState.theme.background.hex)!important;
                --primary-background: \(viewState.theme.background2.hex)!important;
                --secondary-background: \(viewState.theme.background3.hex)!important;
                --tertiary-background: \(viewState.theme.background4.hex)!important;
                --foreground: \(viewState.theme.foreground.hex)!important;
                --secondary-foreground: \(viewState.theme.foreground2.hex)!important;
                --tertiary-foreground: \(viewState.theme.foreground3.hex)!important;
            }
        """
        
        // Create JavaScript to inject the CSS into the webpage.
        let js = """
            var style = document.createElement("style");
            style.innerHTML = `\(css)`;
            document.head.appendChild(style);
        """
        
        // Create a user script that runs the JavaScript after the page loads.
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let controller = WKUserContentController()
        controller.addUserScript(script)
        
        // Create a `WKWebView` configuration and add the user content controller to it.
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        
        // Create the `WKWebView` and apply background color based on the theme.
        let view = WKWebView(frame: .zero, configuration: config)
        view.backgroundColor = .init(viewState.theme.background.color)
        view.underPageBackgroundColor = .init(viewState.theme.background.color)
        view.navigationDelegate = context.coordinator

        return view
    }

    /// Updates the `WKWebView` by reloading the provided URL.
    func updateUIView(_ webView: WKWebView, context: Context) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        request.cachePolicy = .returnCacheDataElseLoad
        webView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                print("🌐 [Discovery iOS] Navigation to URL: \(url.absoluteString)")
                print("🌐 [Discovery iOS] Navigation type: \(navigationAction.navigationType)")
                
                // Log additional details about links
                if navigationAction.navigationType == .linkActivated {
                    print("🔗 [Discovery iOS] Link clicked: \(url.absoluteString)")
                }
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url {
                print("🌐 [Discovery iOS] Started loading: \(url.absoluteString)")
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                print("✅ [Discovery iOS] Finished loading: \(url.absoluteString)")
                
                // Log all links found on the page
                webView.evaluateJavaScript("""
                    var links = document.getElementsByTagName('a');
                    var linkUrls = [];
                    for (var i = 0; i < links.length; i++) {
                        if (links[i].href) {
                            linkUrls.push(links[i].href);
                        }
                    }
                    linkUrls;
                """) { result, error in
                    if let links = result as? [String] {
                        print("📋 [Discovery iOS] Found \(links.count) links on page:")
                        for (index, link) in links.enumerated() {
                            print("  [\(index + 1)] \(link)")
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ [Discovery iOS] Failed to load: \(error.localizedDescription)")
        }
    }
}
#endif

/// `Discovery` view is used to present the "Discovery" section of the app.
/// It displays a web-based view that loads the URL for the discovery page with embedded styles.
/// The toolbar includes a custom icon and title, and the background adapts to the app's theme.
struct Discovery: View {
    @EnvironmentObject var viewState: ViewState  // Access to global app state.
    
    // Get the appropriate discovery URL based on the current base URL
    private func getDiscoveryURL() -> URL {
        let baseURL = viewState.baseURL ?? viewState.defaultBaseURL
        
        if baseURL.contains("peptide.chat") {
            // For PepChat, use the embedded discovery page
            return URL(string: "https://rvlt.gg/discover?embedded=true")!
        } else {
            // For other domains (like app.revolt.chat), show a different discovery or empty state
            // You can customize this based on what should be shown for other instances
            return URL(string: "https://revolt.chat/discover")!
        }
    }

    var body: some View {
        WebView(url: getDiscoveryURL())  // Loads the Discovery URL based on current domain.
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Displays a toolbar with an icon and the "Discovery" label.
                    HStack {
                        Image(systemName: "safari.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                        
                        Text("Discovery")
                    }
                }
            }
            .background(viewState.theme.background.color)  // Sets the background color based on the theme.
            .toolbarBackground(viewState.theme.topBar.color, for: .automatic)  // Applies the top bar background color based on the theme.
    }
}
