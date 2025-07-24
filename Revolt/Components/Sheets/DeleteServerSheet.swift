//
//  DeleteServerSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct DeleteServerSheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented : Bool
    @Binding var isPresentedServerSheet : Bool

    @State private var leaveSilently : Bool = false
    var server : Server
    var isOwner : Bool = false
    
    // Determine if this is a leave or delete action
    private var isLeaving: Bool {
        !isOwner
    }
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: .spacing4){
            
            Group {
                PeptideText(textVerbatim: isLeaving ? "Leave \(server.name)?" : "Delete \(server.name)?",
                            font: .peptideTitle3,
                            textColor: .textDefaultGray01)
                .padding(.bottom, .size32)
                
                PeptideText(text: isLeaving ? "You won't be able to rejoin unless you are re-invited." : "Once it's deleted, there's no going back.",
                            font: .peptideCallout,
                            textColor: .textGray06)
                .padding(.bottom, .size32)
                
                
                if isLeaving {
                    HStack(spacing: .spacing8){
                        
                        VStack(alignment: .leading, spacing: .zero){
                            
                            PeptideText(text: "Silently Leave",
                                        font: .peptideCallout,
                                        textColor: .textDefaultGray01)
                            
                            PeptideText(text: "Other members will not be notified",
                                        font: .peptideFootnote,
                                        textColor: .textGray06)
                        }
                        
                        Spacer(minLength: .zero)
                        
                        Toggle("", isOn: $leaveSilently)
                            .toggleStyle(PeptideSwitchToggleStyle())
                        
                    }
                    .padding(.bottom, .size32)
                }
                
                
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
                              title: isLeaving ? "Leave" : "Delete",
                              bgColor: .bgRed07,
                              contentColor: .textDefaultGray01,
                              buttonState: .default,
                              isFullWidth: false){
                    
                    Task {
                        
                        let deleteResponse = await viewState.http.deleteServer(target: server.id,
                                                                         leaveSilently: leaveSilently)
                        switch deleteResponse {
                            case .success(_):
                                viewState.removeServer(with: server.id)
                                isPresented.toggle()
                                isPresentedServerSheet.toggle()
                            case .failure(let failure):
                                //todo
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
    
    @Previewable @StateObject var viewState = ViewState.preview()
    
    DeleteServerSheet(isPresented: .constant(true), isPresentedServerSheet: .constant(false), server: viewState.servers["0"]!)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}


#Preview {
    
    @Previewable @StateObject var viewState = ViewState.preview()
    
    DeleteServerSheet(isPresented: .constant(true), isPresentedServerSheet: .constant(false), server: viewState.servers["0"]!, isOwner: true)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
