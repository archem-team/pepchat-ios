//
//  HCaptchaView.swift
//  Revolt
//
//  Created by Tom on 2023-11-13.
//
//  File provided under the MIT license by https://github.com/hCaptcha/HCaptcha-ios-sdk
//

#if os(iOS)
import SwiftUI
import HCaptcha
import Types

/// A wrapper view for the hCaptcha UIView, conforming to UIViewRepresentable.
struct HCaptchaUIViewWrapperView: UIViewRepresentable {
    var uiview = UIView()  // UIView instance to host the hCaptcha

    /// Creates the UIView instance.
    func makeUIView(context: Context) -> UIView {
        uiview.backgroundColor = .gray  // Set background color for the view
        return uiview
    }

    /// Updates the UIView instance (no updates needed in this case).
    func updateUIView(_ view: UIView, context: Context) {
        // nothing to update
    }
}

/// A SwiftUI view for displaying the hCaptcha challenge.
struct HCaptchaView: View {
    private(set) var hcaptcha: HCaptcha!  // Instance of HCaptcha
    @Binding var hCaptchaResult: String?  // Binding to capture the result of the hCaptcha validation

    let placeholder = HCaptchaUIViewWrapperView()  // Placeholder view for the hCaptcha

    var body: some View {
        VStack {
            placeholder.frame(width: 330, height: 505, alignment: .center)  // Set the frame for the placeholder
        }
        .background(Color.black)  // Set background color
        .onAppear {
            print("captcha appeared")  // Log when the captcha appears
            showCaptcha(placeholder.uiview)  // Show the captcha
        }
    }

    /// Shows the hCaptcha challenge.
    /// - Parameter view: The UIView instance to host the captcha.
    func showCaptcha(_ view: UIView) {
        hcaptcha.validate(on: view) { result in
            view.removeFromSuperview()  // Remove the captcha view once validated
            let resp = try? result.dematerialize()  // Extract the result from the validation
            print(resp)  // Log the result
            hCaptchaResult = resp  // Update the binding with the result
        }
    }

    /// Initializes the HCaptchaView with the provided API key, base URL, and result binding.
    /// - Parameters:
    ///   - apiKey: The API key for hCaptcha.
    ///   - baseURL: The base URL for hCaptcha API.
    ///   - result: A binding to capture the result of the hCaptcha validation.
    init(apiKey: String, baseURL: String, result: Binding<String?>) {
        self._hCaptchaResult = result
        hcaptcha = try? HCaptcha(
            apiKey: apiKey,
            baseURL: URL(string: baseURL)!
        )
        let hostView = self.placeholder.uiview  // Reference to the placeholder view
        hcaptcha.configureWebView { webview in
            webview.frame = hostView.bounds  // Configure the web view frame
        }
    }
}

#Preview {
    var viewState = ViewState.preview()
    return HCaptchaView(apiKey: viewState.apiInfo!.features.captcha.key, baseURL: "https://api.revolt.chat/", result: .constant(nil))
}
#endif
