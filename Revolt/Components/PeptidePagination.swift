//
//  PeptidePagination.swift
//  Revolt
//
//

import Foundation


enum PageState: Equatable {
    case loading
    case success
    case error(String)
}

struct PeptidePagination {
    var pageState: PageState = .loading
    var currentPage: Int = 1
    var hasNextPage: Bool = false
    
    var isFirstLoading: Bool {
        currentPage == 1 && pageState == .loading
    }
    
    var isFirstError: Bool {
        guard case .error = pageState, currentPage == 1 else {
            return false
        }
        return true
    }
}

