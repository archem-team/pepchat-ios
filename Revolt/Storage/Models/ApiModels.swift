//
//  ApiModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - CaptchaFeature Realm Object

class CaptchaFeatureRealm: Object {
    @Persisted var enabled: Bool = false
    @Persisted var key: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - RevoltFeature Realm Object

class RevoltFeatureRealm: Object {
    @Persisted var enabled: Bool = false
    @Persisted var url: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - VortexFeature Realm Object

class VortexFeatureRealm: Object {
    @Persisted var enabled: Bool = false
    @Persisted var url: String = ""
    @Persisted var ws: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - ApiFeatures Realm Object

class ApiFeaturesRealm: Object {
    @Persisted var captcha: CaptchaFeatureRealm?
    @Persisted var email: Bool = false
    @Persisted var invite_only: Bool = false
    @Persisted var autumn: RevoltFeatureRealm?
    @Persisted var january: RevoltFeatureRealm?
    @Persisted var voso: VortexFeatureRealm?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - ApiInfo Realm Object

class ApiInfoRealm: Object {
    @Persisted var revolt: String = ""
    @Persisted var features: ApiFeaturesRealm?
    @Persisted var ws: String = ""
    @Persisted var app: String = ""
    @Persisted var vapid: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Session Realm Object

class SessionRealm: Object {
    @Persisted var id: String = ""
    @Persisted var name: String = ""
    
    override static func primaryKey() -> String? {
        return "id"
    }
}
