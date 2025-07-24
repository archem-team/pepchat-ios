import SwiftUI
import Types
import PhotosUI
import SwiftyCrop

struct NewEmojiSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool
    var serverId: String
    
    @State private var showPhotoPicker: Bool = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var emojiName: String = ""
    @State private var showFileSizeError: Bool = false
    @State private var showImageCropper: Bool = false
    @State private var textFieldState : PeptideTextFieldState = .default
    @State private var buttonState : ComponentState = .disabled
    
    var body: some View {
        PeptideSheet(isPresented: $isPresented) {
            
            VStack(alignment: .leading, spacing: .zero) {
                
                
                HStack(alignment: .center, spacing: .zero){
                    
                    PeptideIconButton(icon: .peptideCloseLiner){
                        self.isPresented.toggle()
                    }
                    
                    Spacer(minLength: .zero)
                    
                    PeptideText(text: "New Emoji", font: .peptideHeadline)
                    
                    
                    Spacer(minLength: .zero)
                    
                    VStack{}
                        .frame(width: .size24)
                    
                }
                .padding(.bottom, .size24)
                
                VStack(alignment: .leading, spacing: .zero) {
                    
                    PeptideText(text: "Upload Requirements", font: .peptideBody3, textColor: .textGray04)
                        .padding(.bottom, .size8)
                    
                    PeptideText(text: "• File type: JPEG, PNG, GIF", font: .peptideCaption1, textColor: .textGray04)
                    
                    PeptideText(text: "• Recommended dimensions: 128x128", font: .peptideCaption1, textColor: .textGray04)
                    
                    PeptideText(text: "• Max file size: 500 KB", font: .peptideCaption1, textColor: .textGray04)
                    
                }
                .padding(.vertical, .size12)
                
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundColor(.borderGray11)
                    .frame(height: 1)
                    .padding(.bottom, .size24)
                
                Button {
                    if(buttonState != .loading){
                        showPhotoPicker.toggle()
                    }
                } label: {
                    
                    HStack{
                        
                        Spacer()
                        
                        ZStack(alignment: .center) {
                            
                            if let selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .frame(width: 48, height: 48)
                            }else{
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.green)
                                    .frame(width: 48, height: 48)
                                
                                PeptideIcon(iconName: .peptideSmile,
                                            size: .size24,
                                            color: .iconDefaultGray01
                                )
                                
                            }
                            
                            VStack{
                                
                                HStack{
                                    
                                    Spacer()
                                    
                                    PeptideIcon(iconName: .peptideAddPhoto,
                                                size: .size16,
                                                color: .iconInverseGray13)
                                    .frame(width: .size24, height: .size24)
                                    .background{
                                        Circle().fill(Color.bgGray02)
                                    }
                                    .onTapGesture {
                                        showPhotoPicker.toggle()
                                    }
                                }
                                
                                Spacer()
                                
                            }
                            
                        }
                        .frame(width: 60, height: 60)
                        
                        Spacer()
                        
                    }
                }
                .padding(.bottom, 8)
                
                HStack{
                    Spacer()
                    
                    if(showFileSizeError){
                        PeptideText(
                            text: "Max file size: 500 KB",
                            font: .peptideCaption1,
                            textColor: .textRed07
                        )
                    }
                    
                    Spacer()
                }
                
                PeptideTextField(
                    text: $emojiName,
                    state: $textFieldState,
                    label: "Emoji Name",
                    placeholder: "Enter emoji name")
                .padding(.bottom, 48)
                .padding(.top, 24)
                
                PeptideButton(title: "Create Emoji", buttonState: buttonState) {
                    
                    // Check if selectedImage is not nil and its size is less than or equal to 500 KB
                    if let image = selectedImage, let imageData = image.pngData(), imageData.count > 500 * 1024 {
                        showFileSizeError = true
                        return // Prevent further execution
                    }
                    
                    Task {
                        
                        buttonState = .loading
                        textFieldState = .disabled
                        
                        let fileResponse = await viewState.http.uploadFile(data: selectedImage!.pngData()!, name: "emoji", category: .emoji)
                        
                        switch fileResponse{
                        case .success(let file):
                            
                            let emojiResponse = await viewState.http.uploadEmoji(id: file.id, name: emojiName, parent: .server(EmojiParentServer(id: serverId)), nsfw: false)
                            
                            switch emojiResponse{
                            case .success(let emoji):
                                
                                viewState.emojis[emoji.id] = emoji
                                emojiName = ""
                                selectedPhoto = nil
                                selectedImage = nil
                                self.isPresented.toggle()
                                
                            case .failure(_):
                                self.viewState.showAlert(message: "Something went wronge!", icon: .peptideInfo)
                            }
                            
                        case .failure(_):
                            self.viewState.showAlert(message: "Something went wronge!", icon: .peptideInfo)
                        }
                        
                        buttonState = .default
                        textFieldState = .default
                        
                        
                    }
                    
                }
                
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto)
            .onChange(of: selectedPhoto) { _, newValue in
                showFileSizeError = false
                Task {
                    if let newValue {
                        if let data = try? await newValue.loadTransferable(type: Data.self) {
                            selectedImage = UIImage(data: data)
                            showImageCropper = true
                        }
                    }
                }
            }
            .onChange(of: emojiName){ _, value in
                
                emojiName = emojiName.lowercased().replacing(" ", with: "-")
                
                self.buttonState = selectedImage == nil || emojiName.isEmpty ? .disabled : .default
            }.onChange(of: selectedImage){ _, value in
                self.buttonState = selectedImage == nil || emojiName.isEmpty ? .disabled : .default
            }
            .fullScreenCover(isPresented: $showImageCropper) {
                if let toBeCropped = selectedImage {
                    SwiftyCropView(
                        imageToCrop: toBeCropped,
                        maskShape: .square
                    ) { croppedImage in
                        showImageCropper = false
                        selectedImage = croppedImage
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    
    VStack{
        
        
    }
    .sheet(isPresented: .constant(true)){
        
        NewEmojiSheet(isPresented: .constant(true), serverId: "")
        
        
    }
    .background(Color.black)
    .frame(width: .infinity, height: .infinity)
    .applyPreviewModifiers(withState:viewState)
    .preferredColorScheme(.dark)
    
    
}

