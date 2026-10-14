//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Foundation

/// Signs in to any Artise workspace (artise.co by default), points every link at Artise instead of Element, and uses
/// Artise's MapTiler key. "Your workspace" (`ArtiseWorkspaceScreenCoordinator`) replaces Element's server picker.
struct ArtiseAppSettingsHook: AppSettingsHookProtocol {
    func configure(_ appSettings: AppSettings) -> AppSettings {
        appSettings.override(accountProviders: [.managed(serverName: ArtiseConfiguration.serverName,
                                                         baseURL: ArtiseConfiguration.homeserverURL)],
                             allowOtherAccountProviders: true,
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
                             mapTilerConfiguration: MapTilerConfiguration(baseURL: ArtiseConfiguration.Maps.baseURL,
                                                                          apiKey: Secrets.mapLibreAPIKey,
                                                                          lightStyleID: ArtiseConfiguration.Maps.lightStyleID,
                                                                          darkStyleID: ArtiseConfiguration.Maps.darkStyleID))
        return appSettings
    }
}
