//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Registers Artise's hooks. The app calls `setUp()` once at launch, before anything reads a hook.
/// The extensions keep the default (no-op) `setUp()`, because this file is only in the app target.
nonisolated extension AppHooks {
    func setUp() {
        registerAppSettingsHook(ArtiseAppSettingsHook())
        registerUserSessionHook(ArtiseUserSessionHook())
    }
}
