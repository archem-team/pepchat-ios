//
//  MFaNoneStep.swift
//  Revolt
//
//

import SwiftUI

struct MFaNoneStep: View {
    
    @Binding var step : MfaSheetStep
    @Binding var methods: [String]
    
    
    var body: some View {
        let methodsData = [
            TwoFAMethod(type: "Totp", icon: .peptideKey, title: "Authenticator App") {
                step = .otp
            },
            TwoFAMethod(type: "Recovery", icon: .peptideRefresh, title: "Recovery Code") {
                step = .recovery
            }
        ]
        
        VStack(spacing: .zero){
            
            ForEach(methodsData.filter { methods.contains($0.type) }) { mfaItem in
                
                MfaItem(icon: mfaItem.icon, title: mfaItem.title) {
                    mfaItem.action()
                }
                
                if methods.count > 1 && methods.firstIndex(of: mfaItem.type) ?? 0 < methods.count - 1 {
                    PeptideDivider()
                        .padding(.leading, .padding48)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: .radius16)
                .fill(.bgGray11)
        )
    }
}

#Preview {
    MFaNoneStep(step: .constant(.none), methods: .constant(["Totp", "Recovery"]))
}
