//
//  ServerCategorySheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct ServerCategorySheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented : Bool
    
    
    var server : Server
    @State  var selectedCategoryId: String? = nil
    var onSelectedCategory : (Types.Category?) -> Void

    

    var body: some View {
        VStack(spacing: .zero){
            
            let categories = server.categories
            
            PeptideText(text: "Category",
                        font: .peptideButton,
                        textColor: .textDefaultGray01)
            .padding(.top, .padding24)
            
            
            PeptideText(text: "Choose a category to move.",
                        font: .peptideSubhead,
                        textColor: .textGray06)
            .padding(.top, .padding4)
            .padding(.bottom, .padding24)
            
            
            ScrollView(.vertical) {
                
                LazyVStack(spacing: .zero){
                    let lastCategoryId = categories?.last?.id
                    
                    item(categoryName: "Uncategorized",
                         categoryId: nil,
                         lastCategoryId: lastCategoryId)
                    
                    PeptideDivider(backgrounColor: .borderGray11)
                        .padding(.leading, .size48)
                        .padding(.vertical, .padding4)
                        .background(Color.bgGray12)
                    
                    ForEach(categories ?? [], id: \.id) { category in
                        item(categoryName: "\(category.title)",
                             categoryId: category.id,
                             lastCategoryId: lastCategoryId)
                        
                        if category.id != lastCategoryId {
                            PeptideDivider(backgrounColor: .borderGray11)
                                .padding(.leading, .size48)
                                .padding(.vertical, .padding4)
                                .background(Color.bgGray12)
                            
                        }
                    }
                }
                
                
            }
            .scrollBounceBehavior(.basedOnSize)
            
        }
        .padding(.horizontal, .padding16)
        .background(Color.bgDefaultPurple13)
        .onChange(of: selectedCategoryId){
            self.isPresented.toggle()
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
                    onSelectedCategory(server.categories?.first(where: {$0.id == categoryId}))
                }
            }
        )
    }
    
    
    func item(categoryName : String,
              categoryId : String?,
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
        .padding(.top, categoryId == nil ? .padding4 : .zero)
        .padding(.bottom, categoryId == lastCategoryId ? .padding4 : .zero)
        .background{
            
            UnevenRoundedRectangle(topLeadingRadius: categoryId == nil ? .radiusMedium : .zero,
                                   bottomLeadingRadius: categoryId == lastCategoryId ? .radiusMedium : .zero,
                                   bottomTrailingRadius: categoryId == lastCategoryId ? .radiusMedium : .zero,
                                   topTrailingRadius: categoryId == nil ? .radiusMedium : .zero)
            .fill(Color.bgGray12)
            
        }
       
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    ServerCategorySheet(isPresented: .constant(false), server: viewState.servers["1"]!, onSelectedCategory: {_ in
        
        
    })
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
