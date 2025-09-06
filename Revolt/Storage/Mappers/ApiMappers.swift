//
//  ApiMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - CaptchaFeature Mapper

extension CaptchaFeature {
    func toRealm() -> CaptchaFeatureRealm {
        let realm = CaptchaFeatureRealm()
        realm.enabled = self.enabled
        realm.key = self.key
        return realm
    }
}

extension CaptchaFeatureRealm {
    func toOriginal() -> CaptchaFeature {
        return CaptchaFeature(enabled: self.enabled, key: self.key)
    }
}

// MARK: - RevoltFeature Mapper

extension RevoltFeature {
    func toRealm() -> RevoltFeatureRealm {
        let realm = RevoltFeatureRealm()
        realm.enabled = self.enabled
        realm.url = self.url
        return realm
    }
}

extension RevoltFeatureRealm {
    func toOriginal() -> RevoltFeature {
        return RevoltFeature(enabled: self.enabled, url: self.url)
    }
}

// MARK: - VortexFeature Mapper

extension VortexFeature {
    func toRealm() -> VortexFeatureRealm {
        let realm = VortexFeatureRealm()
        realm.enabled = self.enabled
        realm.url = self.url
        realm.ws = self.ws
        return realm
    }
}

extension VortexFeatureRealm {
    func toOriginal() -> VortexFeature {
        return VortexFeature(enabled: self.enabled, url: self.url, ws: self.ws)
    }
}

// MARK: - ApiFeatures Mapper

extension ApiFeatures {
    func toRealm() -> ApiFeaturesRealm {
        let realm = ApiFeaturesRealm()
        realm.captcha = self.captcha.toRealm()
        realm.email = self.email
        realm.invite_only = self.invite_only
        realm.autumn = self.autumn.toRealm()
        realm.january = self.january.toRealm()
        realm.voso = self.voso.toRealm()
        return realm
    }
}

extension ApiFeaturesRealm {
    func toOriginal() -> ApiFeatures {
        return ApiFeatures(
            captcha: self.captcha!.toOriginal(),
            email: self.email,
            invite_only: self.invite_only,
            autumn: self.autumn!.toOriginal(),
            january: self.january!.toOriginal(),
            voso: self.voso!.toOriginal()
        )
    }
}

// MARK: - ApiInfo Mapper

extension ApiInfo {
    func toRealm() -> ApiInfoRealm {
        let realm = ApiInfoRealm()
        realm.revolt = self.revolt
        realm.features = self.features.toRealm()
        realm.ws = self.ws
        realm.app = self.app
        realm.vapid = self.vapid
        return realm
    }
}

extension ApiInfoRealm {
    func toOriginal() -> ApiInfo {
        return ApiInfo(
            revolt: self.revolt,
            features: self.features!.toOriginal(),
            ws: self.ws,
            app: self.app,
            vapid: self.vapid
        )
    }
}

// MARK: - Session Mapper

extension Session {
    func toRealm() -> SessionRealm {
        let realm = SessionRealm()
        realm.id = self.id
        realm.name = self.name
        return realm
    }
}

extension SessionRealm {
    func toOriginal() -> Session {
        return Session(id: self.id, name: self.name)
    }
}
