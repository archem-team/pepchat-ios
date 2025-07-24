//
//  RemoveAuthenticatorAppSheet.swift
//  Revolt
//
//  Created by Mehdi on 2/4/25.
//

import SwiftUI

struct GetPasswordSheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented: Bool
    let title: String
    let subTitle: String
    @State private var sheetHeight: CGFloat = .zero
    @State var password: String = ""
    @State var placeholder: String = ""
    @State var error: String? = nil // Error message for MFA input.
    
    @State private var passwordState : PeptideTextFieldState = .default
    @State private var confirmBtnState : ComponentState = .disabled
    var onConfirm: (String) -> Void
    
    
    var body: some View {
        
        VStack(spacing: .zero){
            
            PeptideText(text: title,
                        font: .peptideHeadline,
                        lineLimit: 1
            )
            .padding(.bottom, .padding4)
            
            PeptideText(text: subTitle,
                        font: .peptideSubhead,
                        textColor: .textGray06,
                        lineLimit: 1
            )
            .padding(.bottom, .padding24)
            
            
            PeptideTextField(
                text: $password,
                state: $passwordState,
                isSecure: true,
                placeholder: placeholder,
                hasSecureBtn: true
            )
            
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
            
            
                PeptideButton(title: "Reset Codes",
                              buttonState: confirmBtnState,
                              onButtonClick: {
                    
                    sendTicket()
                })
                .padding(.top, .padding24)
            
            
            
            
            
        }
        .onChange(of: password){oldValue, newValue in
            error = nil
            if (newValue.isValidPassword){
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
    
    func sendTicket(){
        
        Task {
                        
            error = nil
                confirmBtnState = .loading
            let res = await viewState.http.submitMFATicket(password: password)
                confirmBtnState = .default
                switch res {
                    case .success(let c):
                        onConfirm(c.token)
                    case .failure(_):
                        error = "Password is incorrect."
                     
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
        let step : MfaSheetStep = .recovery
        GetPasswordSheet(isPresented: .constant(true), title: "Reset Codes", subTitle: "Enter your password to reset, recovery codes!", placeholder: "Enter your password"){ _ in
            
        }
    }
    
}

