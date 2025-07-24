//
//  RecoveryCodesView.swift
//  Revolt
//
//

import SwiftUI
import Sentry
import UniformTypeIdentifiers

struct RecoveryCodesView: View {
    @EnvironmentObject var viewState: ViewState // The current application state
    @Binding var showSheet: Bool // Binding to control the visibility of the sheet
    @Binding var sheetIsNotDismissable: Bool // Binding to prevent dismissal of the sheet during code generation
    @State var errorOccurred = false // Flag to indicate if an error occurred
    @State var codes: [String] = [] // Array to hold generated recovery codes
    @State var copyButtonText = String(localized: "Copy to clipboard") // Text for the copy button
    @State var isCopyDisabled = false // Flag to disable the copy button after action
    
    /// Generates recovery codes by calling the appropriate API endpoint using the provided MFA ticket.
    /// - Parameter ticket: The MFA ticket response needed for generating recovery codes.
    func generateCodes(ticket: MFATicketResponse) {
        Task {
            do {
                let _codes = try await viewState.http.generateRecoveryCodes(mfaToken: ticket.token).get() // Fetch recovery codes
                
                sheetIsNotDismissable = true // Prevent sheet dismissal while codes are being generated
                withAnimation {
                    codes = _codes // Store the generated recovery codes
                }
            } catch {
                let error = error as! RevoltError // Cast the error to RevoltError for handling
                SentrySDK.capture(error: error) // Capture the error for reporting
                
                withAnimation {
                    errorOccurred = true // Indicate that an error occurred
                }
            }
        }
    }
    
    // Known bug: The MFATicketView doesn't fully slide offscreen.
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Recovery Codes")){_, _ in
            
            VStack(spacing: .zero) {
                if codes.isEmpty {
                    // View for entering the password to generate recovery codes
                    CreateMFATicketView(requestTicketType: .Password, doneCallback: generateCodes)
                        .transition(.slideNext)
                } else {
                    VStack {
                        // Display generated recovery codes
                        ForEach(0 ..< codes.count, id: \.self) { value in
                            Text(codes[value])
                                .font(.subheadline) // Set font for code display
                                .fontWeight(.heavy) // Set font weight
                                .padding(5) // Padding around each code
                                .textSelection(.enabled) // Enable text selection for copying
                        }
                        Spacer()
                        
                        // Button to copy the recovery codes to clipboard
                        Button(action: {
                            let content = codes.joined(separator: "\n") // Join codes with newline for clipboard
                            UIPasteboard.general.setValue(content, forPasteboardType: UTType.plainText.identifier) // Copy to clipboard
                            
                            withAnimation {
                                copyButtonText = String(localized: "Copied!") // Change button text to indicate success
                                isCopyDisabled = true // Disable copy button temporarily
                            }
                            
                            // Reset button text after a delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: {
                                withAnimation {
                                    copyButtonText = String(localized: "Copy to clipboard") // Restore original button text
                                    isCopyDisabled = false // Re-enable the copy button
                                }
                            })
                        }) {
                            Text(copyButtonText) // Display button text
                        }
                        .padding(.vertical, 10)
                        .frame(width: 250.0) // Set button width
                        .foregroundStyle(viewState.theme.foreground) // Button text color
                        .background(viewState.theme.background2) // Button background color
                        .clipShape(.rect(cornerRadius: 50)) // Rounded corners for button
                        .disabled(isCopyDisabled) // Disable button if copying is in progress
                        
                        // Button to dismiss the sheet
                        Button(action: {
                            showSheet = false // Dismiss the sheet
                        }) {
                            Text("Done") // Button text
                        }
                        .padding(.vertical, 10)
                        .frame(width: 250.0) // Set button width
                        .foregroundStyle(viewState.theme.foreground) // Button text color
                        .background(viewState.theme.background2) // Button background color
                        .clipShape(.rect(cornerRadius: 50)) // Rounded corners for button
                    }
                    .backgroundStyle(viewState.theme.background2) // Background for codes list
                    .padding() // Padding around the content
                    .transition(.slideNext) // Transition effect for view changes
                }
                if errorOccurred {
                    Spacer()
                        .frame(maxHeight: 10)
                    Text("Something went wrong. Try again later?") // Error message for user
                        .foregroundStyle(.red) // Style the error message
                }
            }
            .padding(.horizontal, .padding16)

        }
        
    }
}


// MARK: - MFA Stuff

/// A SwiftUI view that provides an interface for entering a password or TOTP code for multi-factor authentication.
struct CreateMFATicketView: View {
    @EnvironmentObject var viewState: ViewState // State object holding the current view state
    @State private var fieldIsIncorrect = false // Indicates if the input field contains an incorrect value
    @State private var fieldShake = false // Controls the shake animation for the input field
    @State private var fieldValue = "" // Holds the current input value entered by the user
    @State var fieldTextFieldState : PeptideTextFieldState = .default

    /// Enumeration representing the types of requests that can be made: entering a password, TOTP code, or recovery code.
    enum RequestTicketType { case Password, Code, RecoveryCode }
    
    var requestTicketType: RequestTicketType // The type of request being made (password, TOTP code, or recovery code)
    var doneCallback: (MFATicketResponse) -> () // Callback to be executed upon successful submission
    
    /// Animates the input field to indicate an error state when the user provides incorrect input.
    func setBadField() {
        withAnimation {
            fieldIsIncorrect = true
        }
        
        fieldShake = true
        withAnimation(Animation.spring(response: 0.2, dampingFraction: 0.2, blendDuration: 0.2)) {
            fieldShake = false
        }
    }
    
    /// Validates the input value and submits the MFA request based on the input type.
    /// If successful, invokes doneCallback; otherwise, calls setBadField.
    func submitForTicket() async {
        if fieldIsIncorrect {
            withAnimation {
                fieldIsIncorrect = false
            }
        }
        
        if fieldValue.isEmpty {
            setBadField()
            return
        }
        
        var requestType = requestTicketType
        if requestTicketType == .Code && fieldValue.contains("-") {
            requestType = .RecoveryCode
        }
        
        let resp = switch requestType {
        case .Password:
            await viewState.http.submitMFATicket(password: fieldValue)
        case .Code:
            await viewState.http.submitMFATicket(totp: fieldValue)
        case .RecoveryCode:
            await viewState.http.submitMFATicket(recoveryCode: fieldValue)
        }
        
        let ticket = try? resp.get()
        
        if ticket == nil {
            setBadField()
            return
        }
        
        doneCallback(ticket!)
    }
    
    /// Receives values from the pasteboard and sets the field value accordingly.
    /// Attempts to submit the MFA ticket immediately if a valid value is found.
    func receivePasteboardCallback(totp: String?, recovery: String?) {
        if totp != nil {
            fieldValue = totp!
            Task { await submitForTicket() }
        } else if recovery != nil {
            fieldValue = recovery!
            Task { await submitForTicket() }
        }
    }
    
    /// The view body that contains UI components for user input.
    var body: some View {
        VStack(spacing: .zero) {
            
            /*Text("Hold Up!", comment: "title prompt for password when setting up totp")
                .font(.title)*/
            
            
            Image(.peptideRecovery)
                .padding(.top, .padding24)
            
            
            if requestTicketType == .Password {
                /*Text("This area is guarded by trolls. Tell them your password to continue.", comment: "subtitle prompt for password when setting up totp")
                    .font(.title2)*/
                
                Group{
                    PeptideText(text: "Stay Secure with Recovery Codes",
                                font: .peptideTitle2)
                    .padding(.horizontal, .padding4)
                    
                    PeptideText(text: "Recovery Codes ensure you’re never locked out.",
                                font: .peptideBody2,
                                textColor: .textGray07)
                }
                .padding(.horizontal, .padding16)
                
               
                
            } else {
                
                //TODO:
                
                Text("This area is guarded by trolls. Fetch them your TOTP code to continue.", comment: "subtitle prompt for password when modifying totp")
                    .font(.title2)
            }
            
            
            if requestTicketType == .Password {
                
                PeptideTextField(text: $fieldValue,
                                 state: $fieldTextFieldState,
                                 isSecure: true,
                                 label: "Current Password",
                                 placeholder: "",
                                 hasSecureBtn: true)
                    .padding(.top, .padding24)
                
                /*SecureField(String(localized: "Enter Password", comment: "Password prompt"), text: $fieldValue)
                    .textContentType(.password)
                    .offset(x: fieldShake ? 30 : 0)
                    .onChange(of: fieldValue) { _, _ in
                        if fieldIsIncorrect {
                            withAnimation {
                                fieldIsIncorrect = false
                            }
                        }
                    }
                    .onSubmit {
                        Task { await submitForTicket() }
                    }*/
            } else {
                
                // TODO: this needs something to toggle to recovery code mode
                TextField(String(localized: "Enter TOTP code", comment: "Authenticator prompt"), text: $fieldValue)
                    .textContentType(.oneTimeCode)
                    .offset(x: fieldShake ? 30 : 0)
                    #if os(iOS)
                    .keyboardType(UIKeyboardType.numberPad)
                    #endif
                    .onChange(of: fieldValue) { _, _ in
                        if fieldIsIncorrect {
                            withAnimation {
                                fieldIsIncorrect = false
                            }
                        }
                        
                        if fieldValue.count == 6 {
                            Task { await submitForTicket() }
                        }
                    }
                    .onSubmit {
                        Task { await submitForTicket() }
                    }
                    .onTapGesture {
                        maybeGetPasteboardValue(receivePasteboardCallback)
                    }
            }
            /*if fieldIsIncorrect {
                if !fieldValue.isEmpty {
                    Text("Try again", comment: "the user entered an incorrect password")
                        .foregroundStyle(Color.red)
                        .font(.caption)
                } else {
                    Text("You must enter your password", comment: "the user entered a blank password")
                        .foregroundStyle(Color.red)
                        .font(.caption)
                }
            }*/
            
            PeptideButton(title: "Generate Codes", buttonState: .default){
                //TODO Validation and btn satte
                Task {
                    
                }
            }
            .padding(.top, .padding24)
            
            Spacer(minLength: .zero)
        }
        .task {
            let response = await viewState.http.getMfaMethods()
            switch response {
            case .success(let success):
                debugPrint("\(success)")
            case .failure(let failure):
                debugPrint("\(failure)")
            }
        }
    }
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    RecoveryCodesView(showSheet: .constant(false), sheetIsNotDismissable: .constant(false))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}



#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    CreateMFATicketView(requestTicketType: .Password, doneCallback: {_ in
    })
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
