//
//  Welcome.swift
//  Revolt
//
//  Created by Angelo Manca on 2023-11-15.
//

import SwiftUI
import Types
import NavigationTransitions

/// A view that presents a welcome screen for the application, offering options to log in or sign up.
struct Welcome: View {
    
    @EnvironmentObject var viewState: ViewState // Shared application state.
    @State private var path = NavigationPath() // Navigation path for the view.
    @State private var mfaTicket = "" // Ticket for multi-factor authentication.
    @State private var mfaMethods: [String] = [] // Array to store MFA methods.
    @Binding var wasSignedOut: Bool // Binding to indicate if the user was signed out.
    
    @State private var isIntroDisplayed : Bool = true
    
    @Environment(\.colorScheme) var colorScheme: ColorScheme // Determines the current color scheme (light or dark).
    
    var body: some View {
        
        
        if isIntroDisplayed {
            
            IntroScreen(isIntroDisplayed: $isIntroDisplayed)
                .animation(.easeInOut(duration: 1.0), value: isIntroDisplayed)
                .transition(.opacity)
            
        } else {
            NavigationStack(path: $path) { // Navigation stack for managing view transitions.
                
                PeptideTemplateView(
                    toolbarConfig: .init(
                        isVisible: true,
                        onClickBackButton: {
                            withAnimation{
                                isIntroDisplayed.toggle()
                            }
                        },
                        showBottomLine: false
                    )
                ){_,_   in
                    
                    //ZStack {
                    // Display logged out message if the user has been signed out.
                    /*if wasSignedOut {
                     VStack(spacing: .zero) {
                     Spacer()
                     .frame(height: 25)
                     Text("You have been logged out")
                     .padding(.horizontal, 25)
                     .padding(.vertical, 10)
                     .foregroundStyle(.white)
                     .background(Color(hue: 0, saturation: 95, brightness: 25))
                     .addBorder(.red, cornerRadius: 8)
                     Spacer()
                     }
                     .transition(.slideTop)
                     .onAppear {
                     DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                     withAnimation {
                     wasSignedOut = false
                     }
                     }
                     }
                     }*/
                    
                    // Main content of the Welcome view.
                    VStack(spacing: .zero) {
                        
                        // Group containing the welcome image and introductory texts.
                        Group {
                            
                            //Spacer()
                            
                            Image(.peptideWelcome)
                                .padding(.vertical, .size52)
                            
                           //Spacer()

                            
                            PeptideText(text: "Welcome to PepChat!",
                                        font: .peptideTitle1,
                                        textColor: .textDefaultGray01,
                                        alignment: .center)
                            .padding(.bottom, .size4)
                            
                            
                            PeptideText(text: "join-endless",
                                        font: .peptideBody3,
                                        textColor: .textGray06)
                            .padding(.horizontal, .padding24)
                            
                        }
                        
                        
                        // Group for navigation buttons.
                        Group {
                            // Navigation link to Log In view.
                            /*NavigationLink("Log In", value: WelcomeNavigationType.login)
                             .padding(.vertical, 10)
                             .frame(width: 200.0)
                             .background((colorScheme == .light) ? Color.black : Color.white)
                             .foregroundColor((colorScheme == .light) ? Color.white : Color.black)
                             .cornerRadius(50)*/
                            
                            
                            PeptideButton(title: "register"){
                                self.path.append(WelcomePath.signup)
                            }
                            .padding(top: .padding32, bottom: .padding12)
                            
                            // Navigation link to Sign Up view.
                            /*NavigationLink("Sign Up", value: WelcomeNavigationType.signup)
                             .padding(.vertical, 10)
                             .frame(width: 200.0)
                             .foregroundColor(.black)
                             .background((colorScheme == .light) ? Color(white: 0.851) : Color(white: 0.4))
                             .cornerRadius(50)*/
                            
                            PeptideButton(title: "Log In",
                                          bgColor: .bgPurple10,
                                          contentColor: .textDefaultGray01){
                                self.path.append(WelcomePath.login)
                            }
                        }
                        
                        //Spacer()
                        
                        // Group containing legal links.
                        /*Group {
                         // Links to Terms of Service, Privacy Policy, and Community Guidelines.
                         Link("Terms of Service", destination: URL(string: "https://revolt.chat/terms")!)
                         .font(.footnote)
                         .foregroundColor(Color(white: 0.584))
                         Link("Privacy Policy", destination: URL(string: "https://revolt.chat/privacy")!)
                         .font(.footnote)
                         .foregroundColor(Color(white: 0.584))
                         Link("Community Guidelines", destination: URL(string: "https://revolt.chat/aup")!)
                         .font(.footnote)
                         .foregroundColor(Color(white: 0.584))
                         }*/
                        
                        // Navigation links for additional actions.
                        /*NavigationLink("Resend a verification email", destination: { ResendEmail() })
                         .padding(15)*/
                        
                        
                        
                        HStack(spacing: .size4){
                            
                            PeptideText(text: "Didn’t-receive-an-email",
                                        font: .peptideCallout,
                                        textColor: .textGray06)
                            
                            NavigationLink("resend-verification", value: WelcomePath.resendEmail)
                                .font(.peptideButtonFont)
                                .foregroundStyle(.textYellow07)
                            
                        }
                        .padding(top: .padding24, bottom: .padding32)
                        
                        //Spacer()
                        
                        
                    }
                    .padding(.horizontal, .padding16)
                    // Navigation destination based on string identifiers.
                    .navigationDestination(for: WelcomePath.self) { dest in
                        switch dest {
                        case .mfa:
                            Mfa(path: $path, ticket: $mfaTicket, methods: $mfaMethods) // Multi-factor authentication view.
                        case .login:
                            LogIn(path: $path, mfaTicket: $mfaTicket, mfaMethods: $mfaMethods) // Log In view.
                        case .signup:
                            CreateAccount(path: $path, mfaTicket: $mfaTicket, mfaMethods: $mfaMethods) // Sign Up view.
                        case .nameYourSelf:
                            NameYourSelf()
                        case .resendEmail:
                            ResendEmail( path: $path)
                        case .forgetPassword:
                            ForgotPassword(path: $path)
                            
                        }
                    }
                    .animation(.easeInOut(duration: 1.0), value: isIntroDisplayed)
                    .transition(.opacity)
                    .onAppear {
                        //viewState.isOnboarding = false // Set onboarding state to false when the view appears.
                    }
                   
                }
            }
            .navigationTransition(.fade(.in))
            .task {
                debugPrint("fetchApiInfo")
                // Fetch API information asynchronously when the view appears.
                viewState.setBaseUrlToHttp()
                viewState.apiInfo = try? await viewState.http.fetchApiInfo().get()
            }
        }
        
    }
}


enum WelcomePath : Hashable {
    case mfa
    case login
    case signup
    case nameYourSelf
    case resendEmail
    case forgetPassword
}


// Preview for SwiftUI canvas.
#Preview {
    Welcome(wasSignedOut: .constant(true)) // Preview with user signed out.
        .environmentObject(ViewState.preview()) // Provide preview environment object.
        .preferredColorScheme(.dark)
}
