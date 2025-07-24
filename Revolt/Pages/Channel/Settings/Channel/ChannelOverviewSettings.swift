//
//  ChannelOverviewSettings.swift
//  Revolt
//
//  Created by Angelo on 07/01/2024.
//

import Foundation
import SwiftUI
import PhotosUI
import Types

/// A view that allows users to manage the overview settings of a channel.
struct ChannelOverviewSettings: View {
    /// The environment object that holds the current application state.
    @EnvironmentObject var viewState: ViewState
    

    
    /// Struct to hold channel settings values.
    struct ChannelSettingsValues: Equatable {
        var icon: Icon        // The channel's icon.
        var name: String      // The channel's name.
        var description: String // The channel's description.
        var nsfw: Bool        // Indicates if the channel is NSFW (Not Safe For Work).
    }
    
    @State var currentValues: ChannelSettingsValues // The current values of the channel settings.
    @State var showSaveButton: Bool = false         // Flag to show/hide the save button.
    @State var saveBtnState : ComponentState = .default
    @State var showIconPhotoPicker: Bool = false    // Flag to show/hide the photo picker for icons.
    @State var serverIconPhoto: PhotosPickerItem?    // The selected photo item from the photo picker.
    
    @Binding var channel: Channel // A binding to the channel whose settings are being managed.
    var server : Server? = nil
    
    
    @State private var nameTextFieldState : PeptideTextFieldState = .default
    @State private var descriptionTextFieldState : PeptideTextFieldState = .default
    
    //textChannel vs DMGroupChannel
    var isTextChannel : Bool {
        switch self.channel{
        case .text_channel(_):
            return true
        default:
            return false
        }
    }
    
    
    /// Creates an instance of `ChannelOverviewSettings` from the current state.
    /// - Parameters:
    ///   - viewState: The current application state.
    ///   - channel: A binding to the channel whose settings are being managed.
    /// - Returns: A configured `ChannelOverviewSettings` instance.
    @MainActor
    static func fromState(viewState: ViewState,
                          channel c: Binding<Channel>) -> Self {
        let settings = ChannelSettingsValues(
            icon: .remote(c.wrappedValue.icon),
            name: c.wrappedValue.getName(viewState),
            description: c.wrappedValue.description ?? "",
            nsfw: c.wrappedValue.nsfw
        )
        //TODO: server
        return .init(currentValues: settings, channel: c)
    }
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                //TODO:
                Task {
                    
                    self.saveBtnState = .loading
                    
                    var channelName : String? = nil
                    var channelDescription : String? = nil
                    var removeFields : [ChannelEditPayload.RemoveField] = []
                    var icon : (Data,String)? = nil
                    
                     if self.channel.getName(viewState) != currentValues.name && currentValues.name.isNotEmpty {
                         channelName = currentValues.name
                    }
                    
                    
                    if self.channel.description != currentValues.description && currentValues.description.isNotEmpty {
                        channelDescription = currentValues.description
                    }
                    
                    if self.channel.description?.isNotEmpty ?? false && currentValues.description.isEmpty {
                        removeFields.append(.description)
                    }
                    
                    
                    if case .local(let data) = currentValues.icon, let data {
                        icon = (data, "channel icon")
                    }
                    
                    if case .local(let data) = currentValues.icon {
                        if data == nil && channel.icon != nil {
                            removeFields.append(.icon)
                        }
                    }
                    
                    //Check image size
                    
                    //TODO empty name
                    
                    let response = await viewState.http.editChannel(id: self.channel.id,
                                                                    name: channelName,
                                                                    description: channelDescription,
                                                                    icon: icon,
                                                                    nsfw: currentValues.nsfw,
                                                                    remove: removeFields.isEmpty ? nil : removeFields)
                    
                    self.saveBtnState = .default
                    
                    switch response {
                    case .success(let success):
                        self.viewState.channels[self.channel.id] = success
                        self.viewState.showAlert(message: "\(isTextChannel ? "Channel":"Group")  Changes Updated!", icon: .peptideDoneCircle)
                        self.viewState.path.removeLast()
                    case .failure(let failure):
                        debugPrint("error \(failure)")
                    }
                }
                
            } label: {
                
                if saveBtnState == .loading {
                    
                    //PeptideLoading(activeColor: .iconDefaultGray01)
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
    

    var isShowRemovePhotoBtn: Bool {
        switch self.currentValues.icon {
        case .remote(let file):
            return file != nil
        case .local(let data):
            return data != nil
        }
    }

    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: isTextChannel ? "Overview":"Customize Group",
                                                 showBackButton: true,
                                                 customToolbarView: saveBtnView,
                                                 showBottomLine: true)){_,_ in
            
            
            VStack(spacing: .zero){
                Group {
                    
                    ZStack(alignment: .topTrailing) {
                        switch currentValues.icon {
                        case .remote(let file):
                            // Display remote icon if available.
                            if let file = file {
                                AnyView(LazyImage(source: .file(file), height: .size48, width: .size48, clipTo: Circle()))
                            } else {
                                // Display a placeholder if no remote icon is available.
                                ChannelOnlyIcon(channel: self.channel, frameSize: (.size48,.size48))
                                
                            }
                        case .local(let data):
                            if let data {
                                LazyImage(source: .local(data), height: .size48, width: .size48, clipTo: Circle())
                            } else {
                                ChannelOnlyIcon(channel: self.channel, frameSize: (.size48,.size48), showPlaceHolder: true)
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
                        .photosPicker(isPresented: $showIconPhotoPicker, selection: $serverIconPhoto)
                        .onChange(of: serverIconPhoto) { (_, new) in
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
                    .padding(.top, .padding24)
                    .padding(.bottom, .padding8)
                    
                    if(currentValues.icon.isNotEmpty()){

                        Button {
                            self.currentValues.icon = .local(nil)
                        } label: {

                            HStack(spacing: .spacing2){
                                PeptideIcon(iconName: .peptideTrashDelete,
                                            size: .size16,
                                            color: .iconRed07)

                                PeptideText(text: "Remove Photo",
                                            font: .peptideCaption1,
                                            textColor: .textRed07)

                            }
                            .padding(.bottom, .size2)
                        }

                    }
                    
                    PeptideText(text: "Max 2.50 MB",
                                font: .peptideCaption1,
                                textColor: .textGray07)

                }
                .padding(.horizontal, .padding16)

                
                Group {
                    PeptideTextField(text: $currentValues.name,
                                     state: $nameTextFieldState,
                                     size: .large,
                                     label: "\(isTextChannel ? "CHANNEL":"GROUP") NAME",
                                     placeholder: "group name",
                                     keyboardType: .default)
                    .padding(.top, .padding24)
                    
                    
                    PeptideTextField(text: $currentValues.description,
                                     state: $descriptionTextFieldState,
                                     size: .large,
                                     label: "\(isTextChannel ? "CHANNEL":"GROUP") DESCRIPTION",
                                     placeholder: "Add a description...",
                                     keyboardType: .default
                    )
                    .padding(.top, .padding24)
                    
                    
                    HStack(spacing: .spacing8){
                        VStack(alignment: .leading, spacing: .zero){
                            
                            PeptideText(text: "NSFW",
                                        font: .peptideCallout,
                                        textColor: .textDefaultGray01)
                            
                            PeptideText(text: "Set this \(isTextChannel ? "channel":"group")  to NSFW.",
                                        font: .peptideFootnote,
                                        textColor: .textGray06)
                        }
                        
                        Spacer(minLength: .zero)
                        
                        Toggle("", isOn: $currentValues.nsfw)
                            .toggleStyle(PeptideSwitchToggleStyle())
                    }
                    .padding(.top, .padding24)
                    
                }
                .padding(.horizontal, .padding16)
                
              
                
                Spacer(minLength: .zero)
            }
            
            
            
        }
        .onChange(of: currentValues) { showSaveButton = true }

    }
}

#Preview {
    // Preview setup for the ChannelOverviewSettings view.
    let viewState = ViewState.preview()
    let channel = viewState.channels["0"]!
    
    return NavigationStack {
        ChannelOverviewSettings.fromState(viewState: viewState, channel: .constant(channel))
    }
    .applyPreviewModifiers(withState: viewState)
}
