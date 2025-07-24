//
//  PeptideTextField.swift
//  Revolt
//
//

import SwiftUI

struct PeptideTextField: View {
    
    @Binding var text: String
    @Binding var state: PeptideTextFieldState
    @FocusState private var isFocused: Bool
    @State var isSecure: Bool = false
    
    var size : PeptideTextFieldSize = .default
    
    var label: String? = nil
    var placeholder: String? = nil
    var icon : ImageResource? = nil
    var hasSecureBtn: Bool = false
    var hasClearBtn: Bool = true
    var cornerRadius : CGFloat = .radiusXSmall
    var height : CGFloat = .size48
    var forceBackgroundColor : Color? = nil
    
    var textStyle : PeptideFont = .peptideBody
    
    var keyboardType : UIKeyboardType = .default
    var onChangeFocuseState : (Bool) -> Void = {_ in}
    
    
    var body: some View {
        
        let (_, _) = size.getConfig
        
        VStack(alignment: .leading, spacing: .size4) {
            
            if let label {
                
                PeptideText(text: label,
                            font: textStyle,
                            textColor: .textGray06,
                            alignment: .leading)
                .padding(.horizontal, .size4)
            }
            
            
            ZStack {
                RoundedRectangle(cornerRadius: .radiusXSmall)
                    .stroke(state.borderColor, lineWidth: .size2)
                    .background(forceBackgroundColor ?? state.backgroundColor)
                    .cornerRadius(cornerRadius)
                
                HStack(spacing: .size8) {
                    
                    if let icon {
                        PeptideIcon(iconName: icon,
                                    size: .size24,
                                    color: .iconGray04)
                    }
                    
                    
                    ZStack(alignment: .leading) {
                        
                        if text.isEmpty, let placeholder {
                            
                            PeptideText(text: placeholder,
                                        font: textStyle,
                                        textColor: .textGray07,
                                        alignment: .leading)
                            
                        }
                        
                        Group{
                            if isSecure {
                                SecureField("", text: $text)
                            } else {
                                TextField("", text: $text)
                            }
                        }
                        .focused($isFocused)
                        .font(.peptideBodyFont)
                        .foregroundStyle(state.textColor)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .tint(.textDefaultGray01)
                        .keyboardType(keyboardType)
                        .disabled(state == .disabled)
                        .frame(height: height)
                        .onChange(of: isFocused){oldState, newState in
                            withAnimation{
                                onChangeFocuseState(newState)
                            }
                        }
                        
                    }
                    
                    
                    
                    if hasSecureBtn {
                        PeptideIconButton(icon: isSecure ? .peptideEye : .peptideEyeClose,
                                          color: .iconGray04,
                                          disabled: state == .disabled){
                            withAnimation{
                                isSecure.toggle()
                            }
                        }                        
                    }
                    
                    if text.isNotEmpty, hasClearBtn {
                        PeptideIconButton(icon: .peptideClose,
                                          color: .iconGray04,
                                          disabled: state == .disabled){
                            withAnimation{
                                text = ""
                            }
                        }
                    }
                    
                    
                }
                .padding(.horizontal, .size12)
            }
            .frame(height: height)
            
            
            if let message = state.message?.message, message.isNotEmpty {
                
                HStack(spacing: .size4){
                    
                    if let icon = state.message?.icon {
                        PeptideIcon(iconName: icon,
                                    color: state.messageIconColor)
                    }
                    
                    PeptideText(text: message,
                                font: textStyle,
                                textColor: state.messageColor,
                                alignment: .leading)
                    .padding(.horizontal, .size4)
                    
                }
                .padding(.horizontal, .size4)
                
                
                
                
                
            }
        }
        .opacity(state.opacity)
    }
}

enum PeptideTextFieldSize {
    case large
    case `default`
    
    var getConfig : (height:CGFloat, horizontalPadding:CGFloat){
        switch self {
        case .large:
            return (48.0, 12.0)
        case .default:
            return (40.0, 8.0)
        }
    }
}


enum PeptideTextFieldState : Equatable {
    case `default`
    case active
    case pressed
    case filled
    case disabled
    case error(message: String, icon: ImageResource = .peptideClose)
    case success(message: String, icon: ImageResource = .peptideClose)
    
    
    // Return border color based on state
    var borderColor: Color {
        switch self {
        case .default, .filled, .pressed, .disabled:
            return .bgGray11
        case .active:
            return .borderDefaultGray09
        case .error:
            return .borderRed10
        case .success:
            return .borderGreen10
        }
    }
    
    // Return background color based on state
    var backgroundColor: Color {
        switch self {
        case .pressed:
            return .bgGray10
        default:
            return .bgGray11
        }
    }
    
    // Text color based on state
    var textColor: Color {
        return .textDefaultGray01
    }
    
    // Error or success message based on state
    var message: (message: String, icon: ImageResource)? {
        switch self {
        case .error(let message, let icon), .success(let message, let icon):
            return (message,icon)
        default:
            return nil
        }
    }
    
    // Message color based on state
    var messageColor: Color {
        switch self {
        case .error:
            return .textRed07
        case .success:
            return .textGreen07
        default:
            return .textGray06
        }
    }
    
    var messageIconColor: Color {
        switch self {
        case .error:
            return .iconRed07
        case .success:
            return .iconGreen07
        default:
            return .iconGray04
        }
    }
    
    var opacity: Double {
        switch self {
        case .disabled:
            return 0.48
        default:
            return 1.0
        }
    }
}




#Preview {
    
    @Previewable @State var aaaa = "aaa"
    
    VStack(spacing: 20) {
        
        PeptideTextField(text: $aaaa,
                         state: .constant(.default),
                         isSecure: true,
                         label: "Label",
                         icon: .connected,
                         hasSecureBtn: true)
        
        
        
        PeptideTextField(text: $aaaa,
                         state: .constant(.error(message: "Error", icon: .peptideClose)),
                         isSecure: true,
                         label: "Label",
                         hasSecureBtn: true,
                         height: .size40)
        
        
        
    }
    .padding(.horizontal, .size16)
    .fillMaxSize()
    
    
}
