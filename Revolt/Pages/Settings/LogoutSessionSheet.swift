//
//  LogoutSessionDialog.swift
//  Revolt
//
//  Created by Mehdi on 1/29/25.
//

import Foundation
import SwiftUI
import Types

struct LogoutSessionSheet : View{
    @Binding var isPresented: Bool
    var session: Session?
    var isDelletingAllSessions: Bool
    var deleteSessionCallback: (() -> ())?
    var deleteAllSessionCallback: (() -> ())?
    
    var body: some View {
        VStack{
            
            VStack(alignment: .leading){
                
                PeptideText(
                    text: self.isDelletingAllSessions ? "Are You Sure You Want to Log Out All Your Sessions?" : "Log Out from \(self.session?.name ?? "")?",
                    font: .peptideTitle3,
                    textColor: .textDefaultGray01,
                    alignment: .leading
                )
                .padding(.bottom, .size32)
                
                PeptideText(
                    text: "You cannot undo this action.",
                    font: .peptideBody3,
                    textColor: .textGray06,
                    alignment: .leading
                )
                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .size24)
                .padding(.top, .size24)
                .padding(.bottom, .size32)
            
            Divider()
                .frame(height: 1.5)
                .background(.borderGray10)
            
            HStack{
            
                PeptideButton(
                    title: "Dismiss",
                    bgColor: .clear,
                    contentColor: .textDefaultGray01,
                    isFullWidth: false
                ){
                    isPresented.toggle()
                }
                
                PeptideButton(
                    title: self.isDelletingAllSessions ? "Log Out All" : "Log Out",
                    bgColor: .bgRed07,
                    contentColor: .textDefaultGray01,
                    isFullWidth: false
                ){
                    isPresented.toggle()
                    if(self.isDelletingAllSessions){
                        deleteAllSessionCallback?()
                    }else{
                        deleteSessionCallback?()
                    }
                    
                }
                
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.all, .size24)
            
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bgGray11, in: RoundedRectangle(cornerRadius: .size16))
            .padding(.all, .size16)
    }
    
}

struct LogoutSessionSheet_Preview: PreviewProvider {
    static var previews: some View {
        LogoutSessionSheet(
            isPresented: .constant(true), session: .init(id: "1", name: "Mozilla Firefox on Mac"), isDelletingAllSessions: false
        )
    }
}
