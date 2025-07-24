//
//  BaseViewModel.swift
//  Revolt
//
//

import Foundation

protocol UiAction {}

protocol UiEvent{
    associatedtype ACTION : UiAction
    func send(action: ACTION)
}

class BaseViewModel<State, Action: UiAction> : ObservableObject, UiEvent {
    
    
    typealias ACTION = Action
    
    @Published
    var state: State
    @Published
    var isNavigationTriggered : Bool = false
    
    init(initialState: State) {
        self.state = initialState
    }
    
    func send(action: Action) {
        fatalError("send(action:) should be overridden in subclasses")
    }
    
    
    func onNavigation( _ to : () -> Void) {
        to()
        isNavigationTriggered.toggle()
    }
    
}
