//
//  CreateServerRoleView.swift
//  Revolt
//
//

import SwiftUI
import Types

struct CreateServerRoleView: View {
    @EnvironmentObject var viewState: ViewState
    
    @Binding var server: Server
    @State private var roleName : String = ""
    

    
    @State var showSaveButton: Bool = false

    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                
                
                Task {
                    //TODO check conditions
                    let response = await viewState.http.createRole(server: server.id, name: roleName)
                    switch response {
                    case .success(let success):
                        self.viewState.path.removeLast()
                    case .failure(let failure):
                        debugPrint("\(failure)")
                    }
                    
                }
                
                
            } label: {
                PeptideText(text: "Create",
                            font: .peptideButton,
                            textColor: .textYellow07,
                            alignment: .center)
            }
                //.opacity(showSaveButton ? 1 : 0)
                //.disabled(!showSaveButton)
            
            
        )
    }
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Create a New Role",
                                                 showBackButton: true,
                                                 backButtonIcon: .peptideCloseLiner,
                                                 customToolbarView: saveBtnView,
                                                 showBottomLine: true)){_,_ in
            
            
                    VStack(spacing: .zero){
                        
                        
                        PeptideText(text: "Give this role a unique name. You can always change this later.",
                                    font: .peptideBody4,
                                    textColor: .textGray06,
                                    alignment: .center)
                                    .padding(.vertical, .padding24)
                                    .padding(.horizontal, .padding16)
                        
                        
                        PeptideTextField(text: $roleName,
                                         state: .constant(.default),
                                         label: "Role Name",
                                         placeholder: "Enter role name")
                        
                        
                        Spacer(minLength: .zero)
                        
                    }
                    .padding(.horizontal, .padding16)
            
        }
        
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    CreateServerRoleView(server: .constant(viewState.servers["0"]!))
        .applyPreviewModifiers(withState: viewState)
}
