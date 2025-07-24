//
//  MfaRecovery.swift
//  Revolt
//
//

import SwiftUI

struct MfaRecovery: View {
    
    @Binding var currentText: String
    var onChange: (() -> Void)? = nil
    
    
    var body: some View {
        PeptideOtp(numberOfFields: 2,
                   maxCharactersPerField: 5,
                   otpWidth: .infinity,
                   keyBoardType: .alphabet,
                   onChange: self.onChange,
                   onCompletion: { result in
            
            currentText = result
            
        },
                   
                   customView:
                    
                    AnyView(
                        HStack{
                            Text("-")
                                .foregroundStyle(.borderGray10)
                        }
                            .frame(width: 40)
                    )
        )
    }
}

#Preview {
    MfaRecovery(currentText: .constant(""))
}
