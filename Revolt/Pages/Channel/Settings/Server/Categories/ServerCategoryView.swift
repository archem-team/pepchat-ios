//
//  ServerCategoryView.swift
//  Revolt
//
//

import SwiftUI
import Types

struct ServerCategoryView: View {
    
    @EnvironmentObject var viewState : ViewState
    var server : Server
    var category : Types.Category
    
    @State private var categoryName : String
    @State private var categoryNameTextFieldState : PeptideTextFieldState = .default
    @State var showSaveButton: Bool = false
    
    @State private var isPresentedCategoryDelete: Bool = false
    
    
    init(server: Server,
         category: Types.Category) {
        self.server = server
        self.category = category
        self.categoryName = category.title
    }
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                
                Task {
                    
                    self.categoryNameTextFieldState = .disabled
                    
                    let editServerResponse = await viewState.http.editServer(server: server.id,
                                                                             edits: .init(categories: server.updateCategoryTitle(by: category.id, newTitle: categoryName)))
                    
                    self.categoryNameTextFieldState = .default
                    
                    switch editServerResponse {
                        case .success(let success):
                            self.viewState.servers[server.id] = success
                            self.viewState.path.removeLast()
                        case .failure(let failure):
                            debugPrint("\(failure)")
                    }
                    
                }
                
                
            } label: {
                PeptideText(text: "Save",
                            font: .peptideButton,
                            textColor: .textYellow07,
                            alignment: .center)
            }
            .opacity(showSaveButton ? 1 : 0)
            .disabled(!showSaveButton)
            
            
        )
    }
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Category Settings",
                                                 customToolbarView: saveBtnView)){_,_ in
            
            Group {
                
                PeptideTextField(text: $categoryName,
                                 state: $categoryNameTextFieldState,
                                 label: "Category Name",
                                 placeholder: "Category Name")
                
                Button {
                    self.isPresentedCategoryDelete.toggle()
                } label: {
                    
                    HStack(spacing: .spacing4){
                        PeptideIcon(iconName: .peptideTrashDelete,
                                    size: .size16,
                                    color: .iconRed07)
                        .padding(.vertical, .padding8)
                        
                        PeptideText(text: "Delete Category",
                                    font: .peptideButton,
                                    textColor: .textRed07)
                    }
                }
                
            }
            .padding(.horizontal, .padding16)
            .padding(.top, .padding24)
            
            
            
            Spacer(minLength: .zero)
            
        }
         .onChange(of: categoryName){ _ , newCategoryName in
             if newCategoryName.isNotEmpty && newCategoryName != category.title {
                 self.showSaveButton = true
             } else {
                 self.showSaveButton = false
             }
         }
         .popup(isPresented: $isPresentedCategoryDelete, view: {
             
             DeleteCategorySheet(isPresented: $isPresentedCategoryDelete,
                                 server: server,
                                 category: category,
                                 onDismiss: { newServer in
                 self.isPresentedCategoryDelete = false
//                 self.viewState.servers[server.id] = newServer
                 self.viewState.path.removeLast()
//                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
//                     self.viewState.servers[server.id] = newServer
//                     self.viewState.path.removeLast()
//                 }
                 
             })
             
         }, customize: {
             $0.type(.default)
                 .isOpaque(true)
                 .appearFrom(.bottomSlide)
                 .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                 .closeOnTap(false)
                 .closeOnTapOutside(false)
         })
    }
}


extension Server {
    /// Updates the title of a specific category and returns the updated list of categories.
    /// - Parameters:
    ///   - categoryId: The ID of the category to update.
    ///   - newTitle: The new title to set for the category.
    /// - Returns: The updated list of categories, or `nil` if no categories exist.
    func updateCategoryTitle(by categoryId: String, newTitle: String) -> [Types.Category] {
        guard var categories = self.categories else {
            return [] // If there are no categories, return [].
        }
        
        // Find the category by its ID and update its title.
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].title = newTitle
        }
        
        return categories // Return the updated categories.
    }
    
    
    /// Removes a category by its ID and returns the updated list of categories.
    /// - Parameter categoryId: The ID of the category to remove.
    /// - Returns: The updated list of categories, or `nil` if no categories exist.
    func removeCategory(by categoryId: String) -> [Types.Category] {
        guard var categories = self.categories else {
            return [] // If there are no categories, return [].
        }
        
        // Remove the category with the given ID.
        categories.removeAll(where: { $0.id == categoryId })
        
        return categories // Return the updated categories.
    }
}



#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ServerCategoryView(server: viewState.servers["0"]!,
                       category: viewState.servers["0"]!.categories!.first(where: {$0.id == "0"})!)
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
