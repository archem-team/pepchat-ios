//
//  StatusSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct StatusPreviewSheet: View {
    
    @EnvironmentObject private var viewState : ViewState
    @Binding var isPresented : Bool
    
    @State var user : User
    
    var body: some View {
        
        VStack{
            PeptideSheet(isPresented: $isPresented, horizontalPadding: .zero){
                
                ZStack(alignment: .center) {
                    PeptideText(
                        text: "\(user.display_name ?? user.usernameWithDiscriminator())’s Status",
                        font: .peptideHeadline,
                        textColor: .textDefaultGray01
                    )
                    HStack {
                        PeptideIconButton(icon: .peptideBack, color: .iconDefaultGray01, size: .size24) {
                            isPresented.toggle()
                        }
                        Spacer()
                    }
                }
                .padding(.bottom, .padding24)
                .padding(.horizontal, .padding16)
                
                HStack(spacing: .zero){
                    Avatar(user: user, width: 64, height: 64, withPresence: false)
                        .frame(width: 64, height: 64)
                        .background{
                            Circle()
                                .fill(Color.bgGray12)
                        }
                        .padding(.leading, .padding16)
                    
                    ZStack(alignment: .topLeading){
                        
                        Image(.peptideUnion)
                            .renderingMode(.template)
                            .foregroundStyle(.bgGray11)
                        
                        
                        Button {
                            self.isPresented.toggle()
                        } label: {
                                
                            HStack(spacing: .zero){
                                PeptideText(text: user.status?.text ?? "",
                                                font: .peptideSubhead,
                                                textColor: .textGray07,
                                                alignment: .leading,
                                                lineLimit: 3
                                    )
                                    .padding(.horizontal, .size12)
                                    .padding(.vertical, .size8)
                                
                                Spacer()
                            }
                            .padding(leading: .padding8, trailing: .padding12)
                            .frame(minHeight: 70)
                            .background{
                                RoundedRectangle(cornerRadius: .radiusXSmall)
                                    .fill(Color.bgGray11)
                            }
                        }
                        .shadow(color: .bgDefaultPurple13.opacity(0.2), radius: 2, x: 0, y: 0)
                        .padding(.padding16)
                    }
                }
                
            }
        }
        .padding(top: .padding24, bottom: .padding24)
        .background{
            RoundedRectangle(cornerRadius: .radiusMedium)
                .fill(Color.bgGray12)
        }

        
    }
}


struct StatusPreviewSheetPreview: PreviewProvider {
    @StateObject static var viewState: ViewState = ViewState.preview().applySystemScheme(theme: .dark)
    
    static var previews: some View {
        Text("foo")
            .sheet(isPresented: .constant(true)) {
                StatusPreviewSheet(isPresented: .constant(true), user: viewState.users["0"]!)
            }
            .applyPreviewModifiers(withState: viewState)
            .preferredColorScheme(.dark)
    }
}
