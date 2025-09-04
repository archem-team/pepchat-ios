//
//  IntroPlatformView.swift
//  Revolt
//
//

import SwiftUI

struct IntroPlatformView: View {
    
    var platformName : String
    var platformImage : ImageResource?
    var imageURL: String?
    var url : String
    var onClick : (String) -> Void
    
    init(platformName: String, platformImage: ImageResource, url: String, onClick: @escaping (String) -> Void) {
        self.platformName = platformName
        self.platformImage = platformImage
        self.imageURL = nil
        self.url = url
        self.onClick = onClick
    }
    
    init(platformName: String, imageURL: String, url: String, onClick: @escaping (String) -> Void) {
        self.platformName = platformName
        self.platformImage = nil
        self.imageURL = imageURL
        self.url = url
        self.onClick = onClick
    }
    
    var body: some View {
        
        Button(action: {
            withAnimation{
                onClick(url)
            }
        }) {
            
            VStack(alignment: .center, spacing: .spacing8){
                
                Group {
                    if let platformImage = platformImage {
                        Image(platformImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if let imageURL = imageURL {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                                .frame(width: 40, height: 40)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: .radius8)
                            .fill(.bgPurple10)
                            .overlay(
                                Text(String(platformName.prefix(1)))
                                    .font(.title)
                                    .foregroundColor(.primary)
                            )
                    }
                }
                .frame(width: .size72, height: .size72)
                .background{
                    RoundedRectangle(cornerRadius: .radius8)
                        .fill(.bgPurple10)
                }
                
                PeptideText(text: platformName,
                            font: .peptideBody,
                            textColor: .textGray06,
                            alignment: .center)
                .lineLimit(1)
                
            }
        }
    }
}

#Preview {
    
    VStack(spacing: .spacing24) {
        // Local image example
        HStack(spacing: .spacing24){
            IntroPlatformView(platformName: "PepChat",
                              platformImage: .peptidePlatformLogo,
                              url: "https://peptide.chat/api"){_ in
                
            }
            
            IntroPlatformView(platformName: "Revolt",
                              platformImage: .peptideRevolt,
                              url: "https://app.revolt.chat/api"){_ in
                
            }
        }
        
        // Remote image example
        HStack(spacing: .spacing24){
            IntroPlatformView(platformName: "PepChat",
                              imageURL: "https://appconfig.zeko.chat/images/pepchat.png",
                              url: "https://peptide.chat/api"){_ in
                
            }
            
            IntroPlatformView(platformName: "Revolt",
                              imageURL: "https://appconfig.zeko.chat/images/revolt.png",
                              url: "https://app.revolt.chat/api"){_ in
                
            }
        }
    }
    
    
}
