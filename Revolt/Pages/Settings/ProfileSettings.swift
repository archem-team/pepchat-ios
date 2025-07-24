//
//  ProfileSettings.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI
import Types
import PhotosUI

/// A view that displays and manages the user's profile settings.
///
/// This view presents the user's profile picture, username, discriminator, and banner. It retrieves
/// the user's profile data from the environment and displays it accordingly. The user can view their
/// avatar and banner image within the UI.
///
/// - Note: This view fetches the profile data asynchronously when it appears and utilizes the
///         `ViewState` environment object to access the current user and theme.
struct ProfileSettings: View {
    @EnvironmentObject var viewState: ViewState
    
    @State private var isPresentedSatusSheet : Bool = false
    @State private var isPresentedPresenceSheet : Bool = false
    
    
    
    @State var showSaveButton: Bool = true
    
    
    @State var currentValues : ProfileValues
    @State var initialValues : ProfileValues? = nil
    
    
    @State private var displayNameTextFieldState : PeptideTextFieldState = .default
    @State private var contentTextFieldState : PeptideTextFieldState = .default
    
    
    @State var showAvatarPhotoPicker: Bool = false
    @State var avatarPhoto: PhotosPickerItem?
    
    
    @State var showBackgroundPhotoPicker: Bool = false
    @State var backgroundPhoto: PhotosPickerItem?
    
    
    @State var saveBtnState : ComponentState = .default
    
    
    struct ProfileValues: Equatable {
        var avatar: Icon
        var background : Icon
        var displayName: String
        var content : String
    }
    
    @MainActor
    static func fromState(currentUser: User) -> Self {
        let iconType : Icon = {
            if let avatar = currentUser.avatar {
                return .remote(avatar)
            } else {
                return .local(nil)
            }
        }()
        
        let settings = ProfileValues(
            avatar: iconType,
            background: .local(nil),
            displayName: currentUser.display_name ?? "",
            content: ""
        )
        
        return .init(currentValues: settings)
    }
    
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                
                self.displayNameTextFieldState = .default
                
                if(self.currentValues.displayName.count < 2){
                    
                    self.displayNameTextFieldState = .error(message: "Display name could not be shorter that 2 characters.", icon: .peptideInfo)
                    
                    return
                    
                }else if(self.currentValues.displayName.count > 32){
                    
                    self.displayNameTextFieldState = .error(message: "Display name could not be longer that 32 characters.", icon: .peptideInfo)
                    
                    return
                    
                }
                
                Task {
                    
                    self.saveBtnState = .loading
                    
                    var avatarUploadededId : String?
                    var backgroundUploadedId : String?
                    
                    if case .local(let avatar) = currentValues.avatar, let avatar {
                        let uploadedResponse = await viewState.http.uploadFile(data: avatar, name: "profile", category: .avatar)
                        switch uploadedResponse {
                        case .success(let success):
                            avatarUploadededId = success.id
                        case .failure(let failure):
                            debugPrint("\(failure)")
                        }
                    }
                    
                    
                    if case .local(let background) = currentValues.background, let background {
                        let uploadedResponse = await viewState.http.uploadFile(data: background, name: "background", category: .background)
                        switch uploadedResponse {
                        case .success(let success):
                            backgroundUploadedId = success.id
                        case .failure(let failure):
                            debugPrint("\(failure)")
                        }
                    }
                    
                    
                    let updateSelfResponse = await viewState.http.updateSelf(profile: .init(displayName: currentValues.displayName,
                                                                           profile: .init(content: currentValues.content, background: backgroundUploadedId),
                                                                           avatar: avatarUploadededId))
                    
                    self.saveBtnState = .default
                    
                    //TODO:
                    switch updateSelfResponse {
                    case .success(let success):
                        self.viewState.currentUser = success
                        self.viewState.path.removeLast()
                    case .failure(let failure):
                        debugPrint("\(failure)")
                    }
                    
                }
                
                
            } label: {
                
                
                
                if self.saveBtnState == .loading {
                    ProgressView()
                        .tint(.iconDefaultGray01)
                } else if self.initialValues != nil, self.initialValues != self.currentValues {
                    PeptideText(text: "Save",
                                font: .peptideButton,
                                textColor: .textYellow07,
                                alignment: .center)
                }
                
                
            }
                .opacity(showSaveButton ? 1 : 0)
                .disabled(!showSaveButton)
            
            
        )
    }
    
    
    var body: some View {
        let currentUser = viewState.currentUser
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Edit Profile",
                                                 customToolbarView: saveBtnView)){_,_ in
            
            
            
            VStack(alignment: .leading, spacing: .zero) {
                
                ZStack(alignment: .bottomLeading) {
                    
                    ZStack(alignment: .trailing){
                        
                        VStack(spacing: .zero){
                            
                            
                            Group {
                                
                                ZStack(alignment: .topTrailing){
                                
                                    switch self.currentValues.background {
                                        case .remote(let file):
                                            if let file = file {
                                                
                                                ZStack {
                                                    LazyImage(source: .file(file), height: 130, clipTo: RoundedRectangle(cornerRadius: .zero))
                                                        .overlay{
                                                            RoundedRectangle(cornerRadius: .zero)
                                                                .fill(Color.bgDefaultPurple13.opacity(0.2))
                                                        }
                                                }
                                                .frame(height: 130)
                                            } else {
                                                Image(.coverPlaceholder)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(height: 130)
                                            }
                                        case .local(let data):
                                            if let data = data {
                                                
                                                LazyImage(source: .local(data), height: 130, clipTo: Rectangle(), contentMode: .fill)
                                                    .aspectRatio(contentMode: .fill)
                                                    .clipped()
                                                    .overlay{
                                                        RoundedRectangle(cornerRadius: .zero)
                                                            .fill(Color.bgDefaultPurple13.opacity(0.2))
                                                            .frame(height: 130)
                                                    }
                                            } else {
                                                Image(.coverPlaceholder)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(height: 130)
                                            }
                                    }
                                    
                                    PeptideIcon(iconName: .peptideAddPhoto,
                                                size: .size20,
                                                color: .iconDefaultGray01)
                                    .frame(width: .size32, height: .size32)
                                    .background{
                                        Circle().fill(Color.bgDefaultPurple13.opacity(0.6))
                                    }
                                    .padding(.all, .size16)
                                    .onTapGesture { showBackgroundPhotoPicker = true }
                                }
                                                                
                            }
                            .onTapGesture {
                                self.showBackgroundPhotoPicker = true
                            }
                            
                            
                            
                            
                            
                            RoundedRectangle(cornerRadius: .zero)
                                .fill(Color.clear)
                                .frame(height: .size32)
                            
                        }
                        
                        /*PeptideIcon(iconName: .peptideSetting,
                                    size: .size20,
                                    color: .iconDefaultGray01)
                        .frame(width: .size32,
                               height: .size32)
                        .background(Circle().fill(Color.bgPurple13Alpha60))
                        .padding(.padding16)*/
                        
                    }
                    
                    if let currentUser {
                        
                        HStack(spacing: .zero){
                            
                            
                            ZStack(alignment: .topLeading) {
                                
                                Group {
                                    switch currentValues.avatar {
                                    case .remote(let file):
                                        // Display remote icon if available.
                                        if file != nil {
                                            Avatar(user: viewState.currentUser!,
                                                   width: 58,
                                                   height: 58,
                                                   withPresence: false)
                                        }
                                    case .local(let data):
                                        // Display the locally selected icon.
                                        if let data {
                                            LazyImage(source: .local(data), height: 58, width: 58, clipTo: Circle())
                                        } else {
                                            Avatar(user: viewState.currentUser!,
                                                   width: 58,
                                                   height: 58)
                                        }
                                    }
                                }
                                .frame(width: 64, height: 64)
                                .background{
                                    Circle()
                                        .fill(Color.bgGray12)
                                }
                                
                                PeptideIcon(iconName: .peptideAddPhoto,
                                            size: .size20,
                                            color: .iconDefaultGray01)
                                .frame(width: .size32, height: .size32)
                                .background{
                                    Circle().fill(Color.bgDefaultPurple13.opacity(0.6))
                                }
                                .offset(y: -12)
                                .onTapGesture { showAvatarPhotoPicker = true }
                                
                                
                            }
                            .padding(.leading, .padding16)
                            
                            
                            
                            
                            ZStack(alignment: .topLeading){
                                
                                Image(.peptideUnion)
                                    .renderingMode(.template)
                                    .foregroundStyle(.bgGray11)
                                
                                
                                Button {
                                    self.isPresentedSatusSheet.toggle()
                                } label: {
                                    HStack(spacing: .spacing4){
                                        
                                        let statusLabel = currentUser.status?.text ?? "Add Status"
                                        
                                        
                                        if(currentUser.status?.text?.isEmpty ?? true){
                                            PeptideIcon(iconName: .peptideAdd2,
                                                        color: .iconGray07)
                                        }
                                        
                                        PeptideText(text: statusLabel,
                                                    font: .peptideSubhead,
                                                    textColor: .textGray07)
                                        
                                    }
                                    .padding(leading: .padding8, trailing: .padding12)
                                    .frame(minWidth: 80, minHeight: .size36)
                                    .background{
                                        RoundedRectangle(cornerRadius: .radiusXSmall)
                                            .fill(Color.bgGray11)
                                    }
                                }
                                .shadow(color: .bgDefaultPurple13.opacity(0.2), radius: 2, x: 0, y: 0)
                                .padding(.padding16)
                            }
                        }
                        
                    }
                    
                }
                
                
                if let currentUser {
                    VStack(alignment: .leading, spacing: .spacing2) {
                        
                        
                        Button {
                            self.isPresentedPresenceSheet.toggle()
                        } label: {
                            HStack(spacing: .spacing2){
                                
                                PeptideText(textVerbatim: currentUser.display_name ?? currentUser.username,
                                            font: .peptideTitle4,
                                            textColor: .textDefaultGray01)
                                
//                                PeptideIcon(iconName: .peptideArrowRight,
//                                            size: .size16,
//                                            color: .iconGray07)
//                                .rotationEffect(.degrees(90))
                            }
                        }
                        
                        HStack(spacing: .spacing4) {
                            
                            let username = "\(currentUser.username)#\(currentUser.discriminator)"
                            
                            PeptideText(textVerbatim: username,
                                        font: .peptideBody4,
                                        textColor: .textGray07)
                            
//                            PeptideIconButton(icon: .peptideCopy,
//                                              color: .iconGray07,
//                                              size: .size12){
//                                //TODO
//                                copyText(text: username)
//                            }
                            
                            
                        }
                        
                        
                    }
                    .padding(top: .padding16)
                    .padding(.horizontal, .padding16)
                }
                
                
                
                
            }
            
            
            Group {
                
                PeptideTextField(text: self.$currentValues.displayName,
                                 state: self.$displayNameTextFieldState,
                                 label: "Display Name",
                                 placeholder: "Enter Display Name...",
                                 hasClearBtn: false
                )
                
                
                PeptideTextField(text: self.$currentValues.content,
                                 state: self.$contentTextFieldState,
                                 label: "About Me",
                                 placeholder: "Write something cool about yourself...",
                                 hasClearBtn: false
                )
                
                
            }
            .padding(.horizontal, .padding16)
            .padding(.top, .padding16)
            
            
            
            
            
            Spacer(minLength: .zero)
            
            
            
            /*
             
             VStack(alignment: .leading) {
             if let displayName = currentUser!.display_name {
             Text(displayName)
             .foregroundStyle(.white)
             .bold()
             }
             
             Text("\(currentUser!.username)")
             .foregroundStyle(.white)
             + Text("#\(currentUser!.discriminator)")
             .foregroundStyle(.gray)
             }
             
             
             */
            
            
        }
         .sheet(isPresented: self.$isPresentedSatusSheet){
            StatusSheet(isPresented: $isPresentedSatusSheet)
         }
         .photosPicker(isPresented: $showAvatarPhotoPicker, selection: $avatarPhoto, matching: .images)
         .onChange(of: self.currentValues.displayName){
             self.displayNameTextFieldState = .default
         }
         .onChange(of: avatarPhoto) { (_, new) in
             Task {
                 // Load the selected photo and update the icon.
                 if let photo = new {
                     if let data = try? await photo.loadTransferable(type: Data.self) {
                         currentValues.avatar = .local(data)
                     }
                 }
             }
         }
         .photosPicker(isPresented: $showBackgroundPhotoPicker, selection: $backgroundPhoto, matching: .images)
         .onChange(of: backgroundPhoto) { (_, new) in
             Task {
                 // Load the selected photo and update the icon.
                 if let photo = new {
                     if let data = try? await photo.loadTransferable(type: Data.self) {
                         currentValues.background = .local(data)
                     }
                 }
             }
         }
         .task {
             self.initialValues = self.currentValues
             // Asynchronously fetch the user's profile data if not already available
             let profileResponse =  await viewState.http.fetchProfile(user: viewState.currentUser!.id)
             switch profileResponse {
             case .success(let success):
                 
                 if let bg =  success.background {
                     self.currentValues.background = .remote(bg)
                 }
                 self.currentValues.displayName = currentUser?.display_name ?? ""
                 self.currentValues.content = success.content ?? ""
                 self.initialValues = self.currentValues
             case .failure(let failure):
                 debugPrint("\(failure)")
             }
             
         }
        
    }
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ProfileSettings(currentValues: .init(avatar: .local(nil), background: .local(nil), displayName: "Abcd", content: ""))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
