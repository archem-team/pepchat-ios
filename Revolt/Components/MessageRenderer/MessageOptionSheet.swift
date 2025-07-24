//
//  MessageOptionSheet.swift
//  Revolt
//
//

import SwiftUI

struct MessageOptionSheet: View {
    
    @EnvironmentObject var viewState: ViewState
    @ObservedObject var viewModel: MessageContentsViewModel
    
    @Binding var isPresented : Bool
    @State private var sheetHeight: CGFloat = .zero
    
    var isMessageAuthor : Bool = false
    var canDeleteMessage : Bool = false
    
    var onClick : (MessageOptionType) -> Void
    
    
    var body: some View {
        
        VStack(spacing: .spacing24){
            

            
            if let currentUser = viewState.currentUser {
                if  resolveChannelPermissions(from: currentUser, targettingUser: currentUser, targettingMember: viewModel.server.flatMap { viewState.members[$0.id]?[currentUser.id] }, channel: viewModel.channel, server: viewModel.server).contains(.react) {
                    
                    MessageEmojisReact(onClick: {
                        onClick(.sendReact($0))
                    })
                    
                }
            }
            
            if isMessageAuthor {
                Button {
                    print("✏️ Edit button tapped in MessageOptionSheet")
                    onClick(.edit)
                } label: {
                    
                    PeptideActionButton(icon: .peptideEdit,
                                        title: "Edit Message",
                                        hasArrow: false)
                }
                PeptideDivider()
                    .padding(.leading, .padding48)
                Button {
                    onClick(.reply)
                } label: {
                    PeptideActionButton(icon: .peptideReply,
                                        title: "Reply",
                                        hasArrow: false)
                }
            } else {
                
                Button {
                    onClick(.reply)
                } label: {
                    PeptideActionButton(icon: .peptideReply,
                                        title: "Reply",
                                        hasArrow: false)
                    .backgroundGray11(verticalPadding: .padding4)
                    
                }
            }
            if !isMessageAuthor {
                
                Button {
                    onClick(.mention)
                } label: {
                    
                    PeptideActionButton(icon: .peptideAt,
                                        title: "Mention",
                                        hasArrow: false)
                    .backgroundGray11(verticalPadding: .padding4)
                }
                PeptideDivider()
                    .padding(.leading, .padding48)
            }
            
            
            // Button {
            //     onClick(.markUnread)
            // } label: {
            //     PeptideActionButton(icon: .peptideEyeClose,
            //                         title: "Mark Unread",
            //                         hasArrow: false)
            // }
            
            PeptideDivider()
                .padding(.leading, .padding48)
            
            Button {
                print("📋 Copy Text button tapped in MessageOptionSheet")
                onClick(.copyText)
            } label: {
                PeptideActionButton(icon: .peptideCopy,
                                    title: "Copy Text",
                                    hasArrow: false)
            }
            
            PeptideDivider()
                .padding(.leading, .padding48)
            
            Button {
                onClick(.copyLink)
            } label: {
                PeptideActionButton(icon: .peptideLink,
                                    title: "Copy Message Link",
                                    hasArrow: false)
            }
            
            PeptideDivider()
                .padding(.leading, .padding48)
            
            Button {
                onClick(.copyId)
            } label: {
                PeptideActionButton(icon: .peptideId,
                                    title: "Copy Message ID",
                                    hasArrow: false)
            }
            
            if canDeleteMessage {
                
                Button {
                    onClick(.deleteMessage)
                } label: {
                    
                    
                    PeptideActionButton(icon: .peptideTrashDelete,
                                        iconColor: .iconRed07,
                                        title: "Delete Message",
                                        titleColor: .textRed07,
                                        hasArrow: false)
                    .backgroundGray11(verticalPadding: .padding4)
                    
                }
                
            }
            
            if !isMessageAuthor {
                Button {
                    onClick(.report)
                } label: {
                    
                    
                    PeptideActionButton(icon: .peptideReportFlag,
                                        iconColor: .iconRed07,
                                        title: "Report Message",
                                        titleColor: .textRed07,
                                        hasArrow: false)
                    .backgroundGray11(verticalPadding: .padding4)
                    
                }
            }
            
        }
        .padding(top: .padding32,
                 bottom: .padding8,
                 leading: .padding16,
                 trailing: .padding16)
        .overlay {
            GeometryReader { geometry in
                Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
            sheetHeight = newHeight
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.bottom)

        
    }
}

enum MessageOptionType {
    case edit
    case reply
    case mention
    case markUnread
    case copyText
    case copyLink
    case copyId
    case report
    case deleteMessage
    case sendReact(String)
}

/*#Preview {
    MessageOptionSheet(isPresented: .constant(true), viewModel:.init(), onClick: {_ in
    })
    .preferredColorScheme(.dark)
}*/
