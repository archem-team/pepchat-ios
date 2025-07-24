//
//  SessionsSettings.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI
import Types

/// A view that displays and manages the user's active sessions.
///
/// This view shows a list of active sessions for the user, highlighting the current session and allowing
/// users to delete any other active sessions. It fetches the session data asynchronously and provides
/// a user-friendly interface to manage their sessions.
///
/// - Note: The view utilizes the `ViewState` environment object to access the current user session
///         and theme settings.
struct SessionsSettings: View {
    @EnvironmentObject var viewState: ViewState
    @State var sessions: [Session] = []
    @State var showDeletionPopup = false
    @State var isDelletingAllSessions : Bool = false
    @State var delletingSession : Session?
    
    /// Deletes a specific session from the list of active sessions.
    ///
    /// This method performs an asynchronous request to delete the session and updates the
    /// local state to reflect the change.
    ///
    /// - Parameter session: The session to be deleted.
    func deleteSession(session: Session) {
        Task {
            let _ = try! await viewState.http.deleteSession(session: session.id).get()
            sessions = sessions.filter({ $0.id != session.id })
        }
    }
    
    func deleteAllOtherSessions() {
        Task {
            let _ = try! await viewState.http.deleteSession(session: "all").get()
            sessions = sessions.filter({ $0.id == viewState.currentSessionId })
        }
    }
    
    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Sessions")){_,_ in
            
            if !sessions.isEmpty {
                
                VStack(spacing: .zero){
                    
                    let _ = delletingSession
                    let __ = isDelletingAllSessions
                    
                    Group {
                        
                        let currentSession = sessions.first(where: { $0.id == viewState.currentSessionId })
                        
                        PeptideSectionHeader(title: "This Device")
                        // Display the current session
                        if let session = currentSession {
                            SessionView(viewState: viewState, session: session, isCurrentSession: true, deleteAllcallback: {
                                self.isDelletingAllSessions = true
                                showDeletionPopup.toggle()
                            } ,callback: nil)
                        }
                    }
                    
                    let activeSessions = $sessions.filter({ $0.id != viewState.currentSessionId }).sorted(by: { $0.id > $1.id })
                    
                    if(!activeSessions.isEmpty){
                        Group {
                            
                            PeptideSectionHeader(title: "Active Device")
                            
                            LazyVStack(spacing: .padding8){
                                
                                // Display active sessions
                                ForEach(activeSessions) { session in
                                    SessionView(
                                        viewState: viewState,
                                        session: session.wrappedValue,
                                        deleteAllcallback: nil
                                    ){ session in
                                        
                                        self.delletingSession = session
                                        showDeletionPopup.toggle()
                                        
                                    }
                                    /*.swipeActions(edge: .trailing) {
                                     Button {
                                     deleteSession(session: session.wrappedValue)
                                     } label: {
                                     Label("Delete", systemImage: "trash.fill")
                                     }
                                     .tint(.red)
                                     }*/
                                }
                            }
                            
                            
                        }
                    }
                    
                    Spacer(minLength: .size64)
                    
                }
                .padding(.horizontal, .padding12)
            }
            
            
            
        }
        
        .task {
            let response =  await viewState.http.fetchSessions()
            switch response {
            case .success(let success):
                sessions = success
            case .failure(let failure):
                debugPrint("API returned failure: \(failure)")
            }
            
        }
        .popup(
            isPresented: $showDeletionPopup,
            view: {
                
                LogoutSessionSheet(
                    isPresented: $showDeletionPopup,
                    session: self.delletingSession,
                    isDelletingAllSessions: self.isDelletingAllSessions,
                    deleteSessionCallback: {
                        
                        deleteSession(session: self.delletingSession!)
                        self.delletingSession = nil
                        
                    }
                ){
                    
                    deleteAllOtherSessions()
                    self.isDelletingAllSessions = false
                    
                }
                
            },
            customize: {
                $0.type(.default)
                    .isOpaque(true)
                    .appearFrom(.bottomSlide)
                    .backgroundColor(Color.bgDefaultPurple13.opacity(0.7))
                    .closeOnTap(false)
                    .closeOnTapOutside(false)
            })
        
        
    }
}

/// A view that represents a single session in the session list.
///
/// This view displays the session's name, creation time, and associated platform and browser icons.
/// It also provides the functionality to delete the session via a confirmation dialog.
struct SessionView: View {
    @State var viewState: ViewState
    @State var browserType: Image?
    
    var session: Session
    var deleteSessionCallback: ((Session) -> ())?
    var deleteAllSessionsCallback: (() -> ())?
    var platformType: Image
    var isPlatformTypeSystemImage: Bool
    var isBrowserTypeSystemImage: Bool
    var isCurrentSession : Bool
    
    /// Initializes a `SessionView`.
    ///
    /// - Parameters:
    ///   - viewState: The current state of the view, including theme and user session.
    ///   - sess: The session object containing session details.
    ///   - callback: An optional closure to handle session deletion.
    init(viewState: ViewState, session sess: Session, isCurrentSession : Bool = false, deleteAllcallback: (() -> ())?, callback: ((Session) -> ())?) {
        self._viewState = State(initialValue: viewState)
        self.session = sess
        self.deleteSessionCallback = callback
        self.deleteAllSessionsCallback = deleteAllcallback
        isPlatformTypeSystemImage = false
        isBrowserTypeSystemImage = false
        let sessionName = sess.name.lowercased()
        
        self.isCurrentSession = isCurrentSession
        
        // Determine the platform type and browser type based on session name
        if sessionName.contains("ios") {
            platformType = Image(.peptideIos)
            isPlatformTypeSystemImage = true
            browserType = nil
        } else if sessionName.contains("android") {
            platformType = Image(.peptideAndroid)
            browserType = nil
        } else if sessionName.contains("on") { // in browser or on desktop
            let types = try? /(?<browser>revolt desktop|[^ ]+) on (?<platform>.+)/.firstMatch(in: sessionName)
            
            if let types = types {
                let platformName = types.output.platform.lowercased()
                
                if platformName.contains("mac os") {
                    platformType = Image(.peptideIos)
                    isPlatformTypeSystemImage = true
                } else if platformName.contains("windows") {
                    platformType = Image(.windowsLogo!)
                } else {
                    platformType = Image(.linuxLogo!)
                    isPlatformTypeSystemImage = true
                }
                
                let browserName = types.output.browser.lowercased()
                let willSetBrowserType: Image?
                
                // Determine the browser type based on the browser name
                if browserName.contains(/chrome|brave|opera|arc/) {
                    willSetBrowserType = Image(.peptideChrome)
                } else if browserName == "safari" {
                    willSetBrowserType = Image(.peptideSafari)
                    isBrowserTypeSystemImage = true
                } else if browserName == "firefox" {
                    willSetBrowserType = Image(.peptideFirefox)
                } else if browserName == "revolt desktop" {
                    willSetBrowserType = Image(.monochromeDark!)
                } else {
                    willSetBrowserType = Image(systemName: "questionmark")
                    isPlatformTypeSystemImage = true
                }
                _browserType = State(initialValue: willSetBrowserType)
            } else {
                platformType = Image(systemName: "questionmark.circle")
                _browserType = State(initialValue: nil)
                isPlatformTypeSystemImage = true
            }
        } else {
            platformType = Image(systemName: "questionmark.circle")
            _browserType = State(initialValue: nil)
        }
    }
    
    var body: some View {
        
        VStack(spacing: .zero){
            
            HStack(alignment: .center, spacing: .spacing12) {
                ZStack(alignment: .bottomTrailing) {
                    
                    // Display browser type if available
                    if browserType != nil {
                        ZStack(alignment: .center) {
                            Circle()
                                .frame(width: 48, height: 48)
                                .foregroundStyle(viewState.theme.background2)
                            browserType!
                                .resizable()
//                                .maybeColorInvert(
//                                    color: viewState.theme.background2,
//                                    isDefaultImage: isBrowserTypeSystemImage,
//                                    defaultIsLight: false
//                                )
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.black)
                                .frame(height: 48)
                        }
                        .padding(.top, 5)
                    }else{
                        platformType
                            .resizable()
                        //.maybeColorInvert(color: viewState.theme.background2, isDefaultImage: isPlatformTypeSystemImage, defaultIsLight: false)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    }
                }
                VStack(alignment: .leading, spacing: .spacing4) {
                    
                    PeptideText(textVerbatim: session.name,
                                font: .peptideHeadline)
                    let created = createdAt(id: session.id)
                    let days = Calendar.current.dateComponents([.day], from: created, to: Date.now).day!
                    let dayLabel = days == 0 ? "Created today" : "Created \(days) day\(days > 1 ? "s" : "") ago"
                    
                    
                    PeptideText(textVerbatim: dayLabel,
                                font: .peptideBody4,
                                textColor: .textGray07)
                    
                    
                }
                
                Spacer(minLength: .zero)
                
                
            }
            .padding(.horizontal, .padding12)
            .frame(minHeight: .size72)
            
            PeptideDivider(backgrounColor: .borderGray10)
                .padding(.vertical, .padding4)
                .padding(.leading, 48 + 24)
            
            
            Button {
                
                if deleteSessionCallback != nil {
                    deleteSessionCallback?(session)
                }else if(isCurrentSession){
                    deleteAllSessionsCallback?()
                }
                
            } label: {
                
                HStack(spacing: .spacing24){
                    
                    
                    PeptideIcon(iconName: .peptideSignOutLeave,
                                color: isCurrentSession ? .iconRed07 : .iconDefaultGray01)
                    .padding(.leading, .padding12)
                    
                    PeptideText(text: isCurrentSession ? "Log Out All Other Sessions" : "Log Out",
                                font: .peptideButton,
                                textColor: isCurrentSession ? .textRed07 : .textDefaultGray01)
                    
                    Spacer(minLength: .zero)
                    
                    
                    PeptideIcon(iconName: .peptideArrowRight,
                                color: .iconGray07)
                    
                }
                .padding(.horizontal, .padding12)
                .frame(minHeight: .size48)
            }
            
            
            
        }
        .padding(.vertical, .padding4)
        .background{
            RoundedRectangle(cornerRadius: .radiusMedium)
                .fill(Color.bgGray11)
        }
    }
}


#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    
    let sessions: [Session] = [
        Session(id: "01JDPVXKF48R5XY022YF0WP8DJ", name: "Revolt IOS"),
        Session(id: "01JE75XGYMEF9QMSKF87GEDNR8", name: "chrome on Mac OS"),
        Session(id: "01JEK80BA7VE764M4ZE88D306K", name: "chrome on Windows 10"),
        Session(id: "01JF124E740PFA44NQSTXYN986", name: "Revolt IOS"),
        Session(id: "01JFR4ZZZ97D51BV90X64N4KS1", name: "Revolt IOS"),
        Session(id: "01JGG9WE7TDH9M7BJ964Z18W0Q", name: "chrome on Mac OS"),
        Session(id: "01JGPKPGRR8E7B1W5M05ERVY4H", name: "Revolt IOS"),
        Session(id: "01JH928MRC02WSJWD9NTNG9RHD", name: "chrome on Android OS")
    ]
    
    
    SessionsSettings(sessions: sessions)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
        .task {
            (viewState.currentSessionId = "01JDPVXKF48R5XY022YF0WP8DJ")
        }
}
