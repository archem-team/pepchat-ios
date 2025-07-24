//
//  PeptideCheckBox.swift
//  Revolt
//
//

import SwiftUI


struct PeptideCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            if configuration.isOn {
                
                PeptideIcon(iconName: .peptideDone,
                            size: .size20,
                            color: .iconInverseGray13)
                .frame(width: .size24, height: .size24)
                .background{
                    RoundedRectangle(cornerRadius: .radius8).fill(Color.bgYellow07)
                }
                
                
            } else {
                
                RoundedRectangle(cornerRadius: .radius8)
                    .strokeBorder(Color.borderDefaultGray09, lineWidth: .size2)
                    .frame(width: .size24, height: .size24)
                
            }
        }
        .buttonStyle(.plain)
    }
}


struct PeptideCircleCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            if configuration.isOn {
                
                
                Circle()
                    .strokeBorder(.bgYellow07, lineWidth: .size6)
                    .frame(width: .size24, height: .size24)
                
                
            } else {
                
                Circle()
                    .strokeBorder(.borderDefaultGray09, lineWidth: .size2)
                    .frame(width: .size24, height: .size24)
                
            }
        }
        .buttonStyle(.plain)
    }
}


struct PeptideSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            
            HStack(spacing: .zero){
                
                if configuration.isOn {
                    
 
                    Spacer(minLength: .zero)
                    
                    PeptideIcon(iconName: .peptideDone,
                                size: .size16,
                                color: .iconInverseGray13)
                    .frame(width: .size24, height: .size24)

                    .background{
                        Circle()
                            .fill(Color.bgGray02)
                    }
                    
                    
                } else {
                    
                    PeptideIcon(iconName: .peptideCloseLiner,
                                size: .size16,
                                color: .iconInverseGray13)
                    .frame(width: .size24, height: .size24)

                    .background{
                        Circle()
                            .fill(Color.bgGray02)
                    }
                    
                    Spacer(minLength: .zero)
                    
                }
                
            }
            .padding(.padding4)
            .frame(width: .size48, height: .size30)
            .background{
                RoundedRectangle(cornerRadius: .radiusLarge)
                    .fill(configuration.isOn ? Color.bgYellow07 : Color.bgGray10)
                    .overlay{
                        RoundedRectangle(cornerRadius: .radiusLarge)
                            .strokeBorder(configuration.isOn ? Color.bgYellow07 : Color.borderDefaultGray09, lineWidth: .size1)
                    }
            }
            
            
            
        }
        .buttonStyle(.plain)
    }
}





#Preview {
    
    VStack(spacing: 32){
        
        
        Toggle("", isOn: .constant(true))
            .toggleStyle(PeptideCheckToggleStyle())
        
        Toggle("", isOn: .constant(false))
            .toggleStyle(PeptideCheckToggleStyle())
        
        Toggle("", isOn: .constant(true))
            .toggleStyle(PeptideCircleCheckToggleStyle())
        
        Toggle("", isOn: .constant(false))
            .toggleStyle(PeptideCircleCheckToggleStyle())
        
        
        Toggle("", isOn: .constant(true))
            .toggleStyle(PeptideSwitchToggleStyle())
        
        Toggle("", isOn: .constant(false))
            .toggleStyle(PeptideSwitchToggleStyle())
        
    }
    .preferredColorScheme(.dark)
    
}
