//
//  ServerOverviewSettings.swift
//  Revolt
//
//  Created by Angelo on 07/01/2024.
//

import Foundation
import SwiftUI
import PhotosUI
import Types

struct ServerOverviewSettings: View {
    @EnvironmentObject var viewState: ViewState
    
    
    struct ServerSettingsValues: Equatable {
        var icon: SettingImage
        var banner: SettingImage
        var name: String
        var description: String
        var system_channels: SystemMessages
    }
    
    @State var initial: ServerSettingsValues
    @State var currentValues: ServerSettingsValues
    @State var showSaveButton: Bool = false
    
    @State var showIconPhotoPicker: Bool = false
    @State var serverIconPhoto: PhotosPickerItem? = nil
    
    @State var showBannerPhotoPicker: Bool = false
    @State var serverBannerPhoto: PhotosPickerItem? = nil
    
    @Binding var server: Server
    
    
    @State private var serverNameTextFieldState : PeptideTextFieldState = .default
    @State private var serverDescriptionTextFieldState : PeptideTextFieldState = .default
    
    @State private var selectedSystemMessage : SystemMessageType = .userJoined
    @State private var isPresentedSystemMessageSheet: Bool = false

    @State private var saveBtnState : ComponentState = .default
    
    
    init(server s: Binding<Server>) {
        let settings = ServerSettingsValues(
            icon: .remote(s.icon.wrappedValue),
            banner: .remote(s.banner.wrappedValue),
            name: s.name.wrappedValue,
            description: s.description.wrappedValue ?? "",
            system_channels: s.system_messages.wrappedValue ?? SystemMessages()
        )
        
        self.initial = settings
        self.currentValues = settings
        _server = s
    }
    
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                updateServer()
            } label: {
                
                if saveBtnState == .loading {
                    
                    ProgressView()
                    
                } else {
                    
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
    
    
    var isShowRemoveIconBtn: Bool {
        switch self.currentValues.icon {
        case .remote(let file):
            return file != nil
        case .local(let data):
            return data != nil
        }
    }
    
    var isShowRemoveBannerBtn: Bool {
        switch self.currentValues.banner {
        case .remote(let file):
            return file != nil
        case .local(let data):
            return data != nil
        }
    }
    
    
    var body: some View {
        
      
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Overview",
                                                 customToolbarView: saveBtnView)){_,_ in
            
            let _ = selectedSystemMessage
            
            Group {
                
                ZStack(alignment: .topTrailing) {
                    switch currentValues.icon {
                    case .remote(let file):
                        if let file = file {
                            AnyView(LazyImage(source: .file(file), height: .size48, width: .size48, clipTo: Circle()))
                        } else {
                            FallbackServerIcon(name: server.name, width:  .size48, height:  .size48, clipTo: Circle())
                        }
                    case .local(let photo):
                        if let photo = photo {
                            LazyImage(source: .local(photo.content), height: .size48, width: .size48, clipTo: Circle())
                        } else {
                            FallbackServerIcon(name: server.name, width:  .size48, height:  .size48, clipTo: Circle())
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
                .photosPicker(isPresented: $showIconPhotoPicker, selection: $serverIconPhoto)
                .onChange(of: serverIconPhoto) { (_, new) in
                    Task {
                        if let photo = new {
                            if let data = try? await photo.loadTransferable(type: Data.self) {
                                // Check if the file size exceeds 2.5 MB (2.5 * 1024 * 1024 bytes)
                                let maxSize: Int = 2_621_440 // 2.5 MB in bytes
                                if data.count > maxSize {
                                    // File is too large, show alert and reset the photo picker
                                    viewState.showAlert(message: "Icon must be smaller than 2.5 MB", icon: .peptideInfo, color: .iconRed07)
                                    serverIconPhoto = nil
                                } else {
                                    // File size is acceptable, proceed with setting the icon
                                    currentValues.icon = .local(LocalFile(content: data, filename: "icon.\(photo.supportedContentTypes[0].preferredFilenameExtension!)"))  // TODO: figure out filename
                                }
                            }
                        }
                    }
                }
                
                
                if isShowRemoveIconBtn {
                    Button {
                        
                        switch currentValues.icon {
                            case .remote(_):
                                self.currentValues.icon = .local(nil)

                            case .local(_):
                                self.currentValues.icon = .local(nil)

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
                
                
                
                PeptideText(text: "Max 2.50 MB",
                            font: .peptideCaption1,
                            textColor: .textGray07)
                
            }
            .padding(.horizontal, .padding16)
            
            
            Group {
                PeptideTextField(text: $currentValues.name,
                                 state: $serverNameTextFieldState,
                                 label: "SERVER NAME",
                                 placeholder: "Enter server name")
                .onChange(of: currentValues.name){_,_ in
                    self.serverNameTextFieldState = .default
                }
                
               
                PeptideTextField(text: $currentValues.description,
                                 state:$serverDescriptionTextFieldState,
                                 label: "SERVER DESCRIPTION",
                                 placeholder: "Add a description...")
            }
            .padding(.horizontal, .padding16)
            .padding(.top, .padding24)
            
            
            Group {
                
                HStack(spacing: .zero){
                    
                    PeptideText(text: "CUSTOM BANNER",
                                font: .peptideBody3,
                                textColor: .textGray06)
                    
                    Spacer(minLength: .zero)
                }
                .padding(.top, .padding24)
                
                
                Button {
                    showBannerPhotoPicker = true
                } label: {
                    switch currentValues.banner {
                        case .remote(let file):
                            if let file {
                                
                                Color.clear
                                    .overlay {
                                        LazyImage(source: .file(file), height: 176, clipTo: RoundedRectangle(cornerRadius: .radius8))
                                    }
                                    .clipped()
                                    .frame(height: 176)
                                    .clipShape(RoundedRectangle(cornerRadius: .radius8))
                                
                            } else {
                                ServerEmptyBanner()
                            }
                        case .local(let photo):
                            if let photo {
                                
                                Color.clear
                                    .overlay {
                                        LazyImage(source: .local(photo.content), height: 176, clipTo: RoundedRectangle(cornerRadius: .radius8))
                                    }
                                    .clipped()
                                    .frame(height: 176)
                                    .clipShape(RoundedRectangle(cornerRadius: .radius8))
                                
                                
                            } else {
                                ServerEmptyBanner()
                            }
                    }
                }
                .photosPicker(isPresented: $showBannerPhotoPicker, selection: $serverBannerPhoto)
                .onChange(of: serverBannerPhoto) { (_, new) in
                    Task {
                        if let photo = new {
                            if let data = try? await photo.loadTransferable(type: Data.self) {
                                // Check if the file size exceeds 6 MB (6 * 1024 * 1024 bytes)
                                let maxSize: Int = 6_291_456 // 6 MB in bytes
                                if data.count > maxSize {
                                    // File is too large, show alert and reset the photo picker
                                    viewState.showAlert(message: "Banner must be smaller than 6 MB", icon: .peptideInfo, color: .iconRed07)
                                    serverBannerPhoto = nil
                                } else {
                                    // File size is acceptable, proceed with setting the banner
                                    currentValues.banner = .local(LocalFile(content: data, filename: "banner.\(photo.supportedContentTypes[0].preferredFilenameExtension!)"))  // TODO: figure out filename
                                }
                            }
                        }
                    }
                }
                
                
                if isShowRemoveBannerBtn {
                    Button {
                        
                        switch currentValues.banner {
                            case .remote(_):
                                self.currentValues.banner = .local(nil)

                            case .local(_):
                                self.currentValues.banner = .local(nil)

                        }
                        
                    } label: {
                        HStack(spacing: .spacing2){
                            PeptideIcon(iconName: .peptideTrashDelete,
                                        size: .size16,
                                        color: .iconRed07)
                            
                            PeptideText(text: "Remove Banner",
                                        font: .peptideCaption1,
                                        textColor: .textRed07)
                            
                        }
                       
                    }
                }
                
                
                
//                PeptideText(text: "Max 6.00 MB",
//                            font: .peptideCaption1,
//                            textColor: .textGray07)
//                
                
                /*Button {
                    currentValues.banner = .local(nil)
                } label: {
                    Text("Remove")
                        .font(.caption)
                        .foregroundStyle(viewState.theme.foreground2)
                }*/
                
            }
            .padding(.horizontal, .padding16)
             
            
            HStack{
                PeptideText(text: "SYSTEM MESSAGE CHANNELS",
                            font: .peptideBody3,
                            textColor: .textGray06)
//                .padding(.bottom, .size4)
                .padding(.horizontal, .size20)
                .padding(.top, .size24)
                
                Spacer(minLength: .zero)
            }
            
             VStack(spacing: .spacing4){
                 
                 Button {
                     self.selectedSystemMessage = .userJoined
                     self.isPresentedSystemMessageSheet.toggle()
                 } label: {
                     
                     PeptideActionButton(icon: .peptideSignInJoin,
                                         title: "User Joined",
                                         value: currentChannelForSystemMessage(systemMessage: .userJoined).title,
                                         hasArrow: true)
                 }
                 
                 
                 
                 PeptideDivider()
                     .padding(.leading, .padding48)
                 
                 
                 Button {
                     self.selectedSystemMessage = .userLeft
                     self.isPresentedSystemMessageSheet.toggle()
                 } label: {
                     
                     PeptideActionButton(icon: .peptideSignOutLeave,
                                         title: "User Left",
                                         value: currentChannelForSystemMessage(systemMessage: .userLeft).title,
                                         hasArrow: true)
                 }
                 
                 
                 
                 PeptideDivider()
                     .padding(.leading, .padding48)
                 
                 
                 
                 Button {
                     self.selectedSystemMessage = .userKicked
                     self.isPresentedSystemMessageSheet.toggle()
                 } label: {
                     
                     PeptideActionButton(icon: .peptideCancelFriendRequest,
                                         title: "User Kicked",
                                         value: currentChannelForSystemMessage(systemMessage: .userKicked).title,
                                         hasArrow: true)
                 }
                 
                 
                 
                 PeptideDivider()
                     .padding(.leading, .padding48)
                 
                 
                 
                 Button {
                     self.selectedSystemMessage = .userBanned
                     self.isPresentedSystemMessageSheet.toggle()
                 } label: {
                     
                     PeptideActionButton(icon: .peptideProhibitNoneBlock,
                                         title: "User Banned",
                                         value: currentChannelForSystemMessage(systemMessage: .userBanned).title,
                                         hasArrow: true)
                 }
                 
             }
             .backgroundGray11(verticalPadding: .padding4)
             .padding(.horizontal, .padding16)
             .padding(.bottom, .padding24)
             
             
             

            
            Spacer(minLength: .zero)
    
            .onChange(of: currentValues) { showSaveButton = true }
            .sheet(isPresented: $isPresentedSystemMessageSheet){
                SystemMessageSheet(systemMessage: selectedSystemMessage,
                                   server: server,
                                   selectedChannelId: currentChannelForSystemMessage(systemMessage: selectedSystemMessage).id, onSelected: { channelId, type in
                    
                    self.isPresentedSystemMessageSheet.toggle()
                    
                    switch type {
                        case .userJoined :
                            currentValues.system_channels.user_joined = channelId
                        case .userLeft:
                            currentValues.system_channels.user_left = channelId
                        case .userKicked:
                            currentValues.system_channels.user_kicked = channelId
                        case .userBanned:
                            currentValues.system_channels.user_banned = channelId
                        default:
                            debugPrint("error")

                    }
                    
                })
                    .presentationDetents([.medium, .large])
            }
            
        }
        
    }
    
    
    func currentChannelForSystemMessage(systemMessage: SystemMessageType) -> (title: String, id: String?) {
        let systemMessages = currentValues.system_channels

        let channelId: String?
        switch systemMessage {
        case .userJoined:
            channelId = systemMessages.user_joined
        case .userLeft:
            channelId = systemMessages.user_left
        case .userKicked:
            channelId = systemMessages.user_kicked
        case .userBanned:
            channelId = systemMessages.user_banned
        default:
            channelId = nil
        }

        if let id = channelId, let channel = getServerChannel().first(where: { $0.id == id }) {
            return (channel.name, channelId)
        } else {
            return ("None", nil)
        }
    }
    
    func getServerChannel() -> [TextChannel] {
        return server.channels.compactMap { channelId in
            if case .text_channel(let textChannel) = viewState.channels[channelId] {
                return textChannel
            } else {
                return nil
            }
        }
    }
    
    
    func updateServer() {
        Task {
            
            if currentValues.name.isEmpty {
                self.serverNameTextFieldState = .error(message: "The server name is required.")
                return
            }
            
            var edits = ServerEdit()
            
            if currentValues.name != initial.name {
                edits.name = currentValues.name
            }
            
            if currentValues.icon != initial.icon {
                
                switch currentValues.icon {
                    case .local(let photo):
                        if let photo = photo {
                            let fileResponse = await viewState.http.uploadFile(data: photo.content, name: photo.filename, category: .icon)
                            
                            switch fileResponse {
                            case .success(let res):
                                edits.icon = res.id
                            case .failure(_):
                                break
                                
                            }
                            
                        } else {
                            edits.remove = edits.remove ?? []
                            edits.remove!.append(.icon)
                        }
                    default:
                        ()
                }
                
            }
            
            if currentValues.banner != initial.banner {
                
                switch currentValues.banner {
                    case .local(let photo):
                        if let photo = photo {
                            let fileResponse = await viewState.http.uploadFile(data: photo.content, name: photo.filename, category: .banner)
                            
                            switch fileResponse {
                            case .success(let res):
                                edits.banner = res.id
                            case .failure(_):
                                break
                                
                            }
                            
                        } else {
                            edits.remove = edits.remove ?? []
                            edits.remove!.append(.banner)
                        }
                    default:
                        ()
                }
            }
            
            if currentValues.description != initial.description {
                if currentValues.description.isEmpty {
                    edits.remove = edits.remove ?? []
                    edits.remove!.append(.description)
                } else {
                    edits.description = currentValues.description                    
                }
            }
            
            if currentValues.system_channels != initial.system_channels {
                edits.system_messages = currentValues.system_channels
            }
            
            self.hideKeyboard()
            self.saveBtnState = .loading
            
            
            let editServerResponse = await viewState.http.editServer(server: server.id, edits: edits)
            
            self.saveBtnState = .default

            
            switch editServerResponse {
                case .success(let server):
                    self.viewState.servers[server.id] = server
                    initial = currentValues
                    showSaveButton = false
                    serverIconPhoto = nil
                    serverBannerPhoto = nil
                    self.viewState.showAlert(message: "Changes saved!", icon: .peptideInfo)
                    if self.viewState.path.count > 0 {
                        self.viewState.path.removeLast()
                    }
                  
                case .failure(let failure):
                    print("error \(failure)")
            }
            
            //self.viewState.path.removeLast()
            
        }

    }
    
}


struct ServerEmptyBanner : View {
    var body: some View {
        
        ZStack{
            
            RoundedRectangle(cornerRadius: .radius8)
                .fill(Color.bgGray12)
                .frame(height: 176)
                .overlay{
                    RoundedRectangle(cornerRadius: .radius8)
                        .strokeBorder(style: StrokeStyle(
                            lineWidth: .size1,
                            dash: [5,5]
                        ))
                        .foregroundStyle(Color.borderGray10)
                }
            
            
            VStack(spacing: .spacing4){
                PeptideIcon(iconName: .peptideAddPhoto,
                            size: .size24,
                            color: .iconDefaultGray01)
                
                PeptideText(text: "Add Banner Max (6 MB)",
                            font: .peptideFootnote,
                            textColor: .textGray06)
            }
        }
        
    }
}


#Preview {
    @Previewable @StateObject var viewState = ViewState.preview()
    let server = Binding($viewState.servers["0"])!
    
    return NavigationStack {
        ServerOverviewSettings(server: server)
    }
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}


#Preview {
    ServerEmptyBanner()
}



