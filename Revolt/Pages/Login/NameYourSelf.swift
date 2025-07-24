//
//  NameYourSelf.swift
//  Revolt
//
//

import SwiftUI
import SwiftUITooltip

struct NameYourSelf: View {
    
    @EnvironmentObject var viewState: ViewState // Shared state for managing the app's state.

    
    @State private var username : String = ""
    @State private var usernameTextFieldStatus : PeptideTextFieldState = .default
    @State private var completeBtnState : ComponentState = .disabled
    @State var errorMessage: String? = nil

    
    private var imageSize : CGSize = UIImage(resource: .peptideNameYourSelf).size
    
    @State private var imageScale : CGFloat = 1.0
    @State private var isShowingPopover = false
    @State private var sheetHeight: CGFloat = .zero
    
    
    var body: some View {
        
        PeptideTemplateView(
            toolbarConfig: .init(
                isVisible: true,
                backButtonIcon: .peptideCloseLiner
            ) ){_,_   in
                
                VStack(spacing: .zero){
                    
                    
                    Image(.peptideNameYourSelf)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageSize.width * imageScale,
                               height: imageSize.height * imageScale)
                        .clipped()
                        .padding(.top, .size16)
                    
                    
                    PeptideText(text: "Name Yourself!",
                                font: .peptideTitle1)
                    .padding(.top, .padding32)
                    
                    
                    PeptideText(text: "It's time to choose a username.",
                                font: .peptideBody3,
                                textColor: .textGray06)
                    .offset(y: -1 * .size4)
                    
                    
                    HStack(spacing: .size8){
                        
                        PeptideText(text: "Others can find, recognize, and mention you with this name; choose wisely!",
                                    font: .peptideSubhead,
                                    textColor: .textGray06,
                                    alignment: .leading)
                        
                        Spacer(minLength: .zero)
                        
                        PeptideIconButton(icon: .peptideInfo2,
                                          color: .iconGray04){
                            self.isShowingPopover.toggle()
                        }
                         .popover(isPresented: $isShowingPopover,
                                  arrowEdge: .bottom){
                          Text("You can change it anytime in User Settings. You’ll get a unique number tag, visible in Settings.")
                              .padding(.horizontal, .size4)
                              .font(.peptideCaption1Font)
                              .foregroundStyle(.textDefaultGray01)
                              .presentationBackground{
                                  Color.bgGray11
                              }
                              .presentationCompactAdaptation(.popover)
                      }
                        
                        
                        
                    }
                    
                    .padding(top: .padding32, bottom: .padding4, leading: .padding8, trailing: .padding8)
                    
                    
                    PeptideTextField(text: self.$username,
                                     state: $usernameTextFieldStatus,
                                     placeholder: "Username",
                                     onChangeFocuseState: { isFocus in
                        withAnimation{
                            imageScale = isFocus ? 0.4 : 1.0
                        }
                    })
                    .onChange(of: username){ oldValue, newValue in
                        if newValue.isEmpty {
                            completeBtnState = .disabled
                        } else {
                            completeBtnState = .default
                        }
                    }
                    
                    PeptideButton(title: "Complete Registration",
                                  buttonState: completeBtnState){
                        
                        if username.isEmpty {
                            withAnimation {
                                errorMessage = "Please enter a username"
                                usernameTextFieldStatus = .error(message: "Please enter a username")
                            }
                            return
                        }
                        errorMessage = nil
                        
                        withAnimation{
                            usernameTextFieldStatus = .disabled
                            completeBtnState = .loading
                        }
                        
                        /*withAnimation {
                            //isWaitingWithSpinner = true // Show spinner while waiting for username submission.
                        }*/
                        Task {
                            do {
                                _ = try await viewState.http.completeOnboarding(username: username).get()
                            } catch {
                                withAnimation {
                                    //isWaitingWithSpinner = false
                                    //errorMessage = "Invalid Username, try something else"
                                    usernameTextFieldStatus = .error(message: "Invalid Username, try something else")
                                    completeBtnState = .default
                                }
                                return
                            }
                            
                            Task {
                                
                                try! await Task.sleep(for: .seconds(2))
                                
                                usernameTextFieldStatus = .default
                                completeBtnState = .default
                                viewState.isOnboarding = false // Mark onboarding as complete.
                                viewState.state = .connecting
                            }
                    
                            
                        }
                        
                    }
                    .padding(.top, .padding32)
                    
                    
                    Spacer(minLength: .zero)
                    
                }
                .padding(.horizontal, .size16)
                
            }
            .fillMaxSize()
        
        
        
    }
    
}



#Preview {
    NameYourSelf()
}
