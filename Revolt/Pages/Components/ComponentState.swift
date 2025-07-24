//
//  ComponentState.swift
//  Revolt
//
//

import Foundation


enum ComponentState {
    case `default`
    case loading
    case disabled
    
    var isDisabled: Bool {
        switch self {
        case .disabled, .loading:
            return true
        case .default:
            return false
        }
    }
    
    var bgColorOpacity: CGFloat {
        switch self {
        case .disabled:
            return 0.48
        case .loading:
            return 0.8
        case .default:
            return 1.0
        }
    }
    
}
