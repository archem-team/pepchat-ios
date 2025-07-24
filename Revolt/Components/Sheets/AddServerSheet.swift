//
//  JoinServer.swift
//  Revolt
//
//  Created by Angelo on 01/11/2023.
//

import Foundation
import SwiftUI
import Types

/// A view representing a sheet that allows the user to add a server.
struct AddServerSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Environment(\.dismiss) var dismiss
    //@State var showJoinServerAlert: Bool = false
    
    @Binding var isPresented : Bool
    
    
    @State var serverName = ""
    @State var serverNameTextFieldStatus : PeptideTextFieldState = .default
    @State var createServerBtnState : ComponentState = .disabled
    
    var body: some View {
        
        PeptideSheet(isPresented: $isPresented, topPadding: .padding24){
            
            PeptideText(
                text: "Create Your Server",
                font: .peptideHeadline,
                textColor: .textDefaultGray01
            )
            
            
            PeptideText(text: "A place to chat, share, and collaborate with your members." ,
                        font: .peptideSubhead,
                        textColor: .textGray06)
            .padding(top: .padding4)
            
            PeptideTextField(
                text: $serverName,
                state: $serverNameTextFieldStatus,
                placeholder : "Enter server name",
                keyboardType: .default)
            .padding(.top, .padding24)
            .onChange(of: serverName){_, newServerName in
                
                serverNameTextFieldStatus = .default
                
                if newServerName.isEmpty {
                    createServerBtnState = .disabled
                } else {
                    createServerBtnState = .default
                }
                
            }
            
            PeptideButton(title: "Create Server",
                          buttonState: createServerBtnState){
                self.createServer()
            }
            .padding(.top, .padding24)
            
        }
        
        // Alert configuration for joining a server
        /*.alert("Invite code or link", isPresented: $showJoinServerAlert) {
         JoinServerAlert() // The alert content is defined in the JoinServerAlert view
         } message: {
         // Message shown in the alert
         Text("Enter a link like rvlt.gg/Testers or an invite code like Testers")
         }*/
    }
    

    func createServer() {
        Task {
            if self.serverName.isEmpty {
                return
            }
            self.createServerBtnState = .loading
            
            let response = await self.viewState.http.createServer(createServer: .init(name: self.serverName))
            
            self.createServerBtnState = .default
            
            switch response {
                case .success(let serverChannel):
                let server = serverChannel.server
                    self.viewState.servers[server.id] = server
                    
                    // Add the server's channels to ViewState's channels collection
                    for channel in serverChannel.channels {
                        self.viewState.channels[channel.id] = channel
                    }
                    
                    self.isPresented.toggle()
                
                    withAnimation {
                        viewState.selectServer(withId: server.id)
                    }
                    
                    // OPTIMIZED: Move API call outside animation block to prevent UI freeze
                    Task.detached(priority: .userInitiated) {
                        await self.viewState.getServerMembers(target: server.id)
                    }
                
                case .failure(let failure):
                    debugPrint("error \(failure)")
            }
        }
    }
}

/// A view that presents an alert for joining a server via invite code or link.
struct JoinServerAlert: View {
    // Environment object to access the application's view state
    @EnvironmentObject var viewState: ViewState
    
    // State variable to hold the input text from the user
    @State var text: String = ""
    
    /// Parses the invite code from the input text.
    /// - Returns: The extracted invite code if it matches the expected format, otherwise nil.
    func parseInvite() -> String? {
        // Regular expression to match the invite code
        if let match = text.wholeMatch(of: /(?:(?:https?:\/\/)?rvlt\.gg\/)?(\w+)/) {
            return String(match.output.1) // Return the matched invite code
        } else {
            return nil // No match found
        }
    }
    
    var body: some View {
        // Text field for the user to enter the invite code or link
        TextField("Invite code or link", text: $text)
        
        // Button to join the server with the provided invite code
        Button("Join") {
            Task {
                // Attempt to parse the invite code
                if let invite_code = parseInvite(),
                   (try? await viewState.http.fetchInvite(code: invite_code).get()) != nil {
                    // Navigate to the invite if successful
                    viewState.path.append(NavigationDestination.invite(invite_code))
                }
            }
        }
        
        // Cancel button to dismiss the alert
        Button("Cancel", role: .cancel) {}
    }
}

/// Preview provider for the AddServerSheet view.
#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    AddServerSheet(isPresented: .constant(false))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
