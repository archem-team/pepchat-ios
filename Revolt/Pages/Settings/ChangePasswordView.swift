//
//  ChangePasswordView.swift
//  Revolt
//

import SwiftUI

struct ChangePasswordView: View {
   @Environment(\.dismiss) var dismiss
   @EnvironmentObject private var viewState: ViewState // The current application state
   
   @State var newPassword: String = "" // The new username input by the user
   @State var currentPassword: String = "" // The password needed to authorize the username change
    
    @State var newPasswordTextFieldState : PeptideTextFieldState = .default
    @State var currentPasswordTextFieldState : PeptideTextFieldState = .default
    @State var changePasswordBtnState : ComponentState = .disabled
   
   @State var errorOccurred = false // Flag to indicate if an error occurred during the update
   
  
   
   /// Submits the new username and password to the server for updating.
   func changePassword() async {
       //do {
           //TODO:
           self.changePasswordBtnState = .loading
           let updatePasswordResponse =  await viewState.http.updatePassword(newPassword: newPassword, oldPassword: currentPassword)
           self.changePasswordBtnState = .default
       
           switch updatePasswordResponse {
           case .success(_):
               viewState.showAlert(message: "Password Updated!", icon: .peptideDoneCircle)
               dismiss()
           case .failure(_):
               debugPrint("failure")
               currentPasswordTextFieldState = .error(message: "Password is incorrect.")
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
       
       PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Change Password")){_,_ in
           VStack(spacing: .zero){
               
               PeptideText(text: "Update Your Password",
                           font: .peptideTitle2)
                            .padding(.top, .padding24)
               
               
               PeptideText(text: "Please enter your existing password and your new password.",
                           font: .peptideBody4,
                           textColor: .textGray07)
               .padding(.horizontal, .padding12)
               .padding(.top, .padding4)
               
               
    
               PeptideTextField(text: $currentPassword,
                                state: $currentPasswordTextFieldState,
                                isSecure: true,
                                label: "Current Password",
                                placeholder: "",
                                hasSecureBtn: true,
                                hasClearBtn: false
               )
                   .padding(.top, .padding24)
               
               
               PeptideTextField(text: $newPassword,
                                state: $newPasswordTextFieldState,
                                isSecure: true,
                                label: "New Password",
                                placeholder: "",
                                hasSecureBtn: true,
                                hasClearBtn: false
               )
               .padding(.top, .padding24)
               
           
               
               PeptideButton(title: "Change Password", buttonState: changePasswordBtnState){
                   
                   currentPasswordTextFieldState = .default
                   newPasswordTextFieldState = .default
                   
                   if currentPassword.isValidPassword == false {
                       currentPasswordTextFieldState = .error(message: "Password is incorrect.")
                   } else if newPassword.isValidPassword == false {
                       newPasswordTextFieldState = .error(message: "Enter a valid password")
                   } else {
                       hideKeyboard()
                       Task {
                           await changePassword()
                       }
                   }
               }
               .padding(.top, .padding24)
               
               Spacer(minLength: .zero)
           }
           .padding(.horizontal, .padding16)
       }
       
       
      
       .onChange(of: currentPassword, {_, _ in updateButtonState()}) // Reset error on value change
       .onChange(of: newPassword, {_, _ in updateButtonState()}) // Reset error on password change
       .task {
           //TODO:
           //value = viewState.userSettingsStore.cache.user!.username
       }
   }
    
    private func updateButtonState() {
        if currentPassword.isNotEmpty && newPassword.isNotEmpty {
            changePasswordBtnState = .default
        } else {
            changePasswordBtnState = .disabled
        }
        errorOccurred = false
    }
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ChangePasswordView()
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}


/*
 
 
 fileprivate struct PasswordUpdateSheet: View {
     @EnvironmentObject var viewState: ViewState // The current application state
     @Binding var showSheet: Bool // Binding to control the visibility of the sheet
     
     @State var oldPassword: String = "" // The old password input by the user
     @State var newPassword: String = "" // The new password input by the user
     
     @FocusState var oldPasswordFocus: Bool // Focus state for the old password input field
     @FocusState var newPasswordFocus: Bool // Focus state for the new password input field
     
     @State var errorOccurred = false // Flag to indicate if an error occurred during password update
     
     /// Submits the old and new passwords to the server for updating.
     func submitPassword() async {
         do {
             _ = try await viewState.http.updatePassword(newPassword: newPassword, oldPassword: oldPassword).get() // Attempt to update password
             showSheet = false // Close the sheet upon success
         } catch {
             // TODO: Provide better error messages
             withAnimation {
                 errorOccurred = true // Indicate that an error occurred
             }
         }
     }
     
     var body: some View {
         VStack {
             // Input field for the old password
             SecureField("Old Password", text: $oldPassword)
                 .textContentType(.password) // Set text content type for password
                 .onSubmit {
                     if newPassword.isEmpty {
                         newPasswordFocus = true // Focus new password field if empty
                     } else {
                         Task {
                             await submitPassword() // Submit password if new password is provided
                         }
                     }
                 }
                 .focused($oldPasswordFocus) // Bind focus state
             
             Spacer()
                 .frame(maxHeight: 30)
             // Input field for the new password
             SecureField("New Password", text: $newPassword)
                 .textContentType(.newPassword) // Set text content type for new password
                 .onSubmit {
                     if oldPassword.isEmpty {
                         oldPasswordFocus = true // Focus old password field if empty
                     } else {
                         Task {
                             await submitPassword() // Submit password if both fields are filled
                         }
                     }
                 }
                 .focused($newPasswordFocus) // Bind focus state
             
             // Error message if password update fails
             if errorOccurred {
                 Text("The trolls have rejected your old password", comment: "The password was rejected by the server")
                     .foregroundStyle(Color.red) // Style the error message
             }
             Spacer()
                 .frame(minHeight: 30, maxHeight: 70)
             // Button to change the password
             Button(action: {
                 if oldPassword.isEmpty {
                     oldPasswordFocus = true // Focus old password field if empty
                 } else if newPassword.isEmpty {
                     newPasswordFocus = true // Focus new password field if empty
                 } else {
                     Task {
                         await submitPassword() // Submit password if both fields are filled
                     }
                 }
             }) {
                 Text("Change it", comment: "'done' button for changing password") // Button text
             }
         }
         .onChange(of: oldPassword, {_, _ in errorOccurred = false}) // Reset error on old password change
         .onChange(of: newPassword, {_, _ in errorOccurred = false}) // Reset error on new password change
     }
 }

 
 */
