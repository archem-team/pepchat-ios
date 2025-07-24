//
//  RecoveryCodesView.swift
//  Revolt
//
//

import SwiftUI
import Sentry
import UniformTypeIdentifiers

enum ValidatePasswordReason: Codable, Equatable, Hashable{
    
    case recoveryCode(Bool)
    case authenticatorApp
    
    func getAppbarTitleTitle() -> String{
        switch self {
        case .recoveryCode: return "Recovery Codes"
        case .authenticatorApp: return "Authenticator App"
        }
    }
    
    func getImage() -> ImageResource{
        switch self {
        case .recoveryCode: return .peptideRecovery
        case .authenticatorApp: return .peptideLock2
        }
    }
    
    func getTitle() -> String{
        switch self {
        case .recoveryCode: return "Stay Secure with Recovery Codes"
        case .authenticatorApp: return "Secure Your Account with an Authenticator App"
        }
    }
    
    func getSubtitle() -> String{
        switch self {
        case .recoveryCode: return "Recovery Codes ensure you’re never locked out."
        case .authenticatorApp: return "Adding an authenticator app helps protect your account from unauthorized access."
        }
    }
    
    func getButtonTitle(isActiveRecoveryCodes: Bool) -> String{
        switch self {
        case .recoveryCode: return isActiveRecoveryCodes ? "Show Codes" : "Generate Codes"
        case .authenticatorApp: return "Next"
        }
    }
    
}

struct ValidatePasswordView: View {
    @EnvironmentObject var viewState: ViewState // The current application state
    @State private var fieldValue = "" // Holds the current input value entered by the user
    @State var fieldTextFieldState : PeptideTextFieldState = .default
    @State var btnState : ComponentState = .disabled
    let validatePasswordReason : ValidatePasswordReason
    
    func validatePassword(){
        
        Task {
            
            fieldTextFieldState = .default
            if !fieldValue.isValidPassword {
                fieldTextFieldState = .error(message: "Password is incorrect.")
                return
            }
            
            btnState = .loading
            let res = await viewState.http.submitMFATicket(password: fieldValue)
            btnState = .default
            switch res {
            case .success(let c):
                
                if(validatePasswordReason == .recoveryCode(true)){
                    viewState.path.append(NavigationDestination.show_recovery_codes(c.token, true))
                }else if(validatePasswordReason == .recoveryCode(false)){
                    viewState.path.append(NavigationDestination.show_recovery_codes(c.token, false))
                }else if(validatePasswordReason == ValidatePasswordReason.authenticatorApp){
                    viewState.path.append(NavigationDestination.enable_authenticator_app(c.token))
                }

                case .failure(_):
                fieldTextFieldState = .error(message: "Password is incorrect.")
                 
            }
        }
        
    }
    
    var body: some View {
                
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: validatePasswordReason.getAppbarTitleTitle())){_, _ in
            
            VStack(spacing: .zero) {
                
                Image(validatePasswordReason.getImage())
                    .padding(.top, .padding24)
                
                Group{
                    PeptideText(text: validatePasswordReason.getTitle(),
                                font: .peptideTitle2)
                    .padding(.bottom, .padding4)
                    
                    PeptideText(text: validatePasswordReason.getSubtitle(),
                                font: .peptideBody2,
                                textColor: .textGray07)
                }
                .padding(.horizontal, .padding16)
                
                PeptideTextField(text: $fieldValue,
                                 state: $fieldTextFieldState,
                                 isSecure: true,
                                 label: "Password",
                                 placeholder: "",
                                 hasSecureBtn: true)
                    .padding(.top, .padding24)
                
                let isActiveRecoveryCodes = viewState.userSettingsStore.cache.accountData!.mfaStatus.recovery_active
                
                PeptideButton(
                    buttonType: .large(),
                    title: validatePasswordReason.getButtonTitle(isActiveRecoveryCodes: isActiveRecoveryCodes), buttonState: btnState){
                    validatePassword()
                }
                .padding(.top, .padding40)
                
                Spacer(minLength: .zero)
                
            }
            .padding(.horizontal, .padding16)
            .onChange(of: fieldValue){ _, _ in
                
                btnState = fieldValue.isEmpty ? .disabled : .default
                
            }

        }
        
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ValidatePasswordView(validatePasswordReason: .recoveryCode(true))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
