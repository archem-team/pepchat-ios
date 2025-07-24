//
//  UserSettings.swift
//  Revolt
//
//  Created by Angelo on 2024-02-10.
//

import SwiftUI
import OSLog
import Sentry
import Alamofire // literally just for types
import UniformTypeIdentifiers
import Types


// Logger initialization for tracking events in the UserSettingsViews context
let log = Logger(subsystem: "app.peptide.chat", category: "UserSettingsViews")

/// Generates a TOTP (Time-based One-Time Password) URL for the given secret and email.
///
/// - Parameters:
///   - secret: The shared secret key used for generating TOTP codes.
///   - email: The email address of the user, used as an identifier in the TOTP URL.
/// - Returns: A formatted string representing the TOTP URL, which can be used by authenticator applications for generating TOTP codes.
func generateTOTPUrl(secret: String, email: String) -> String {
    return "otpauth://totp/Revolt:\(email)?secret=\(secret)&issuer=Revolt"
}


/// Takes a callback that receives either the totp code or the recovery code (in that argument order).
/// Wont be called if neither are found.
/// Attempts to retrieve a TOTP code or a recovery code from the system's pasteboard.
/// This function calls the provided callback with the retrieved values, if any.
///
/// - Parameter callback: A closure that receives two optional strings: the first string for the TOTP code
///                      and the second for the recovery code. The callback is invoked with either
///                      the TOTP code or the recovery code found in the pasteboard, or nil if neither is found.
func maybeGetPasteboardValue(_ callback: (String?, String?) -> ()) {
#if os(iOS)
    let pasteboardItem = UIPasteboard.general.string
#elseif os(macOS)
    let pasteboardItem = NSPasteboard.general.string(forType: .string)
#endif
    if let pasteboardItem = pasteboardItem {
        let regex = /(?<totp>\d{6})|(?<recovery>[a-z0-9]{5}-[a-z0-9]{5})/
        if let match = try? regex.wholeMatch(in: pasteboardItem) {
            if match.output.recovery != nil {
                callback(nil, String(match.output.recovery!))
            } else if match.output.totp != nil {
                callback(String(match.output.totp!), nil)
            }
        }
    }
}



// MARK: - AddTOTPSheet

/// A SwiftUI view for managing the process of adding Time-based One-Time Password (TOTP) authentication.
/// It handles user input for TOTP setup, retrieves the TOTP secret, and verifies the TOTP code.
fileprivate struct AddTOTPSheet: View {
    // Enum representing the various phases of the TOTP setup process.
    private enum Phase {
        case Password, // Phase for entering the password
             Code,         // Phase for displaying the TOTP secret
             Verify,       // Phase for entering the TOTP code
             FatalError    // Phase for handling errors
    }
    
    @EnvironmentObject var viewState: ViewState // The current application state
    @State private var currentPhase: Phase = .Password // Tracks the current phase of the TOTP setup process
    @Binding var showSheet: Bool // Binding to control the visibility of the sheet
    
    @State var OTP = "" // The One-Time Password entered by the user
    @State var fieldShake = false // Flag for triggering shake animation on incorrect input
    @State var fieldIsIncorrect = false // Indicates if the current input field is incorrect
    
    @State var ticket: MFATicketResponse? = nil // Holds the MFA ticket response
    @State var secret: String? = nil // Holds the TOTP secret for the user
    
    /// Animates the input field to indicate an error state when the user provides incorrect input.
    func setBadField() {
        withAnimation {
            fieldIsIncorrect = true // Mark the field as incorrect
        }
        
        fieldShake = true // Start shaking the input field
        withAnimation(Animation.spring(response: 0.2, dampingFraction: 0.2, blendDuration: 0.2)) {
            fieldShake = false // Stop shaking after animation completes
        }
    }
    
    /// Receives the MFA ticket and retrieves the TOTP secret from the server.
    /// - Parameter mfaTicket: The MFA ticket response received after validating the password.
    func receiveTicket(mfaTicket: MFATicketResponse) async {
        ticket = mfaTicket // Store the MFA ticket
        
        // Fetch the TOTP secret associated with the MFA token
        let secretResp = await viewState.http.getTOTPSecret(mfaToken: ticket!.token)
        do {
            let secretModel = try secretResp.get() // Attempt to extract the TOTP secret
            secret = secretModel.secret // Store the TOTP secret
            
            withAnimation {
                currentPhase = .Code // Move to the Code phase after successful retrieval
            }
        } catch {
            log.error("Errored out attempting to receive TOTP secret: \(error.localizedDescription)") // Log any errors
            withAnimation {
                currentPhase = .FatalError // Move to FatalError phase in case of an error
            }
        }
    }
    
    /// Finalizes the TOTP setup by validating the OTP input and sending it to the server.
    func finalize() async {
        if fieldIsIncorrect {
            withAnimation {
                fieldIsIncorrect = false // Reset error state
            }
        }
        
        if OTP.isEmpty {
            setBadField() // Indicate an error if the input field is empty
            return
        }
        
        // Attempt to enable TOTP with the provided OTP
        let resp = await viewState.http.enableTOTP(mfaToken: ticket!.token, totp_code: OTP)
        
        do {
            _ = try resp.get() // Attempt to get the response
        } catch {
            setBadField() // Mark the field as bad if there's an error
            return
        }
        
        showSheet = false // Close the sheet upon successful completion
    }
    
    /// Receives TOTP or recovery code from the pasteboard and initiates the finalize process.
    /// - Parameters:
    ///   - totp: The TOTP code retrieved from the pasteboard.
    ///   - recovery: The recovery code retrieved from the pasteboard.
    func receivePasteboardCallback(totp: String?, recovery: String?) {
        if let totp = totp {
            OTP = totp // Set the OTP if available
            Task { await finalize() } // Finalize the process
        }
    }
    
    /// The body of the view defining its layout and behavior.
    var body: some View {
        VStack {
            // Different views based on the current phase
            if currentPhase == .Password {
                // Phase for entering the password
                CreateMFATicketView(requestTicketType: .Password, doneCallback: { ticket in
                    Task { await receiveTicket(mfaTicket: ticket) } // Handle ticket receipt
                })
            } else if currentPhase == .Code {
                // Phase for displaying the TOTP secret
                Text("Code time", comment: "debug print, don't translate")
                Spacer()
                    .frame(maxHeight: 10)
                Text(secret!) // Display the TOTP secret
                    .selectionDisabled(false) // Allow selection for copying
                    .onTapGesture {
                        copyText(text: secret!) // Copy the TOTP secret on tap
                    }
                Spacer()
                    .frame(maxHeight: 10)
                Link(destination: URL(
                    string: generateTOTPUrl(
                        secret: secret!,
                        email: viewState.userSettingsStore.cache.accountData!.email
                    ))!) {
                        Text("Open in authenticator app", comment: "Open the user's authenticator app") // Link to open the authenticator app
                    }
                    .foregroundStyle(Color.blue)
                Spacer()
                    .frame(maxHeight: 10)
                Button(action: {
                    withAnimation {
                        currentPhase = .Verify // Move to Verify phase
                    }
                }) {
                    Text("Next") // Button to proceed to the next phase
                }
            } else if currentPhase == .Verify {
                // Phase for entering the TOTP code
                Text("Verify time", comment: "debug print, don't translate")
                Text("Enter the code provided by your authenticator app", comment: "Prompting the user for their OTP while setting up TOTP")
                TextField(String(localized: "code", comment: "TOTP code"), text: $OTP)
                    .textContentType(.oneTimeCode) // Specify the field type for OTP
                    .onSubmit {
                        Task { await finalize() } // Finalize on submission
                    }
#if os(iOS)
                    .keyboardType(.numberPad) // Show number pad on iOS
#endif
                    .onTapGesture {
                        maybeGetPasteboardValue(receivePasteboardCallback) // Try to retrieve code from pasteboard
                    }
                    .onAppear {
                        maybeGetPasteboardValue(receivePasteboardCallback) // Attempt to get code on appear
                    }
            } else if currentPhase == .FatalError {
                // Phase for handling errors
                Text("Something went wrong. Try again later?") // Error message for user
            }
        }
        .padding() // Padding around the content
        .transition(.slide) // Transition effect for view changes
    }
}

// MARK: - RemoveTOTPSheet

/// A SwiftUI view for managing the process of removing Time-based One-Time Password (TOTP) authentication.
/// It handles user input for password verification and attempts to disable TOTP.
fileprivate struct RemoveTOTPSheet: View {
    @EnvironmentObject var viewState: ViewState // The current application state
    @Binding var showSheet: Bool // Binding to control the visibility of the sheet
    @State var errorOccurred = false // Flag indicating if an error occurred during the removal process
    
    /// Removes the TOTP for the user after verifying with the provided MFA ticket.
    /// - Parameter ticket: The MFA ticket response needed for disabling TOTP.
    func removeTOTP(ticket: MFATicketResponse) {
        Task {
            do {
                print(try await viewState.http.disableTOTP(mfaToken: ticket.token).get()) // Attempt to disable TOTP
                showSheet = false // Close the sheet upon success
            } catch {
                let error = error as! RevoltError // Cast the error to RevoltError
                SentrySDK.capture(error: error) // Capture the error for reporting
                
                withAnimation {
                    errorOccurred = true // Indicate that an error occurred
                }
            }
        }
    }
    
    /// The body of the view defining its layout and behavior.
    var body: some View {
        VStack {
            // View for entering the password to confirm removal of TOTP
            CreateMFATicketView(requestTicketType: .Password, doneCallback: removeTOTP)
            if errorOccurred {
                Spacer()
                    .frame(maxHeight: 10)
                Text("Something went wrong. Try again later?") // Error message for user
                    .foregroundStyle(.red) // Style the error message
            }
        }
        .padding() // Padding around the content
    }
}





// MARK: - DisableAccountSheet

/// A SwiftUI view for disabling a user’s account.
/// It prompts the user for confirmation before proceeding with the account deactivation.
fileprivate struct DisableAccountSheet: View {
    @EnvironmentObject var viewState: ViewState // The current application state
    @Binding var showSheet: Bool // Binding to control the visibility of the sheet
    @State var ticket: MFATicketResponse? = nil // The MFA ticket response for account deactivation
    @State var errorOccurred = false // Flag to indicate if an error occurred during deactivation
    @State var presentConfirmationDialog = false // Flag to control the display of the confirmation dialog
    
    /// Receives the MFA ticket response and updates the state.
    /// - Parameter ticket: The MFA ticket response needed for account deactivation.
    func receiveTicket(ticket: MFATicketResponse) {
        withAnimation {
            self.ticket = ticket // Store the received ticket
        }
    }
    
    /// Deactivates the account by calling the appropriate API endpoint.
    func deactivateAccount() {
        Task {
            do {
                _ = try await viewState.http.disableAccount(mfaToken: ticket!.token).get() // Attempt to disable account
            } catch {
                SentrySDK.capture(error: error) // Capture any errors for reporting
                
                withAnimation {
                    errorOccurred = true // Indicate that an error occurred
                }
                return
            }
            
            viewState.ws?.stop() // Stop the WebSocket connection
            showSheet = false // Close the sheet
            
            withAnimation {
                viewState.state = .signedOut // Update the application state to signed out
            }
        }
    }
    
    var body: some View {
        if ticket == nil {
            // View for entering the password to receive the MFA ticket
            CreateMFATicketView(requestTicketType: .Password, doneCallback: receiveTicket)
                .transition(.slideNext)
        } else {
            VStack {
                Text("Wait a minute!") // Title for the confirmation prompt
                    .font(.title)
                Text("Are you sure you want to disable your account?") // Prompt message
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Spacer()
                    .frame(maxHeight: 10)
                Text("This will prevent you from being able to sign in. You'll need to message support to get your account reactivated.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                // Button to confirm account deactivation
                Button(role: .destructive, action: {
                    presentConfirmationDialog = true // Show confirmation dialog
                }) {
                    Text("Do it") // Button text
                }
                .padding(.vertical, 10)
                .frame(width: 250.0) // Set button width
                .foregroundStyle(viewState.theme.foreground) // Button text color
                .background(viewState.theme.background2) // Button background color
                .clipShape(.rect(cornerRadius: 50)) // Rounded corners for button
                
                Spacer()
                    .frame(maxHeight: 10)
                
                // Button to cancel and go back
                Button(role: .cancel, action: {
                    showSheet = false // Close the sheet
                }) {
                    Text("Go back") // Button text
                }
                .padding(.vertical, 10)
                .frame(width: 250.0) // Set button width
                .foregroundStyle(viewState.theme.foreground) // Button text color
                .background(viewState.theme.background2) // Button background color
                .clipShape(.rect(cornerRadius: 50)) // Rounded corners for button
            }
            .confirmationDialog("Confirm disabling your account", isPresented: $presentConfirmationDialog) {
                // Confirmation dialog for account deactivation
                Button("Confirm", role: .destructive) {
                    deactivateAccount() // Deactivate account on confirmation
                }
            }
            .transition(.slideNext) // Transition effect for view changes
            
            // Error message if deactivation fails
            if errorOccurred {
                Spacer()
                    .frame(maxHeight: 10)
                Text("Something went wrong. Try again later?") // Error message
                    .foregroundStyle(.red) // Style the error message
            }
        }
    }
}



import SwiftUI

/// A view that prompts the user for confirmation to delete their account.
///
/// This view handles the entire process of account deletion, including displaying a confirmation dialog,
/// managing the multi-factor authentication (MFA) ticket required for secure deletion, and handling any
/// errors that might occur during the account deletion process.
///
/// - Parameters:
///   - showSheet: A binding Boolean value indicating whether the sheet should be presented or dismissed.
///   - viewState: An environment object containing the application's current state, including user settings
///                and web socket connections.
fileprivate struct DeleteAccountSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var showSheet: Bool
    @State var ticket: MFATicketResponse? = nil
    @State var errorOccurred = false
    @State var presentConfirmationDialog = false
    
    /// Receives the MFA ticket response from the multi-factor authentication process.
    ///
    /// - Parameter ticket: The multi-factor authentication ticket received upon successful verification.
    func receiveTicket(ticket: MFATicketResponse) {
        withAnimation {
            self.ticket = ticket
        }
    }
    
    /// Deletes the user's account after confirming the deletion with the user.
    ///
    /// This method performs the asynchronous account deletion process and handles any potential errors,
    /// updating the UI accordingly. If successful, the user's state is set to `signedOut`.
    func deleteAccount() {
        Task {
            do {
                _ = try await viewState.http.deleteAccount(mfaToken: ticket!.token).get()
            } catch {
                SentrySDK.capture(error: error)
                
                withAnimation {
                    errorOccurred = true
                }
                return
            }
            
            viewState.ws?.stop()
            showSheet = false
            
            withAnimation {
                viewState.state = .signedOut
            }
        }
    }
    
    var body: some View {
        if ticket == nil {
            CreateMFATicketView(requestTicketType: .Password, doneCallback: receiveTicket)
                .transition(.slideNext)
        } else {
            VStack {
                Text("Stop right there!")
                    .font(.title)
                Text("Are you sure you want to delete your account?")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Spacer()
                    .frame(maxHeight: 10)
                Text("Your account will be disabled, and may be reactivated by opening a support request. After a week, it will be permanently deleted.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                Button(role: .destructive, action: {
                    presentConfirmationDialog = true
                }) {
                    Text("Do it")
                }
                .padding(.vertical, 10)
                .frame(width: 250.0)
                .foregroundStyle(viewState.theme.foreground)
                .background(viewState.theme.background2)
                .clipShape(.rect(cornerRadius: 50))
                
                Spacer()
                    .frame(maxHeight: 10)
                
                Button(role: .cancel, action: {
                    showSheet = false
                }) {
                    Text("Go back")
                }
                .padding(.vertical, 10)
                .frame(width: 250.0)
                .foregroundStyle(viewState.theme.foreground)
                .background(viewState.theme.background2)
                .clipShape(.rect(cornerRadius: 50))
            }
            .confirmationDialog("Confirm deleting your account", isPresented: $presentConfirmationDialog) {
                Button("Confirm", role: .destructive) {
                    deleteAccount()
                }
            }
            .transition(.slideNext)
            
            if errorOccurred {
                Spacer()
                    .frame(maxHeight: 10)
                Text("Something went wrong. Try again later?")
                    .foregroundStyle(.red)
            }
        }
    }
}

/// A view that presents the user's account settings and allows modification of user information.
///
/// This view contains multiple settings options, including changing the username, email, password,
/// and managing two-factor authentication. Each setting action presents a corresponding sheet for user input.
///
/// - Parameters:
///   - viewState: An environment object containing the application's current state and user settings.
struct UserSettings: View {
    @EnvironmentObject var viewState: ViewState
    
    // State variables to manage the presentation of different sheets
    @State var presentGenerateCodesSheet = false
    @State var GenerateCodeSheetIsNotDismissable = false
    @State var presentAddTOTPSheet = false
    @State var presentRemoveTOTPSheet = false
    @State var presentChangeUsernameSheet = false
    @State var presentChangeEmailSheet = false
    @State var presentChangePasswordSheet = false
    @State var presentDisableAccountSheet = false
    @State var presentDeleteAccountSheet = false
    
    @State var emailSubstitute = ""
    
    /// Substitutes parts of the email for privacy purposes.
    ///
    /// The email address is masked by replacing the characters with dots for each part of the email,
    /// preserving privacy while displaying a placeholder format.
    ///
    /// - Parameter email: The original email address to be masked.
    /// - Returns: A masked version of the email address.
    func substituteEmail(_ email: String) -> String {
        let groups = try! /(?<addr>[^@]+)\@(?<url>[^.]+)\.(?<domain>.+)/.wholeMatch(in: email)
        guard let groups = groups else { return "loading@loading.com" }
        
        // Create masked parts
        let m1 = String(repeating: "•", count: groups.output.addr.count)
        let m2 = String(repeating: "•", count: groups.output.url.count)
        let m3 = String(repeating: "•", count: groups.output.domain.count)
        let resp = "\(m1)@\(m2).\(m3)"
        emailSubstitute = resp
        return resp
    }
    
    
    var blockedUsers: [Types.User] {
        return viewState.users.values.filter { $0.relationship == .Blocked }
    }
    
    var body: some View {
        
        
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Account")){_,_ in
            
            let currentUser = viewState.currentUser!
            
            
            VStack(spacing: .zero){
                Group {
                    
                    
                    PeptideSectionHeader(title: "Account Information")
                    
                    VStack(spacing: .spacing4){
                        
                        /*
                         
                         Button(action: {
                         presentChangeUsernameSheet = true
                         }) {
                         HStack {
                         Text("Username")
                         Spacer()
                         if viewState.userSettingsStore.cache.user != nil {
                         Text(verbatim: "\(viewState.userSettingsStore.cache.user!.username)#\(viewState.userSettingsStore.cache.user!.discriminator)")
                         } else {
                         Text("")
                         }
                         }
                         }
                         
                         
                         */
                        
                        Button{
                            
                            self.viewState.path.append(NavigationDestination.username_view)
                            
                        } label: {
                            PeptideActionButton(icon: .peptideAt,
                                                title: "Username",
                                                value: "\(currentUser.username)#\(currentUser.discriminator)",
                                                valueStyle: .peptideBody4,
                                                valueColor: .textGray07,
                                                arrowColor: .iconGray07,
                                                hasArrow: true)
                        }
                        
                        PeptideDivider()
                            .padding(.leading, .padding48)
                        
                        
                        /*Button(action: {
                         presentChangeEmailSheet = true
                         }) {
                         HStack {
                         Text("Email")
                         Spacer()
                         Text(verbatim: emailSubstitute)
                         .onChange(of: viewState.userSettingsStore.cache.accountData?.email, { _, value in
                         let raw = viewState.userSettingsStore.cache.accountData?.email
                         guard let raw = raw else { return }
                         _ = substituteEmail(raw)
                         })
                         }
                         }*/
                        
                        Button{
                            
                            self.viewState.path.append(NavigationDestination.change_email_view)
                            
                        } label: {
                            PeptideActionButton(icon: .peptideMail,
                                                title: "Email",
                                                value: emailSubstitute,
                                                valueStyle: .peptideBody4,
                                                valueColor: .textGray07,
                                                arrowColor: .iconGray07,
                                                hasArrow: true)
                        }
                        
                        
                        PeptideDivider()
                            .padding(.leading, .padding48)
                        
                        
                        Button {
                            copyText(text: currentUser.id)
                            viewState.showAlert(message: "User Identifier Copied!", icon: .peptideDoneCircle)
                        } label: {
                            
                            PeptideActionButton(icon: .peptideRoleIdCard,
                                                title: "User Identifier",
                                                value: currentUser.id,
                                                valueStyle: .peptideBody4,
                                                valueColor: .textGray07,
                                                arrowColor: .iconGray07, arrowIcon: .peptideCopy,
                                                hasArrow: true)
                        }
                        
                        
                        
                    }
                    .backgroundGray11(verticalPadding: .padding4)
                }
                .padding(.horizontal, .padding16)
                
                
                
                Group {
                    
                    
                    PeptideSectionHeader(title: "Account Security")

                    
                    VStack(spacing: .spacing4){
                        
                        Button{
                            
                            self.viewState.path.append(NavigationDestination.change_password_view)
                            
                        } label: {
                            PeptideActionButton(icon: .peptideKey,
                                                title: "Password",
                                                arrowColor: .iconGray07,
                                                hasArrow: true)
                        }
                        
                        if viewState.userSettingsStore.cache.accountData?.mfaStatus == nil {
                            /*Text("Loading Data...", comment: "User settings notice - still fetching data")*/
                        } else {
                            
                            PeptideDivider()
                                .padding(.leading, .padding48)
                            
                            /*if !viewState.userSettingsStore.cache.accountData!.mfaStatus.anyMFA {
                             Text("You have not enabled two-factor authentication!", comment: "User settings info notice")
                             .font(.callout)
                             }*/
                            
                            
                            /*
                             
                             presentGenerateCodesSheet = true
                             
                             */
                        
                            let isActiveRecoveryCodes = viewState.userSettingsStore.cache.accountData!.mfaStatus.recovery_active
                            
                            Button(
                                action:{
                                    viewState.path.append(NavigationDestination.validate_password_view(.recoveryCode(!isActiveRecoveryCodes)))
                                },
                                label: {
                                
                                    PeptideActionButton(icon: .peptideList,
                                                        title: "Recovery Codes",
                                                        arrowColor: .iconGray07,
                                                        hasArrow: true)
                                    
                                    
                                    
                                }
                            )
                                
                            PeptideDivider()
                                .padding(.leading, .padding48)
                            
                            /*if !viewState.userSettingsStore.cache.accountData!.mfaStatus.totp_mfa {
                             Button(action: {
                             presentAddTOTPSheet = true
                             }, label: {
                             Text("Add Authenticator", comment: "User settings button")
                             })
                             } else {
                             Button(action: {
                             presentRemoveTOTPSheet = true
                             }, label: {
                             Text("Remove Authenticator", comment: "User settings button")
                             })
                             }*/
                            
                            let isActiveAuthenticator = viewState.userSettingsStore.cache.accountData!.mfaStatus.totp_mfa
                            
                                                        
                            Button(action: {
                                if (isActiveRecoveryCodes){
                                    if isActiveAuthenticator {
                                        presentRemoveTOTPSheet = true
                                    } else {
                                        viewState.path.append(NavigationDestination.validate_password_view(.authenticatorApp))
                                    }
                                }
                            }, label: {
                                
                                PeptideActionButton(
                                    icon: .peptideLock,
                                    iconColor: isActiveRecoveryCodes ? .iconDefaultGray01 : .iconGray07,
                                    title: "Authenticator App",
                                    titleColor: isActiveRecoveryCodes ? .textDefaultGray01 : .textGray07,
                                    arrowColor: isActiveRecoveryCodes ? .iconDefaultGray01 : .iconGray07,
                                    hasArrow: !isActiveAuthenticator,
                                    hasToggle: isActiveAuthenticator,
                                    onToggle: { _ in
                                        if (isActiveRecoveryCodes){
                                            if isActiveAuthenticator {
                                                presentRemoveTOTPSheet = true
                                            } else {
                                                viewState.path.append(NavigationDestination.validate_password_view(.authenticatorApp))
                                            }
                                        }
                                    }
                                )
                                
                            })
                            
//                            let isActiveToto = viewState.userSettingsStore.cache.accountData!.mfaStatus.totp_mfa
//                            
//                            
//                            Button(action: {
//                                if isActiveToto {
//                                    presentRemoveTOTPSheet = true
//                                } else {
//                                    presentAddTOTPSheet = true
//                                }
//                            }, label: {
//                                
//                                
//                                let authLabel = isActiveToto ? "Remove Authenticator" : "Add Authenticator"
//                                
//                                PeptideActionButton(icon: .peptideLock,
//                                                    title: authLabel,
//                                                    arrowColor: .iconGray07,
//                                                    hasArrow: true)
//                                
//                            })
                            
                            
                            
                        }
                        
                        
                    }
                    .backgroundGray11(verticalPadding: .padding4)
                }
                .padding(.horizontal, .padding16)
                
                
                /*Section("Account Management") {
                 Button(action: {
                 presentDisableAccountSheet = true
                 }, label: {
                 Text("Disable Account", comment: "User settings button")
                 .foregroundStyle(.red)
                 })
                 
                 Button(action: {
                 presentDeleteAccountSheet = true
                 }, label: {
                 Text("Delete Account", comment: "User settings button")
                 .foregroundStyle(.red)
                 })
                 }
                 .listRowBackground(viewState.theme.background2)*/
                
                
                
                Group {
                    
                    PeptideSectionHeader(title: "Users")
                    
                    VStack(spacing: .spacing4){
                        
                        
                        
                        Button(action: {
                            viewState.path.append(NavigationDestination.blocked_users_view)
                        }, label: {
                            
                            PeptideActionButton(icon: .peptideCancelFriendRequest,
                                                title: "Blocked User",
                                                value: "\(blockedUsers.count)",
                                                valueStyle: .peptideBody4,
                                                valueColor: .textGray07,
                                                arrowColor: .iconGray07,
                                                hasArrow: true)
                            
                        })
                    
                        
                    }
                    .backgroundGray11(verticalPadding: .padding4)

                    
                }
                .padding(.horizontal, .padding16)

            
            
            Spacer(minLength: .zero)
        }
        
        
        
        
        
        
    }
    /*.refreshable {
     await viewState.userSettingsStore.fetchFromApi()
     }*/
        .onAppear {
            let raw = viewState.userSettingsStore.cache.accountData?.email
            guard let raw = raw else {
                Task {
                    await viewState.userSettingsStore.fetchFromApi()
                }
                return
            }
            emailSubstitute = /*substituteEmail*/(raw)
        }
        /*.sheet(isPresented: $presentGenerateCodesSheet, onDismiss: {
            Task {
                await viewState.userSettingsStore.fetchFromApi()
            }
        }) {
            SettingsSheetContainer(showSheet: $presentGenerateCodesSheet) {
                GenerateRecoveryCodesSheet(showSheet: $presentGenerateCodesSheet, sheetIsNotDismissable: $GenerateCodeSheetIsNotDismissable)
            }
            .presentationBackground(viewState.theme.background)
            .interactiveDismissDisabled(GenerateCodeSheetIsNotDismissable)
        }*/
        .sheet(isPresented: $presentAddTOTPSheet, onDismiss: {
            Task {
                await viewState.userSettingsStore.fetchFromApi()
            }
        }) {
            SettingsSheetContainer(showSheet: $presentAddTOTPSheet) {
                AddTOTPSheet(showSheet: $presentAddTOTPSheet)
            }
            .presentationBackground(viewState.theme.background)
        }
        .sheet(isPresented: $presentRemoveTOTPSheet) {
            RemoveAuthenticatorAppSheet(isPresented: $presentRemoveTOTPSheet, step: .none, ticket: .constant(""), methods: .constant([ "Totp", "Recovery"]))

        }
        /*.sheet(isPresented: $presentChangeUsernameSheet, onDismiss: {
            Task {
                await viewState.userSettingsStore.fetchFromApi()
            }
        }) {
            SettingsSheetContainer(showSheet: $presentChangeUsernameSheet) {
                UsernameUpdateSheet(viewState: viewState, showSheet: $presentChangeUsernameSheet)
            }
            .presentationBackground(viewState.theme.background)
        }*/
        /*.sheet(isPresented: $presentChangePasswordSheet) {
            SettingsSheetContainer(showSheet: $presentChangePasswordSheet) {
                PasswordUpdateSheet(showSheet: $presentChangePasswordSheet)
            }
            .presentationBackground(viewState.theme.background)
        }*/
        .sheet(isPresented: $presentDisableAccountSheet) {
            SettingsSheetContainer(showSheet: $presentDisableAccountSheet) {
                DisableAccountSheet(showSheet: $presentDisableAccountSheet)
            }
            .presentationBackground(viewState.theme.background)
        }
        .sheet(isPresented: $presentDeleteAccountSheet) {
            SettingsSheetContainer(showSheet: $presentDeleteAccountSheet) {
                DeleteAccountSheet(showSheet: $presentDeleteAccountSheet)
            }
            .presentationBackground(viewState.theme.background)
        }
}
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    UserSettings()
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}



