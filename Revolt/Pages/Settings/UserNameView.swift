//
//  UserNameView.swift
//  Revolt
//
//

import SwiftUI



/// A SwiftUI view for updating the user's username.
/// It allows users to input their new username and password to validate the change.
 struct UserNameView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var viewState: ViewState // The current application state
    
    @State var username: String = "" // The new username input by the user
    @State var password: String = "" // The password needed to authorize the username change
     
     @State var usernameTextFieldState : PeptideTextFieldState = .default
     @State var passwordTextFieldState : PeptideTextFieldState = .default
     @State var updateBtnState : ComponentState = .disabled
    
    @State var errorOccurred = false // Flag to indicate if an error occurred during the update
    
   
    
    /// Submits the new username and password to the server for updating.
    func submitName() async {
        //do {
            //TODO:
            self.updateBtnState = .loading
        
            let updateUsernameResponse =  await viewState.http.updateUsername(newName: username, password: password)
        
            self.updateBtnState = .default

            switch updateUsernameResponse {
            case .success(let success):
                self.viewState.currentUser = success
                self.viewState.showAlert(message: "Username Updated!", icon: .peptideDoneCircle)
                //self.viewState.path.removeLast()
                self.dismiss()
            case .failure(let failure):
                
                switch failure {
                case .Alamofire(_): break
                case .JSONDecoding(_): break
                case .HTTPError(_, _):
                    withAnimation{
                        usernameTextFieldState = .error(message: "")
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
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Username")){_,_ in
            VStack(spacing: .zero){
                
                SettingAttentionView(items: ["Changing your username may change your number tag.",
                                             "You can freely change the case of your username.",
                                             "Your number tag may change at most once a day."])
                
                
                
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
                
                    PeptideTextField(text: $username,
                                     state: $usernameTextFieldState,
                                     label: "Username",
                                     placeholder: "Enter username",
                                     hasClearBtn: false
                    )
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
                )
                .padding(.top, .padding24)
                
            
                
                PeptideButton(title: "Update Username", buttonState: updateBtnState){
                    if username.isEmpty {
                        withAnimation{
                            usernameTextFieldState = .error(message: "Username can not be empty")
                        }
                    } else if password.isEmpty {
                        withAnimation{
                            passwordTextFieldState = .error(message: "Password can not be empty")
                        }
                    } else {
                        withAnimation{
                            usernameTextFieldState = .default
                            passwordTextFieldState = .default
                        }
                        Task {
                            await submitName()
                        }
                    }
                }
                .padding(.top, .padding24)
                
                
                
                
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
        
        
       
        .onChange(of: username) { _, _ in
            updateButtonState()
        }
        .onChange(of: password) { _, _ in
            updateButtonState()
        }
        .task {
            //TODO:
            //value = viewState.userSettingsStore.cache.user!.username
            username = viewState.currentUser?.username ?? ""
        }
    }
     
     private func updateButtonState() {
         if username.isNotEmpty && password.isNotEmpty {
             updateBtnState = .default
         } else {
             updateBtnState = .disabled
         }
         errorOccurred = false
     }
}



#Preview {
    @Previewable @StateObject  var viewState : ViewState = .preview()
    UserNameView()
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}


