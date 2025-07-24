//
//  Mfa.swift
//  Revolt
//
//

import SwiftUI

/// A view for multi-factor authentication (MFA) input.
struct Mfa: View {
    @EnvironmentObject var viewState: ViewState // Access to the global view state.
    
    @Binding public var path: NavigationPath // The navigation path for view transitions.
    @Binding var ticket: String // Binding for MFA ticket.
    @Binding var methods: [String] // Binding for available MFA methods.
    
    @State var selected: String? = nil // Currently selected MFA method.
    @State var currentText: String = "" // Current input text for MFA.
    @State var error: String? = nil // Error message for MFA input.
    
    @FocusState var textEntryFocus: String? // Focus state for the text entry.
    
    @Environment(\.colorScheme) var colorScheme: ColorScheme // Access to the current color scheme.
    
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
    
    /// Sends the MFA response to the server based on the selected method.
    func sendMfa() {
        let key: String // The key to use in the MFA response.
        
        // Determine the key based on the selected method.
        switch selected {
        case "Password":
            key = "password"
        case "Totp":
            key = "totp_code"
        case "Recovery":
            key = "recovery_code"
        default:
            return // Exit if no valid method is selected.
        }
        
        Task {
            await viewState.signIn(mfa_ticket: ticket, mfa_response: [key: currentText], callback: { response in
                switch response {
                case .Success: // Handle successful MFA input.
                    path = NavigationPath() // Reset navigation path.
                case .Disabled: // Handle account disabled case.
                    error = "Account disabled"
                case .Invalid: // Handle invalid MFA input.
                    error = "Invalid \(selected!.replacing("_", with: " "))"
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
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .center, spacing: 16) {
                Spacer()
                
                Text("One more thing") // Header for MFA input.
                    .bold()
                    .font(.title)
                
                Spacer()
                
                Text("You've got 2FA enabled to keep your account extra-safe.") // Description for MFA.
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let error { // Display error message if available.
                    Text(verbatim: error)
                        .foregroundStyle(.red)
                }
                
                ScrollView { // Scrollable view for MFA methods.
                    ForEach(methods, id: \.self) { method in
                        let (icon, text, desc, placeholder, keyboardType) = getMethodDetails(method: method) // Get method details.
                        
                        VStack(alignment: .leading) {
                            Button {
                                withAnimation {
                                    if selected == method { // Toggle selection for the method.
                                        selected = nil
                                        textEntryFocus = nil
                                    } else {
                                        selected = method
                                        textEntryFocus = method
                                    }
                                    
                                    currentText = "" // Reset text input.
                                }
                            } label: {
                                VStack(alignment: .center, spacing: 12) {
                                    HStack(alignment: .center, spacing: 16) {
                                        Image(systemName: icon) // Method icon.
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 24)
                                        
                                        Text(text) // Method text.
                                            .bold()
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.down") // Dropdown indicator.
                                    }
                                    
                                    if selected == method { // Display details if method is selected.
                                        Text(desc) // Description for the selected method.
                                            .foregroundStyle(.secondary)
                                        
                                        VStack(alignment: .leading, spacing: 16) {
                                            TextField(placeholder, text: $currentText) // TextField for MFA input.
                                                .focused($textEntryFocus, equals: method)
#if os(iOS)
                                                .keyboardType(keyboardType) // Set keyboard type.
#endif
                                                .textContentType(.oneTimeCode)
                                                .onSubmit(sendMfa) // Send MFA response on submit.
                                            
                                            // Button to proceed with MFA input.
                                            Button {
                                                sendMfa()
                                            } label: {
                                                HStack {
                                                    Spacer()
                                                    Text("Next") // Button label.
                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .buttonBorderShape(.roundedRectangle(radius: 8))
                                            .tint(.themePrimary) // Button tint color.
                                        }
                                    }
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                            }
                            .background(RoundedRectangle(cornerRadius: 8)
                                .foregroundStyle(.gray.opacity(0.2)) // Background for each method.
                            )
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Full-width frame.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Full-height frame.
        .foregroundColor((colorScheme == .light) ? Color.black : Color.white) // Text color based on theme.
    }
}

#Preview {
    Mfa(path: .constant(NavigationPath()), ticket: .constant(""), methods: .constant(["Password", "Totp", "Recovery"]))
}
