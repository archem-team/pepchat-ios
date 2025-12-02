//
//  PlatformConfigService.swift
//  Revolt
//
//

import Foundation

@MainActor
class PlatformConfigService: ObservableObject {
    @Published var platforms: [PlatformConfig] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    private let configURL = "https://appconfig.zeko.chat/data.json"
    
    func fetchPlatforms() async {
        isLoading = true
        error = nil
        
        do {
            guard let url = URL(string: configURL) else {
                throw URLError(.badURL)
            }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            let decodedPlatforms = try JSONDecoder().decode([PlatformConfig].self, from: data)
            
            platforms = decodedPlatforms
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            
            // Fallback to default platforms if API fails
            platforms = getDefaultPlatforms()
        }
    }
    
    private func getDefaultPlatforms() -> [PlatformConfig] {
        return [
            PlatformConfig(title: "Pepchat", image: "", url: "https://peptide.chat/api"),
            PlatformConfig(title: "Revolt", image: "", url: "https://app.revolt.chat/api")
        ]
    }
}
