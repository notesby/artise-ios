//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Foundation

/// Locks the app to artise.co and points every link at Artise instead of Element.
struct ArtiseAppSettingsHook: AppSettingsHookProtocol {
    func configure(_ appSettings: AppSettings) -> AppSettings {
        appSettings.override(accountProviders: [.managed(serverName: ArtiseConfiguration.serverName,
                                                         baseURL: ArtiseConfiguration.homeserverURL)],
                             allowOtherAccountProviders: false,
                             hideBrandChrome: false,
                             pushGatewayBaseURL: ArtiseConfiguration.pushGatewayBaseURL,
                             // artise.co signs in with a password, so the OAuth values are never used.
                             oAuthRedirectURL: appSettings.oAuthRedirectURL,
                             oAuthClientURIPath: appSettings.oAuthClientURIPath,
                             websiteURL: ArtiseConfiguration.websiteURL,
                             logoURL: ArtiseConfiguration.logoURL,
                             copyrightURL: ArtiseConfiguration.sourceCodeURL,
                             acceptableUseURL: ArtiseConfiguration.termsURL,
                             privacyURL: ArtiseConfiguration.privacyURL,
                             encryptionURL: ArtiseConfiguration.Help.encryptionURL,
                             deviceVerificationURL: ArtiseConfiguration.Help.deviceVerificationURL,
                             chatBackupDetailsURL: ArtiseConfiguration.Help.recoveryURL,
                             identityPinningViolationDetailsURL: ArtiseConfiguration.Help.identityChangeURL,
                             historySharingDetailsURL: ArtiseConfiguration.Help.historySharingURL,
                             elementWebHosts: [ArtiseConfiguration.webAppHost],
                             accountProvisioningHost: appSettings.accountProvisioningHost,
                             bugReportApplicationID: "artise-ios",
                             analyticsTermsURL: ArtiseConfiguration.privacyURL,
                             mapTilerConfiguration: AppSettings.bundledMapTilerConfiguration)
        return appSettings
    }
}
