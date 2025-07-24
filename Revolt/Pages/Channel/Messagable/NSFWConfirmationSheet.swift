import SwiftUI

struct NSFWConfirmationSheet: View {
    @Binding var isPresented: Bool
    let channelName: String
    @State private var isChecked: Bool = false
    @State private var sheetHeight: CGFloat = .zero
    let onResult: (Bool) -> Void
    
    var body: some View {
        
        
        ZStack(alignment: .topTrailing){
            
            VStack(spacing: .zero) {
                
                Group{
                    
                    Image(.peptideOver18)
                        .resizable()
                        .frame(width: .size100, height: .size100)
                        .padding(.top, .size8)
                        .padding(.bottom, .size32)
                    
                    PeptideText(
                        text: "Mature Content Ahead",
                        font: .peptideTitle3
                    )
                    .padding(.bottom, .size4)
                    
                    PeptideText(
                        text: "This area may include adult themes. Please confirm you're 18 or older.",
                        font: .peptideBody3,
                        textColor: .textGray07
                    )
                    .padding(.bottom, .size32)
                    
                    Button {
                        isChecked.toggle()
                    } label: {
                        
                        Toggle("", isOn: $isChecked)
                            .toggleStyle(PeptideCheckToggleStyle())
                        
                        PeptideText(
                            text: "I confirm I’m at least 18 years of age.",
                            font: .peptideCallout
                        )
                        
                    }
                    .padding(.horizontal, .size12)
                    .padding(.bottom, .size32)
                    
                }
                .padding(.horizontal, .size24)
                
                PeptideDivider()
                    .padding(.bottom, .size24)
                
                HStack(spacing: .spacing12){
                    
                    PeptideButton(
                        title: "Enter Group",
                        bgColor: .bgYellow07,
                        contentColor: .textInversePurple13,
                        buttonState: isChecked ? .default : .disabled,
                        isFullWidth: true
                    ){
                        onResult(true)
                        self.isPresented.toggle()
                        
                    }
                    
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, .size24)
                .padding(.horizontal, .size24)
                
            }
            
            PeptideIconButton(icon: .peptideCloseLiner){
                
                self.isPresented.toggle()
                onResult(false)
                
            }
            .padding(.all, .size16)
            
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgGray11, in: RoundedRectangle(cornerRadius: .size16))
        .padding(.all, .size16)
        
        
        
        
    }
} 



#Preview {
    @Previewable @StateObject var viewState = ViewState.preview().applySystemScheme(theme: .dark)
    
    
    VStack{
        
        PeptideText(text: "asd ksj ldfj lsdkjf ldkfj ldfjlfgjlfkg jlfkjg lfkgj lfkgj lffk jl j")
        PeptideText(text: "asd ksj ldfj lsdkjf ldkfj ldfjlfgjlfkg jlfkjg lfkgj lfkgj lffk jl j")
        Spacer()
        
    }
    .popup(isPresented: .constant(true), view: {
        NSFWConfirmationSheet(
            isPresented: .constant(true),
            channelName: "AAAAAAA"
        ){ confirmed in
            
            
            
        }
    }, customize: {
        $0.type(.default)
          .isOpaque(true)
          .appearFrom(.bottomSlide)
          .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
          .closeOnTap(false)
          .closeOnTapOutside(false)
    })
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
    
    
    
}
