//
//  DeleteCategorySheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct DeleteCategorySheet: View {
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented : Bool

    var server : Server
    var category : Types.Category
    var onDismiss : (Server) -> Void
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: .spacing4){
            
            
            Group {
                PeptideText(textVerbatim: "Delete Category?",
                            font: .peptideTitle3,
                            textColor: .textDefaultGray01)
                
                
                PeptideText(text: "Are you sure you want to delete \(category.title)? This cannot be undone.",
                            font: .peptideCallout,
                            textColor: .textGray06,
                            alignment: .leading)
                .padding(.top, .padding24)
                
                
            }
            .padding(.horizontal, .padding24)
            
            
            PeptideDivider(backgrounColor: .borderGray10)
                .padding(top: .padding28, bottom: .padding20)
            
            HStack(spacing: .padding12){
                Spacer(minLength: .zero)
                
                PeptideButton(buttonType: .medium(),
                              title: "Cancel",
                              bgColor: .clear,
                              contentColor: .textDefaultGray01,
                              buttonState: .default,
                              isFullWidth: false){
                    self.isPresented.toggle()
                }
                
                PeptideButton(buttonType: .medium(),
                              title: "Delete",
                              bgColor: .bgRed07,
                              contentColor: .textDefaultGray01,
                              buttonState: .default,
                              isFullWidth: false){
                    
                    Task {
                        
                        let editServerResponse = await viewState.http.editServer(server: server.id,
                                                                                 edits: .init(categories: server.removeCategory(by: category.id)))
                        
                        
                        switch editServerResponse {
                            case .success(let success):
                                onDismiss(success)
                            case .failure(let failure):
                                debugPrint("\(failure)")
                        }
                        
                    }
                    
                }
            }
            .padding(.horizontal, .padding24)
            
        }
        .padding(top: .padding24, bottom: .padding24)
        .background{
            RoundedRectangle(cornerRadius: .radiusMedium)
                .fill(Color.bgGray11)
        }
        .padding(.padding16)

    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    let category = viewState.servers["0"]?.categories?.first!
    DeleteCategorySheet(isPresented: .constant(true), server: viewState.servers["0"]!, category: category!, onDismiss: {_ in 
        
    })
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
