//
//  RoleDeleteSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct RoleDeleteSheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented : Bool
    
    var serverId : String
    var roleId : String
    var role : Role
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: .spacing4){
            
            Group {
                PeptideText(textVerbatim: "Delete \(role.name)?",
                            font: .peptideTitle3,
                            textColor: .textDefaultGray01)
                
                PeptideText(text: "Do you want delete \(role.name) role? This cannot be undone.",
                            font: .peptideCallout,
                            textColor: .textGray06,
                            alignment: .leading
                )
                
                
                
            }
            .padding(.horizontal, .padding24)
            
            
            PeptideDivider(backgrounColor: .borderGray10)
                .padding(top: .padding28, bottom: .padding20)
            
            HStack(spacing: .padding12){
                Spacer(minLength: .zero)
                
                PeptideButton(buttonType: .medium(),
                              title: "Dismiss",
                              bgColor: .clear,
                              contentColor: .textDefaultGray01,
                              buttonState: .default,
                              isFullWidth: false){
                    self.isPresented.toggle()
                }
                
                PeptideButton(buttonType: .medium(),
                              title: "Delete Role",
                              bgColor: .bgRed07,
                              contentColor: .textDefaultGray01,
                              buttonState: .default,
                              isFullWidth: false){
                    
                    Task {
                        let response =  await viewState.http.deleteRole(server: serverId, role: roleId)
                        switch response {
                        case .success(let success):
                            self.isPresented.toggle()
                        case .failure(let failure):
                            debugPrint("error \(failure)")
                        }
                    }
                    
                    
                }
            }
            .padding(.horizontal, .padding24)
            
        }
        .padding(top: .padding24, bottom: .padding24)
        .background{
            RoundedRectangle(cornerRadius: .radiusMedium)
                .fill(Color.bgGray11)
        }
        .padding(.padding16)
        
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    RoleDeleteSheet(isPresented: .constant(false), serverId: "abcdf", roleId: "01JBBFJFF6BVX7WZ22RVPHF65N", role: .init(name: "New Role", permissions: .init(a: .all, d: .all), rank: 1))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
