//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Fixed facts about the Artise service that every Artise feature shares.
public enum ArtiseConfiguration {
    /// The only server the app signs in to.
    public static let serverName = "artise.co"
    
    public static let websiteURL = URL(staticString: "https://artise.co")
    public static let termsURL = URL(staticString: "https://artise.co/terms.html")
    public static let privacyURL = URL(staticString: "https://artise.co/privacy.html")
    
    /// Artise's own Sygnal push gateway.
    public static let pushGatewayURL = URL(staticString: "https://matrix.artise.co/_matrix/push/v1/notify")
    
    /// The pusher app ID registered in Sygnal for APNs, with `.debug` for development builds.
    public static func pushAppID(isDebugBuild: Bool) -> String {
        isDebugBuild ? "co.artise.app.ios.debug" : "co.artise.app.ios"
    }
}

extension URL {
    /// Builds a URL from a literal that is known to be valid at compile time.
    init(staticString: StaticString) {
        guard let url = URL(string: "\(staticString)") else {
            fatalError("Invalid URL literal: \(staticString)")
        }
        self = url
    }
}
