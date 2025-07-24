//
//  ReportMessageSheetView.swift
//  Revolt
//
//  Created by Angelo Manca on 2023-11-05.
//

import SwiftUI
import Types

/// A view that allows users to report a message with a specific reason and description.
/// The report submission will not be sent to the server's moderators but to the platform team.
struct ReportMessageSheetView: View {
    // MARK: - Properties
    
    /// Global view state to manage shared application data and perform actions.
    @EnvironmentObject var viewState: ViewState
    
    /// System's color scheme (light/dark mode) that can be used to adjust UI appearance.
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    
    /// The user's input providing context or explanation for why the message is being reported.
    @State var userContext: String = ""
    
    /// Holds error messages related to form validation.
    @State var error: String? = nil
    
    /// The reason selected by the user for reporting the message.
    @State var reason: ContentReportPayload.ContentReportReason = .NoneSpecified
    
    /// Controls the visibility of the sheet.
    @Binding var showSheet: Bool
    
    /// The view model representing the message that is being reported.
    @ObservedObject var messageView: MessageContentsViewModel

    // MARK: - Methods
    
    /// Submits the report to the server after validating the form input.
    ///
    /// - Validates that the user has selected a reason for reporting and provided additional details.
    /// - If validation passes, the report is submitted asynchronously to the platform's report endpoint.
    /// - Toggles the sheet visibility upon successful submission.
    ///
    /// - Parameters: None
    /// - Returns: None
    func submit() {
        // Validate that the user has selected a report reason
        if reason == .NoneSpecified {
            error = "Please select a category"
        } else {
            error = nil
        }
        
        // Validate that the user has provided additional context
        if userContext.isEmpty {
            if error != nil {
                error! += " and add a reason"
            } else {
                error = "Please add a reason"
            }
        }
        
        // If there are validation errors, stop submission
        if error != nil {
            return
        }
        
        // Submit the report asynchronously if no errors
        Task {
            viewState.http.logger.debug("Start report task")
            print(await viewState.http.safetyReport(type: .Message, id: messageView.message.id, reason: reason, userContext: userContext))
        }
        
        // Close the report sheet after submission
        showSheet.toggle()
    }
    
    // MARK: - Body
    
    /// The main content of the report message sheet view.
    ///
    /// - Contains a header, the message being reported, input fields for the report reason and user context, and the submit button.
    /// - If the form is incomplete, it displays validation errors.
    ///
    /// - Returns: A `View` representing the UI for reporting a message.
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            // Spacer for layout adjustment
            Spacer()
                .frame(maxHeight: 20)

            // Header text to explain the purpose of the form
            VStack(alignment: .center) {
                Text("Tell us what's wrong with this message")
                    .font(.title)
                    .multilineTextAlignment(.center)
                
                Text("Please note that this does not get sent to this server's moderators")
                    .font(.caption)
                    .foregroundStyle(viewState.theme.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

            // Display the message being reported
            MessageView(viewModel: messageView, isStatic: true)
                .padding(.horizontal, 5)
                .padding(.vertical, 10)

            // Picker for selecting the report reason
            VStack {
                Text("Pick a category")
                    .font(.caption)
    
                // Dropdown to select the reason for reporting
                Picker("Report reason", selection: $reason) {
                    ForEach(ContentReportPayload.ContentReportReason.allCases, id: \.rawValue) { reason in
                        Text(reason.rawValue)
                            .tag(reason)
                    }
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .foregroundStyle(viewState.theme.foreground)
                .overlay(
                    // Red border if no reason is selected and form is invalid
                    RoundedRectangle(cornerRadius: 5)
                        .stroke((error != nil && userContext.isEmpty) ? viewState.theme.error : viewState.theme.foreground, lineWidth: 1)
                )
            }

            // TextField for the user to provide additional details
            VStack {
                Text("Give us some detail")
                    .font(.caption)
                    .foregroundStyle(viewState.theme.foreground.color)

                // Text input for the user to explain the issue
                TextField("", text: $userContext, axis: .vertical)
                    .padding(.vertical, 15)
                    .padding(.leading)
                    .overlay(
                        // Red border if the text field is empty and form is invalid
                        RoundedRectangle(cornerRadius: 5)
                            .stroke((error != nil && userContext.isEmpty) ? viewState.theme.error : viewState.theme.foreground, lineWidth: 1)
                    )
                    .placeholder(when: userContext.isEmpty) {
                        Text("What's wrong...")
                            .padding()
                    }
                    .frame(minHeight: 50)
            }
            
            // Display an error message if validation fails
            if error != nil {
                Text(error!)
                    .font(.subheadline)
                    .foregroundStyle(viewState.theme.error)
            }

            // Submit button to trigger the report submission
            Button(action: submit, label: {
                Text("Submit")
            })
            .padding()
            .frame(maxWidth: .infinity)
            .background(viewState.theme.accent) // Button background color
            .clipShape(.rect(cornerRadius: 5)) // Rounded corners for the button

            Spacer() // Spacer to push the button upwards
        }
        .padding(.horizontal, 32)
        .background(viewState.theme.background) // Background color for the sheet
    }
}

// Preview code for testing the UI in light/dark mode
//struct ReportMessageSheetView_Preview: PreviewProvider {
//    @StateObject static var viewState = ViewState.preview()
//
//    static var message = viewState.messages["01HD4VQY398JNRJY60JDY2QHA5"]!
//    static var model = MessageViewModel(
//        viewState: viewState,
//        message: .constant(message),
//        author: .constant(viewState.users[message.author]!),
//        member: .constant(viewState.members["0"]!["0"]),
//        server: .constant(viewState.servers["0"]),
//        channel: .constant(viewState.channels["0"]!),
//        replies: .constant([Reply(message: message, mention: false)]),
//        channelScrollPosition: .constant(nil)
//    )
//
//    static var previews: some View {
//        ReportMessageSheetView(showSheet: .constant(true), messageView: model)
//            .applyPreviewModifiers(withState: viewState.applySystemScheme(theme: .light))
//
//        ReportMessageSheetView(showSheet: .constant(true), messageView: model)
//            .applyPreviewModifiers(withState: viewState.applySystemScheme(theme: .dark))
//    }
//}
