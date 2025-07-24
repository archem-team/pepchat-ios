//
//  CreateAccount.swift
//  Revolt
//
//  Created by Tom on 2023-11-13.
//

import SwiftUI
import Types
import Foundation

/// A view for creating an account, handling user inputs for email, password, verification code, and username.
struct CreateAccount: View {
    
    
    @Environment(\.colorScheme) var colorScheme // To adapt the UI based on the color scheme (light or dark).
    @EnvironmentObject var viewState: ViewState // Shared state for managing the app's state.
    @Binding var path: NavigationPath // The navigation path for view transitions.
    
    // State variables for user inputs and UI state.
    @State var email = ""
    @State var password = ""
    
    @State var verifyCode = ""
    @State var username = ""
    
    @State var showPassword = false
    @State var errorMessage: String? = nil
    @State var isWaitingWithSpinner = false // Indicates if a spinner should be shown.
    @State var isSpinnerComplete = false // Indicates if the spinner action is complete.
    @State var hCaptchaResult: String? = nil // Stores the result of the hCaptcha.
    
    @State var emailTextFieldStatus : PeptideTextFieldState = .default
    @State var passwordTextFieldStatus : PeptideTextFieldState = .default
    @State var continueBtnStatus : ComponentState = .disabled
    
    
    
    @Binding public var mfaTicket: String // Binding for MFA ticket.
    @Binding public var mfaMethods: [String] // Binding for available MFA methods.
    
    // State variables for user inputs and UI state.
    @State var onboardingStage = OnboardingStage.Initial // Tracks the current stage of onboarding.
    
    // Focus states for managing focus on input fields.
    @FocusState private var focus1: Bool
    @FocusState private var focus2: Bool
    @FocusState private var autoFocusPull: Bool // Manages automatic focus for input fields.
    
    var customtoolbarView: AnyView {
        AnyView(
            
            NavigationLink("Log In", value: WelcomePath.login)
                .font(.peptideButtonFont)
                .foregroundStyle(.textDefaultGray01)
        )
    }
    
    var body: some View {
        
        PeptideTemplateView(
            toolbarConfig: .init(
                isVisible: true,
                onClickBackButton: {
                    path = NavigationPath()
                },
                customToolbarView: customtoolbarView
            )){_,_   in
                
                
                
                ZStack {
                    VStack(spacing: .zero) {
                        
                        PeptideAuthHeaderView(imageResourceName: .peptideRegister,
                                              title: "make-it-official",
                                              subtitle: "New Here? Let’s Get You Set Up!")
                        
                        
                        // Check if waiting for spinner; if not, display the appropriate fields based on onboarding stage.
                        if (!(isWaitingWithSpinner) && onboardingStage == .Initial ){
                            Group {
                                // TextField for email input.
                                /*TextField("Email", text: $email)
                                 .textContentType(.emailAddress)
                                 #if os(iOS)
                                 .keyboardType(.emailAddress)
                                 #endif
                                 .disabled(isWaitingWithSpinner)
                                 .focused($autoFocusPull)*/
                                
                                
                                PeptideTextField(
                                    text: $email,
                                    state: self.$emailTextFieldStatus,
                                    placeholder : "Email",
                                    keyboardType: .emailAddress)
                                .onChange(of: email){_, _ in
                                    
                                    withAnimation{
                                        onChangeEmail()
                                    }
                                    
                                }
                                .padding(.top, .padding32)
                                
                                
                                // Secure field for password input with visibility toggle.
                                /*ZStack(alignment: .trailing) {
                                 TextField("Password", text: $password)
                                 .textContentType(.password)
                                 .modifier(PasswordModifier())
                                 .opacity(showPassword ? 1 : 0)
                                 .focused($focus1)
                                 .disabled(isWaitingWithSpinner)
                                 
                                 SecureField("Password", text: $password)
                                 .textContentType(.password)
                                 .modifier(PasswordModifier())
                                 .opacity(showPassword ? 0 : 1)
                                 .focused($focus2)
                                 .disabled(isWaitingWithSpinner)
                                 }*/
                                
                                
                                
                                PeptideTextField(text: $password,
                                                 state: $passwordTextFieldStatus,
                                                 isSecure: true,
                                                 placeholder: "Password",
                                                 hasSecureBtn: true)
                                .onChange(of: password){_, _ in
                                    
                                    withAnimation{
                                        onChangePassword()
                                    }
                                    
                                }
                                .padding(.top, .padding8)
                                
                            }
                            
                        }
                        // Verification stage for entering the verification code.
                        else if onboardingStage == .Verify {
                            Group {
                                if let error = errorMessage {
                                    Text(error)
                                        .foregroundStyle(Color.red)
                                } else {
                                    Text("Enter the verification code sent to your email")
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle((colorScheme == .light) ? Color.black : Color.white)
                                }
                                TextField("Verification Code", text: $verifyCode)
                                    .textContentType(.oneTimeCode)
                                    .padding()
                                    .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.2))
                                    .clipShape(.rect(cornerRadius: 5))
                                    .foregroundStyle((colorScheme == .light) ? Color.black : Color.white)
                                    .disabled(isWaitingWithSpinner)
                                    .focused($autoFocusPull)
                            }
                            .onAppear {
                                autoFocusPull = true // Auto focus on the verification code input field on appear.
                            }
                        }
                        // Username stage for entering the username.
                        else if onboardingStage == .Username {
                            /*Group {
                                if let error = errorMessage {
                                    Text(error)
                                        .foregroundStyle(Color.red)
                                } else {
                                    Text("Enter your Username")
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle((colorScheme == .light) ? Color.black : Color.white)
                                }
                                TextField("Username", text: $username)
                                    .textContentType(.username)
                                    .padding()
                                    .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.2))
                                    .clipShape(.rect(cornerRadius: 5))
                                    .foregroundStyle((colorScheme == .light) ? Color.black : Color.white)
                                    .disabled(isWaitingWithSpinner)
                                    .focused($autoFocusPull)
                            }
                            .onAppear {
                                autoFocusPull = true // Auto focus on the username input field on appear.
                            }*/
                        }
                        
                        //Spacer()
                        
                        // Button to proceed based on the current onboarding stage.
                        /*Group {
                         Button(action: {
                         autoFocusPull = false // Reset focus state for re-enabling.
                         
                         // Handle actions based on the current onboarding stage.
                         if onboardingStage == .Initial {
                         // Validate email and password fields.
                         if email.isEmpty || password.isEmpty {
                         withAnimation {
                         errorMessage = "Please enter your email and password"
                         }
                         return
                         }
                         errorMessage = nil
                         // Check if captcha is required.
                         if viewState.apiInfo!.features.captcha.enabled && hCaptchaResult == nil {
                         withAnimation {
                         isWaitingWithSpinner.toggle() // Show spinner while waiting for captcha.
                         }
                         } else {
                         // Create account asynchronously.
                         Task {
                         do {
                         _ = try await viewState.http.createAccount(email: email, password: password, invite: nil, captcha: hCaptchaResult).get()
                         } catch {
                         withAnimation {
                         isSpinnerComplete = false
                         isWaitingWithSpinner = false
                         errorMessage = "Sorry, your email or password was invalid"
                         }
                         return
                         }
                         withAnimation {
                         isWaitingWithSpinner = false
                         isSpinnerComplete = false
                         onboardingStage = .Verify // Move to verification stage.
                         }
                         }
                         }
                         }
                         // Verification stage action.
                         else if onboardingStage == .Verify {
                         if verifyCode.isEmpty {
                         withAnimation {
                         errorMessage = "Please enter the verification code"
                         }
                         return
                         }
                         errorMessage = nil
                         withAnimation {
                         isWaitingWithSpinner = true // Show spinner while waiting for verification.
                         }
                         Task {
                         let resp = await viewState.signInWithVerify(code: verifyCode, email: email, password: password)
                         if !resp {
                         withAnimation {
                         isWaitingWithSpinner = false
                         errorMessage = "Invalid verification code"
                         }
                         return
                         }
                         withAnimation {
                         isSpinnerComplete = true
                         }
                         try! await Task.sleep(for: .seconds(2)) // Delay before moving to the next stage.
                         withAnimation {
                         isWaitingWithSpinner = false
                         isSpinnerComplete = false
                         onboardingStage = .Username // Move to username stage.
                         }
                         }
                         }
                         // Username stage action.
                         else if onboardingStage == .Username {
                         if username.isEmpty {
                         withAnimation {
                         errorMessage = "Please enter a username"
                         }
                         return
                         }
                         errorMessage = nil
                         withAnimation {
                         isWaitingWithSpinner = true // Show spinner while waiting for username submission.
                         }
                         Task {
                         do {
                         _ = try await viewState.http.completeOnboarding(username: username).get()
                         } catch {
                         withAnimation {
                         isWaitingWithSpinner = false
                         errorMessage = "Invalid Username, try something else"
                         }
                         return
                         }
                         withAnimation {
                         isSpinnerComplete = true
                         }
                         try! await Task.sleep(for: .seconds(2)) // Delay before finishing onboarding.
                         viewState.isOnboarding = false // Mark onboarding as complete.
                         }
                         }
                         }) {
                         // Show loading spinner if waiting for response, otherwise show action text.
                         if isWaitingWithSpinner || isSpinnerComplete {
                         LoadingSpinnerView(frameSize: CGSize(width: 25, height: 25), isActionComplete: $isSpinnerComplete)
                         } else {
                         Text(onboardingStage == .Initial ? "Create Account" : onboardingStage == .Verify ? "Verify" : "Select Username")
                         .font(.title2)
                         }
                         }
                         .padding(.vertical, 10)
                         .frame(width: isWaitingWithSpinner || isSpinnerComplete ? 100 : 250.0)
                         .foregroundStyle(.black)
                         .background(colorScheme == .light ? Color(white: 0.851) : Color.white)
                         .clipShape(.rect(cornerRadius: 50))
                         }*/
                        
                        PeptideButton(title: "continue",
                                      buttonState: continueBtnStatus){
                            
                            // Handle actions based on the current onboarding stage.
                            if onboardingStage == .Initial {
                                // Validate email and password fields.
                                
                                
                                /*if email.isEmpty || password.isEmpty {
                                 withAnimation {
                                 errorMessage = "Please enter your email and password"
                                 }
                                 return
                                 }
                                 errorMessage = nil
                                 */
                                
                                hideKeyboard()
                                
                                
                                let inValidEmail = email.isValidEmail == false
                                let inValidPassword = password.isValidPassword == false
                                
                                if inValidEmail {
                                    withAnimation {
                                        emailTextFieldStatus = .error(message: "Please enter a valid email.",
                                                                      icon: .peptideClose)
                                    }
                                }
                                
                                
                                if inValidPassword {
                                    withAnimation {
                                        passwordTextFieldStatus = .error(message: "Please use 6+ characters, a letter, number & symbol.",
                                                                        icon: .peptideClose)
                                    }
                                }
                                
                                if (inValidEmail || inValidPassword) {
                                    return
                                }
                                
                                
                                // Check if captcha is required.
                                if viewState.apiInfo!.features.captcha.enabled && hCaptchaResult == nil {
                                    withAnimation {
                                        isWaitingWithSpinner.toggle() // Show spinner while waiting for captcha.
                                    }
                                } else {
                                    // Create account asynchronously.
                                    
                                    emailTextFieldStatus = .disabled
                                    passwordTextFieldStatus = .disabled
                                    continueBtnStatus = .loading
                                    
                                    Task {
                                        do {
                                            _ = try await viewState.http.createAccount(email: email, password: password, invite: nil, captcha: hCaptchaResult).get()
                                        } catch {
                                            withAnimation {
                                                isSpinnerComplete = false
                                                isWaitingWithSpinner = false
                                                //errorMessage = "Sorry, your email or password was invalid"
                                                emailTextFieldStatus = .error(message: "Email might be incorrect.")
                                                passwordTextFieldStatus = .error(message: "Password might be incorrect.")
                                                
                                                continueBtnStatus = .default
                                            }
                                            return
                                        }
                                        withAnimation {
                                            isWaitingWithSpinner = false
                                            isSpinnerComplete = false
                                            
                                            emailTextFieldStatus = .default
                                            passwordTextFieldStatus = .default
                                            continueBtnStatus = .default
                                            //onboardingStage = .Verify
                                            path.append(CreateAccountPath.verifyEmail)
                                        }
                                    }
                                }
                            }
                            // Verification stage action.
                            /*else if onboardingStage == .Verify {
                             if verifyCode.isEmpty {
                             withAnimation {
                             errorMessage = "Please enter the verification code"
                             }
                             return
                             }
                             errorMessage = nil
                             withAnimation {
                             isWaitingWithSpinner = true // Show spinner while waiting for verification.
                             }
                             Task {
                             let resp = await viewState.signInWithVerify(code: verifyCode, email: email, password: password)
                             if !resp {
                             withAnimation {
                             isWaitingWithSpinner = false
                             errorMessage = "Invalid verification code"
                             }
                             return
                             }
                             withAnimation {
                             isSpinnerComplete = true
                             }
                             try! await Task.sleep(for: .seconds(2)) // Delay before moving to the next stage.
                             withAnimation {
                             isWaitingWithSpinner = false
                             isSpinnerComplete = false
                             onboardingStage = .Username // Move to username stage.
                             }
                             }
                             }*/
                            // Username stage action.
                            /*else if onboardingStage == .Username {
                                if username.isEmpty {
                                    withAnimation {
                                        errorMessage = "Please enter a username"
                                    }
                                    return
                                }
                                errorMessage = nil
                                withAnimation {
                                    isWaitingWithSpinner = true // Show spinner while waiting for username submission.
                                }
                                Task {
                                    do {
                                        _ = try await viewState.http.completeOnboarding(username: username).get()
                                    } catch {
                                        withAnimation {
                                            isWaitingWithSpinner = false
                                            errorMessage = "Invalid Username, try something else"
                                        }
                                        return
                                    }
                                    withAnimation {
                                        isSpinnerComplete = true
                                    }
                                    try! await Task.sleep(for: .seconds(2)) // Delay before finishing onboarding.
                                    viewState.isOnboarding = false // Mark onboarding as complete.
                                }
                            }*/
                        }
                                      .padding(.top, .padding32)
                        
                        Spacer()
                        
                        // Navigation link to resend verification email.
                        /*if (!isWaitingWithSpinner && onboardingStage == .Initial) {
                         NavigationLink("Resend a verification email", destination: ResendEmail())
                         .padding(15)
                         }*/
                        // Display additional spacers based on the current onboarding state.
                        /*if (!isWaitingWithSpinner && onboardingStage == .Initial) || [OnboardingStage.Username, OnboardingStage.Verify].contains(onboardingStage) {
                         Spacer()
                         }*/
                    }
                    //.padding()
                    
                    // Display hCaptcha view if waiting for captcha.
                    if isWaitingWithSpinner && onboardingStage == .Initial {
                        VStack {
#if canImport(UIKit)
                            HCaptchaView(apiKey: viewState.apiInfo!.features.captcha.key, baseURL: viewState.http.baseURL, result: $hCaptchaResult)
                                .onChange(of: hCaptchaResult) {oldValue, newValue in
                                    withAnimation {
                                        isWaitingWithSpinner = false
                                        isSpinnerComplete = true // Mark spinner as complete once captcha is resolved.
                                    }
                                    Task {
                                        do {
                                            // Attempt to create account after resolving captcha.
                                            _ = try await viewState.http.createAccount(email: email, password: password, invite: nil, captcha: hCaptchaResult).get()
                                        } catch {
                                            withAnimation {
                                                isSpinnerComplete = false
                                                isWaitingWithSpinner = false
                                                errorMessage = "Sorry, your email or password was invalid"
                                            }
                                            return
                                        }
                                        try! await Task.sleep(for: .seconds(2)) // Delay before checking for email feature.
                                        withAnimation {
                                            isSpinnerComplete = false
                                            // Move to verification stage if email feature is enabled.
                                            if viewState.apiInfo?.features.email == true {
                                                onboardingStage = .Verify
                                            } else {
                                                onboardingStage = .Username // Move to username stage if not.
                                            }
                                        }
                                    }
                                }
#else
                            Text("No hcaptcha support") // Fallback for platforms without hCaptcha support.
#endif
                        }
                    }
                }
                .navigationDestination(for: CreateAccountPath.self){destination in
                    switch destination {
                    case .verifyEmail :
                        VerifyEmail(path: $path, email: email)
                    }
                }
                .padding(.horizontal, .size16)
                .onAppear {
                    //TODO
                    //viewState.isOnboarding = true // Set onboarding state on view appear.
                }
            }
        
    }
    
    private func onChangeEmail(){
        emailTextFieldStatus = .default
        onChangeData()
    }
    
    private func onChangePassword(){
        passwordTextFieldStatus = .default
        onChangeData()
    }
    
    private func onChangeData(){
        
        if email.isNotEmpty && self.password.isNotEmpty{
            continueBtnStatus = .default
        } else {
            continueBtnStatus = .disabled
        }
        
    }
}

enum CreateAccountPath : Hashable {
    case verifyEmail
}

// Preview for SwiftUI canvas.
#Preview {
    var viewState = ViewState.preview()
    
    /*
     
     @Binding public var mfaTicket: String // Binding for MFA ticket.
     @Binding public var mfaMethods: [String]
     
     
     */
    
    CreateAccount(path: .constant(NavigationPath()), mfaTicket: .constant(""), mfaMethods: .constant([]))
        .environmentObject(viewState) // Provide the view state for previewing the CreateAccount view.
}


// Preview for SwiftUI canvas.
/*#Preview {
 var viewState = ViewState.preview()
 
 return CreateAccount(
 onboardingStage: .Verify)
 .environmentObject(viewState) // Provide the view state for previewing the CreateAccount view.
 }*/


// Preview for SwiftUI canvas.
/*#Preview {
 var viewState = ViewState.preview()
 
 return CreateAccount(
 onboardingStage: .Username)
 .environmentObject(viewState) // Provide the view state for previewing the CreateAccount view.
 }*/
