//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Sentry

/// Crash reports go to Artise's own Sentry (crashes.artise.co, EU), only after "Help improve Artise" is accepted
/// (Element's consent check). They carry the crash and the device, never message text, names or breadcrumbs.
enum ArtiseCrashReports {
    static func limit(_ options: Options) {
        options.sendDefaultPii = false
        // Breadcrumbs could hold text from the screen; a crash report doesn't need them.
        options.maxBreadcrumbs = 0
        options.enableCaptureFailedRequests = false
        // Crashes only: no performance traces or profiles.
        options.tracesSampleRate = 0
        options.configureProfiling = nil
    }
}
