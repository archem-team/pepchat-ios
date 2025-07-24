//
//  CreateGroupName.swift
//  Revolt
//
//

import SwiftUI

struct CreateGroupName: View {
    @EnvironmentObject var viewState: ViewState
    @State var groupName = ""
    @State var groupNameTextFieldStatus : PeptideTextFieldState = .default
    @State var continueBtnState : ComponentState = .disabled
    
    let toolbarConfig: ToolbarConfig = .init(isVisible: true,
                                             title: "New Group",
                                             showBottomLine: true)
    
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: toolbarConfig){scrollViewProxy, keyboardVisibility in
            
            VStack(alignment: .leading, spacing: .zero) {
                
                
                PeptideText(text: "Set a Group Name",
                            font: .peptideTitle3,
                            textColor: .textDefaultGray01)
                            .padding(.top, .padding32)
                
                
                PeptideText(text: "Choose a name that stands out to your members.",
                            font: .peptideBody3,
                            textColor: .textGray07)
                .padding(.top, .padding8)
                
               
                PeptideTextField(
                    text: $groupName,
                    state: $groupNameTextFieldStatus,
                    placeholder : "Enter group name",
                    keyboardType: .default)
                .onChange(of: groupName){_, newGroupName in
                    
                    groupNameTextFieldStatus = .default
                    
                    if newGroupName.isEmpty {
                        continueBtnState = .disabled
                    } else {
                        continueBtnState = .default
                    }
                    
                }
                .onChange(of: keyboardVisibility.wrappedValue) { oldState,  newState in
                    if newState  {
                        withAnimation{
                            scrollViewProxy.scrollTo("groupname-keyboard-spacer", anchor: .top)
                        }
                        
                    }
                }
                .padding(.top, .padding24)
                
                Spacer()
                
                
                PeptideButton(title: "Continue",
                              buttonState: continueBtnState){
                    viewState.path.append(NavigationDestination.create_group_add_memebers(groupName))
                }
                .padding(.top, .padding32)
                
             
                
                Spacer()
                    .frame(height: .size8)
                    .id("groupname-keyboard-spacer")
                
                
                Spacer()
                    .frame(height: .size24)

                
            }
            .padding(.horizontal, .padding16)
            
            
        }

    }
}

#Preview {
    CreateGroupName()
}
