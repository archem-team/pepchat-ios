//
//  ReportView.swift
//  Revolt
//
//

import SwiftUI
import Types
import SwiftUIIntrospect

struct ReportView: View {
    @EnvironmentObject var viewState : ViewState
    var user : User?
    var server : Server?
    var message : Message?
    
    var reportType : ContentReportPayload.ContentReportType
    
    @State private var confirmBtnState : ComponentState = .disabled
    @State var  additionalInformationTextFieldStatus : PeptideTextFieldState = .default
    @State private var reason : ContentReportPayload.ContentReportReason? = nil
    @State var additionalInformation = ""
    
    @State private var keyboardHeight: CGFloat = 0
    @State private var step : ReportStep = .reportStep
    
    
    func report() {
        Task {
            if let reason = self.reason {
                self.confirmBtnState = .loading
                       
               guard let (type, id) = getReportTarget() else {
                   debugPrint("No valid target for reporting.")
                   self.confirmBtnState = .default
                   return
               }

               let reportResponse = await viewState.http.safetyReport(
                   type: type,
                   id: id,
                   reason: reason,
                   userContext: additionalInformation
               )
               
               self.confirmBtnState = .default
                
                switch reportResponse {
                    case .success:
                        step = .finalStep
                    case .failure(let error):
                        debugPrint("Report failed with error: \(error)")
                }
            }
        }
    }
    
    func blockUser() {
        Task {
            await blockUserIfNeeded(user: user)
            if let message, let user = viewState.users[message.author] {
                await blockUserIfNeeded(user: user)
            }
        }
    }

    private func blockUserIfNeeded(user: User?) async {
        guard let user else { return }
        
        let blockUserResponse = await viewState.http.blockUser(user: user.id)
        switch blockUserResponse {
        case .success:
            viewState.path.removeLast()
        case .failure(let error):
            debugPrint("Block user failed with error: \(error)")
        }
    }
    
    private func getReportTarget() -> (ContentReportPayload.ContentReportType, String)? {
        if let user {
            return (.User, user.id)
        } else if let server {
            return (.Server, server.id)
        } else if let message {
            return (.Message, message.id)
        }
        return nil
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func headerView() -> some View {
            HStack {
                Spacer(minLength: .zero)
                
                PeptideIconButton(icon: .peptideCloseLiner,
                                  color: .iconDefaultGray01,
                              size: .size24) {
                    viewState.path.removeLast()
                }
            }
            .padding(.horizontal, .padding16)
            .frame(height: .size48)
    }
    
    @ViewBuilder
    private func titleSection(_ title: String, _ description: String, _ icon: ImageResource) -> some View {
                        Group {
                            Image(icon)
                            
                            PeptideText(text: title,
                                        font: .peptideTitle1)
                            .padding(.vertical, .padding4)
                            
                            PeptideText(text: description,
                                        font: .peptideBody2,
                                        textColor: .textGray07)
                            .padding(.horizontal, .padding16)
        }
                        }
                        
    @ViewBuilder
    private func finalStepContent() -> some View {
                            if reportType != .Server {
            let _user: User? = {
                                if reportType == .User {
                    return user
                } else if reportType == .Message, let message = message {
                    return viewState.users[message.author]
                }
                return nil
            }()
                                
                                if let user = _user {
                                    PeptideDivider()
                                        .padding(.top, .padding32)
                                    
                                    PeptideText(text: "Block This User or Move On?",
                                                font: .peptideHeadline)
                                    .padding(.top, .padding32)
                                    
                blockUserSection(user)
            }
        }
    }
    
    @ViewBuilder
    private func blockUserSection(_ user: User) -> some View {
        HStack(spacing: .spacing8) {
            VStack(alignment: .leading, spacing: .zero) {
                                            PeptideText(textVerbatim: "Block \(user.username)#\(user.discriminator)",
                                                        font: .peptideBody3)
                                            
                                            PeptideText(text: "Stop seeing their messages",
                                                        font: .peptideFootnote,
                                                        textColor: .textGray07)
                                        }
                                        
                                        Spacer(minLength: .zero)
                                        
                                        PeptideButton(buttonType: .small(),
                                                      title: "Block",
                                                      bgColor: .bgRed07,
                                                      contentColor: .textDefaultGray01,
                                                      buttonState: .default,
                          isFullWidth: false) {
                                            self.blockUser()
                                        }
                                    }
                                    .padding(.padding16)
        .background {
                                        RoundedRectangle(cornerRadius: .radiusMedium)
                                            .fill(Color.bgGray11)
                                    }
                                    .padding(.top, .padding32)
                                }
                                
    @ViewBuilder
    private func reportOptionsSection(_ selectedTitle: String) -> some View {
                                Group {
            HStack(spacing: .zero) {
                                        PeptideText(text: selectedTitle,
                                                    font: .peptideCallout,
                                                    textColor: .textGray07)
                                        Spacer(minLength: .zero)
                                    }
                                    .padding(top: .padding32, bottom: .padding8)
                                    
            reportSelectedContent()
            reportOptionsListSection()
        }
    }
    
    @ViewBuilder
    private func reportSelectedContent() -> some View {
                                    if let user = user {
                                        PeptideUserAvatar(user: user,
                                                          nameStyle: .peptideTitle4,
                                                          usernameStyle: .peptideFootnote,
                                                          spaceBetween: .size16,
                                                          usernameColor: .textGray06)
                                        .padding(.padding8)
            .background {
                                            RoundedRectangle(cornerRadius: .radiusXSmall)
                                                .strokeBorder(Color.borderGray11, lineWidth: .size1)
                                        }
                                    }
                                    
                                    if let server = server {
            HStack(spacing: .spacing16) {
                                            ServerIcon(server: server, height: .size40, width: .size40, clipTo: Rectangle())
                                                .addBorder(Color.clear, cornerRadius: .radiusXSmall)
                                                .padding(.padding8)
                                            
                                            PeptideText(textVerbatim: server.name,
                            font: .peptideTitle4)
                                            
                                            Spacer(minLength: .zero)
                                        }
            .background {
                                            RoundedRectangle(cornerRadius: .radiusXSmall)
                                                .strokeBorder(Color.borderGray11, lineWidth: .size1)
                                        }
                                    }
                                    
                                    if let message = message {
                                        MessageView(
                                            viewModel: .init(
                    viewState: viewState,
                    message: .constant(message),
                    author: .constant(viewState.users[message.author]!),
                    member: .constant(nil),
                    server: .constant(nil),
                    channel: .constant(viewState.channels[message.channel]!),
                    replies: .constant([]),
                    channelScrollPosition: .empty,
                    editing: .constant(nil)
                                            ),
                isStatic: true
                                        )
                                        .padding(.horizontal, .padding8)
                                        .padding(.vertical, .padding4)
            .background {
                                            RoundedRectangle(cornerRadius: .radiusXSmall)
                                                .strokeBorder(Color.borderGray11, lineWidth: .size1)
                                        }
        }
    }
    
    @ViewBuilder
    private func reportOptionsListSection() -> some View {
        HStack(spacing: .zero) {
                                PeptideText(text: "Report Options",
                                            font: .peptideHeadline,
                                            textColor: .textDefaultGray01)
                                Spacer(minLength: .zero)
                            }
                            .padding(top: .padding32, bottom: .padding8)
                            
        ForEach(ContentReportPayload.ContentReportReason.reasons(for: reportType), id: \.rawValue) { reason in
            HStack(spacing: .spacing4) {
                                    PeptideText(text: reason.title(for: reportType),
                                                font: .peptideButton,
                                                alignment: .leading)
                                    Spacer(minLength: .zero)
                                    
                                    Toggle("", isOn: toggleBinding(for: reason))
                                        .toggleStyle(PeptideCircleCheckToggleStyle())
                                        .padding(.trailing, .padding12)
                                }
                                .padding(.horizontal, .padding12)
                                .frame(height: .size56)
            .background {
                                    RoundedRectangle(cornerRadius: .radiusMedium).fill(Color.bgGray11)
                    .overlay {
                                            RoundedRectangle(cornerRadius: .radiusMedium)
                                                .strokeBorder(Color.borderGray10, lineWidth: .size1)
                                        }
                                }
                                .padding(.bottom, .padding8)
                            }
                            
                            PeptideTextField(
                                text: $additionalInformation,
                                state: $additionalInformationTextFieldStatus,
                                label: "Additional Information (Optional)",
            placeholder: "Enter additional information",
                                textStyle: .peptideBody3,
            keyboardType: .default
        )
                            .padding(top: .padding32, bottom: .size40)
                        }
                        
    @ViewBuilder
    private func bottomButtonBar() -> some View {
                HStack(spacing: .zero) {
                    PeptideButton(
                        buttonType: .large(),
                title: step == .reportStep ? "Report" : "Done",
                buttonState: confirmBtnState) {
                        if step == .reportStep {
                            report()
                        } else {
                            self.viewState.path.removeLast()
                        }
                    }
                }
                .padding(.horizontal, .padding16)
                .padding(top: .padding8, bottom: keyboardHeight > 0 ? .padding8 : .zero)
                .background(Color.bgDefaultPurple13)
    }
    
    // MARK: - Main View Construction
    
    @ViewBuilder
    private func mainContentView(_ title: String, _ description: String, _ selectedTitle: String, _ icon: ImageResource) -> some View {
        ScrollView([.vertical]) {
            LazyVStack(spacing: .zero) {
                titleSection(title, description, icon)
                
                if step == .finalStep {
                    finalStepContent()
                } else {
                    reportOptionsSection(selectedTitle)
                }
        }
            .padding(.horizontal, .padding16)
        }
        .introspect(.scrollView, on: .iOS(.v16, .v17)) { (scrollView: UIScrollView) in
            scrollView.keyboardDismissMode = .onDrag
            scrollView.backgroundColor = .clear
        }
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
    
    @ViewBuilder
    private func contentContainer() -> some View {
        VStack(spacing: .zero) {
            let details = step.details(type: reportType)
            let (title, description, selectedTitle, icon) = details
            
            mainContentView(title, description, selectedTitle, icon)
            
            Spacer(minLength: .zero)
            
            bottomButtonBar()
        }
        .offset(y: keyboardHeight > 0 ? -keyboardHeight : 0)
        .clipped()
    }
    
    var body: some View {
        VStack(spacing: .zero) {
            headerView()
            contentContainer()
        }
        .onChange(of: reason) { _, newVal in
            confirmBtnState = (newVal != nil) ? .default : .disabled
        }
        .animation(.easeOut(duration: 0.3), value: keyboardHeight)
        .keyboardHeight(keyboardHeight: $keyboardHeight)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden)
        .fillMaxSize()
    }
    
    private func toggleBinding(for reason: ContentReportPayload.ContentReportReason) -> Binding<Bool> {
        Binding(
            get: {
                self.reason == reason
            },
            set: { isSelected in
                if isSelected {
                    self.reason = reason
                }
            }
        )
    }
}

enum ReportStep {
    case reportStep
    case finalStep
    
    func details(type : ContentReportPayload.ContentReportType) -> (title: String,
                                                                    description: String,
                                                                    selectedTitle : String,
                                                                    image: ImageResource) {
           switch self {
               case .reportStep:
                   
                       switch type {
                           case .Message:
                               return (
                                   title: "Report Message",
                                   description: "Please select the option that best describes the problem.",
                                   selectedTitle : "Selected Message",
                                   image: .peptideReport
                               )
                           case .Server:
                               return (
                                   title: "Report Server",
                                   description: "Please select the option that best describes the problem.",
                                   selectedTitle : "Selected Server",
                                   image: .peptideReport
                               )
                           case .User:
                               return (
                                   title: "Report User Profile",
                                   description: "Please select the option that best describes the problem.",
                                   selectedTitle : "Selected User",
                                   image: .peptideReport
                               )
                       }
               
              
               case .finalStep:
                   
                       switch type {
                           case .Message:
                               return (
                                   title: "Thank You!",
                                   description: "Thank you for helping to keep ZekoChat safe. We will review your report as soon as possible.",
                                   selectedTitle: "",
                                   image: .peptideLike
                               )
                           case .Server:
                               return (
                                   title: "Thank You!",
                                   description: "Thank you for helping to keep ZekoChat safe. We will review your report as soon as possible.",
                                   selectedTitle:"",
                                   image: .peptideLike
                               )
                           case .User:
                               return (
                                   title: "Thank You!",
                                   description: "Thank you for helping to keep ZekoChat safe. We will review your report as soon as possible.",
                                   selectedTitle: "",
                                   image: .peptideLike
                               )
                       }
               
               
           }
       }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    ReportView(user: viewState.users["0"]!, reportType: .User)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    ReportView(server: viewState.servers["0"]!,
               reportType: .Server)
        .applyPreviewModifiers(withState: viewState)
}


/*#Preview {
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    ReportView(message: viewState.messages["0"],
               reportType: .Message)
        .applyPreviewModifiers(withState: viewState)
}*/
