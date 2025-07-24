//
//  RemoveAuthenticatorAppSheet.swift
//  Revolt
//
//  Created by Mehdi on 2/4/25.
//

import SwiftUI

struct RemoveAuthenticatorAppSheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented: Bool
    @State private var sheetHeight: CGFloat = .zero
    @State var step : MfaSheetStep = .none
    @Binding var ticket: String // todo remove
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
                MfaRecovery(currentText : $currentText)
                
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
                    
                    sendTicket()
                })
                .padding(.top, .padding24)
            }
            
            
            
            
        }
        .onChange(of: currentText){oldValue, newValue in
            if (newValue.count == 6 && step == .otp) || (newValue.count == 10 && step == .recovery){
                confirmBtnState = .default
                sendTicket()
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
            return ("Verify Your Identity", "Verify your identity to turn off the authenticator app.")
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
    
    func sendTicket(){
        
        Task {
                        
            error = nil
            if(step == .recovery){
                confirmBtnState = .loading
                let res = await viewState.http.submitMFATicket(recoveryCode: currentText)
                confirmBtnState = .default
                switch res {
                    case .success(let c):
                        removeTOTP(token: c.token)
                    case .failure(_):
                        error = "That code doesn’t match. Check again and try."
                     
                }
            }else if(step == .otp){
                confirmBtnState = .loading
                let res = await viewState.http.submitMFATicket(totp: currentText)
                confirmBtnState = .default
                switch res {
                    case .success(let c):
                        removeTOTP(token: c.token)
                    case .failure(_):
                        error = "That code doesn’t match. Check again and try."
                     
                }
            }
        }
        
    }
    
    func removeTOTP(token: String){
        
        Task{
            confirmBtnState = .loading
            let response = await viewState.http.disableTOTP(mfaToken: token)
            confirmBtnState = .default
            
            switch response {
            case .success(_):
                viewState.userSettingsStore.cache.accountData!.mfaStatus.totp_mfa = false
                viewState.showAlert(message: "Authenticator App Disabled!", icon: .peptideWarningCircle)
                self.isPresented.toggle()
            case .failure(_):
                error = "Please try again"
            }
            
        }
        
    }
}

#Preview {
    
    VStack {
        Spacer()
        HStack {
            Spacer()
        }
    }
    .sheet(isPresented: .constant(true)){
        let step : MfaSheetStep = .none
        RemoveAuthenticatorAppSheet(isPresented: .constant(true), step: step, ticket: .constant(""), methods: .constant([ "Totp", "Recovery"]))
    }
    
}

