//
//  ChangeEmailView.swift
//  Revolt
//
//

import SwiftUI

struct ChangeEmailView: View {
   @Environment(\.dismiss) var dismiss
   @EnvironmentObject private var viewState: ViewState // The current application state
   
   @State var email: String = "" // The new username input by the user
   @State var password: String = "" // The password needed to authorize the username change
    
    @State var emailTextFieldState : PeptideTextFieldState = .default
    @State var passwordTextFieldState : PeptideTextFieldState = .default
    @State var receiveEmailBtnState : ComponentState = .disabled
    

   
   @State var errorOccurred = false // Flag to indicate if an error occurred during the update
   
  
   
   /// Submits the new username and password to the server for updating.
   func submitEmail() async {
       //do {
           //TODO:
           self.receiveEmailBtnState = .loading
           let updateEmailResponse =  await viewState.http.updateEmail(updateEmail: .init(email: email, currentPassword: password)) // Attempt to update username
           self.receiveEmailBtnState = .default
       
           switch updateEmailResponse {
               case .success(_):
                    self.viewState.showAlert(message: "Confirmation link sent to your email.", icon: .peptideInfo)
                   dismiss()
               case .failure(let failure):
               switch failure {
                    case .Alamofire(_): break
                    case .JSONDecoding(_): break
                    case .HTTPError(_, _):
                        withAnimation{
                            emailTextFieldState = .error(message: "")
                            passwordTextFieldState = .error(message: "Failed to validate fields.")
                        }
               }
           }
           //showSheet = false // Close the sheet upon success
       /*} catch {
           // TODO: Provide better error messages
           withAnimation {
               errorOccurred = true // Indicate that an error occurred
           }
       }*/
   }
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Change Email")){_,_ in
            VStack(spacing: .zero){
                
                SettingAttentionView(items: ["We will send a verification email to your new mail."])
                
                
                
                /*HStack {
                 TextField("Enter a new username", text: $value)
                 .textContentType(.username) // Set text content type
                 .onSubmit {
                 if password.isEmpty {
                 passwordFieldState = true // Focus password field if empty
                 } else {
                 Task {
                 await submitName() // Submit name if password is provided
                 }
                 }
                 }
                 
                 Text("#\(viewState.userSettingsStore.cache.user!.discriminator)") // Display user's discriminator
                 //.addBorder(viewState.theme.accent, cornerRadius: 1.0) // Optional border styling
                 }*/
                
                PeptideTextField(text: $email,
                                 state: $emailTextFieldState,
                                 label: "New Email",
                                 placeholder: "Enter your new email",
                                 keyboardType: .emailAddress){ isFocus in
                    
                    if email.isNotEmpty, !isFocus{
                        self.emailTextFieldState = email.isValidEmail ? .default : .error(message: "Enter valid email.", icon: .peptideClose)
                    }
                    
                }
                                 .padding(.top, .padding24)
                
                
                /*
                 
                 
                 // Input field for password
                 SecureField("Password", text: $password)
                 .textContentType(.password) // Set text content type for password
                 .onSubmit {
                 if value.isEmpty {
                 nameFieldState = true // Focus name field if empty
                 } else {
                 Task {
                 await submitName() // Submit name if password is provided
                 }
                 }
                 }
                 
                 */
                
                PeptideTextField(text: $password,
                                 state: $passwordTextFieldState,
                                 isSecure: true,
                                 label: "Password",
                                 placeholder: "Enter your current password",
                                 hasSecureBtn: true,
                                 hasClearBtn: false
                ){ isFocus in
                    
                    if password.isNotEmpty, !isFocus {
                        self.passwordTextFieldState = password.isValidPassword ? .default : .error(message: "Enter valid password.", icon: .peptideClose)
                    }
                        
                    
                }
                                 .padding(.top, .padding24)
                    
                    
                    PeptideButton(
                        buttonType: .large(),
                        title: "Receive Email",
                        buttonState: receiveEmailBtnState
                    ){
                        emailTextFieldState = .default
                        passwordTextFieldState = .default
                        if email.isValidEmail == false {
                            emailTextFieldState = .error(message: "Enter valid email.")
                        } else if password.isValidPassword == false {
                            passwordTextFieldState = .error(message: "Password is incorrect.")
                        } else {
                            Task {
                                hideKeyboard()
                                await submitEmail()
                            }
                        }
                    }
                    .padding(.top, .padding40)
                    
                    
                    
                    
                    /*
                     
                     if errorOccurred {
                     Text("The trolls have rejected your password") // Error message if password update fails
                     .foregroundStyle(Color.red) // Style the error message
                     }
                     
                     */
                    
                    Spacer(minLength: .zero)
                }
                                 .padding(.horizontal, .padding16)
            }
            
            
            
            .onChange(of: email, {_, _ in
                self.emailTextFieldState = .default
                updateButtonState()
            }) // Reset error on value change
            .onChange(of: password, {_, _ in
                self.passwordTextFieldState = .default
                updateButtonState() }
            ) // Reset error on password change
            .task {
                //TODO:
                //value = viewState.userSettingsStore.cache.user!.username
            }
        }
    
    
    private func updateButtonState() {
        if email.isNotEmpty && password.isNotEmpty {
            receiveEmailBtnState = .default
        } else {
            receiveEmailBtnState = .disabled
        }
        errorOccurred = false
    }
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ChangeEmailView()
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
