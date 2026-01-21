//
//  LogoutSessionDialog.swift
//  Revolt
//
//  Created by Mehdi on 1/29/25.
//

import Foundation
import SwiftUI
import Types

struct ConfirmationSheet : View{
    @Binding var isPresented: Bool
    @Binding var isLoading: Bool
    var title: String
    var titleButtomPadding: CGFloat = .size32
    var subTitle: String
    var confirmText: String
    var dismissText: String = "Dismiss"
    var onDismiss: (() -> Void)?
    var popOnDismiss: Bool = true
    var popOnConfirm: Bool = true
    var showCloseButton: Bool = false
    var buttonAlignment: Alignment = .trailing
    var onConfirm: () -> Void
    
    var body: some View {
        VStack {
            if showCloseButton {
            
                HStack{
                    Spacer(minLength: .zero)
                    
                    PeptideIconButton(icon: .peptideCloseLiner, size: 24){
                        
                        if(popOnDismiss){
                            isPresented.toggle()
                        }
                        if let onDismiss = onDismiss {
                            onDismiss()
                        }
                        
                    }
                }
                
            }
            
            VStack(alignment: .leading) {
                PeptideText(
                    text: title,
                    font: .peptideTitle3,
                    textColor: .textDefaultGray01,
                    alignment: .leading
                )
                .padding(.bottom, self.titleButtomPadding)
                
                PeptideText(
                    text: subTitle,
                    font: .peptideBody3,
                    textColor: .textGray06,
                    alignment: .leading
                ).padding(.bottom, self.titleButtomPadding)
                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 1.5)
                .background(.borderGray10)
            
            HStack{
            
                PeptideButton(
                    title: dismissText,
                    bgColor: .clear,
                    contentColor: .textDefaultGray01,
                    isFullWidth: false
                ){
                    if(popOnDismiss){
                        isPresented.toggle()
                    }
                    if let onDismiss = onDismiss {
                        onDismiss()
                    }
                }
                
                PeptideButton(
                    title: confirmText,
                    bgColor: .bgRed07,
                    contentColor: .textDefaultGray01,
                    buttonState: isLoading ? .loading : .default,
                    isFullWidth: false
                ){
                    if(popOnConfirm){
                        isPresented.toggle()
                    }
                    onConfirm()
                    
                }
                
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }.padding()
            .frame(maxWidth: .infinity)
            .background(.bgGray11, in: RoundedRectangle(cornerRadius: .size16))
            .padding()
        
        
//        VStack{
//            
//            ZStack(alignment: .topTrailing){
//            
//                VStack(spacing: .zero){
//                    
//                    if showCloseButton {
//                    
//                        HStack{
//                            Spacer(minLength: .zero)
//                            
//                            PeptideIconButton(icon: .peptideCloseLiner, size: 24){
//                                
//                                if(popOnDismiss){
//                                    isPresented.toggle()
//                                }
//                                if let onDismiss = onDismiss {
//                                    onDismiss()
//                                }
//                                
//                            }
//                            .padding()
////                            .padding(.all, .size16)
//                        }
//                        
//                    }
//                    
//                
//                    VStack(alignment: .leading){
//                        
//                        PeptideText(
//                            text: title,
//                            font: .peptideTitle3,
//                            textColor: .textDefaultGray01,
//                            alignment: .leading
//                        )
//                        .padding(.bottom, self.titleButtomPadding)
//                        
//                        PeptideText(
//                            text: subTitle,
//                            font: .peptideBody3,
//                            textColor: .textGray06,
//                            alignment: .leading
//                        )
//                        
//                    }
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                        .padding(.horizontal, .size24)
//                        .padding(.top, .size24)
//                        .padding(.bottom, .size32)
//                    
//                    Divider()
//                        .frame(height: 1.5)
//                        .background(.borderGray10)
//                    
//                    HStack{
//                    
//                        PeptideButton(
//                            title: dismissText,
//                            bgColor: .clear,
//                            contentColor: .textDefaultGray01,
//                            isFullWidth: false
//                        ){
//                            if(popOnDismiss){
//                                isPresented.toggle()
//                            }
//                            if let onDismiss = onDismiss {
//                                onDismiss()
//                            }
//                        }
//                        
//                        PeptideButton(
//                            title: confirmText,
//                            bgColor: .bgRed07,
//                            contentColor: .textDefaultGray01,
//                            buttonState: isLoading ? .loading : .default,
//                            isFullWidth: false
//                        ){
//                            if(popOnConfirm){
//                                isPresented.toggle()
//                            }
//                            onConfirm()
//                            
//                        }
//                        
//                    }
//                    .frame(maxWidth: .infinity, alignment: buttonAlignment)
//                    .padding(.all, .size24)
//                    
//                }
//            }
//            
//        }
//            .frame(maxWidth: .infinity, alignment: .leading)
//            .background(.bgGray11, in: RoundedRectangle(cornerRadius: .size16))
//            .padding(.all, .size16)
    }
    
}

struct ConfirmationSheet_Preview: PreviewProvider {
    static var previews: some View {
        ConfirmationSheet(
            isPresented: .constant(true),
            isLoading: .constant(true),
            title: "Close Conversation with Abi?",
            subTitle: "You can re-open it later but it will disappear on both sides.",
            confirmText: "Close DM",
            showCloseButton: true
        ){
            
        }
    }
}


