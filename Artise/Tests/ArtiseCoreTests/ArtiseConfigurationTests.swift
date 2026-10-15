//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Testing

struct ArtiseConfigurationTests {
    /// Maps use MapTiler's standard styles, as in the Android app, over HTTPS.
    @Test
    func mapsUseMapTilersStandardStyles() {
        #expect(ArtiseConfiguration.Maps.lightStyleID == "basic-v2")
        #expect(ArtiseConfiguration.Maps.darkStyleID == "basic-v2-dark")
        #expect(ArtiseConfiguration.Maps.baseURL.absoluteString == "https://api.maptiler.com/maps")
    }
    
    /// Sygnal routes pushes by app ID, so release and debug builds must use the IDs registered on the server.
    @Test
    func pushAppIDMatchesSygnal() {
        #expect(ArtiseConfiguration.pushAppID(isDebugBuild: false) == "co.artise.app.ios")
        #expect(ArtiseConfiguration.pushAppID(isDebugBuild: true) == "co.artise.app.ios.debug")
    }
    
    /// A workspace's sign-in page (MAS) returns to the app's own scheme, which MAS accepts: a native app's custom
    /// scheme must begin with the client URI's host reversed. The client URI is websiteURL + "apps/ios" (artise.co),
    /// so the scheme must start "co.artise".
    @Test
    func signInReturnsToTheAppWithASchemeTheSignInServiceAccepts() {
        let scheme = ArtiseConfiguration.oAuthRedirectURL.scheme ?? ""
        let reversedHost = (ArtiseConfiguration.websiteURL.host() ?? "").split(separator: ".").reversed()
        #expect(Array(scheme.split(separator: ".").prefix(reversedHost.count)) == Array(reversedHost))
        #expect(scheme == "co.artise.app") // the app's registered URL scheme (BASE_BUNDLE_IDENTIFIER)
        #expect(ArtiseConfiguration.oAuthRedirectURL.path() == "/oauth")
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
    
    /// The default workspace and push notifications reach Artise's own servers, never a third-party one.
    @Test
    func homeserverAndPushGatewayAreArtise() {
        #expect(ArtiseConfiguration.homeserverURL.host() == "matrix.artise.co")
        #expect(ArtiseConfiguration.pushGatewayBaseURL.appending(path: "_matrix/push/v1/notify").absoluteString
            == "https://push.artise.co/_matrix/push/v1/notify")
    }
}
