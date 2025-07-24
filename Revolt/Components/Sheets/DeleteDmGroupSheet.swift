//
//  DeleteChannelSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct DeleteGroupSheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented : Bool
    //@Binding var isPresentedServerSheet : Bool

    @State private var leaveSilently : Bool = false
    var channel : Channel
    var isOwner : Bool = false
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: .spacing4){
            
            Group {
                PeptideText(textVerbatim: "Leave \(channel.getName(viewState))?",
                            font: .peptideTitle3,
                            textColor: .textDefaultGray01)
                
                PeptideText(text: "You won't be able to rejoin unless you are re-invited.",
                            font: .peptideCallout,
                            textColor: .textGray06)
                
                if !isOwner {
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
                    .padding(top: .padding28)
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
                              title: isOwner ? "Delete" : "Leave",
                              bgColor: .bgRed07,
                              contentColor: .textDefaultGray01,
                              buttonState: .default,
                              isFullWidth: false){
                    
                    Task {
                        
                        let deleteResponse = await viewState.http.deleteChannel(target: channel.id,
                                                                         leaveSilently: leaveSilently)
                        switch deleteResponse {
                            case .success(_):
                                isPresented.toggle()
                                viewState.removeChannel(with: channel.id)
                                //isPresentedServerSheet.
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
    
    DeleteGroupSheet(isPresented: .constant(true), channel: viewState.channels["0"]!)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}

