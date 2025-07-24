//
//  ServerEmojiSettings.swift
//  Revolt
//
//  Created by Angelo on 01/10/2024.
//

import Foundation
import Types
import SwiftUI
import PhotosUI
import SwiftyCrop

/// A view that allows users to manage emojis for a server, including uploading new emojis and displaying existing ones.
struct ServerEmojiSettings: View {
    /// The environment object that holds the current state of the application.
    @EnvironmentObject var viewState: ViewState
    
    /// A binding to the server whose emojis are being managed.
    @Binding var server: Server
    
    /// State variable to control the display of the photo picker for selecting emojis.
    @State var showPhotoPicker: Bool = false
    
    /// State variable for the selected photo from the photo picker.
    @State var selectedPhoto: PhotosPickerItem? = nil
    
    /// State variable for the selected image to be uploaded as an emoji.
    @State var selectedImage: UIImage? = nil
    
    /// State variable to control the display of the image cropper.
    @State var showImageCropper: Bool = false
    
    /// State variable to hold the name for the new emoji being created.
    @State var emojiName: String = ""
    
    /// State variable to control the display of the new emoji sheet.
    @State var showNewEmojiSheet: Bool = false
    
    @State var showDeleteEmojiPopup: Bool = false
    
    /// Computed property that retrieves emojis associated with the current server.
    var serverEmojis: [Emoji] {
        viewState.emojis.values.filter { $0.parent.id == server.id }
    }
    
    @State var selectedEmojiForDelete: Emoji? = nil
    
    var body: some View {
        
        let emojis = serverEmojis
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Emojis", customToolbarView: emojis.isEmpty ? nil : AnyView(
            PeptideIconButton(icon: .peptideAdd, size: .size24){
                showNewEmojiSheet.toggle()
            }
        ))){_,_ in
            
            /*HStack(spacing: 16) {
             // Button to select an emoji from the photo library.
             Button {
             showPhotoPicker.toggle() // Toggle the photo picker visibility.
             } label: {
             Text("Select Emoji")
             .foregroundStyle(viewState.theme.accent) // Apply accent color to the text.
             }
             .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto)
             .onChange(of: selectedPhoto) { oldValue, newValue in
             Task {
             if let newValue {
             // Load the selected image data and prepare to show the cropper.
             if let data = try? await newValue.loadTransferable(type: Data.self) {
             selectedImage = UIImage(data: data)
             showImageCropper = true
             }
             }
             }
             }
             .fullScreenCover(isPresented: $showImageCropper) {
             // Show the image cropper if an image is selected.
             if let toBeCropped = selectedImage {
             SwiftyCropView(
             imageToCrop: toBeCropped,
             maskShape: .square
             ) { croppedImage in
             showImageCropper = false // Dismiss the cropper.
             selectedImage = croppedImage // Update the selected image with the cropped image.
             }
             }
             }
             
             // TextField for entering the emoji name.
             TextField("Emoji Name", text: $emojiName)
             .autocorrectionDisabled() // Disable autocorrection.
             .textCase(.lowercase) // Set text case to lowercase.
             .textInputAutocapitalization(.never) // Disable autocapitalization.
             .padding(8)
             .background(RoundedRectangle(cornerRadius: 8).fill(viewState.theme.background))
             }
             
             // HStack for displaying the selected image and emoji name with a Create button.
             HStack {
             if let selectedImage {
             // Display the selected image as a thumbnail.
             Image(uiImage: selectedImage)
             .resizable()
             .frame(width: 32, height: 32)
             }
             
             // Display the emoji name in a formatted way.
             if !emojiName.isEmpty {
             Text(":").foregroundStyle(viewState.theme.foreground2)
             +
             Text(verbatim: emojiName)
             +
             Text(":").foregroundStyle(viewState.theme.foreground2)
             }
             
             Spacer() // Add space between the emoji display and the Create button.
             
             // Button to create the emoji.
             Button("Create") {
             Task {
             // Upload the selected image and create the emoji on the server.
             let file = try! await viewState.http.uploadFile(data: selectedImage!.pngData()!, name: "emoji", category: .emoji).get()
             let emoji = try! await viewState.http.uploadEmoji(id: file.id, name: emojiName, parent: .server(EmojiParentServer(id: server.id)), nsfw: false).get()
             viewState.emojis[emoji.id] = emoji // Add the new emoji to the view state.
             emojiName = "" // Reset the emoji name field.
             selectedPhoto = nil // Clear the selected photo.
             selectedImage = nil // Clear the selected image.
             }
             }
             .disabled(selectedImage == nil || emojiName.isEmpty) // Disable the button if no image or name is provided.
             }*/
            
            
            
            
            
            
            if emojis.isEmpty {
                
                HStack(spacing: .zero) {
                    
                    VStack(spacing: .spacing4){
                        
                        Image(.peptideDmEmpty)
                        
                        PeptideText(text: "Your Emoji Board is Blank",
                                    font: .peptideHeadline,
                                    textColor: .textDefaultGray01)
                        
                        PeptideText(text: "Add custom emojis to make your server chats \n unforgettable.",
                                    font: .peptideSubhead,
                                    textColor: .textGray07,
                                    alignment: .center)
                        .padding(.horizontal , .padding16)
                        
                        PeptideButton(buttonType: .small(),
                                      title: "Create Emoji",
                                      bgColor: .bgYellow07,
                                      contentColor: .textInversePurple13,
                                      buttonState: .default,
                                      isFullWidth: false){
                            
                            showNewEmojiSheet.toggle()
                            
                        }
                                      .padding(.top, .padding12)
                        
                        
                    }
                    
                }
                .padding(.horizontal, .padding16)
                .padding(.top, .padding24)
                
            } else {
                
                HStack{
                    
                    PeptideText(text:"Emojis - \(emojis.count)")
                        .padding(.horizontal, 32)
                        .padding(.top, .padding24)
                    
                    Spacer()
                    
                }
                
                LazyVStack(spacing: .spacing8){
                    
                    ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                        ServerEmojiItemView(emoji: emoji){
                            
                            self.selectedEmojiForDelete = emoji
                            self.showDeleteEmojiPopup.toggle()
                            
                        }
                        
                        if index != emojis.count - 1 {
                            PeptideDivider()
                                .padding(.leading, .padding48)
                        }
                    }
                    
                }
                .backgroundGray11(verticalPadding: .padding4)
                .padding(.horizontal, 16)
                .popup(
                    isPresented: $showDeleteEmojiPopup,
                    view: {
                        
                        DeleteEmojiPopup(
                                isPresented: $showDeleteEmojiPopup,
                                emojiName: self.selectedEmojiForDelete?.name ?? ""
                            ){
                                
                                Task{
                                    
                                    let response = await self.viewState.http.deleteEmoji(emoji: selectedEmojiForDelete?.id ?? "")
                                    
                                    switch response{
                                    case .success(_):
                                        viewState.emojis.removeValue(forKey: selectedEmojiForDelete?.id ?? "")
                                    case .failure(_):
                                        self.viewState.showAlert(message: "Something went wronge!", icon: .peptideInfo)
                                    }
                                    
                                }
                                
                            }
                        
                    },
                    customize: {
                    $0.type(.default)
                      .isOpaque(true)
                      .appearFrom(.bottomSlide)
                      .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                      .closeOnTap(false)
                      .closeOnTapOutside(false)
                })
                
            }
            
            Spacer(minLength: .zero)
            
        }
        .sheet(isPresented: $showNewEmojiSheet) {
            NewEmojiSheet(isPresented: $showNewEmojiSheet, serverId: server.id)
        }
        
    }
}


#Preview {
    @Previewable @StateObject  var viewState : ViewState = .preview()
    ServerEmojiSettings(server: .constant(viewState.servers["0"]!))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
