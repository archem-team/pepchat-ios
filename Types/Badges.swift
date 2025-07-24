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
    
    public func getImage() -> String {
        switch self{
        case .developer: return "developer.png"
        case .translator: return "translator.png"
        case .supporter: return "supporter.png"
        case .responsible_disclosure: return "responsible_disclosure.png"
        case .founder: return "founder.png"
        case .moderation: return "moderation.png"
        case .active_supporter: return "active_supporter.png"
        case .paw: return "paw.png"
        case .early_adopter: return "early_adopter.png"
        case .amog: return "amog.png"
        case .amorbus: return "amorbus.png"
        }
    }
    
}
