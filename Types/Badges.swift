//
//  Badges.swift
//  Revolt
//
//  Created by Mehdi on 2/12/25.
//

/// Enum representing various badge types with associated raw integer values.
public  enum Badges: Int, CaseIterable {
    case developer = 1
    case translator = 2
    case supporter = 4
    case responsible_disclosure = 8
    case founder = 16
    case moderation = 32
    case active_supporter = 64
    case paw = 128
    case early_adopter = 256
    case amog = 512
    case amorbus = 1024
    
    static func fromCode(code: Int?) -> Badges? {
        switch code {
        case 1 : return .developer
        case 2 : return .translator
        case 4 : return .supporter
        case 8 : return .responsible_disclosure
        case 16 : return .founder
        case 32 : return .moderation
        case 64 : return .active_supporter
        case 128 : return .paw
        case 256 : return .early_adopter
        case 512 : return .amog
        case 1024 : return .amorbus
        default: return nil
        }
    }
    
    /// Extract all badges from a bitfield value
    static func allBadgesFromCode(code: Int?) -> [Badges] {
        guard let code = code, code > 0 else { return [] }
        
        var badges: [Badges] = []
        for badge in Badges.allCases {
            if (code & badge.rawValue) != 0 {
                badges.append(badge)
            }
        }
        return badges
    }
    
    public func getImage() -> String {
        switch self{
        case .developer: return "developer"
        case .translator: return "translator"
        case .supporter: return "supporter"
        case .responsible_disclosure: return "verified" // fallback to verified badge
        case .founder: return "founder"
        case .moderation: return "moderation"
        case .active_supporter: return "supporter" // fallback to supporter badge
        case .paw: return "paw"
        case .early_adopter: return "early_adopter"
        case .amog: return "amog"
        case .amorbus: return "amorbus"
        }
    }
    
    /// Get the remote URL for the badge
    public func getRemoteURL() -> String {
        switch self{
        case .developer: return "https://peptide.chat/assets/badges/developer.png"
        case .translator: return "https://peptide.chat/assets/badges/first_100_members.svg"
        case .supporter: return "https://peptide.chat/assets/badges/supporter.png"
        case .responsible_disclosure: return "https://peptide.chat/assets/badges/trusted-seller.png"
        case .founder: return "https://peptide.chat/assets/badges/founder.svg"
        case .moderation: return "https://peptide.chat/assets/badges/administrator.png"
        case .active_supporter: return "https://peptide.chat/assets/badges/supporter.png" // same as supporter
        case .paw: return "https://peptide.chat/assets/badges/clown.png"
        case .early_adopter: return "https://peptide.chat/assets/badges/top-contributor.png"
        case .amog: return "https://peptide.chat/assets/badges/karen.png"
        case .amorbus: return "https://peptide.chat/assets/badges/gump.png"
        }
    }
    
}
