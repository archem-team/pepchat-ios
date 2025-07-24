//
//  ChannelCategoryCreateView.swift
//  Revolt
//
//

import SwiftUI
import Types
import ULID


struct ChannelCategoryCreateView: View {
    @EnvironmentObject var viewState : ViewState
    
    var server : Server
    var type : ChannelCategoryCreateType
    
    @State private var createBtnState : ComponentState = .disabled
    @State private var name : String = ""
    @State private var nameTextFieldState : PeptideTextFieldState = .default
    
    
    @State private var selectedCategoryId: String? = nil
    
    
    private var uiInfo : (title: String, edtLabel: String, edtPlaceHolder: String) {
        switch type {
        case .categories:
            return ("Create Category","Category Name","Enter category name")
        case .channels:
            return ("Create Channel","Channel Name","Enter channel name")
        }
    }
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: uiInfo.title),
                            fixBottomView: AnyView(
                                HStack(spacing: .zero) {
                                    
                                    PeptideButton(title: "Create",
                                                  buttonState: createBtnState){
                                        
                                        hideKeyboard()
                                        
                                        if type == .categories {
                                            
                                            
                                            Task {
                                                
                                                self.createBtnState = .loading
                                                self.nameTextFieldState = .disabled
                                                                                                
                                                let editServerResponse = await viewState.http.editServer(server: server.id,
                                                                                        edits: .init(categories: addCategoryToServerCategories(newCategoryTitle: name)))
                                                
                                                self.createBtnState = .default
                                                self.nameTextFieldState = .default
                                                
                                                switch editServerResponse {
                                                    case .success(let success):
                                                        self.viewState.servers[server.id] = success
                                                        self.viewState.path.removeLast()
                                                    case .failure(let failure):
                                                        debugPrint("\(failure)")
                                                }
                                                
                                            }
                                            
                                        } else if type == .channels {
                                            
                                            Task {
                                                
                                                
                                                self.createBtnState = .loading
                                                self.nameTextFieldState = .disabled
                                                
                                                let createChannelResponse = await viewState.http.createChannel(server: server.id, createChannel: .init(type: "Text", name: name))
                                                
                                                self.createBtnState = .default
                                                self.nameTextFieldState = .default
                                                
                                                switch createChannelResponse {
                                                    case .success(let success):
                                                        viewState.channels[success.id] = success
                                                        viewState.servers[server.id]?.channels.append(success.id)
                                                    
                                                    if  let selectedCategoryId {
                                                        
                                                        let editServerResponse = await viewState.http.editServer(server: server.id, edits: .init(
                                                            categories: server.addChannelToCategory(categoryId: selectedCategoryId, channelId: success.id)
                                                        ))
                                                        
                                                        switch editServerResponse {
                                                            case .success(let success):
                                                                viewState.servers[server.id] = success
                                                                self.viewState.path.removeLast()
                                                            case .failure(let failure):
                                                                debugPrint("\(failure)")
                                                        }
                                                        
                                                    } else {
                                                        self.viewState.path.removeLast()
                                                    }
                                                        
                                                    
                                                    case .failure(let failure):
                                                        debugPrint("\(failure)")
                                                    }
                                                
                                                
                                            }
                                            
                                        }
                                    }
                                    
                                }
                                    .padding(.horizontal, .padding16)
                                    .padding(top: .padding8, bottom: .padding24)
                                    .background(Color.bgDefaultPurple13)
                            )){_,_ in
                                
                                
                                PeptideTextField(text: $name,
                                                 state: $nameTextFieldState,
                                                 label: uiInfo.edtLabel,
                                                 placeholder: uiInfo.edtPlaceHolder)
                                .padding(.horizontal, .padding16)
                                .padding(.vertical, .padding24)
                                .onChange(of: self.name){_ , newName in
                                    if newName.isEmpty {
                                        self.createBtnState = .disabled
                                    } else {
                                        self.createBtnState = .default
                                    }
                                }
                                
                                if type == .channels, server.categories?.isEmpty == false {
                                    HStack(spacing: .zero){
                                        
                                        VStack(alignment: .leading, spacing: .spacing4){
                                            PeptideText(text: "Category",
                                                        font: .peptideBody3,
                                                        textColor: .textGray06)
                                            
                                            PeptideText(text: "Choose a channel category.",
                                                        font: .peptideSubhead,
                                                        textColor: .textGray07)
                                        }
                                        
                                        Spacer(minLength: .zero)
                                        
                                    }
                                    .padding(.horizontal, .padding16)
                                    .padding(.bottom, .padding16)
                                    
                                    LazyVStack(spacing: .zero){
                                        
                                        let lastCategoryId = server.categories?.last?.id
                                        let firstCategoryId = server.categories?.first?.id
                                        
                                        
                                        ForEach(server.categories ?? []) { category in
                                            
                                            item(categoryName: category.title,
                                                 categoryId: category.id,
                                                 firstCategoryId: firstCategoryId,
                                                 lastCategoryId: lastCategoryId)
                                            
                                            if category.id != lastCategoryId {
                                                PeptideDivider(backgrounColor: .borderGray11)
                                                    .padding(.leading, .size48)
                                                    .padding(.vertical, .padding4)
                                                    .background(Color.bgGray12)
                                                
                                            }
                                            
                                        }
                                        
                                    }
                                    .padding(.horizontal, .padding16)
                                    
                                    
                                }
                                
                                Spacer(minLength: .zero)
                                
                                
                            }
    }
    
    
    private func toggleBinding(for categoryId: String?) -> Binding<Bool> {
        Binding(
            get: {
                self.selectedCategoryId == categoryId
            },
            set: { isSelected in
                if isSelected {
                    self.selectedCategoryId = categoryId
                }
            }
        )
    }
    
    
    func item(categoryName : String,
              categoryId : String?,
              firstCategoryId: String?,
              lastCategoryId : String?) -> some View {
        
        HStack(spacing: .spacing12){
            
            PeptideIcon(iconName: .peptideFolder,
                        color: .iconGray07)
            
            PeptideText(text: categoryName,
                        font: .peptideButton,
                        alignment: .leading)
            Spacer(minLength: .zero)
            
            Toggle("", isOn: toggleBinding(for: categoryId))
                .toggleStyle(PeptideCircleCheckToggleStyle())
        }
        .padding(.horizontal, .padding12)
        .frame(height: .size48)
        .padding(.top, categoryId == firstCategoryId ? .padding4 : .zero)
        .padding(.bottom, categoryId == lastCategoryId ? .padding4 : .zero)
        .background{
            
            UnevenRoundedRectangle(topLeadingRadius: categoryId == firstCategoryId ? .radiusMedium : .zero,
                                   bottomLeadingRadius: categoryId == lastCategoryId ? .radiusMedium : .zero,
                                   bottomTrailingRadius: categoryId == lastCategoryId ? .radiusMedium : .zero,
                                   topTrailingRadius: categoryId == firstCategoryId ? .radiusMedium : .zero)
            .fill(Color.bgGray12)
            
        }
        
    }
    
    
    // Function to generate a 32-character custom ID using UUID
    /*func generateCustomID() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        let trimmedID = String(uuid.prefix(28))
        return trimmedID
    }*/
    

    // Function to add a new category to server categories
    func addCategoryToServerCategories(
        newCategoryTitle: String
    ) -> [Types.Category] {
        var categories = server.categories ?? []

        // Generate a unique identifier using UUID instead of ULID
        let newCategoryId = UUID().uuidString

        let newCategory = Category(
            id: newCategoryId,
            title: newCategoryTitle,
            channels: []
        )

        categories.append(newCategory)

        return categories
    }
    
    
}


extension Server {
    /// Adds a channel to a specific category by its ID.
    /// - Parameters:
    ///   - categoryId: The ID of the category to which the channel will be added.
    ///   - channelId: The ID of the channel to add.
    /// - Returns: The updated list of categories, or `nil` if the category is not found.
    func addChannelToCategory(categoryId: String, channelId: String) -> [Types.Category]? {
        guard var categories = self.categories else {
            return [] // If there are no categories, return [].
        }
        
        // Find the category by ID and add the channel to its list.
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            var category = categories[index]
            if !category.channels.contains(channelId) {
                category.channels.append(channelId) // Add the channel if not already present.
                categories[index] = category // Update the category in the list.
            }
        } else {
            return [] // Category with the given ID not found.
        }
        
        return categories // Return the updated list of categories.
    }
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ChannelCategoryCreateView(server: viewState.servers["0"]!, type: .categories)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ChannelCategoryCreateView(server: viewState.servers["0"]!, type: .channels)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
