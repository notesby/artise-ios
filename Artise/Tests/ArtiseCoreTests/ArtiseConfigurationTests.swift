//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Testing

struct ArtiseConfigurationTests {
    /// Sygnal routes pushes by app ID, so release and debug builds must use the IDs registered on the server.
    @Test
    func pushAppIDMatchesSygnal() {
        #expect(ArtiseConfiguration.pushAppID(isDebugBuild: false) == "co.artise.app.ios")
        #expect(ArtiseConfiguration.pushAppID(isDebugBuild: true) == "co.artise.app.ios.debug")
    }
    
    /// The links shown in the app must point at Artise's public pages over HTTPS.
    @Test
    func publicLinksUseArtiseOverHTTPS() {
        let links = [ArtiseConfiguration.websiteURL, ArtiseConfiguration.logoURL,
                     ArtiseConfiguration.termsURL, ArtiseConfiguration.privacyURL,
                     ArtiseConfiguration.Help.encryptionURL, ArtiseConfiguration.Help.deviceVerificationURL,
                     ArtiseConfiguration.Help.recoveryURL, ArtiseConfiguration.Help.identityChangeURL,
                     ArtiseConfiguration.Help.historySharingURL]
        for url in links {
            #expect(url.scheme == "https")
            #expect(url.host() == "artise.co")
        }
    }
    
    /// The source link must point at this app's public repository, as the AGPL requires.
    @Test
    func sourceCodeLinkIsThePublicRepository() {
        #expect(ArtiseConfiguration.sourceCodeURL.absoluteString == "https://github.com/notesby/artise-ios")
    }
    
    /// Sign-in and push notifications must reach Artise's own server, never a third-party one.
    @Test
    func homeserverAndPushGatewayAreArtise() {
        #expect(ArtiseConfiguration.homeserverURL.host() == "matrix.artise.co")
        #expect(ArtiseConfiguration.pushGatewayBaseURL.host() == "matrix.artise.co")
        #expect(ArtiseConfiguration.pushGatewayBaseURL.appending(path: "_matrix/push/v1/notify").absoluteString
            == "https://matrix.artise.co/_matrix/push/v1/notify")
    }
}
