//
//  IntroScreen.swift
//  Revolt
//
//

import SwiftUI

struct IntroScreen: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isIntroDisplayed : Bool
    
    @StateObject private var platformService = PlatformConfigService()
    @State var baseUrl : String = ""
    @State var urlEdtStatus : PeptideTextFieldState = .default
    @State var confirmButtonStatus : ComponentState = .disabled
    
    
    @ViewBuilder
    private func introBody(scrollViewProxy: ScrollViewProxy,
                           keyboardVisibility : Binding<Bool>) -> some View {
        
        VStack(spacing: .zero){
            
            Image(.peptideIntro)
                .padding(top: .padding8, bottom: .padding32)
            
            
            PeptideText(text: "Welcome to ZekoChat!",
                        font: .peptideTitle1,
                        textColor: .textDefaultGray01,
                        alignment: .center)
            .padding(bottom: .padding4)
            
            PeptideText(text: "Choose your preferred platform!",
                        font: .peptideBody3,
                        textColor: .textGray06,
                        alignment: .center)
            .padding(.horizontal, .padding24)
            
            VStack(spacing: .spacing8) {
                if platformService.isLoading {
                    ProgressView("Loading platforms...")
                        .frame(height: 100)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(platformService.platforms.count, 2)), spacing: .spacing24) {
                        ForEach(platformService.platforms) { platform in
                            IntroPlatformView(
                                platformName: platform.title,
                                imageURL: platform.image,
                                url: platform.url
                            ) {
                                baseUrl = $0
                            }
                        }
                    }
                    
                    if let error = platformService.error {
                        PeptideText(text: "Using default platforms (API error: \(error))",
                                    font: .peptideCaption1,
                                    textColor: .textGray06,
                                    alignment: .center)
                        .padding(.top, .padding8)
                    }
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
                
                PeptideText(text: "ZekoChat v\(Bundle.main.releaseVersionNumber)",
                            font: .peptideFootnote,
                            textColor: .textGray06,
                            alignment: .center)
                .padding(.bottom, .padding28)
                
                
                
            }
            
        }
        .task {
            await platformService.fetchPlatforms()
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
        .environmentObject(ViewState())
}
