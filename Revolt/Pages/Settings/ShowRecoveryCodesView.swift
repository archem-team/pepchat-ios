

//
//  RecoveryCodesView.swift
//  Revolt
//
//

import SwiftUI
import Sentry
import UniformTypeIdentifiers

struct ShowRecoveryCodesView: View {
    @EnvironmentObject var viewState: ViewState // The current application state
    @State var token: String
    var isGenerate: Bool
    @State var codes: [String] = []
    @State var codesRecorded: Bool = false
    @State var showResetCodesSheet: Bool = false
    @State var btnState : ComponentState = .disabled
    
    let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    
    func getCodes() {
        
        Task{
            
            let res = await viewState.http.getRecoveryCodes(mfaToken: token)
            
            switch res {
            case .success(let res):
                codes = res
            case .failure(_):
                let _ = ""
            }
            
        }
        
    }
    
    func generateCodes() {
        
        Task{
            
            let res = await viewState.http.generateRecoveryCodes(mfaToken: token)
            
            switch res {
            case .success(let res):
                codes = res
            case .failure(_):
                let _ = ""
            }
            
        }
        
    }
    
    // Known bug: The MFATicketView doesn't fully slide offscreen.
    var body: some View {
                
        
        PeptideTemplateView(
            toolbarConfig: .init(isVisible: true, title: "Recovery Codes",showBackButton: false, customToolbarView: AnyView(
                
                Button(action: {
                    showResetCodesSheet.toggle()
                }, label: {
                    PeptideText(text: "Reset Codes", font: .peptideButton, textColor: .textYellow07)
                })
                
            )),
            fixBottomView: AnyView(
                VStack{
                    
                    PeptideDivider()
                        .padding(.bottom, .size12)
                    
                    HStack(spacing: .zero){
                        
                        Toggle("", isOn: $codesRecorded)
                            .toggleStyle(PeptideCheckToggleStyle())
                            .padding(.trailing, .size8)
                        
                        PeptideText(text: "I have safely recorded these codes.")
                            .padding(.trailing, .size16)
                        
                    }
                    
                    PeptideButton(
                        buttonType: .large(),
                        title: "Done", buttonState: btnState){
                            viewState.path.removeLast(2)
                    }
                        .padding(.horizontal, .padding16)
                        .padding(.top, .padding16)
                        .padding(.bottom, .padding24)
                    
                }
            )
        ){_, _ in
            
            VStack(spacing: .zero) {
                
                Image(.peptideRecovery)
                    .padding(.top, .padding24)
                
                Group{
                    PeptideText(text: "Your Recovery Codes",
                                font: .peptideTitle2)
                    .padding(.bottom, .padding4)
                    
                    PeptideText(text: "Save these codes somewhere only you can access.",
                                font: .peptideBody2,
                                textColor: .textGray07)
                    .padding(.bottom, .size32)
                }
                .padding(.horizontal, .padding16)
                
                VStack(spacing: .zero){
                
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(codes.enumerated()), id: \.element) { index, item in
                                            HStack {
                                                
                                                PeptideText(
                                                    text:"\(index + 1)",
                                                    font: .peptideBody2,
                                                    textColor: .textGray07
                                                )
                                                
                                                PeptideText(
                                                    text: item,
                                                    font: .peptideBody2
                                                )
                                                
                                                Spacer()
                                           
                                            }
                                            .padding(.all, .size12)
                                            .background(Color.bgGray12)
                                            .background(
                                                RoundedRectangle(cornerRadius: .radiusMedium)
                                                    .fill(Color.bgGray11)
                                                    //todo stroke color
                                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                            )
                                            .cornerRadius(.size8)
                                        }
                                    }
                        
                    Spacer(minLength: .zero)
                    
                }
                
                
            }
            .padding(.horizontal, .padding16)
            .onAppear{
                
                if(isGenerate){
                    generateCodes()
                }else{
                    getCodes()
                }
                
            }
            .onChange(of: codesRecorded){ _, _ in
                withAnimation{
                    if(codesRecorded){
                        btnState = .default
                    }else{
                        btnState = .disabled
                    }
                }
            }
            .sheet(isPresented: $showResetCodesSheet){
                
                    GetPasswordSheet(
                        isPresented: $showResetCodesSheet,
                        title: "Reset Codes",
                        subTitle: "Enter your password to reset recovery codes!",
                        placeholder: "Enter your password"
                    ){ token in
                        showResetCodesSheet.toggle()
                        self.token = token
                        generateCodes()
                    }
                
            }

        }
        
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ShowRecoveryCodesView(token: "", isGenerate: true, codes:["aaaaa-sssss", "aaaaa-sssss", "aaaaa-sssss", "aaaaa-sssss"])
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
