//
//  StatusSheet.swift
//  Revolt
//
//

import SwiftUI

struct StatusSheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented : Bool
    
    @State private var status : String = ""
    @State private var statusTextFieldState : PeptideTextFieldState = .default
    
    @State private var isShowSaveBtn : Bool = false
    @State private var showDeleteButton : Bool = false
    
    

    
    var body: some View {
        
        let currentUser = viewState.currentUser
        
        PeptideSheet(isPresented: $isPresented, topPadding: .padding16){
            
            ZStack {
                PeptideText(
                    text: "Edit Status",
                    font: .peptideHeadline,
                    textColor: .textDefaultGray01
                )
                
                HStack(spacing: .zero){
                    Spacer(minLength: .zero)
                    
                    
                    if isShowSaveBtn {
                        Button {
                            
                            if(self.status.count > 128){
                                
                                self.statusTextFieldState = .error(message: "Max allowed length is 128 charachters!", icon: .peptideInfo)
                                return
                            }
                            
                            Task {
                                let updateUserStatusResponse = await viewState.http.updateSelf(profile: .init(status: .init(text:self.status, presence: currentUser?.status?.presence)))
                                
                                switch updateUserStatusResponse {
                                    case .success(let success):
                                        self.viewState.currentUser = success
                                        self.isPresented.toggle()
                                    case .failure(let failure):
                                        debugPrint("\(failure)")
                                }
                            }
                            
                        } label: {
                            PeptideText(text: "Save",
                                        font: .peptideButton,
                                        textColor: .textYellow07)
                        }
                    }
                
                }
                //.padding(.horizontal, .padding16)
            }
            
            
            
            
            PeptideTextField(text: $status, state: $statusTextFieldState, placeholder: "What're you up to?", icon: .peptideSmile)
                .padding(.top, .padding24)
                .onChange(of: self.status){_, newState in
                    self.isShowSaveBtn = newState.isNotEmpty
                    self.statusTextFieldState = .default
                }
            
            if(showDeleteButton){
                Button {

                    Task {
                        let result = await viewState.http.updateSelf(profile: .init(remove: [.statusText]))
                        
                        switch result {
                            case .success(let success):
                                self.viewState.currentUser = success
                                self.isPresented.toggle()
                            case .failure(let failure):
                                debugPrint("\(failure)")
                        }
                    }
                    
                } label: {
                    
                    PeptideActionButton(icon: .peptideTrashDelete,
                                        iconColor: .iconRed07,
                                        title: "Delete Status",
                                        titleColor: .textRed07,
                                        hasArrow: false
                    )
                    .backgroundGray11(verticalPadding: .padding4)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
            }
            
            
        }
        .task {
            self.status = currentUser?.status?.text ?? ""
            self.showDeleteButton = currentUser?.status?.text?.isNotEmpty ?? false
        }
        
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    StatusSheet(isPresented: .constant(false))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
