//
//  ServerChannelsView.swift
//  Revolt
//
//

import SwiftUI
import Types

struct ServerChannelsView: View {
    @EnvironmentObject var viewState : ViewState
    var server : Server
    
    @State var isPresentedCreateSheet: Bool = false

    
    var body: some View {
        
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Channels"),
                            fixBottomView: AnyView(
                                HStack(spacing: .zero) {
                                    
                                    Button {
                                        isPresentedCreateSheet.toggle()
                                    } label: {
                                        
                                        HStack(spacing: .spacing4){
                                            
                                            PeptideIcon(iconName: .peptideAdd,
                                                        color: .iconInverseGray13)
                                            
                                            PeptideText(text: "Create",
                                                        textColor: .textInversePurple13)
                                            .padding(.trailing, .padding4)
                                            
                                        }
                                        .padding(.horizontal, .padding8)
                                        .frame(height: .size40)
                                        .background{
                                            RoundedRectangle(cornerRadius: .radiusLarge)
                                                .fill(Color.bgYellow07)
                                        }
                                        .padding(.bottom, .padding24)
                                        
                                    }
                                    
                                }
                                    .padding(.horizontal, .padding16)
                                    .padding(top: .padding8, bottom: .padding24)
                                    .background(Color.bgDefaultPurple13)
                            )){_,_ in
            
                                let categoryChannels = server.categories?.flatMap(\.channels) ?? []
                                let nonCategoryChannels = server.channels.filter({ !categoryChannels.contains($0) })
            
            Spacer()
                                    .frame(height: (nonCategoryChannels.isEmpty) ? .spacing8 : .spacing24)
            
            LazyVStack(spacing: .zero){
                
                ForEach(nonCategoryChannels.compactMap({viewState.channels[$0]})){ channel in
                    ServerChannelItemView(channel: channel,
                                          server: server)
                }
                
                
                ForEach(server.categories ?? []) { category in
                    
                    HStack(spacing: .spacing12){
                        PeptideText(textVerbatim: category.title,
                                    font: .peptideHeadline,
                                    textColor: .textGray06)
                        
                        Spacer(minLength: .zero)
                        
                        Button {
                            viewState.path.append(NavigationDestination.server_category(server.id, category.id))
                        } label: {
                            PeptideText(text: "Edit",
                                        font: .peptideButton,
                                        textColor: .textGray06)
                        }
                    }
                    .padding(.vertical , .padding16)
                    
                    ForEach(category.channels.compactMap({ viewState.channels[$0] }), id: \.id) { channel in
                        ServerChannelItemView(channel: channel,
                                              server: server)
                    }
                }
            }
            .padding(.horizontal, .padding16)
            
            Spacer(minLength: .zero)
            
        }
        .sheet(isPresented: $isPresentedCreateSheet){
            ChannelCategoryCreateSheet(isPresented: $isPresentedCreateSheet, onNavigate: {type in
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    
                    self.viewState.path.append(NavigationDestination.channel_category_create(server.id, type))

                }
                
            })
        }
    }
}


struct ServerChannelItemView : View {
    
    @EnvironmentObject private var viewState : ViewState
    
    var channel : Channel
    var server : Server
    
    var body: some View {
        
        Button {
            self.viewState.path.append(NavigationDestination.server_channel_overview_setting(channel.id, server.id))
        } label: {
            
            HStack(spacing: .spacing12){
                PeptideIcon(iconName: .peptideTag,
                            size: .size20,
                            color: .iconGray07)
                
                PeptideText(textVerbatim: channel.getName(viewState),
                            font: .peptideBody3,
                            textColor: .textGray06)
                
                Spacer(minLength: .zero)
            }
        }
        .padding(.bottom, .padding16)
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    ServerChannelsView(server: viewState.servers["0"]!)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}


#Preview{
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    ServerChannelItemView(channel: viewState.channels["0"]!, server: viewState.servers["0"]!)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
    
}
