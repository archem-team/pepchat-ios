//
//  ForgotPassword_Reset.swift
//  Revolt
//
//

import SwiftUI
import Types


/// View for resetting the password using a token sent to the user's email.
struct ForgotPassword_Reset: View {
    @EnvironmentObject var viewState: ViewState // Shared application state.
    @Environment(\.colorScheme) var colorScheme // Current color scheme (light or dark).
    
    @Binding var path : NavigationPath

    
    @State var errorMessage: String? = nil // Holds any error messages.
    
    @State var resetToken = "" // Token received via email for password reset.
    @State var newPassword = "" // User's new password.
    
    @State var showSpinner = false // Indicates if the loading spinner should be displayed.
    @State var completeSpinner = false // Indicates if the loading action is complete.
    
    @State var goToOnboarding: Bool = false // Controls navigation to the onboarding page.
    
    var email: String // User's email for signing in after password reset.
    
    @State private var tokenTextFieldStatus: PeptideTextFieldState = .default
    @State private var newPasswordTextFieldStatus: PeptideTextFieldState = .default
    
    @State private var resetPasswordBtnState: ComponentState = .disabled
    
    /// Processes the password reset request.
    func process() {
        Task {
            
            resetPasswordBtnState = .loading
            tokenTextFieldStatus = .disabled
            newPasswordTextFieldStatus = .disabled
            
            
            do {
                // Attempt to reset the password using the provided token and new password.
                _ = try await viewState.http.resetPassword(token: resetToken, password: newPassword).get()
            } catch {
                withAnimation {
                    
                    resetPasswordBtnState = .default
                    
                    tokenTextFieldStatus = .error(message: "Your token was invalid or your password does not meet requirements.")
                    newPasswordTextFieldStatus = .error(message: "Your token was invalid or your password does not meet requirements. Direct all complaints about this message to zomatree.")

                    
                    // Display an error message if the reset fails.
                    errorMessage = "Your token was invalid or your password does not meet requirements." // TODO: refine error handling
                    showSpinner = false
                }
                return
            }
            
            tokenTextFieldStatus = .default
            newPasswordTextFieldStatus = .default
            resetPasswordBtnState = .default
            path = NavigationPath()
            
            /*completeSpinner = true // Indicate the spinner is complete.
            try! await Task.sleep(for: .seconds(3)) // Simulate loading time before proceeding.
            
            // Attempt to sign in with the new password.
            await viewState.signIn(email: email, password: newPassword) { state in
                switch state {
                case .Disabled, .Invalid:
                    // Show error if the account is disabled, but the reset was successful.
                    withAnimation {
                        errorMessage = "Your account has been disabled,\nhowever the reset was successful."
                    }
                case .Onboarding:
                    // Navigate to onboarding if applicable.
                    goToOnboarding = true
                default:
                    viewState.isOnboarding = false // Reset onboarding state if the user successfully logs in.
                }
            }*/
        }
    }
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 onClickBackButton: {
            path = NavigationPath()
        })){_,_ in
            
            VStack(spacing: .zero) {
                
                PeptideAuthHeaderView(imageResourceName: .peptideForgotPassword,
                                      title: "Set Up Your New Password",
                                      subtitle: "Make sure it’s unique and secure.")
                
             
                
      
                
                // Display error message or instructions.
                /*Text(errorMessage != nil ? errorMessage! : "We sent a token to your email.\nEnter it here, along with your new password")
                    .font(.callout)
                    .foregroundStyle(errorMessage != nil ? Color.red : (colorScheme == .light) ? Color.black : Color.white)
                    .multilineTextAlignment(.center)*/
                
                // Text field for the email token.
                
                PeptideTextField(text: $resetToken,
                                 state: $tokenTextFieldStatus,
                                 placeholder: "Email Token")
                                .padding(.top, .padding32)
                                .onChange(of: resetToken){ _, _ in
                                    onChangeToken()
                                }
                
                
                PeptideTextField(text: $newPassword,
                                 state: $newPasswordTextFieldStatus,
                                 placeholder: "New Password")
                                .padding(.top, .padding8)
                                .onChange(of: newPassword){ _, _ in
                                    onChangePassword()
                                }
                
                
                /*TextField("Email Token", text: $resetToken)
                    .padding()
                    .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.2))
                    .clipShape(.rect(cornerRadius: 5))*/
                
                // Text field for the new password.
                /*TextField("New Password", text: $newPassword)
                    .textContentType(.newPassword) // Set text content type for password.
                    .padding()
                    .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.2))
                    .clipShape(.rect(cornerRadius: 5))*/
                
                
            
                PeptideButton(title: "Set New Password",
                              buttonState: resetPasswordBtnState,
                              
                              onButtonClick: {
                    // Validate input fields.
                    /*if resetToken.isEmpty || newPassword.isEmpty {
                        withAnimation {
                            errorMessage = "Please enter the token sent to your email, and your new password."
                        }
                        return
                    }*/
                    
                    hideKeyboard()
                    
                    
                    let inValidToken = resetToken.isEmpty
                    let inValidPassword = newPassword.isValidPassword == false
                    
                    if inValidToken {
                        withAnimation {
                            tokenTextFieldStatus = .error(message: "Please enter a valid token.")
                        }
                    }
                    
                    
                    if inValidPassword {
                        withAnimation {
                            newPasswordTextFieldStatus = .error(message: "Please use 6+ characters, a letter, number & symbol.")
                        }
                    }
                    
                    if (inValidToken || inValidPassword) {
                        return
                    }
                    
                    
                    
                    withAnimation {
                        showSpinner = true // Show spinner while processing.
                    }
                    
                    process() // Call the process function to handle the password reset.
                })
                .padding(.top, .padding32)
                
                
                // Button to reset the password.
                /*Button(action: {
                    // Validate input fields.
                    if resetToken.isEmpty || newPassword.isEmpty {
                        withAnimation {
                            errorMessage = "Please enter the token sent to your email, and your new password."
                        }
                        return
                    }
                    
                    withAnimation {
                        showSpinner = true // Show spinner while processing.
                    }
                    
                    process() // Call the process function to handle the password reset.
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
                
                Spacer()
            }
            .padding() // Padding for the entire view.
        }
        
        
       
        /*.navigationDestination(isPresented: $goToOnboarding) {
            // Navigate to onboarding page.
            CreateAccount(path: .constant(NavigationPath()), mfaTicket: .constant(""), mfaMethods: .constant([]), onboardingStage: .Username)
        }*/
    }
    
    
    private func onChangeToken(){
        tokenTextFieldStatus = .default
        onChangeData()
    }
    
    private func onChangePassword(){
        newPasswordTextFieldStatus = .default
        onChangeData()
    }
    
    private func onChangeData(){
        
        if resetToken.isNotEmpty && newPassword.isNotEmpty{
            resetPasswordBtnState = .default
        } else {
            resetPasswordBtnState = .disabled
        }
        
    }
}



// Preview for development.
#Preview {
    NavigationStack {
        ForgotPassword_Reset(path: .constant(NavigationPath()), email: "")
            .environmentObject(ViewState.preview()) // Provide a preview environment.
    }
}

