//
//  RoleColorPickerSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct RoleColorPickerSheet: View {
    
    @Binding var isPresented: Bool
    @Binding var currentValue: Role
    @State var selectedColor: String? = nil
    
    var colors: [RoleColor] = [
        RoleColor(colorName: "role-light-01", colorCode: "#7B68EE"),
        RoleColor(colorName: "role-light-02", colorCode: "#3498DB"),
        RoleColor(colorName: "role-light-03", colorCode: "#1ABC9C"),
        RoleColor(colorName: "role-light-04", colorCode: "#F1C40F"),
        
        
        RoleColor(colorName: "role-dark-01", colorCode: "#594CAD"),
        RoleColor(colorName: "role-dark-02", colorCode: "#206694"),
        RoleColor(colorName: "role-dark-03", colorCode: "#11806A"),
        RoleColor(colorName: "role-dark-04", colorCode: "#C27C0E"),
        
        RoleColor(colorName: "role-light-05", colorCode: "#FF7F50"),
        RoleColor(colorName: "role-light-06", colorCode: "#FD6671"),
        RoleColor(colorName: "role-light-07", colorCode: "#E91E63"),
        RoleColor(colorName: "role-light-08", colorCode: "#D468EE"),
        
        RoleColor(colorName: "role-dark-05", colorCode: "#CD5B45"),
        RoleColor(colorName: "role-dark-06", colorCode: "#DD555F"),
        RoleColor(colorName: "role-dark-07", colorCode: "#AD1457"),
        RoleColor(colorName: "role-dark-08", colorCode: "#954AA8"),
        
    ]
    
    // Define four columns with zero spacing between them (horizontal spacing)
    let columns: [GridItem] = Array(repeating: .init(.flexible(minimum: 40, maximum: 40), spacing: .spacing24), count: 4)
    
    var body: some View {
        PeptideSheet(isPresented: $isPresented) {
            PeptideText(text: "Role Color", font: .peptideHeadline, textColor: .textDefaultGray01)
            PeptideText(text: "Choose a color to make this role stand out.", font: .peptideSubhead, textColor: .textGray06, alignment: .center)
                .padding(.top, .padding4)
            
            // LazyVGrid with zero horizontal spacing between items.
            // The 'spacing' parameter here controls vertical spacing between rows.
            LazyVGrid(columns: columns, spacing: .spacing24) {
                ForEach(colors, id: \.colorName) { color in
                    RoleColorView(selectedColor: self.$selectedColor, roleColor: color)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 0)
            .padding(.top, .padding24)
            
            
            PeptideButton(buttonType: .medium(), title: "Save Color", bgColor: .bgGray11, contentColor: .textDefaultGray01, isFullWidth: false){
                self.currentValue.colour = self.selectedColor
                self.isPresented.toggle()
            }
            .padding(.top, .padding24)
        }
    }
}




struct RoleColor {
    var colorName : String
    var colorCode : String?
}



struct RoleColorView : View {
    
    @EnvironmentObject var viewState : ViewState
    
    @Binding var selectedColor : String?
    var roleColor : RoleColor
    
    var body: some View {
        
        let isSelected : Bool = $selectedColor.wrappedValue == roleColor.colorCode
        
        ZStack {
            Circle()
                .frame(width: 40, height: 40)
                .foregroundStyle(roleColor.colorCode.map { parseCSSColor(currentTheme: viewState.theme, input: $0) } ?? AnyShapeStyle(viewState.theme.foreground))
                .if(isSelected) {
                    $0.overlay(
                        Circle()
                            .stroke(Color.iconDefaultGray01, lineWidth: 1)
                    )
                }
            
            if isSelected {
                PeptideIcon(iconName: .peptideDone,
                            size: .size24,
                            color: .iconDefaultGray01)
            }
                
        }
        .onTapGesture{
            self.selectedColor = roleColor.colorCode
        }
    }
}


#Preview {
    
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    
    
    RoleColorPickerSheet(isPresented: .constant(false), currentValue: .constant(.init(name: "Role",
                                                                                      permissions: .init(a: .all, d: .all),
                                                                                      colour : "#AA0000",
                                                                                      rank: 1)))
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)}



#Preview {
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    
    VStack(spacing: .spacing16){
        
        RoleColorView(selectedColor: .constant("#AAAA00") , roleColor: .init(colorName: "color-1", colorCode: "#AAAA00"))
        
        RoleColorView(selectedColor: .constant("#AAAA11") , roleColor: .init(colorName: "color-1", colorCode: "#AAAA00"))

        
    }
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
