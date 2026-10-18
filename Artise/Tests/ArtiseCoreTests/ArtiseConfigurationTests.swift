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
        for url in [ArtiseConfiguration.websiteURL, ArtiseConfiguration.termsURL, ArtiseConfiguration.privacyURL] {
            #expect(url.scheme == "https")
            #expect(url.host() == "artise.co")
        }
    }
    
    /// Push notifications must reach Artise's own gateway, never a third-party one.
    @Test
    func pushGatewayIsArtiseSygnal() {
        #expect(ArtiseConfiguration.pushGatewayURL.host() == "matrix.artise.co")
        #expect(ArtiseConfiguration.pushGatewayURL.path() == "/_matrix/push/v1/notify")
    }
}
