//
//  RecoveryCodesView.swift
//  Revolt
//
//

import SwiftUI
import Sentry
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

struct EnableAuthenticatorAppView: View {
    @EnvironmentObject var viewState: ViewState // The current application state
    var token: String
    @State var secret: String = ""
    @State private var code = "" // Holds the current input value entered by the user
    @State var codeState : PeptideTextFieldState = .default
    @State var btnState : ComponentState = .disabled
    
    func getSecret() {
        
        Task{
            
            let res = await viewState.http.getTOTPSecret(mfaToken: token)
            
            switch res {
            case .success(let res):
                secret = res.secret
            case .failure(_):
                let _ = ""
            }
            
        }
        
    }
    
    func validateCode(){
        
        Task {
                    
            
            codeState = .default
            btnState = .loading
            let res = await viewState.http.enableTOTP(mfaToken: token, totp_code: code)
            btnState = .default
            switch res {
                case .success(_):
                viewState.userSettingsStore.cache.accountData!.mfaStatus.totp_mfa = true
                viewState.showAlert(message: "Authenticator App Enabled!", icon: .peptideDoneCircle)
                viewState.path.removeLast(2)
                case .failure(_):
                    codeState = .error(message: "Code is incorrect.")
                 
            }
        }
        
    }
    
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
            
    func generateQRCode(from secret: String) -> UIImage? {
        
        let email = viewState.userSettingsStore.cache.accountData?.email ?? ""
        
        let otpAuthURL = "otpauth://totp/PepChat:\(email)?secret=\(secret)&issuer=PepChat&algorithm=SHA1&digits=6&period=30"
                
                guard let data = otpAuthURL.data(using: .utf8) else { return nil }
                filter.setValue(data, forKey: "inputMessage")
                
                if let outputImage = filter.outputImage,
                   let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                    return UIImage(cgImage: cgImage)
                }
                return nil
        }
    
    // Known bug: The MFATicketView doesn't fully slide offscreen.
    var body: some View {
                
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Authenticator App")){_, _ in
            
            VStack(spacing: .zero) {
                
                Image(.peptideLock2)
                    .padding(.top, .padding24)
                
                Group{
                    PeptideText(text: "Enable Authenticator App",
                                font: .peptideTitle2)
                    .padding(.bottom, .padding4)
                    
                    PeptideText(text: "Please scan or use the token below in your authentication app.",
                                font: .peptideBody2,
                                textColor: .textGray07)
                    .padding(.bottom, .size24)
                }
                .padding(.horizontal, .padding16)
                
                if let qrImage = generateQRCode(from: secret) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 136, height: 136)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.all, .size8)
                        } else {
                            Text("Failed to generate QR Code")
                        }
                
                PeptideText(
                    text: secret,
                    font: .peptideBody2,
                    textColor: .textDefaultGray01
                )
                .padding(.bottom, .size24)
                
                PeptideTextField(text: $code,
                                 state: $codeState,
                                 label: "Enter Code",
                                 placeholder: "")
                    .padding(.top, .padding24)
                
                PeptideButton(
                    buttonType: .large(),
                    title: "Confirm Code", buttonState: btnState){
                    validateCode()
                }
                .padding(.top, .padding24)
                
                Spacer(minLength: .zero)
                
            }
            .padding(.horizontal, .padding16)
            .onAppear{
                
                getSecret()
                
            }
            .onChange(of: code){ _, _ in
                
                btnState = code.isEmpty ? .disabled : .default
                
            }

        }
        
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    EnableAuthenticatorAppView(token: "")
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
