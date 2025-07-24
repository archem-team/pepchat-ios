//
//  VerifyEmail.swift
//  Revolt
//
//

import SwiftUI
import Foundation


struct VerifyEmail : View {
    
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var path : NavigationPath
    var email : String
    var verifyEmailType : VerifyEmailType = .none
    
    var customToolbarView : AnyView {
        
        AnyView(
            NavigationLink("Log In", value: WelcomePath.login)
                .font(.peptideButtonFont)
                .foregroundStyle(.textDefaultGray01)
        )
    }
    
    var body: some View {
        
        PeptideTemplateView(
            
            toolbarConfig: .init(isVisible: true,
                                 onClickBackButton: {
                                     path = NavigationPath()
                                 }
//                                 ,customToolbarView: customToolbarView
                                )){_,_   in
                                     
                                     VStack(spacing: .zero){
                                         
                                         Image(.peptideEmail)
                                          .padding(top: .padding16, bottom: .padding4)
                                         
                                         let title = verifyEmailType == .none ? "verify-your-email" :  "Check Your Email"
                                         
                                         PeptideText(text: title,
                                                     font: .peptideTitle1)
                                         .padding(bottom: .padding4)
                                         
                                         
                                         PeptideText(text: LocalizedStringKey("we-sent-a-verification-mail-to \(email)"),
                                                     font: .peptideBody3,
                                                     textColor: .textGray06)
                                         .offset(y: -1 * .size4)
                                         
                                         
                                         Spacer()
                                             .frame(height: .padding32)
                                         
                                         if verifyEmailType == .forgetPassword {
                                             PeptideButton(title: "Reset Password"){
                                                 path.append(VerifyEmailPath.verifyResetPassword)
                                             }
                                             .padding(.bottom, .padding12)
                                         }
                                         
                                         
                                         PeptideButton(title: "Check Your Mail"){
                                             openMailApp()
                                         }
                                         
                                         
                                         HStack(spacing: .size4){
                                             
                                             PeptideText(text: "Didn’t-receive-an-email",
                                                         font: .peptideCallout,
                                                         textColor: .textGray06)
                                             
                                             NavigationLink("resend-verification", destination: { ResendEmail( path: $path) })
                                                 .font(.peptideButtonFont)
                                                 .foregroundStyle(.textYellow07)
                                             
                                         }
                                         .padding(.top, .padding32)
                                         
                                         Spacer(minLength: .zero)
                                         
                                         
                                     }
                                     .padding(.horizontal, .size16)
                                     
                                 }
                                 .navigationDestination(for: VerifyEmailPath.self){des in
                                     switch des {
                                     case .verifyResetPassword:
                                         ForgotPassword_Reset(path: $path, email: email)
                                         
                                     }
                                 }
        
    }
    
    func openMailApp() {
        if let mailURL = URL(string: "mailto:") {
            if UIApplication.shared.canOpenURL(mailURL) {
                UIApplication.shared.open(mailURL, options: [:], completionHandler: nil)
            } else {
                print("Mail app is not available.")
            }
        }
    }
}

enum VerifyEmailPath : Hashable {
    case verifyResetPassword
}

enum VerifyEmailType {
    case none
    case forgetPassword
    case resendVerification
}




#Preview {
    VerifyEmail(path: .constant(NavigationPath()), email: "noreply@peptide.chat", verifyEmailType: .forgetPassword)
        .environmentObject(ViewState.preview())
}

