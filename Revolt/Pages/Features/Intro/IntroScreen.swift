//
//  IntroScreen.swift
//  Revolt
//
//

import SwiftUI

struct IntroScreen: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isIntroDisplayed : Bool
    
    @State var baseUrl : String = ""
    @State var urlEdtStatus : PeptideTextFieldState = .default
    @State var confirmButtonStatus : ComponentState = .disabled
    
    
    @ViewBuilder
    private func introBody(scrollViewProxy: ScrollViewProxy,
                           keyboardVisibility : Binding<Bool>) -> some View {
        
        VStack(spacing: .zero){
            
            Image(.peptideIntro)
                .padding(top: .padding8, bottom: .padding32)
            
            
            PeptideText(text: "Welcome to PepChat!",
                        font: .peptideTitle1,
                        textColor: .textDefaultGray01,
                        alignment: .center)
            .padding(bottom: .padding4)
            
            PeptideText(text: "Choose your preferred platform!",
                        font: .peptideBody3,
                        textColor: .textGray06,
                        alignment: .center)
            .padding(.horizontal, .padding24)
            
            HStack(spacing: .spacing24){
                IntroPlatformView(platformName: "PepChat",
                                  platformImage: .peptidePlatform,
                                  url: "https://peptide.chat/api"){
                    baseUrl = $0
                }
                
                IntroPlatformView(platformName: "Revolt",
                                  platformImage: .peptideRevolt,
                                  url: "https://app.revolt.chat/api"){
                    baseUrl = $0
                }
                
            }
            .padding(.vertical, .padding32)
            
            PeptideTextField(text: $baseUrl,
                             state: $urlEdtStatus,
                             placeholder: "Enter custom API url...",
                             icon: .connected,
                             hasSecureBtn: false,
                             hasClearBtn: false,
                             keyboardType: .URL)
            .padding(bottom: .padding32)
            .onChange(of: baseUrl){_,_ in
                withAnimation{
                    onChangedUrl()
                }
            }
            .onChange(of: keyboardVisibility.wrappedValue) { oldState,  newState in
                if newState  {
                    withAnimation{
                        scrollViewProxy.scrollTo("confirm-btn", anchor: .bottom)
                    }
                    
                }
            }
            
            PeptideButton(title: "Confirm",
                          buttonState: confirmButtonStatus){
                onClickConfirm()
            }
                          .padding(bottom: .size24)
                          .id("confirm-btn")
            
            
        }
        .padding(.horizontal, .padding16)
        
    }
    
    private func onChangedUrl() {
        
        urlEdtStatus = .default
        
        if baseUrl.isEmpty {
            confirmButtonStatus = .disabled
        } else {
            confirmButtonStatus = .default
        }
    }
    
    
    private func onClickConfirm() {
        if baseUrl.isValidURL {
            hideKeyboard()
            viewState.baseURL = baseUrl
            isIntroDisplayed.toggle()
        } else {
            urlEdtStatus = .error(message: "Your entered API url not correct!", icon: .peptideClose)
        }
    }
    
    
    var body: some View {
        PeptideTemplateView(
        ){ scrollViewProxy, keyboardVisibility  in
            
            VStack(spacing: .zero){
                
                LazyVStack(pinnedViews: .sectionHeaders){
                    
                    Section {
                        introBody(scrollViewProxy: scrollViewProxy,
                                  keyboardVisibility: keyboardVisibility)
                    } header: {
                        introHeader
                    }
                    
                }
                
                Spacer()
                
                PeptideText(text: "PepChat v\(Bundle.main.releaseVersionNumber)",
                            font: .peptideFootnote,
                            textColor: .textGray06,
                            alignment: .center)
                .padding(.bottom, .padding28)
                
                
                
            }
            
        }
        /*.navigationDestination(for: IntroPath.self){_ in
            Welcome(wasSignedOut: $wasSignedOut)
        }
        .onChange(of: viewModel.isNavigationTriggered){_, _ in
            if viewModel.path == .welcome {
                viewState.baseURL = viewModel.state.baseUrl
                viewState.path.append(viewModel.path)
            }
        }*/
        
    }
}



#Preview {
    IntroScreen(isIntroDisplayed: .constant(true))
}
