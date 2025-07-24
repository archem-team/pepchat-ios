//
//  ServerChannelOverviewSettings.swift
//  Revolt
//
//


import Foundation
import SwiftUI
import PhotosUI
import Types

struct ServerChannelOverviewSettings: View {
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
    
    var channel: Channel // A binding to the channel whose settings are being managed.
    @Binding var server : Server
    
    @State var selectedcategory : Types.Category? = nil
    
    
    @State private var nameTextFieldState : PeptideTextFieldState = .default
    
    
    @State private var isPresentedCategoriesSheet: Bool = false
    @State private var isPresentedDeleteChannel : Bool = false
    
    
    @State var isLoading: Bool = false


    
    /// Creates an instance of `ChannelOverviewSettings` from the current state.
    /// - Parameters:
    ///   - viewState: The current application state.
    ///   - channel: A binding to the channel whose settings are being managed.
    /// - Returns: A configured `ChannelOverviewSettings` instance.
    init(viewState: ViewState, channel: Channel, server: Binding<Server>) {
            self.channel = channel
            self._server = server
            
            self._currentValues = State(initialValue: ChannelSettingsValues(
                icon: .remote(channel.icon),
                name: channel.getName(viewState),
                description: channel.description ?? "",
                nsfw: channel.nsfw
            ))
            
            self._selectedcategory = State(initialValue: server.wrappedValue.categories?.first(where: { $0.channels.contains(channel.id) }))
        }
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                //TODO:
                Task {
                    
                    if currentValues.name.isEmpty {
                        self.nameTextFieldState = .error(message: "The group name is required.")
                        return
                    }
                    
                    var channelName : String? = nil
//                    var channelDescription : String? = nil
//                    var removeFields : [ChannelEditPayload.RemoveField] = []
//                    var icon : (Data,String)? = nil
                    
                     if self.channel.getName(viewState) != currentValues.name && currentValues.name.isNotEmpty {
                         channelName = currentValues.name
                    }
                    
                    
//                    if self.channel.description != currentValues.description && currentValues.description.isNotEmpty {
//                        channelDescription = currentValues.description
//                    }
//                    
//                    if self.channel.description?.isNotEmpty ?? false && currentValues.description.isEmpty {
//                        removeFields.append(.description)
//                    }
//                    
//                    
//                    if case .local(let data) = currentValues.icon, let data {
//                        icon = (data, "channel icon")
//                    }
//                    
//                    if case .local(let data) = currentValues.icon {
//                        if data == nil && channel.icon != nil {
//                            removeFields.append(.icon)
//                        }
//                    }
                                    
                    let updateServer = {
                        let fromCatgory = server.categories?.first(where: {$0.channels.contains(channel.id)})
                        if(fromCatgory?.id != selectedcategory?.id){
                        
                            let response = await viewState.http.editServer(server: server.id, edits: .init(categories: moveChannel(in: server, channelId: channel.id, fromCategoryId: fromCatgory?.id , toCategoryId: selectedcategory?.id)))
                            
                            switch response {
                            case .success(_): break
                            case .failure(_): throw URLError(.badServerResponse)
                            }
                            
                        }
                    }
                    
                    let updateChannelName = {
                        
                        if(channelName != channel.name){
                        
                            let response = await viewState.http.editChannel(id: self.channel.id,
                                                                            name: channelName
//                                                                            description: channelDescription,
//                                                                            icon: icon,
//                                                                            nsfw: currentValues.nsfw,
//                                                                            remove: removeFields.isEmpty ? nil : removeFields
                            )
                            
                            switch response {
                            case .success(let success):
                                self.viewState.channels[self.channel.id] = success
                                self.viewState.showAlert(message: "Group Changes Updated!", icon: .peptideDoneCircle)
                                self.viewState.path.removeLast()
                            case .failure(let failure):
                                debugPrint("error \(failure)")
                                throw URLError(.badServerResponse)
                            }
                            
                        }
                        
                    }
                    
                    do {
                        
                        self.saveBtnState = .loading
                        
                        try await updateServer()
                        try await updateChannelName()
                        
                        self.saveBtnState = .default
                        
                    } catch {
                        self.saveBtnState = .default
                        self.viewState.showAlert(message: "Something went wronge!", icon: .peptideInfo)
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
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Channel Settings",
                                                 showBackButton: true,
                                                 customToolbarView: saveBtnView,
                                                 showBottomLine: true)){_,_ in
            
            
            VStack(spacing: .zero){
            

                
                Group {
                    PeptideTextField(text: $currentValues.name,
                                     state: $nameTextFieldState,
                                     size: .large,
                                     label: "GROUP NAME",
                                     placeholder: "group name",
                                     keyboardType: .default)
                    .onChange(of: self.currentValues.name){_,_ in
                        self.nameTextFieldState = .default
                    }
                    
                    if self.server.categories?.isEmpty == false {
                    
                        Button {
                            self.isPresentedCategoriesSheet.toggle()
                        } label: {
                            
                            PeptideActionButton(icon: .peptideFolder,
                                                title: "Category",
                                                value: self.selectedcategory?.title ?? "",
                                                valueColor: .textGray06,
                                                arrowColor: .iconGray07,
                                                hasArrow: true)
                        }
                        .backgroundGray11(verticalPadding: .padding4)
                        
                    }
                    
                    
                    Button {
                        self.isPresentedDeleteChannel.toggle()
                    } label: {
                        
                        HStack(spacing: .spacing4){
                            PeptideIcon(iconName: .peptideTrashDelete,
                                        size: .size16,
                                        color: .iconRed07)
                            .padding(.vertical, .padding8)
                            
                            PeptideText(text: "Delete Channel",
                                        font: .peptideButton,
                                        textColor: .textRed07)
                        }
                    }
                    
                }
                .padding(.top, .padding24)
                .padding(.horizontal, .padding16)

              
                Spacer(minLength: .zero)
            }
            
            
            
        }
        .onChange(of: currentValues) {
            
            self.updateSaveButtonVisibility()
            
        }
        .onChange(of: selectedcategory){
            
            self.updateSaveButtonVisibility()
            
        }
        .sheet(isPresented: $isPresentedCategoriesSheet){
            ServerCategorySheet(
                isPresented: $isPresentedCategoriesSheet,
                server:self.server, selectedCategoryId: selectedcategory?.id, onSelectedCategory: { category in
                self.selectedcategory = category
            })
        }
        .popup(isPresented: $isPresentedDeleteChannel, view: {
            
            ConfirmationSheet(
                isPresented: $isPresentedDeleteChannel,
                isLoading: $isLoading,
                title: "Delete Channel?",
                subTitle: "Are you sure you want to delete \(self.channel.name ?? "")? This cannot be undone.",
                confirmText: "Delete",
                dismissText: "Cancel"
            ){
                
                Task {
                    
                    isLoading.toggle()
                    
                    let deleteResponse = await viewState.http.deleteChannel(target: channel.id)
                    
                    isLoading.toggle()
                    
                    switch deleteResponse {
                    case .success(_):
                        self.isPresentedDeleteChannel.toggle()
                        viewState.removeChannel(with: channel.id, initPath: false)
                        viewState.path.removeLast()
                    case .failure(let failure):
                        debugPrint("\(failure)")
                    }
                    
                }
                
            }
            
        }, customize: {
            $0.type(.default)
                .isOpaque(false)
                .appearFrom(.bottomSlide)
                .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                .closeOnTap(false)
                .closeOnTapOutside(false)
        })

    }
    
    
    func updateSaveButtonVisibility(){
        
        let fromCatgory = server.categories?.first(where: {$0.channels.contains(channel.id)})
        
        showSaveButton = currentValues.name != self.channel.name || selectedcategory?.id != fromCatgory?.id
        
    }
    
    func moveChannel(in server: Server, channelId: String, fromCategoryId: String?, toCategoryId: String?) -> [Types.Category]? {
        guard var categories = server.categories else {
            return nil
        }
        
        if let fromIndex = categories.firstIndex(where: { $0.id == fromCategoryId }) {
            categories[fromIndex].channels.removeAll { $0 == channelId }
        }
        
        if let toIndex = categories.firstIndex(where: { $0.id == toCategoryId }) {
            categories[toIndex].channels.append(channelId)
        }
        
        return categories
    }
}


#Preview {
    
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    ServerChannelOverviewSettings(viewState: viewState, channel: (viewState.channels["0"]!), server: .constant(viewState.servers["0"]!))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
    
}
