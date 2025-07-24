//
//  MfaSheet.swift
//  Revolt
//
//

import SwiftUI

struct MfaSheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding public var path: NavigationPath
    
    @State private var sheetHeight: CGFloat = .zero
    @State var step : MfaSheetStep = .none
    @Binding var ticket: String
    @Binding var methods: [String]
    @State var currentText: String = ""
    @State var error: String? = nil // Error message for MFA input.
    
    @State private var confirmBtnState : ComponentState = .disabled
    
    
    var body: some View {
        
        let (title, subTitle) = getStepData()
        
        VStack(spacing: .zero){
            
            PeptideText(text: title,
                        font: .peptideHeadline)
            .padding(.bottom, .padding4)
            
            PeptideText(text: subTitle,
                        font: .peptideSubhead,
                        textColor: .textGray06)
            .padding(.bottom, .padding24)
            
            
            switch step {
            case .none:
                MFaNoneStep(step: $step, methods: $methods)
            case .password:
                MfaOtp(currentText: $currentText)
                
            case .otp:
                MfaOtp(currentText: $currentText)
                
            case .recovery:
                MfaRecovery(
                    currentText : $currentText
                ){
                    self.error = nil
                }
                
            }
            
            if let error {
                
                HStack(spacing: .size4){
                    
                    PeptideIcon(iconName: .peptideClose,
                                color: .iconRed07)
                    
                    
                    PeptideText(text: error,
                                font: .peptideBody,
                                textColor: .textRed07,
                                alignment: .leading)
                    .padding(.horizontal, .size4)
                    
                    Spacer(minLength: .zero)
                    
                }
                .padding(.horizontal, .size4)
                .padding(.top, .padding8)
                
            }
            
            if step != .none {
                PeptideButton(title: "Confirm",
                              buttonState: confirmBtnState,
                              onButtonClick: {
                    
                    //TODO
                    //check lenght of current text
                    sendMfa()
                })
                .padding(.top, .padding24)
            }
            
            
            
            
        }
        .onChange(of: currentText){oldValue, newValue in
            if (newValue.count == 6 && step == .otp) || (newValue.count == 10 && step == .recovery){
                confirmBtnState = .default
            } else {
                confirmBtnState = .disabled
            }
        }
        .padding(top: .padding24,
                 bottom: .padding16,
                 leading: .padding16,
                 trailing: .padding16)
        .overlay {
            GeometryReader { geometry in
                Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
            sheetHeight = newHeight
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.all)
        
    }
    
    
    func getStepData() -> (String,String){
        switch step {
        case .none:
            return ("Verify Your Identity", "Select how you’d like to verify your account.")
        case .otp:
            return ("Authenticator App", "Enter the 6-digit code from your authenticator app.")
        case .password:
            return ("Authenticator App", "Enter the 6-digit code from your authenticator app.")
        case .recovery:
            return ("Recovery Code", "Enter one of your backup codes to verify.")
        }
    }
    
    
    /// Provides details for a given MFA method.
    /// - Parameter method: The MFA method to describe.
    /// - Returns: A tuple with icon name, text, description, placeholder, and keyboard type.
    func getMethodDetails(method: String) -> (String, String, String, String, UIKeyboardType) {
        switch method {
        case "Password":
            return ("lock.fill", "Enter a password", "Enter your saved password.", "Password", .default)
        case "Totp":
            return ("checkmark", "Enter a six-digit code", "Enter the six-digit code from your authenticator app", "Code", .numberPad)
        case "Recovery":
            return ("arrow.counterclockwise", "Enter a recovery code", "Enter your backup recovery code", "Recovery code", .default)
        default:
            return ("questionmark", "Unknown", "Unknown", "Unknown", .default)
        }
    }
    
    
    func sendMfa() {
        
        confirmBtnState = .loading
        
        error = nil
        let key: String // The key to use in the MFA response.
        
        // Determine the key based on the selected method.
        switch step {
        case .password:
            key = "password"
        case .otp:
            key = "totp_code"
        case .recovery:
            key = "recovery_code"
        default:
            return // Exit if no valid method is selected.
        }
        
        Task {
            await viewState.signIn(mfa_ticket: ticket, mfa_response: [key: currentText], callback: { response in
                
                confirmBtnState = .default
                
                switch response {
                case .Success: // Handle successful MFA input.
                    path = NavigationPath() // Reset navigation path.
                case .Disabled: // Handle account disabled case.
                    error = "Account disabled"
                case .Invalid: // Handle invalid MFA input.
                    error = "That code doesn’t match. Check again and try."
                case .Onboarding: // Handle onboarding requirement.
                    ()
                case .Mfa(let ticket, let methods): // Handle new MFA response.
                    self.ticket = ticket // Update MFA ticket.
                    self.methods = methods // Update MFA methods.
                    error = "Please try again" // Prompt retry on failure.
                }
            })
        }
    }
}


enum MfaSheetStep {
    case none
    case password
    case otp
    case recovery
}


struct TwoFAMethod: Identifiable {
    let id = UUID()
    let type: String
    let icon: ImageResource
    let title: String
    let action: () -> Void
}

#Preview {
    
    VStack {
        Spacer()
        HStack {
            Spacer()
        }
    }
    .sheet(isPresented: .constant(true)){
        let step : MfaSheetStep = .recovery
        MfaSheet(path: .constant(NavigationPath()), step: step, ticket: .constant(""), methods: .constant([ "Totp", "Recovery"]))
    }
    
}

