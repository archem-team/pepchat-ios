//
//  ForgotPassword.swift
//  Revolt
//
//  Created by Tom on 2023-11-16.
//

import SwiftUI
import Types

/// View for initiating the password reset process by requesting a reset token.
struct ForgotPassword: View {
    @EnvironmentObject var viewState: ViewState // Shared application state.
    @Environment(\.colorScheme) var colorScheme // Current color scheme (light or dark).
    
    @Binding var path : NavigationPath
    
    
    @State var errorMessage: String? = nil
    
    @State var email = ""
    @State var showSpinner = false
    @State var completeSpinner = false
    @State var captchaResult: String? = nil
    @State var emailTextFieldStatus : PeptideTextFieldState = .default
    @State var receiveResetLinkBtnState : ComponentState = .disabled
    
    
    @State var goToResetPage = false
    
    let toolbarConfig: ToolbarConfig = .init(isVisible: true)
    
    
    /// Prepares the request for sending a password reset token.
    func preProcessRequest() {
        withAnimation {
            errorMessage = nil // Clear any previous error messages.
        }
        
        // Validate email input.
        if email.isEmpty {
            withAnimation {
                errorMessage = "Enter your email" // Set error message if email is empty.
            }
            return
        }
        
        withAnimation {
            showSpinner = true // Show the loading spinner while processing.
        }
    }
    
    /// Processes the request to send a password reset token.
    func processRequest() {
        Task {
            //completeSpinner = true // Indicate the spinner is complete.
            //try! await Task.sleep(for: .seconds(3)) // Simulate loading time for the spinner.
            
            let inValidEmail = email.isValidEmail == false
            
            if inValidEmail {
                withAnimation {
                    emailTextFieldStatus = .error(message: "Please enter a valid email.")
                }
                return
            }
            
            emailTextFieldStatus = .disabled
            receiveResetLinkBtnState = .loading
            
            do {
                // Attempt to send the password reset token to the provided email.
                _ = try await viewState.http.createAccount_ResendVerification(email: email, captcha: captchaResult).get()
            } catch {
                // Handle error if the email is invalid.
                withAnimation {
                    //errorMessage = "Invalid email"
                    emailTextFieldStatus = .error(message: "Invalid email")
                    receiveResetLinkBtnState = .default
                    //showSpinner = false
                    //completeSpinner = false
                    //captchaResult = nil // Reset captcha result on error.
                }
                return
            }
            
            emailTextFieldStatus = .default
            receiveResetLinkBtnState = .default

            path.append(ForgetPasswordPath.forgetPasswordVerifyEmail)
            
            //try! await Task.sleep(for: .seconds(1)) // Brief pause before navigating.
            //goToResetPage = true // Navigate to the password reset page.
            
            // Reset UI state after navigation.
            //try! await Task.sleep(for: .seconds(1))
            //showSpinner = false
            //completeSpinner = false
            //captchaResult = nil // Clear captcha result.
        }
    }
    
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: toolbarConfig){_,_ in
            
            VStack(spacing: .zero) {
                
                PeptideAuthHeaderView(imageResourceName: .peptideForgotPassword,
                                      title: "Forgot Your Password?",
                                      subtitle: "Enter your email to receive a reset link.")
                
                
                // Display instructions if spinner is not shown and captcha is not needed.
                /*if !(showSpinner) && captchaResult == nil {
                 Text("Let's fix that")
                 .multilineTextAlignment(.center)
                 .font(.callout)
                 
                 Spacer()
                 .frame(maxHeight: 30) // Spacer for layout.
                 }*/
                
                // Display error message if there is one.
                /*if let errorMessage = errorMessage {
                 Text(errorMessage)
                 .font(.caption)
                 .foregroundStyle(Color.red)
                 }*/
                
                // Text field for user email input.
                /*TextField("Email", text: $email)
                 .textContentType(.emailAddress) // Set text content type for email.
                 #if os(iOS)
                 .keyboardType(.emailAddress) // Set keyboard type for iOS.
                 #endif
                 .padding()
                 .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.2)) // Background color based on theme.
                 .clipShape(RoundedRectangle(cornerRadius: 5)) // Rounded corners for the text field.
                 .foregroundStyle((colorScheme == .light) ? Color.black : Color.white) // Text color based on theme.
                 .disabled(showSpinner) // Disable text field if spinner is shown.*/
                
                // Display captcha if required.
                /*if showSpinner && captchaResult == nil && viewState.apiInfo!.features.captcha.enabled {
                 #if os(macOS)
                 Text("No hcaptcha support")
                 #else
                 HCaptchaView(apiKey: viewState.apiInfo!.features.captcha.key, baseURL: viewState.http.baseURL, result: $captchaResult)
                 #endif
                 } else {
                 Spacer() // Spacer if no captcha is displayed.
                 }*/
                
                
                
                
                PeptideTextField(
                    text: $email,
                    state: self.$emailTextFieldStatus,
                    placeholder : "Email",
                    keyboardType: .emailAddress)
                .onChange(of: email){_, newEmail in
                    
                    emailTextFieldStatus = .default
                    
                    if newEmail.isEmpty {
                        receiveResetLinkBtnState = .disabled
                    } else {
                        receiveResetLinkBtnState = .default
                    }
                    
                    
                    //viewModel.send(action: .onChangeEmail(newValue))
                    
                }
                .padding(.top, .padding32)
                
                
                PeptideButton(title: "Receive Reset Link",
                              buttonState: receiveResetLinkBtnState){
                    
                    //preProcessRequest() // Prepare the request.
                    
                    // Check if captcha is enabled or already solved.
                    //if !viewState.apiInfo!.features.captcha.enabled || captchaResult != nil {
                        processRequest() // Process the request if valid.
                    //}
                }
                .padding(.top, .padding32)
                
                
                
                // Button to submit the email for password reset.
                /*Button(action: {
                 preProcessRequest() // Prepare the request.
                 
                 // Check if captcha is enabled or already solved.
                 if !viewState.apiInfo!.features.captcha.enabled || captchaResult != nil {
                 processRequest() // Process the request if valid.
                 }
                 }) {
                 // Button label based on spinner state.
                 if showSpinner {
                 LoadingSpinnerView(frameSize: CGSize(width: 25, height: 25), isActionComplete: $completeSpinner)
                 } else {
                 Text("Reset Password")
                 }
                 }
                 .padding(.vertical, 10)
                 .frame(width: showSpinner ? 100 : 250.0) // Width based on spinner state.
                 .foregroundStyle(.black)
                 .background(colorScheme == .light ? Color(white: 0.851) : Color.white)
                 .clipShape(.rect(cornerRadius: 50)) // Rounded corners for the button.*/
            }
            .padding(.horizontal, .padding16)
            
            Spacer() // Spacer for layout.
            
        }
        .navigationDestination(for: ForgetPasswordPath.self){ des in
            switch des {
            case .forgetPasswordVerifyEmail:
                VerifyEmail(path: $path, email: email, verifyEmailType: .none)
            }
        }
        /*.navigationDestination(isPresented: $goToResetPage) {
            // Navigate to the reset password view.
            ForgotPassword_Reset(email: email)
        }*/
        /*.onChange(of: captchaResult) { // Monitor changes in captcha result.
            if captchaResult != nil {
                processRequest() // Process request if captcha is solved.
            }
        }*/
        
    }
}

enum ForgetPasswordPath : Hashable {
    case forgetPasswordVerifyEmail
}



#Preview {
    ForgotPassword(path: .constant(NavigationPath()))
}
