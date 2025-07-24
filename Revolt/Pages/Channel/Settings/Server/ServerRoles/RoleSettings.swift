//
//  RoleSettings.swift
//  Revolt
//
//  Created by Angelo on 25/09/2024.
//

import Foundation
import Types
import SwiftUI


struct RoleSettings: View {
    @EnvironmentObject var viewState: ViewState
    
    @Binding var server: Server
    var roleId: String
    @State var initial: Role?
    @State var currentValue: Role
    
    @State private var isPresentedColorSheet : Bool = false
    
    
    init(server s: Binding<Server>, roleId: String, role: Role) {
        self._server = s
        self.roleId = roleId
        self.initial = role
        self.currentValue = role
    }
    
    @State var showSaveButton: Bool = false
    @State var isLoadingaveButton: Bool = false
    @State var isPresentedSavePopup: Bool = false
    
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                
                saveChanges()
                
                
                /*Task{
                 let _ = await self.viewState.http.setRolePermissions(server: server.id, role: roleId, permissions: currentValue.permissions)
                 }*/
                
                
            } label: {
                
                if self.isLoadingaveButton {
                    
                    ProgressView()
                    
                }else{
                
                    PeptideText(text: "Save",
                                font: .peptideButton,
                                textColor: .textYellow07,
                                alignment: .center)
                    
                }
                
            }
            //.opacity(showSaveButton ? 1 : 0)
            //.disabled(!showSaveButton)
            
            
        )
    }
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "\(currentValue.name)",
                                                 showBackButton: true,
                                                 backButtonIcon: .peptideCloseLiner,
                                                 onClickBackButton:{
            
            self.isPresentedSavePopup = true
            
        },
                                                 customToolbarView: saveBtnView,
                                                 showBottomLine: true)){_,_ in
            
            
            VStack(spacing: .zero){
                
                
                PeptideText(text: "Give this role a unique name and color. You can always change this later.",
                            font: .peptideBody4,
                            textColor: .textGray06,
                            alignment: .center)
                .padding(.vertical, .padding24)
                .padding(.horizontal, .padding16)
                
                
                PeptideTextField(text: $currentValue.name,
                                 state: .constant(.default),
                                 label: "Role Name",
                                 placeholder: "Role Name")
                
                
                
                
                Group {
                    
                    HStack {
                        PeptideText(text: "Role ID", font: .peptideHeadline, textColor: .textDefaultGray01, lineLimit: 1)
                            .padding(top: .padding32, bottom: .padding4)
                        
                        Spacer(minLength: .zero)
                    }
                    
                    HStack(spacing: .spacing2){
                        RoleIdTooltip()
                        PeptideText( textVerbatim: roleId, font: .peptideBody4, textColor: .textGray06, alignment: .leading)
                        
                        Spacer(minLength: .zero)
                    }
                    
                }
                
                HStack{
                    
                    PeptideText(text: "Role Color", font: .peptideHeadline, textColor: .textDefaultGray01, lineLimit: 1)
                        .padding(bottom: .padding8)
                        .padding(top: .padding32)
                    
                    Spacer()
                    
                }
                
                HStack(spacing: .spacing12){
                    
                    
                    /*
                     
                     TextField(text: $currentValue.colour.bindOr(defaultTo: "")) {
                     Text("Role Colour")
                     }
                     
                     */
                    
                    PeptideIcon(iconName: .peptideColour,
                                size: .size24,
                                color: .iconDefaultGray01)
                    
                    VStack(alignment: .leading, spacing: .zero){
                        PeptideText(textVerbatim: "Color",
                                    font: .peptideButton,
                                    textColor: .textDefaultGray01,
                                    alignment: .center)
                        
                    }
                    
                    
                    Spacer(minLength: .zero)
                    
                    
                    RoundedRectangle(cornerRadius: .radiusXSmall)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(currentValue.colour.map { parseCSSColor(currentTheme: viewState.theme, input: $0) } ?? AnyShapeStyle(viewState.theme.foreground))
                    
                    
                    PeptideIcon(iconName: .peptideArrowRight,
                                size: .size24,
                                color: .iconGray07)
                    
                    
                }
                .padding(.horizontal, .padding12)
                .frame(height: .size48)
                .backgroundGray11(verticalPadding: .padding4)
                .onTapGesture {
                    self.isPresentedColorSheet.toggle()
                }
                .padding(.bottom, .padding32)
                
                
                CheckboxListItem(title: "Hoist role",
                                 description: "Display this role above others.",
                                 isOn: $currentValue.hoist.bindOr(defaultTo: false))
                .padding(.bottom, .padding32)
                
                /*Section("Role Rank") {
                 TextField(value: $currentValue.rank, format: .number) {
                 Text("Role Name")
                 }
                 }
                 .listRowBackground(viewState.theme.background2)*/
                
                /*Section("Edit Permissions") {
                 }
                 .listRowBackground(viewState.theme.background2)*/
                
                LazyVStack(alignment: .leading, spacing: .zero){
                    
                    AllPermissionSettings(permissions: .role($currentValue.permissions),
                                          filter: [
                                            .manageChannel,
                                            .manageServer,
                                            .managePermissions,
                                            .manageRole,
                                            .manageCustomisation,
                                            .kickMembers,
                                            .banMembers,
                                            .timeoutMembers,
                                            .assignRoles,
                                            .changeNicknames,
                                            .manageNickname,
                                            .changeAvatars,
                                            .removeAvatars,
                                            .viewChannel,
                                            .sendMessages,
                                            .manageMessages,
                                            .inviteOthers,
                                            .sendEmbeds,
                                            .uploadFiles,
                                            .masquerade,
                                            .react,
                                            .connect
                                          ])
                }
                .padding(.bottom, .padding32)
                
            }
            .padding(.horizontal, .padding16)
            
        }
         .sheet(isPresented: $isPresentedColorSheet){
             RoleColorPickerSheet(isPresented: $isPresentedColorSheet,
                                  currentValue: $currentValue,
                                  selectedColor: self.currentValue.colour)
         }        .popup(isPresented: $isPresentedSavePopup, view: {
             ConfirmationSheet(
                 isPresented: $isPresentedSavePopup,
                 isLoading: $isLoadingaveButton,
                 title: "Save Changes?",
                 subTitle: "You've made changes. Do you want to save them before leaving this page?",
                 confirmText: "Save Changes",
                 dismissText: "Don't Save",
                 onDismiss: {
                     self.isPresentedSavePopup = false
                     self.viewState.path.removeLast()
                 },
                 popOnConfirm: false
             ){
                 
                 saveChanges()

             }
         }, customize: {
             $0.type(.default)
               .isOpaque(true)
               .appearFrom(.bottomSlide)
               .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
               .closeOnTap(false)
               .closeOnTapOutside(false)
         })
        
    }
    
    func saveChanges() {
        
        Task {
            var payload = RoleEditPayload()
            
            if initial?.name != currentValue.name {
                payload.name = currentValue.name
            }
            
            if initial?.colour != currentValue.colour {
                if currentValue.colour == nil || currentValue.colour == "" {
                    if payload.remove == nil {
                        payload.remove = []
                    }
                    payload.remove!.append(.colour)
                } else {
                    payload.colour = currentValue.colour
                }
            }
            
            if initial?.hoist != currentValue.hoist {
                payload.hoist = currentValue.hoist
            }
            
            self.isLoadingaveButton = true
            
            let result = await viewState.http.editRole(server: server.id, role: roleId, payload: payload)
            
            self.isLoadingaveButton = false
            
            switch result{
            case .success(let role):
                initial = role
                if initial?.permissions != currentValue.permissions {
                    let _ = try! await viewState.http.setRolePermissions(server: server.id, role: roleId, permissions: currentValue.permissions).get()
                    initial?.permissions = currentValue.permissions
                }
                
                currentValue = initial!
                self.isPresentedSavePopup = false
                self.viewState.showAlert(message: "Saved changes", icon: .peptideInfo, color: .iconGreen07)
                self.viewState.path.removeLast()
            case .failure(_):
                self.viewState.showAlert(message: "Something went wrong!", icon: .peptideInfo)
            }
            
            
        }
        
    }
}

struct RoleIdTooltip: View {
    @State private var showTooltip = false
    
    var body: some View {
        ZStack(alignment: .center) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTooltip.toggle()
                }
            } label: {
                PeptideIcon(iconName: .peptideInfo2, size: .size20, color: .iconGray04)
            }
            
            if showTooltip {
                VStack(spacing: 0) {
                    // Tooltip content
                    PeptideText(
                        text: "This is a unique identifier for this role.",
                        font: .peptideCaption1,
                        textColor: .textDefaultGray01,
                        alignment: .leading
                    )
                    .padding(.all, .padding8)
                    .background(Color.bgGray11)
                    .cornerRadius(.radius8)
                    .overlay(
                        RoundedRectangle(cornerRadius: .radiusXSmall)
                            .stroke(Color.borderGray10, lineWidth: 1)
                    )
                    
//                    // Triangle indicator pointing down
//                    Path { path in
//                        path.move(to: CGPoint(x: 10, y: 0))
//                        path.addLine(to: CGPoint(x: 20, y: 10))
//                        path.addLine(to: CGPoint(x: 0, y: 10))
//                        path.closeSubpath()
//                    }
//                    .fill(Color.bgGray11)
//                    .frame(width: 20, height: 10)
//                    .offset(x: -5, y: -1) // Align with the info icon
                }
                .offset(y: -25) // Position above the info icon
                .offset(x: 80) // Position above the info icon
                .transition(.opacity)
                .zIndex(1)
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                .frame(width: 190)
            }
        }
        .frame(width: 20, height: 20)
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    RoleSettings(server: .constant(viewState.servers["0"]!),
                 roleId: "1",
                 role: .init(name: "role 1", permissions: .init(a: .none, d: .none),
                             rank: 1))
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
