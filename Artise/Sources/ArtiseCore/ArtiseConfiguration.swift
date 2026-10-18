//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Fixed facts about the Artise service that every Artise feature shares.
public enum ArtiseConfiguration {
    /// The only server the app signs in to. Its `.well-known/matrix/client` points at `homeserverURL`.
    public static let serverName = "artise.co"
    public static let homeserverURL = URL(staticString: "https://matrix.artise.co")
    
    public static let websiteURL = URL(staticString: "https://artise.co")
    public static let logoURL = URL(staticString: "https://artise.co/icon.png")
    public static let termsURL = URL(staticString: "https://artise.co/terms.html")
    public static let privacyURL = URL(staticString: "https://artise.co/privacy.html")
    /// The app's source code and licence (AGPL), crediting Element X, which Artise is built on.
    public static let sourceCodeURL = URL(staticString: "https://github.com/notesby/artise-ios")
    
    /// Artise's web app, whose links open in the app.
    public static let webAppHost = "chat.artise.co"
    
    /// "Learn more" pages, shared with the Android app.
    public enum Help {
        public static let encryptionURL = URL(staticString: "https://artise.co/help.html#encryption")
        public static let deviceVerificationURL = URL(staticString: "https://artise.co/help.html#verification")
        public static let recoveryURL = URL(staticString: "https://artise.co/help.html#recovery")
        public static let identityChangeURL = URL(staticString: "https://artise.co/help.html#identity")
        public static let historySharingURL = URL(staticString: "https://artise.co/help.html#history")
    }
    
    /// Artise's own Sygnal push gateway. The app adds `_matrix/push/v1/notify` to this base URL.
    public static let pushGatewayBaseURL = URL(staticString: "https://matrix.artise.co")
    
    /// The pusher app ID registered in Sygnal for APNs, with `.debug` for development builds.
    public static func pushAppID(isDebugBuild: Bool) -> String {
        isDebugBuild ? "co.artise.app.ios.debug" : "co.artise.app.ios"
    }
    
    /// Maps come from MapTiler with its standard styles, as in the Android app. The key is added at build time
    /// (`MAPLIBRE_API_KEY`) and never committed.
    public enum Maps {
        public static let baseURL = URL(staticString: "https://api.maptiler.com/maps")
        public static let lightStyleID = "basic-v2"
        public static let darkStyleID = "basic-v2-dark"
    }
}

public extension URL {
    /// Builds a URL from a literal that is known to be valid at compile time.
    init(staticString: StaticString) {
        guard let url = URL(string: "\(staticString)") else {
            fatalError("Invalid URL literal: \(staticString)")
        }
        self = url
    }
}
