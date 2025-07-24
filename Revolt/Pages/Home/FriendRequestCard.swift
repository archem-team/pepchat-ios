import SwiftUI
import Types

struct FriendRequestCard: View {
    @EnvironmentObject var viewState: ViewState
    @State var isPresentedSheet: Bool = false
    let users: [User]
    
    var body: some View {
        
        Button {
            
            isPresentedSheet.toggle()
            
        } label: {
            VStack(spacing: .zero){
                
                PeptideDivider(backgrounColor: .bgGray11)
                
                HStack (spacing: .zero){
                    
                    if let firstUser = users.first{
                        
                        Avatar(user: firstUser, width: .size40, height: .size40)
                        
                        if users.count >= 2 {
                            
                            Avatar(user: users[1], width: .size40, height: .size40)
                                .offset(x: -20 )
                            
                        }
                        
                        HStack(spacing: .zero){
                            
                            PeptideIcon(iconName: .peptideHandWave, size: .size20)
                            
                            if users.count > 3{
                                
                                PeptideText(
                                    text: "+\(users.count - 2)",
                                    font: .peptideHeadline
                                )
                                
                            }
                            
                        }
                        .padding(.all, 6)
                        .background{
                            RoundedRectangle(cornerRadius: .size32)
                                .fill(Color.bgPurple07)
                                .overlay(
                                    RoundedRectangle(cornerRadius: .size32)
                                        .stroke(Color.borderGray12, lineWidth: 3)
                                )
                        }
                        .offset(x: users.count == 1 ? -20 : -40)
                        
                    }
                    
                    VStack(alignment: .leading ,spacing: .zero) {
                        
                        PeptideText(
                            text: "Incoming Friend Request",
                            font: .peptideHeadline
                        )
                        
                        let subtitle = users.count == 1 ?  "From \(users.first?.username ?? "")" : users.count == 2 ? "From \(users.first?.username ?? "") and \(users[1].username)" : "From \(users.first?.username ?? ""), \(users[1].username) and \(users.count - 2) more"
                        
                        PeptideText(
                            text: subtitle,
                            font: .peptideBody4
                        )
                        
                    }
                    .padding(.horizontal, .size8)
                    .offset(x: users.count == 1 ? -20 : -40)
                    
                    Spacer(minLength: .zero)
                    
                    PeptideIcon(iconName: .peptideArrowRight)
                    
                }
                .padding(.horizontal, .size16)
                .padding(.vertical, .size12)
                .background(Color.bgGray12)
                
                PeptideDivider(backgrounColor: .bgGray11)
            }
        }
        .sheet(isPresented: $isPresentedSheet){
            IncomingFriendRequestsSheet(isPresented: $isPresentedSheet)
        }
        
    }
}


#Preview {
    
    @Previewable @StateObject var viewState : ViewState = .preview()
    
    let users = [viewState.users["0"]!, viewState.users["0"]!, viewState.users["0"]!, viewState.users["0"]!]
    
    VStack{
        
        
    }
    .background(Color.black)
    .frame(width: .infinity, height: .infinity)
    .applyPreviewModifiers(withState:viewState)
    .preferredColorScheme(.dark)
    
}
