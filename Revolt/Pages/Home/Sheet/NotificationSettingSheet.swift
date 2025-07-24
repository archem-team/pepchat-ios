//
//  NotificationSettingSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct NotificationSettingSheet: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool
    var channel: Channel? = nil
    var server : Server? = nil
    

    @State private var notificationState: NotificationState = .useDefault

    // Notification options
    private let items: [PeptideSheetItem] = [
        .init(index: 1, title: "Use Default", icon: .peptideSetting),
        .init(index: 2, title: "Mute", icon: .peptideNotificationOff),
        .init(index: 3, title: "All Messages", icon: .peptideNotificationOn),
        .init(index: 4, title: "Mentions Only", icon: .peptideAt),
        .init(index: 5, title: "None", icon: .peptideProhibitNoneBlock, isLastItem: true),
    ]

    var body: some View {
        PeptideSheet(isPresented: $isPresented, topPadding: .padding16) {
            headerSection
            notificationOptionsList
        }
        .task {
            loadInitialNotificationState()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        ZStack(alignment: .center) {
            PeptideText(
                text: "Notification Options",
                font: .peptideHeadline,
                textColor: .textDefaultGray01
            )
//            HStack {
//                PeptideIconButton(icon: .peptideBack, color: .iconDefaultGray01, size: .size24) {
//                    self.isPresented.toggle()
//                }
//                Spacer()
//            }
        }
        .padding(.bottom, .padding24)
    }

    private var notificationOptionsList: some View {
        VStack(spacing: .spacing4) {
            ForEach(items, id: \.index) { item in
                notificationOptionRow(for: item)
                if !item.isLastItem {
                    PeptideDivider()
                        .padding(.leading, .padding48)
                }
            }
        }
        .backgroundGray11(verticalPadding: .padding4)
    }

    private func notificationOptionRow(for item: PeptideSheetItem) -> some View {
        /*Button {
            self.isPresented.toggle()
        } label: {
         
        }*/
        
        HStack {
            PeptideActionButton(icon: item.icon, title: item.title, hasArrow: false)
            Toggle("", isOn: toggleBinding(for: item.index))
                .toggleStyle(PeptideCircleCheckToggleStyle())
                .padding(.trailing, .padding12)
        }
    }

    private func toggleBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: {
                notificationState == mapIndexToNotificationState(index: index)
            },
            set: { isSelected in
                if isSelected {
                    updateNotificationState(
                        newState: mapIndexToNotificationState(index: index)
                    )
                }
            }
        )
    }

    // MARK: - Index to NotificationState Mapper
    private func mapIndexToNotificationState(index: Int) -> NotificationState {
        switch index {
        case 1: return .useDefault
        case 2: return .muted
        case 3: return .all
        case 4: return .mention
        default: return .none
        }
    }


    private func loadInitialNotificationState() {
        if let channel = channel, let _ = server {
            notificationState = viewState.userSettingsStore.cache.notificationSettings.channel[channel.id] ?? .useDefault
        } else if let server = server {
            notificationState = viewState.userSettingsStore.cache.notificationSettings.server[server.id] ?? .useDefault
        } else if let channel = channel {
            notificationState = viewState.userSettingsStore.cache.notificationSettings.channel[channel.id] ?? .useDefault
        }
    }

    private func updateNotificationState(newState: NotificationState) {
        notificationState = newState
        viewState.userSettingsStore.updateNotificationState(forChannel: self.channel?.id,
                                                            forServer: self.server?.id,
                                                            with: newState)
        
        Task {
            let timestamp = "\(Int64(Date().timeIntervalSince1970 * 1000))"
            let keys = viewState.userSettingsStore.prepareNotificationSettings()
            _ = await viewState.http.setSettings(timestamp: timestamp, keys: keys)
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState = ViewState.preview()
    NotificationSettingSheet(
        isPresented: .constant(false),
        channel: viewState.channels["0"]!
    )
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
