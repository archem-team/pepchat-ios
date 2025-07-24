//
//  YouView.swift
//  Revolt
//
//

import SwiftUI
import Types

struct YouView: View {
    
    @EnvironmentObject private var viewState : ViewState
    @State private var isPresentedStatusEditSheet : Bool = false
    @State private var isPresentedPresenceSheet : Bool = false    
    @State private var profile : Profile? = nil
    
    var body: some View {
        
        let currentUser = viewState.currentUser
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: false)){_,_ in
            
            
            VStack(alignment: .leading, spacing: .zero) {
                
                ZStack(alignment: .bottomLeading) {
                    
                    ZStack(alignment: .trailing){
                        
                        VStack(spacing: .zero){
                            
                            if let banner = profile?.background {
                                
                                ZStack {
                                    LazyImage(source: .file(banner), height: 130, clipTo: RoundedRectangle(cornerRadius: .zero))
                                        .overlay{
                                            RoundedRectangle(cornerRadius: .zero)
                                                .fill(Color.bgDefaultPurple13.opacity(0.2))
                                                .frame(height: 130)
                                        }
                                }
                                
                            } else {
                                
                                Image(.peptideProfileBanner)
                                    .resizable()
                                    .frame(height: 130)
                                    .aspectRatio(contentMode: .fill)
                                    .clipped()
                                    .overlay{
                                        RoundedRectangle(cornerRadius: .zero)
                                            .fill(Color.bgDefaultPurple13.opacity(0.2))
                                            .frame(height: 130)
                                    }
                                
                            }
                            
                            
                            RoundedRectangle(cornerRadius: .zero)
                                .fill(Color.clear)
                                .frame(height: .size32)
                            
                        }
                        
                        
                        Button {
                            self.viewState.path.append(NavigationDestination.settings)
                        } label: {
                            PeptideIcon(iconName: .peptideSetting,
                                        size: .size20,
                                        color: .iconDefaultGray01)
                            .frame(width: .size32,
                                   height: .size32)
                            .background(Circle().fill(Color.bgPurple13Alpha60))
                        }
                        .padding(.padding16)
                        
                    }
                    
                    if let currentUser {
                        
                        HStack(spacing: .zero){
                            Avatar(user: currentUser, width: .size64, height: .size64, statusWidth: .size20, statusHeight: .size20, statusPadding: .zero, withPresence: true)
                                .frame(width: .size72, height: .size72)
                                .background{
                                    Circle()
                                        .fill(Color.bgGray12)
                                }
                                .padding(.leading, .padding16)
                                .onTapGesture {
                                    self.isPresentedPresenceSheet.toggle()
                                }
                            
                            ZStack(alignment: .topLeading){
                                
                                Image(.peptideUnion)
                                    .renderingMode(.template)
                                    .foregroundStyle(.bgGray11)
                                
                                
                                Button {
                                    self.isPresentedStatusEditSheet.toggle()
                                } label: {
                                    HStack(spacing: .spacing4){
                                        
                                        let statusLabel = currentUser.status?.text ?? "Add Status"
                                        
                                        if(currentUser.status?.text?.isEmpty ?? true){
                                            PeptideIcon(iconName: .peptideAdd2,
                                                        color: .iconGray07)
                                        }
                                        
                                        PeptideText(text: statusLabel,
                                                    font: .peptideSubhead,
                                                    textColor: .textGray07,
                                                    alignment: .leading
                                        )
                                        
                                    }
                                    .padding(leading: .padding8, trailing: .padding12)
                                    .frame(minWidth: 80, minHeight: .size36)
                                    .background{
                                        RoundedRectangle(cornerRadius: .radius8)
                                            .fill(Color.bgGray11)
                                    }
                                }
                                .shadow(color: .bgDefaultPurple13.opacity(0.2), radius: 2, x: 0, y: 0)
                                .padding(.padding16)
                            }
                        }
                        
                    }
                    
                }
                
                
                if let currentUser {
                    VStack(alignment: .leading, spacing: .spacing2) {
                        
                        
                        Button {
                            self.isPresentedPresenceSheet.toggle()
                        } label: {
                            HStack(spacing: .spacing2){
                                
                                PeptideText(textVerbatim: currentUser.display_name ?? currentUser.username,
                                            font: .peptideTitle4,
                                            textColor: .textDefaultGray01)
                                
                                PeptideIcon(iconName: .peptideArrowRight,
                                            size: .size16,
                                            color: .iconGray07)
                                .rotationEffect(.degrees(90))
                            }
                        }

                        HStack(spacing: .spacing4) {
                            
                            let username = "\(currentUser.username)#\(currentUser.discriminator)"
                            
                            PeptideText(textVerbatim: username,
                                        font: .peptideBody4,
                                        textColor: .textGray07)
                            
                            PeptideIconButton(icon: .peptideCopy,
                                              color: .iconGray07,
                                              size: .size16){
                                copyText(text: currentUser.usernameWithDiscriminator())
                                self.viewState.showAlert(message: "User ID Copied!", icon: .peptideCopy)
                            }
                            
                            
                        }
                        
                        
                    }
                    .padding(top: .padding16)
                    .padding(.horizontal, .padding16)
                }
                
                PeptideButton(title: "Edit Profile",
                              leadingIcon: .peptideEdit){
                    self.viewState.path.append(NavigationDestination.profile_setting)
                }
                .padding(.padding16)
                
                if let content = self.profile?.content, self.profile?.content?.isNotEmpty == true {
                    
                    VStack(alignment: .leading){
            
                        PeptideText(
                            text: "About me",
                            font: .peptideHeadline,
                            textColor: .textGray06
                        )
                        .padding(.bottom, .size6)
                        
                        PeptideText(
                            text: content,
                            font: .peptideBody4,
                            textColor: .textGray04,
                            alignment: .leading
                        )
                        
                    }
                    .padding(.all, .size16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bgGray11, in: RoundedRectangle(cornerRadius: .size16))
                    .padding(.horizontal, .size16)
            
                }
                
            }
            
            Spacer(minLength: .zero)
            
        }
        .sheet(isPresented: self.$isPresentedStatusEditSheet){
            StatusSheet(isPresented: $isPresentedStatusEditSheet)
        }
        .sheet(isPresented: self.$isPresentedPresenceSheet){
            PresenceSheet(isPresented: $isPresentedPresenceSheet,
                          selectedPresence: currentUser?.status?.presence,
                          onClickSetStatusText: {
                self.isPresentedPresenceSheet.toggle()
                self.isPresentedStatusEditSheet.toggle()
            })
        }
        .task {
            
            if self.viewState.state != .signedOut {
                
                let profileResponse = await viewState.http.fetchProfile(user: currentUser?.id ?? "")
                switch profileResponse {
                case .success(let success):
                    self.profile = success
                case .failure(let failure):
                    debugPrint("\(failure)")
                }
            }
            
        }
        
    }
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    YouView()
        .applyPreviewModifiers(withState: viewState)
}
