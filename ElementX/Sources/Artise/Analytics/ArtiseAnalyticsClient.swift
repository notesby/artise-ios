//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import AnalyticsEvents
import ArtiseNotes
import FirebaseAnalytics
import FirebaseCore
import Foundation

/// Usage statistics for people who said yes on "Help improve Artise", sent to Google Analytics for Firebase,
/// as in the Android app. Element's consent screen and settings decide when it runs.
///
/// Nothing is collected before a yes (collection is off in Info.plist), there's no advertising ID (the identity
/// support library isn't linked), ad storage and personalization are always denied, and only what was done is sent:
/// screens and taps, never content, names or a user ID.
final class ArtiseAnalyticsClient: AnalyticsClientProtocol {
    static let shared = ArtiseAnalyticsClient()
    
    /// Whether this build has Artise's Firebase file; without it, analytics are off and consent isn't asked.
    nonisolated static var isConfigured: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }
    
    private(set) var isRunning = false
    
    func start(analyticsConfiguration: AnalyticsConfiguration) {
        guard Self.isConfigured, !isRunning else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Analytics.setConsent([.analyticsStorage: .granted,
                              .adStorage: .denied,
                              .adUserData: .denied,
                              .adPersonalization: .denied])
        Analytics.setAnalyticsCollectionEnabled(true)
        isRunning = true
    }
    
    func reset() {
        guard FirebaseApp.app() != nil else { return }
        Analytics.resetAnalyticsData()
    }
    
    /// Withdrawing consent stops collection and resets what was collected on the phone.
    func stop() {
        guard FirebaseApp.app() != nil else { return }
        Analytics.setAnalyticsCollectionEnabled(false)
        Analytics.resetAnalyticsData()
        isRunning = false
    }
    
    func capture(_ event: AnalyticsEventProtocol) {
        guard isRunning else { return }
        Analytics.logEvent(Self.eventName(event.eventName), parameters: Self.parameters(event.properties))
    }
    
    func screen(_ event: AnalyticsScreenProtocol) {
        guard isRunning else { return }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [AnalyticsParameterScreenName: event.screenName.rawValue])
    }
    
    /// Element's user properties describe the account (how many rooms, which features); they aren't sent.
    func updateUserProperties(_ event: AnalyticsEvent.UserProperties) { }
    
    // MARK: - Notes
    
    func track(_ event: NotesAnalyticsEvent) {
        guard isRunning else { return }
        Analytics.logEvent(Self.eventName(event.name), parameters: event.properties.isEmpty ? nil : event.properties)
    }
    
    func screen(_ screen: NotesAnalyticsScreen) {
        guard isRunning else { return }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [AnalyticsParameterScreenName: screen.rawValue])
    }
    
    // MARK: - Firebase's rules
    
    /// Firebase takes letters, digits and underscores, starting with a letter, up to 40 characters.
    nonisolated static func eventName(_ name: String) -> String {
        let cleaned = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" }.prefix(40))
        return cleaned.first?.isLetter == true ? cleaned : "e_" + cleaned.prefix(38)
    }
    
    /// Only plain values, with Firebase's limits on names and lengths.
    nonisolated static func parameters(_ properties: [String: Any]) -> [String: Any]? {
        var parameters: [String: Any] = [:]
        for (key, value) in properties.prefix(25) {
            let name = eventName(key)
            switch value {
            case let text as String: parameters[name] = String(text.prefix(100))
            case let number as Int: parameters[name] = number
            case let number as Double: parameters[name] = number
            case let flag as Bool: parameters[name] = flag ? 1 : 0
            default: continue
            }
        }
        return parameters.isEmpty ? nil : parameters
    }
}
