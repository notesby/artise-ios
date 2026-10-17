//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI

/// Keeps the keyboard in the app's appearance. Element applies a forced light or dark appearance (Settings → Advanced)
/// to its own windows only; after the app comes back from the background, iOS redraws the keyboard's window in the
/// phone's appearance, so the keys and the system's strips above and below them can show light and dark at once.
/// When the app becomes active, every window of the scene gets the main window's appearance and the keyboard redraws.
@MainActor
enum ArtiseKeyboardAppearance {
    private static var observer: NSObjectProtocol?
    
    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in apply() }
        }
    }
    
    static func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            guard let main = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { continue }
            let style = main.overrideUserInterfaceStyle
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
        // The keyboard that's open redraws in that appearance.
        UIResponder.artiseCurrentFirstResponder()?.reloadInputViews()
    }
}

private extension UIResponder {
    private weak static var found: UIResponder?
    
    /// The text field or view that has the keyboard, if any.
    static func artiseCurrentFirstResponder() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(artiseRememberFirstResponder), to: nil, from: nil, for: nil)
        return found
    }
    
    @objc func artiseRememberFirstResponder() {
        UIResponder.found = self
    }
}
