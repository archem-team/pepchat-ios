//
//  PeptideTemplateView.swift
//  Revolt
//
//

import SwiftUI

struct PeptideTemplateView<Content: View>: View {
    
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @State private var keyboardIsVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    
    
    var toolbarConfig: ToolbarConfig
    var fixBottomView: AnyView?
    var content: (ScrollViewProxy, Binding<Bool>) -> Content
    
    init(toolbarConfig: ToolbarConfig = .init(),
         fixBottomView: AnyView? = nil,
         @ViewBuilder content: @escaping (ScrollViewProxy, Binding<Bool>) -> Content) {
        self.toolbarConfig = toolbarConfig
        self.fixBottomView = fixBottomView
        self.content = content
    }
    
    
    private var mainToolbar: some View {
        ZStack(alignment: .bottom) {
            
            ZStack(alignment: .center) {
                
                HStack(spacing: .zero) {
                    
                    if toolbarConfig.showBackButton {
                        PeptideIconButton(icon: toolbarConfig.backButtonIcon,
                                          color: .iconDefaultGray01,
                                          size: .size24) {
                            
                            if let onClickBackButton = toolbarConfig.onClickBackButton {
                                onClickBackButton()
                            } else {
                                self.presentationMode.wrappedValue.dismiss()
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if let customToolbarView = toolbarConfig.customToolbarView {
                        customToolbarView
                    }
                }
                .padding(.horizontal, .size16)
                .frame(height: .size48)
                
                if let title = toolbarConfig.title {
                    PeptideText(text: title,
                                font: .peptideHeadline,
                                textColor: .textDefaultGray01)
                    
                }
                
                
            }
            
            
            
            if toolbarConfig.showBottomLine {
                RoundedRectangle(cornerRadius: .zero)
                    .foregroundStyle(.borderGray11)
                    .frame(height: .size1)
            }
        }
        .frame(height: .size48)
        .background(.bgDefaultPurple13)
    }
    
    var body: some View {
        
        
        VStack(spacing: .zero){
            
            
            if toolbarConfig.isVisible {
                mainToolbar
            }
            
            GeometryReader { proxy in
                ScrollViewReader { scrollViewProxy in
                                        
                    ScrollView([.vertical]) {
                        content(scrollViewProxy, $keyboardIsVisible)
                            .frame(maxWidth: proxy.size.width, minHeight: proxy.size.height)
                    }
                    .scrollContentBackground(.hidden)
                    .clipped()
                    .scrollBounceBehavior(.basedOnSize)
                    
                }
            }
            //.ignoresSafeArea(.container, edges: .bottom)
            
            if let bottomView = fixBottomView {
                bottomView
                    .frame(maxWidth: .infinity) 
                    .background(Color.bgDefaultPurple13)
            }
            
            
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden)
        .observeKeyboardVisibility(isVisible: $keyboardIsVisible)
        .fillMaxSize()
        
        
    }
}


struct ToolbarConfig {
    var isVisible: Bool = false
    var title: String? = nil
    var showBackButton : Bool = true
    var backButtonIcon: ImageResource = .peptideBack
    var onClickBackButton: (() -> Void)? = nil
    var customToolbarView: AnyView? = nil
    var showBottomLine: Bool = true    
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    
    PeptideTemplateView(toolbarConfig: .init(isVisible: true,title: "aaaaaaa", customToolbarView: AnyView(Text("aaaaaa")))){ _, _ in
        VStack{}
    }
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
