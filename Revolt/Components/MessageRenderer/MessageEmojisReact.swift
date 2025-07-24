//
//  MessageEmojisReact.swift
//  Revolt
//
//

import SwiftUI

struct MessageEmojisReact: View {
    let items = [[128077], [129315], [9786,65039], [10084,65039], [128559]]
    var onClick : (String) -> Void
    
    var body: some View {
    
        HStack(spacing: .spacing12){
            
            ForEach(items, id: \.self){ item in
                
                Button {
                    onClick(String(String.UnicodeScalarView(item.compactMap(Unicode.Scalar.init))))
                } label: {
                    Text(String(String.UnicodeScalarView(item.compactMap(Unicode.Scalar.init))))
                        .font(.system(size: 24))
                        .frame(width: .size48, height: .size48)
                        .background{
                            Circle().fill(Color.bgGray11)
                        }
                }
                
               
            }
            
            
            Button {
                onClick("-1")
            } label: {
                
                PeptideIcon(iconName: .peptideSmile, size: .size24, color: .iconDefaultGray01)
                    .frame(width: .size48, height: .size48)
                    .background{
                        Circle().fill(Color.bgGray11)
                    }
                
            }
                
            
        }
        
        
        
    }
}

//:thumbs-up: 128077
//:rofl: 129315
//:warm-smile: [9786,65039]
//:red-heart: [10084,65039]
//:hushed: [128559]



#Preview {
    MessageEmojisReact(onClick: {_ in
        
    })
}


