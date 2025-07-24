//
//  IdentitySheet.swift
//  Revolt
//
//

import SwiftUI
import Types
import PhotosUI


struct IdentitySheet: View {
    
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented : Bool
    
    var server : Server
    @State var member : Member
    
    @State var currentValues : IdentityValues
    
    @State var remove: Set<RemoveMemberField> = []
    
    
    @State var showIconPhotoPicker: Bool = false
    @State var memberIconPhoto: PhotosPickerItem?
    
    
    @State private var nicknameTextFieldState : PeptideTextFieldState = .default
    @State private var saveBtnState : ComponentState = .default
    
    
    @MainActor
    static func fromState(isPresented : Binding<Bool>,
                          server: Server,
                          user: User,
                          member : Member) -> Self {
        let settings = IdentityValues(
            icon: .remote(member.avatar),
            nickname: member.nickname ?? user.display_name ?? user.username
        )
        return .init(isPresented: isPresented, server: server, member: member, currentValues: settings)
    }
    
    
    private var headerSection: some View {
        ZStack(alignment: .center) {
            PeptideText(
                text: "Change Identity on \(server.name)",
                font: .peptideHeadline,
                textColor: .textDefaultGray01
            )
            HStack {
                PeptideIconButton(icon: .peptideBack, color: .iconDefaultGray01, size: .size24) {
                    self.isPresented.toggle()
                }
                Spacer()
            }
        }
        .padding(.bottom, .padding24)
    }
    
    var body: some View {
        
        PeptideSheet(isPresented: $isPresented,
                     topPadding: .padding16,
                     horizontalPadding: .zero) {
            VStack(spacing: .zero){
                
                let currentUser = viewState.currentUser
                
                headerSection
                .padding(.horizontal, .padding16)

                Group {
                    
                    ZStack(alignment: .topTrailing) {
                        
                        ZStack {
                            
                            Circle()
                                .fill(Color.bgGray11)
                                .frame(width: .size48, height: .size48)
                            
                            switch currentValues.icon {
                            case .remote(let file):
                                // Display remote icon if available.
                                if let file = file {
                                    AnyView(LazyImage(source: .file(file), height: .size48, width: .size48, clipTo: Circle()))
                                } else {
                                    
                                    
                                    PeptideIcon(iconName: .peptideUsers,
                                                size: .size24,
                                                color: .iconDefaultGray01
                                    )
                                    .background {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 48, height: 48)
                                    }
                                    
                                }
                            case .local(let data):
                                // Display the locally selected icon.
                                if let data {
                                    LazyImage(source: .local(data), height: .size48, width: .size48, clipTo: Circle())
                                } else {
                                    
                                    PeptideIcon(iconName: .peptideUsers,
                                                size: .size24,
                                                color: .iconDefaultGray01
                                    )
                                    .background {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 48, height: 48)
                                    }
                                    
                                }
                            }
                            
                        }
                        
                        
                        PeptideIcon(iconName: .peptideAddPhoto,
                                    size: .size16,
                                    color: .iconInverseGray13)
                        .frame(width: .size24, height: .size24)
                        .background{
                            Circle().fill(Color.bgGray02)
                        }
                        .offset(x: .size12)
                        .onTapGesture { showIconPhotoPicker = true }
                        
                        
                    }
                    .padding(.top, .padding24)
                    
                    VStack(spacing: .spacing2){
                        
                        if isShowRemovePhotoBtn {
                            Button {
                                switch currentValues.icon {
                                    case .remote(let file):
                                        if file != nil {
                                            remove.insert(.avatar)
                                            self.currentValues.icon = .remote(nil)
                                            self.member.avatar = nil
                                        }
                                    case .local(let data):
                                        if data != nil {
                                            self.currentValues.icon = .local(nil)
                                        }
                                }
                            } label: {
                                HStack(spacing: .spacing2){
                                    PeptideIcon(iconName: .peptideTrashDelete,
                                                size: .size16,
                                                color: .iconRed07)
                                    
                                    PeptideText(text: "Remove Photo",
                                                font: .peptideCaption1,
                                                textColor: .textRed07)
                                    
                                }
                                
                            }
                        }
                        
                        PeptideText(text: "Max 4MB",
                                    font: .peptideCaption1,
                                    textColor: .textGray07)
                        
                        
                    }
                    .padding(.top, .padding8)
                    
                    
                }
                .padding(.horizontal, .padding16)
                
                
                

                PeptideTextField(text: $currentValues.nickname,
                                 state: $nicknameTextFieldState,
                                 size: .large,
                                 label: "Nickname",
                                 placeholder: member.nickname ?? currentUser?.display_name ?? currentUser?.username,
                                 keyboardType: .default)
                .padding(.top, .padding24)
                .padding(.horizontal, .padding16)

                Group {
                    
                    DashedDivider()
                        .padding(.vertical, .padding24)

                    VStack(spacing: .spacing8){
                        
                        HStack(spacing: .zero){
                            PeptideText(text: "Preview",
                                        font: .peptideBody3,
                                        textColor: .textGray06)
                            
                            Spacer(minLength: .zero)
                        }
                        
                        HStack(alignment: .top, spacing: .spacing16){
                            
                            Avatar(user: currentUser!,
                                   member: member,
                                   width: .size40,
                                   height: .size40)
                            
                            VStack(alignment: .leading, spacing: .spacing2){
                                HStack(spacing: .spacing4){
                                    
                                    PeptideText(text: currentValues.nickname,
                                                font: .peptideTitle4,
                                                textColor: .textDefaultGray01)
                                    
                                    PeptideText(text: "Today at 11:20 AM",
                                                font: .peptideFootnote,
                                                textColor: .textGray06)
                                }
                                
                                PeptideText(text: "Message",
                                            font: .peptideBody1,
                                            textColor: .textGray04)
                                
                                
                            }
                            
                            Spacer(minLength: .zero)

                        }
                        
                    }
                    .padding(.horizontal, .padding16)
                    
                    
                    
                    DashedDivider()
                        .padding(.vertical, .padding24)

                }
                
                
                Group {
                    PeptideButton(title: "Save",
                                  buttonState: self.saveBtnState){
                        Task {
                            
                            self.saveBtnState = .loading
                            
                            if case .local(let data)  = currentValues.icon, let data = data{
                                uploadAvatar(data: data, dataName: "avatar")
                            } else {
                                updateMemeber()
                            }
                            
                        }
                    }
                    
                    PeptideButton(title: "Cancel",
                                  bgColor: .clear,
                                  contentColor: .textDefaultGray01){
                        self.isPresented.toggle()
                    }
                                  .padding(.top, .padding12)
                }
                .padding(.horizontal, .padding16)
                
                
                
                
                
            }
            
        }
        .photosPicker(isPresented: $showIconPhotoPicker, selection: $memberIconPhoto)
        .onChange(of: memberIconPhoto) { (_, new) in
            Task {
                // Load the selected photo and update the icon.
                if let photo = new {
                    if let data = try? await photo.loadTransferable(type: Data.self) {
                        currentValues.icon = .local(data)
                    }
                }
            }
        }
        
    }
    
    
    var isShowRemovePhotoBtn: Bool {
        switch self.currentValues.icon {
        case .remote(let file):
            return file != nil
        case .local(let data):
            return data != nil
        }
    }
    
    func uploadAvatar(data : Data, dataName : String) {
        Task {
            let uploadResponse = await viewState.http.uploadFile(data: data, name: dataName, category: .avatar)
            switch uploadResponse {
            case .success(let success):
                self.currentValues.newIconId = success.id
                self.updateMemeber()
            case .failure(_):
                self.saveBtnState = .default
                debugPrint("error upload file")
            }
        }
    }
    
    func updateMemeber() {
        
        Task {
            
            
            
            if currentValues.nickname.isEmpty && self.member.nickname != nil {
                self.remove.insert(.nickname)
            }
            
            if currentValues.newIconId != nil {
                self.remove.remove(.avatar)
            }else if self.remove.contains(.avatar){
                self.remove.insert(.avatar)
            }
            
            let edits = EditMember(nickname: currentValues.nickname,
                            avatar: currentValues.newIconId,
                            remove: Array(self.remove))
                        
            let editMemberResponse = await viewState.http.editMember(server: member.id.server,
                                                                     memberId: member.id.user,
                                                                     edits: edits)
            
            self.saveBtnState = .default
            
            switch editMemberResponse {
            case .success(let member):
                self.viewState.addOrReplaceMember(member)
                self.isPresented.toggle()
            case .failure(let failure):
                debugPrint("\(failure)")
            }
        }
        
        
    }
}


struct IdentityValues: Equatable {
    var icon: Icon
    var nickname: String
    var newIconId : String? = nil
}

#Preview {
    @Previewable @StateObject var viewState = ViewState.preview()
    IdentitySheet(isPresented: .constant(true), server: viewState.servers["0"]!,
                  member: (.init(id: .init(server: "0", user: "0"), joined_at: "")),
                  currentValues: .init(icon: .local(Data()), nickname: "Jack"))
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
