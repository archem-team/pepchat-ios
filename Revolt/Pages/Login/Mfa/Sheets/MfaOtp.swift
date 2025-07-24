//
//  MfaOtp.swift
//  Revolt
//
//

import SwiftUI

struct MfaOtp: View {
    
    @Binding var currentText: String

    
    var body: some View {
        
        PeptideOtp(numberOfFields: 6, onCompletion: {result in
            
            currentText = result
            
        }, customView: AnyView(
            Spacer()
                .frame(width: 12)
        ))
        
    }
}

#Preview {
    MfaOtp(currentText: .constant(""))
}
