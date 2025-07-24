import SwiftUI
import Types

/// A view representing the login screen for the application.
struct LogIn: View {
    
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    
    
    @EnvironmentObject var viewState: ViewState // Access to the global view state for user session management.
    
    @Binding var path: NavigationPath // The navigation path for view transitions.
    
    
    @Binding public var mfaTicket: String // Binding for MFA ticket.
    @Binding public var mfaMethods: [String] // Binding for available MFA methods.
    
    @FocusState private var focus1: Bool // Focus state for email field.
    @FocusState private var focus2: Bool // Focus state for password field.
    
    @Environment(\.colorScheme) var colorScheme: ColorScheme // Access to the current color scheme (light/dark).
    
    
    @State var email = "" // State for storing user email input.
    @State var password = "" // State for storing user password input.
    @State var showPassword = false // State to toggle password visibility.
    @State var showMfa = false // State to indicate if MFA input should be shown.
    @State var errorMessage: String? = nil // State for error messages.
    @State var needsOnboarding = false // State to track if onboarding is required.
    
    
    
    @State var emailTextFieldStatus : PeptideTextFieldState = .default
    @State var passwordTextFieldStatus : PeptideTextFieldState = .default
    @State var loginBtnStatus : ComponentState = .disabled
    
    
    @State var showMfasMethodsSheet : Bool = false
    
    
    @State private var step : MfaSheetStep = .none
    
    /// Asynchronously logs in the user with the provided email and password.
    private func logIn() async {
        
        
        let inValidEmail = email.isValidEmail == false
        
        if inValidEmail {
            withAnimation {
                emailTextFieldStatus = .error(message: "Enter valid email.",
                                              icon: .peptideClose)
            }
            return
        }
        
        emailTextFieldStatus = .disabled
        passwordTextFieldStatus = .disabled
        
        loginBtnStatus = .loading
        
        await viewState.signIn(email: email, password: password, callback: { state in
            
            emailTextFieldStatus = .default
            passwordTextFieldStatus = .default
            loginBtnStatus = .default
            
            switch state {
            case .Mfa(let ticket, let methods): // Handle MFA response.
                self.mfaTicket = ticket // Store MFA ticket.
                self.mfaMethods = methods // Store available MFA methods.
                //self.path.append("mfa") // Navigate to MFA view.
                showMfasMethodsSheet.toggle()
                
                
            case .Disabled: // Handle disabled account case.
                emailTextFieldStatus = .error(message: "Account has been disabled.")
                self.errorMessage = "Account has been disabled."
                
            case .Success: // Successful login.
                path = NavigationPath() // Reset navigation path.
                
            case .Invalid: // Handle invalid login credentials.
                passwordTextFieldStatus = .error(message: "Invalid credentials")
                //self.errorMessage = "Invalid email and/or password."
                
            case .Onboarding: // Handle onboarding requirement.
                viewState.isOnboarding = true
                //self.needsOnboarding = true
                path.append(WelcomePath.nameYourSelf)
            }
        })
        
    }
    
    
    var customToolbarView: AnyView {
        AnyView(
            NavigationLink("Register", value: WelcomePath.signup)
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
                customToolbarView: customToolbarView
            )
        ){_,_   in
            
            VStack(spacing: .zero) {
                
                
                PeptideAuthHeaderView(imageResourceName: .peptideLogin,
                                      title: "welcome-back",
                                      subtitle: "great-to-see-you-again")
                
                
                
                Group {
                    
                    PeptideTextField(text: $email,
                                     state: $emailTextFieldStatus,
                                     placeholder: "Email",
                                     keyboardType: .emailAddress){ isFocus in
                        
                        if(!isFocus && email.isNotEmpty){
                            emailTextFieldStatus = email.isValidEmail == false ? .error(message: "Enter valid email.",
                                                                                        icon: .peptideClose) : .default
                        }
                        
                        
                    }
                    .padding(.top, .padding32)
                    .onChange(of: email){_,_ in
                        onChangeEmail()
                    }
                    
                    
                    PeptideTextField(text: $password,
                                     state: $passwordTextFieldStatus,
                                     isSecure: true,
                                     placeholder: "Password",
                                     hasSecureBtn: true,
                                     hasClearBtn: false
                    )
                    .padding(.top, .padding8)
                    .onChange(of: password){_,_ in
                        onChangePassword()
                    }
                    
                    
                    
                    
                    /*if let error = errorMessage { // Display error message if available.
                     Text(verbatim: error)
                     .foregroundStyle(.red)
                     }
                     
                     TextField("Email", text: $email) // TextField for email input.
                     #if os(iOS)
                     .keyboardType(.emailAddress) // Set keyboard type for email input.
                     #endif
                     .textContentType(.emailAddress)
                     .padding()
                     .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.2)) // Background color based on theme.
                     .clipShape(.rect(cornerRadius: 5))
                     .foregroundStyle((colorScheme == .light) ? Color.black : Color.white)
                     
                     ZStack(alignment: .trailing) { // ZStack to overlay password fields.
                     TextField("Password", text: $password) // TextField for password input.
                     .textContentType(.password)
                     .padding()
                     .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.2))
                     .clipShape(.rect(cornerRadius: 5))
                     .modifier(PasswordModifier())
                     .textContentType(.password)
                     .foregroundStyle((colorScheme == .light) ? Color.black : Color.white)
                     .opacity(showPassword ? 1 : 0) // Show or hide based on toggle.
                     .focused($focus1) // Bind focus to the email field.
                     
                     SecureField("Password", text: $password) // SecureField for password input.
                     .textContentType(.password)
                     .padding()
                     .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.2))
                     .clipShape(.rect(cornerRadius: 5))
                     .modifier(PasswordModifier())
                     .textContentType(.password)
                     .foregroundStyle((colorScheme == .light) ? Color.black : Color.white)
                     .opacity(showPassword ? 0 : 1) // Show or hide based on toggle.
                     .focused($focus2) // Bind focus to the password field.
                     
                     // Button to toggle password visibility.
                     Button(action: {
                     showPassword.toggle() // Toggle visibility.
                     if showPassword {
                     focus1 = true // Focus on email field if password is shown.
                     } else {
                     focus2 = true // Focus on password field if secure is shown.
                     }
                     }, label: {
                     Image(systemName: self.showPassword ? "eye.slash.fill" : "eye.fill") // Eye icon to indicate visibility state.
                     .font(.system(size: 16, weight: .regular))
                     .padding()
                     .foregroundColor(colorScheme == .light ? Color.black : Color.white)
                     })
                     }*/
                }
                
                HStack {
                    
                    NavigationLink("Forgot Password", value: WelcomePath.forgetPassword)
                        .font(.peptideButtonFont)
                        .foregroundStyle(.textYellow07)
                        .padding(.top, .padding12)
                    
                    Spacer(minLength: .zero)
                }
                
                
                
                //Spacer()
                
                // Button to initiate login.
                /*Button(action: { Task { await logIn() } }) {
                 Text("Log In") // Button label.
                 }
                 .padding(.vertical, 10)
                 .frame(width: 200.0)
                 .foregroundStyle(.black)
                 .background(Color(white: 0.851))
                 .clipShape(.rect(cornerRadius: 50))*/
                
                
                PeptideButton(title: "Log In",
                              buttonState: loginBtnStatus){
                    Task { await logIn() }
                }
                              .padding(.top, .padding32)
                
                // Navigation links for additional actions.
                /*NavigationLink("Resend a verification email", destination: { ResendEmail() })
                 .padding(15)*/
                
                
                
                Spacer()
            }
            .padding(.horizontal, .padding16)
            /*.navigationDestination(isPresented: $needsOnboarding) { // Navigate to onboarding if needed.
             CreateAccount(path: $path, mfaTicket: $mfaTicket, mfaMethods: $mfaMethods, onboardingStage: .Username)
             }*/
            .sheet(isPresented: $showMfasMethodsSheet){
                MfaSheet(path: $path, ticket: $mfaTicket, methods: $mfaMethods)
            }
            
        }
        
    }
    
    
    private func onChangeEmail(){
        emailTextFieldStatus = .default
        passwordTextFieldStatus = .default
        onChangeData()
    }
    
    private func onChangePassword(){
        emailTextFieldStatus = .default
        passwordTextFieldStatus = .default
        onChangeData()
    }
    
    private func onChangeData(){
        
        if email.isNotEmpty && password.isNotEmpty{
            loginBtnStatus = .default
        } else {
            loginBtnStatus = .disabled
        }
        
    }
}



/// A view modifier for password input fields.
struct PasswordModifier: ViewModifier {
    var borderColor: Color = Color.gray // Default border color.
    
    func body(content: Content) -> some View {
        content
            .disableAutocorrection(true) // Disable autocorrection for password input.
    }
}

// Preview for the LogIn view with sample data.
#Preview {
    LogIn(path: .constant(NavigationPath()), mfaTicket: .constant(""), mfaMethods: .constant([]))
        .environmentObject(ViewState.preview())
}
