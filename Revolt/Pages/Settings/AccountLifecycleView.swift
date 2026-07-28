import SwiftUI
import Sentry

enum AccountLifecycleAction: String, Codable, Equatable, Hashable {
    case disable
    case delete

    var appBarTitle: String {
        switch self {
        case .disable:
            return "Disable Account"
        case .delete:
            return "Delete Account"
        }
    }

    var icon: ImageResource {
        switch self {
        case .disable:
            return .peptideDisconnect
        case .delete:
            return .peptideTrashDelete
        }
    }

    var title: String {
        switch self {
        case .disable:
            return "Secure Your Account"
        case .delete:
            return "Confirm Account Deletion"
        }
    }

    var passwordSubtitle: String {
        switch self {
        case .disable:
            return "Enter your password to continue disabling your account."
        case .delete:
            return "Enter your password to continue deleting your account."
        }
    }

    var confirmTitle: String {
        switch self {
        case .disable:
            return "Disable your account?"
        case .delete:
            return "Delete your account?"
        }
    }

    var confirmSubtitle: String {
        switch self {
        case .disable:
            return "You will not be able to access your account unless you contact support. Your data will not be deleted."
        case .delete:
            return "Your account and all of your data, including messages and friends, will be queued for deletion. A confirmation email will be sent, and you can cancel within 7 days by contacting support."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .disable:
            return "Disable Account"
        case .delete:
            return "Delete Account"
        }
    }
}

struct AccountLifecyclePasswordView: View {
    @EnvironmentObject var viewState: ViewState

    let action: AccountLifecycleAction

    @State private var fieldValue = ""
    @State private var fieldTextFieldState: PeptideTextFieldState = .default
    @State private var buttonState: ComponentState = .disabled

    private func validatePassword() {
        Task {
            fieldTextFieldState = .default

            if !fieldValue.isValidPassword {
                fieldTextFieldState = .error(message: "Password is incorrect.")
                return
            }

            buttonState = .loading
            let response = await viewState.http.submitMFATicket(password: fieldValue)
            buttonState = .default

            switch response {
            case .success(let ticket):
                viewState.path.append(NavigationDestination.account_lifecycle_confirm(action, ticket.token))
            case .failure:
                fieldTextFieldState = .error(message: "Password is incorrect.")
            }
        }
    }

    var body: some View {
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: action.appBarTitle)) { _, _ in
            VStack(spacing: .zero) {
                Image(action.icon)
                    .renderingMode(.template)
                    .foregroundStyle(Color.iconRed07)
                    .padding(.top, .padding24)

                Group {
                    PeptideText(
                        text: action.title,
                        font: .peptideTitle2
                    )
                    .padding(.bottom, .padding4)

                    PeptideText(
                        text: action.passwordSubtitle,
                        font: .peptideBody2,
                        textColor: .textGray07,
                        alignment: .center
                    )
                }
                .padding(.horizontal, .padding16)

                PeptideTextField(
                    text: $fieldValue,
                    state: $fieldTextFieldState,
                    isSecure: true,
                    label: "Password",
                    placeholder: "",
                    hasSecureBtn: true
                )
                .padding(.top, .padding24)

                PeptideButton(
                    buttonType: .large(),
                    title: "Next",
                    buttonState: buttonState
                ) {
                    validatePassword()
                }
                .padding(.top, .padding40)

                Spacer(minLength: .zero)
            }
            .padding(.horizontal, .padding16)
            .onChange(of: fieldValue) { _, _ in
                buttonState = fieldValue.isEmpty ? .disabled : .default
            }
        }
    }
}

struct AccountLifecycleConfirmView: View {
    @EnvironmentObject var viewState: ViewState

    let action: AccountLifecycleAction
    let mfaToken: String

    @State private var buttonState: ComponentState = .default
    @State private var showError = false

    private func performAction() {
        Task {
            showError = false
            buttonState = .loading

            let response: Result<EmptyResponse, RevoltError>
            switch action {
            case .disable:
                response = await viewState.http.disableAccount(mfaToken: mfaToken)
            case .delete:
                response = await viewState.http.deleteAccount(mfaToken: mfaToken)
            }

            switch response {
            case .success:
                viewState.ws?.stop()
                withAnimation {
                    viewState.state = .signedOut
                }
            case .failure(let error):
                SentrySDK.capture(error: error)
                showError = true
                buttonState = .default
            }
        }
    }

    var body: some View {
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: action.appBarTitle)) { _, _ in
            VStack(spacing: .zero) {
                Image(action.icon)
                    .renderingMode(.template)
                    .foregroundStyle(Color.iconRed07)
                    .padding(.top, .padding24)

                PeptideText(
                    text: action.confirmTitle,
                    font: .peptideTitle2,
                    alignment: .center
                )
                .padding(.top, .padding16)
                .padding(.bottom, .padding4)

                PeptideText(
                    text: action.confirmSubtitle,
                    font: .peptideBody2,
                    textColor: .textGray07,
                    alignment: .center
                )

                if showError {
                    PeptideText(
                        text: "Something went wrong. Try again later?",
                        font: .peptideBody2,
                        textColor: .textRed07,
                        alignment: .center
                    )
                    .padding(.top, .padding24)
                }

                PeptideButton(
                    buttonType: .large(),
                    title: action.confirmButtonTitle,
                    buttonState: buttonState
                ) {
                    performAction()
                }
                .padding(.top, .padding40)

                Spacer(minLength: .zero)
            }
            .padding(.horizontal, .padding16)
        }
    }
}
