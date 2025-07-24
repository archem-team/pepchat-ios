//
//  ResendEmail.swift
//  Revolt
//
//  Created by Tom on 2023-11-15.
//

import SwiftUI
import Types

/// A view that allows users to request a new verification email if they did not receive the original one.
struct ResendEmail: View {
    @EnvironmentObject var viewState: ViewState // Shared application state.
    @Environment(\.colorScheme) var colorScheme // Determines the current color scheme (light or dark).
    
    @State var errorMessage: String? = nil // Holds error messages, if any.
    @State var email = "" // User input for the email address.
    
    @State var showSpinner = false // Indicates if the loading spinner should be displayed.
    @State var completeSpinner = false // Indicates if the loading action is complete.
    @State var captchaResult: String? = nil // Holds the result of the captcha verification.
    
    @Binding var path: NavigationPath

    
    @State var goToVerificationPage = false // Controls navigation to the verification page.
    
    @State private var emailTextFieldState: PeptideTextFieldState = .default
    @State private var receiveBtnState : ComponentState = .disabled
    
    /// Prepares the request by validating input and showing the loading spinner if necessary.
    func preProcessRequest() {
        withAnimation {
            errorMessage = nil // Clear any previous error messages.
        }
        
        // Validate email input.
        if email.isEmpty {
            withAnimation {
                errorMessage = "Enter your email" // Set an error message if email is empty.
            }
            return
        }
        
        withAnimation {
            showSpinner = true // Show the loading spinner while processing.
        }
    }
    
    /// Processes the request to resend the verification email.
    func processRequest() {
        Task {
            //completeSpinner = true // Indicate the spinner is complete.
            //try! await Task.sleep(for: .seconds(3)) // Simulate loading time for the spinner.
            
            
            let inValidEmail = email.isValidEmail == false
            
            if inValidEmail {
                withAnimation {
                    emailTextFieldState = .error(message: "Please enter a valid email.")
                }
                return
            }
            
            emailTextFieldState = .disabled
            
            receiveBtnState = .loading
            

            do {
                // Attempt to resend the verification email.
                _ = try await viewState.http.createAccount_ResendVerification(email: email, captcha: captchaResult).get()
            } catch {
                // Handle error if the email is invalid.
                withAnimation {
                    //errorMessage = "Invalid email"
                    //showSpinner = false
                    //completeSpinner = false
                    //captchaResult = nil // Reset captcha result on error.
                    emailTextFieldState = .error(message: "Please enter a valid email.")
                    receiveBtnState = .default

                }
                return
            }
            
            emailTextFieldState = .default
            receiveBtnState = .default
            path.append(ResendEmailPath.resendVerifyEmail)
            
            
            //try! await Task.sleep(for: .seconds(1)) // Brief pause before navigating to the next screen.
            //goToVerificationPage = true // Navigate to the verification page.
            
            // Reset UI state after navigation.
            //try! await Task.sleep(for: .seconds(1))
            //showSpinner = false
            //completeSpinner = false
            //captchaResult = nil // Clear captcha result.
        }
    }
    
    
    let toolbarConfig: ToolbarConfig = .init(isVisible: true)
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: toolbarConfig){_,_ in
            VStack(spacing: .zero) {
                
                PeptideAuthHeaderView(imageResourceName: .peptideEmail,
                                      title: "Didn’t receive an email?",
                                      subtitle: "Enter your email to receive a verification mail.")
                
                
                
               
                // Display instructions if spinner is not shown and captcha is not needed.
                /*if !showSpinner && captchaResult == nil {
                    Text("Enter your email, and if we've got you on record we'll send you another one")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                }*/
                    
                // Display error message if there is one.
                /*if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }*/
                
                
                PeptideTextField(text: $email,
                                 state: $emailTextFieldState,
                                 placeholder: "Email",
                                 keyboardType: .emailAddress)
                .onChange(of: email){ oldValue, newValue in
                    if newValue.isEmpty {
                        receiveBtnState = .disabled
                    } else {
                        receiveBtnState = .default
                    }
                }
                .padding(.top, .padding32)
                
                
                // Text field for user email input.
                /*TextField(
                    "Email",
                    text: $email
                )
                .textContentType(.emailAddress) // Set text content type for email.
                #if os(iOS)
                .keyboardType(.emailAddress) // Set keyboard type for iOS.
                #endif
                .disabled(showSpinner) // Disable text field if spinner is shown.*/
                
                // Display captcha if required.
                /*if showSpinner && captchaResult == nil && viewState.apiInfo!.features.captcha.enabled {
                    #if os(macOS)
                    Text("No hcaptcha support") // Message for macOS users.
                    #else
                    // HCaptcha view for captcha verification.
                    HCaptchaView(apiKey: viewState.apiInfo!.features.captcha.key, baseURL: viewState.http.baseURL, result: $captchaResult)
                    #endif
                } else {
                    Spacer() // Spacer if captcha is not shown.
                }*/
                
                PeptideButton(title: "Receive Verification Mail",
                              buttonState: receiveBtnState,
                              onButtonClick: {
                    preProcessRequest() // Pre-process before sending request.
                    
                    // Process request if captcha is not required or already solved.
                    if !viewState.apiInfo!.features.captcha.enabled || captchaResult != nil {
                        processRequest() // Send the request.
                    }
                })
                .padding(.top, .padding32)
                
                // Button to resend verification email.
                /*Button(action: {
                    preProcessRequest() // Pre-process before sending request.
                    
                    // Process request if captcha is not required or already solved.
                    if !viewState.apiInfo!.features.captcha.enabled || captchaResult != nil {
                        processRequest() // Send the request.
                    }
                }) {
                    // Button label based on spinner state.
                    if showSpinner {
                        LoadingSpinnerView(frameSize: CGSize(width: 25, height: 25), isActionComplete: $completeSpinner)
                    } else {
                        Text("Get another code")
                    }
                }*/
                
                Spacer() // Spacer for layout.
            }
            .padding(.horizontal, .padding16)
            .onChange(of: captchaResult) {oldValue, newValue in
                if newValue != nil {
                    processRequest() // Automatically process the request when captcha is solved.
                }
            }
            .navigationDestination(for: ResendEmailPath.self){des in
                switch des {
                    case .resendVerifyEmail:
                    VerifyEmail(path: $path, email: email, verifyEmailType: .resendVerification)
                }
            }
        }
       
        
        
        /*.navigationDestination(isPresented: $goToVerificationPage) {
            // Navigate to verification page.
            CreateAccount(path: $path, mfaTicket: .constant(""), mfaMethods: .constant([]), onboardingStage: .Verify)

        }*/
    }
}

enum ResendEmailPath : Hashable {
    case resendVerifyEmail
}

// Preview for SwiftUI canvas.
#Preview {
    ResendEmail(path: .constant(NavigationPath())) // Preview for ResendEmail view.
        .environmentObject(ViewState.preview()) // Provide preview environment object.
        .preferredColorScheme(.dark)
}
