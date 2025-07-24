//
//  PresenceSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct PresenceSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool
    @State var selectedPresence : Presence? = nil
    var onClickSetStatusText : () -> Void
    
    var body: some View {
        PeptideSheet(isPresented: $isPresented, topPadding: .padding16) {
            headerSection
            notificationOptionsList
            
           
            
            
            Button {
                self.onClickSetStatusText()
            } label: {
                
                let currentUser = viewState.currentUser
                let statusText = currentUser?.status?.text
                let isSetStatus = !(statusText?.isEmpty ?? true)
                
                PeptideActionButton(
                    icon: .peptideSmile,
                    iconColor: .iconDefaultGray01,
                    title: isSetStatus ? statusText ?? "" : "Set a Custom Status",
                    titleAlignment: .leading,
                    iconAction: isSetStatus ? .peptideTrashDelete : nil,
                    onClicIconAction: {
                        Task {
                            _ = viewState.currentUser
                            let updateUserStatusResponse = await viewState.http.updateSelf(profile: .init(remove: [.statusText]))
                            
                            switch updateUserStatusResponse {
                                case .success(let success):
                                    self.viewState.currentUser = success
                                case .failure(let failure):
                                    debugPrint("\(failure)")
                            }
                        }
                    },
                    hasArrow: !isSetStatus
                )
                .backgroundGray11(verticalPadding: .padding4, hasBorder: true)                

            }
            .padding(.top, .padding24)

            
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        ZStack(alignment: .center) {
            PeptideText(
                text: "Change Online Status",
                font: .peptideHeadline,
                textColor: .textDefaultGray01
            )
//            HStack {
//                PeptideIconButton(icon: .peptideBack, color: .iconDefaultGray01, size: .size24) {
//                    self.isPresented.toggle()
//                }
//                Spacer()
//            }
        }
        .padding(.bottom, .padding24)
    }

    private var notificationOptionsList: some View {
        VStack(spacing: .spacing4) {
            
            ForEach(Presence.allCases, id: \.rawValue) { item in
                notificationOptionRow(for: item)
                if item != .Invisible{
                    PeptideDivider()
                        .padding(.leading, .padding48)
                }
            }
        }
        .backgroundGray11(verticalPadding: .padding4)
    }

    private func notificationOptionRow(for item: Presence) -> some View {
        Button {
            self.isPresented.toggle()
        } label: {
            HStack {
                
                PresenceIndicator(presence: item, width: .size24, height: .size24)
                    .padding(.leading, .size12)
                
                HStack(spacing: .spacing12){
                    
                    PeptideText(textVerbatim: item.rawValue,
                                font: .peptideButton,
                                textColor: .textDefaultGray01,
                                alignment: .center)
                    
                    Spacer(minLength: .zero)
                    
                }
                .padding(.horizontal, .padding12)
                .frame(height: .size48)
                
                
                Toggle("", isOn: toggleBinding(for: item))
                    .toggleStyle(PeptideCircleCheckToggleStyle())
                    .padding(.trailing, .padding12)
            }
        }
    }

    private func toggleBinding(for presence: Presence) -> Binding<Bool> {
        Binding(
            get: {
                presence == selectedPresence
            },
            set: { isSelected in
                if isSelected {
                    self.selectedPresence = presence
                    Task {
                        let currentUser = viewState.currentUser
                        let updateUserStatusResponse = await viewState.http.updateSelf(profile: .init(status: .init(text: currentUser?.status?.text, presence: presence)))
                        
                        switch updateUserStatusResponse {
                            case .success(let success):
                                self.viewState.currentUser = success
                                self.isPresented.toggle()
                            case .failure(let failure):
                                debugPrint("\(failure)")
                        }
                    }
                }
            }
        )
    }

   


    
}


#Preview {
    
    @Previewable @StateObject var viewState : ViewState = .preview()
    PresenceSheet(isPresented: .constant(false), onClickSetStatusText: {})
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}

