//
//  PeptideOtp.swift
//  Revolt
//
//

//https://github.com/WesCSK/OTPEnteries/blob/completed/OTPEnteries/VIews/OTPTextField.swift

import SwiftUI
import Combine


struct PeptideOtp: View {
    //MARK -> PROPERTIES
    var numberOfFields: Int
    var maxCharactersPerField: Int
    var otpWidth: CGFloat? = .size48
    var otpHeight: CGFloat = .size48
    
    var customView: AnyView?
    
    var keyBoardType: UIKeyboardType = .numberPad
    
    @FocusState private var fieldFocus: Int?
    @State private var enterValue: [String]
    var onCompletion: (String) -> Void
    var onChange: (() -> Void)? = nil
    
    init(numberOfFields: Int = 6,
         maxCharactersPerField: Int = 1,
         otpWidth: CGFloat? = .size48,
         otpHeight: CGFloat = .size48,
         keyBoardType: UIKeyboardType = .numberPad,
         onChange: (() -> Void)? = nil,
         onCompletion: @escaping (String) -> Void,
         customView: AnyView? = nil) {
        self.numberOfFields = numberOfFields
        self.otpWidth = otpWidth
        self.otpHeight = otpHeight
        self.maxCharactersPerField = maxCharactersPerField
        self.customView = customView
        self.keyBoardType = keyBoardType
        self.enterValue = Array(repeating: "", count: numberOfFields)
        self.onCompletion = onCompletion
        self.onChange = onChange
    }
    
    var body: some View {
        HStack(spacing: .zero) {
            ForEach(0..<numberOfFields, id: \.self) { index in
                
                    TextField("", text: $enterValue[index])
                    .foregroundStyle(.textDefaultGray01)
                    .keyboardType(keyBoardType)
                    .frame(width:  otpWidth , height: otpHeight)
                    .background(.bgGray11)
                    .cornerRadius(.radiusXSmall)
                    .font(.peptideBody3Font)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .focused($fieldFocus, equals: index)
                    .tag(index)
                    .onChange(of: enterValue[index]) { _, newValue in
                        
                        if let onChange = self.onChange{
                            onChange()
                        }
                        
                        if !newValue.isEmpty {
                            
                            // Check if this is a paste operation (multiple characters entered at once)
                            if newValue.count > maxCharactersPerField {
                                // Handle paste operation
                                handlePaste(pastedText: newValue, startingIndex: index)
                            } else {
                                // Normal single character input
                                // Limit character count for each field
                                if newValue.count > maxCharactersPerField {
                                    enterValue[index] = String(newValue.prefix(maxCharactersPerField))
                                }
                                
                                // Move focus when max characters reached
                                if enterValue[index].count == maxCharactersPerField {
                                    if index < numberOfFields - 1 {
                                        fieldFocus = index + 1
                                    } else {
                                        fieldFocus = nil // End editing
                                        onCompletion(enterValue.joined())
                                    }
                                }
                            }
                            
                        } else {
                            
                            if fieldFocus ?? 0 > 0 {
                                fieldFocus = (fieldFocus ?? 0) - 1
                            }
                            
                            
                        }
                    }
                    
                    
                    if  (customView != nil) && index != numberOfFields - 1 {
                        customView
                    }
                    
                
                
            }
        }
        .onAppear {
            fieldFocus = 0 // Start with the first field focused
        }
    }
    
    // Handle paste operation by distributing characters across fields
    private func handlePaste(pastedText: String, startingIndex: Int) {
        // Extract only valid characters based on keyboard type
        let validCharacters: String
        if keyBoardType == .numberPad {
            // For number pad, only accept digits and remove spaces/dashes that might be in copied OTP codes
            validCharacters = pastedText.replacingOccurrences(of: " ", with: "")
                                       .replacingOccurrences(of: "-", with: "")
                                       .filter { $0.isNumber }
        } else {
            // For other keyboard types, preserve letters, numbers, and dashes (for recovery codes)
            validCharacters = pastedText.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        }
        
        // Clear all fields from the starting index onward before pasting
        for i in startingIndex..<numberOfFields {
            enterValue[i] = ""
        }
        
        // Distribute characters across fields starting from the current index
        var currentIndex = startingIndex
        var characterIndex = 0
        
        while currentIndex < numberOfFields && characterIndex < validCharacters.count {
            let endIndex = min(characterIndex + maxCharactersPerField, validCharacters.count)
            let startIdx = validCharacters.index(validCharacters.startIndex, offsetBy: characterIndex)
            let endIdx = validCharacters.index(validCharacters.startIndex, offsetBy: endIndex)
            enterValue[currentIndex] = String(validCharacters[startIdx..<endIdx])
            
            characterIndex += maxCharactersPerField
            currentIndex += 1
        }
        
        // Set focus to the next empty field or remove focus if all fields are filled
        let filledCount = enterValue.filter { !$0.isEmpty }.count
        if filledCount < numberOfFields {
            // Find the first empty field and set focus there
            for i in 0..<numberOfFields {
                if enterValue[i].isEmpty {
                    fieldFocus = i
                    break
                }
            }
        } else {
            // All fields are filled
            fieldFocus = nil
            onCompletion(enterValue.joined())
        }
    }
}


struct PeptideOtp_Previews: PreviewProvider {
    static var previews: some View {
        
        VStack(spacing: 32){
            
            PeptideOtp(numberOfFields: 6, onCompletion: { result in
            }, customView: AnyView(
                Spacer()
                    .frame(width: 12)
            ))
            
            
            PeptideOtp(numberOfFields: 2,
                             otpWidth: .infinity,
                       onCompletion: { result in
                
            }, customView:
                        
                        AnyView(
                            HStack{
                                Text("-")
                                    .foregroundStyle(.white)
                            }
                                .frame(width: 40)
                        ) )
            
            
            
        }
        .fillMaxSize()
        
        
    }
}

