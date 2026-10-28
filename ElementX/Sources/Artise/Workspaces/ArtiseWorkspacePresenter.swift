//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import SafariServices
import SwiftUI

/// Shows the workspace's messages, join pages and welcome over whatever screen is open.
@MainActor
enum ArtiseWorkspacePresenter {
    /// The open browser's delegate: the browser itself only keeps a weak reference.
    private static var browserDelegate: BrowserDelegate?
    
    /// A short message with an OK button.
    static func alert(_ message: String) {
        guard let presenter = UIViewController.artiseTopViewController() else {
            MXLog.error("No screen to show the workspace message on")
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.actionOk, style: .default))
        presenter.present(alert, animated: true)
    }
    
    /// A page in the app's browser; `onClose` runs when the person closes it.
    static func openInBrowser(_ url: URL, onClose: @escaping @MainActor () -> Void) {
        guard let presenter = UIViewController.artiseTopViewController() else {
            MXLog.error("No screen to open the join page on")
            return
        }
        let browser = SFSafariViewController(url: url)
        let delegate = BrowserDelegate {
            browserDelegate = nil
            onClose()
        }
        browserDelegate = delegate
        browser.delegate = delegate
        MXLog.info("Opening a page in the app's browser over \(type(of: presenter))")
        presenter.present(browser, animated: true)
    }
    
    /// A sheet over the current screen.
    @discardableResult
    static func present<Content: View>(_ content: Content) -> UIViewController? {
        guard let presenter = UIViewController.artiseTopViewController() else { return nil }
        let controller = UIHostingController(rootView: content)
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        controller.sheetPresentationController?.prefersGrabberVisible = true
        presenter.present(controller, animated: true)
        return controller
    }
    
    private final class BrowserDelegate: NSObject, SFSafariViewControllerDelegate {
        let onClose: @MainActor () -> Void
        
        init(onClose: @escaping @MainActor () -> Void) {
            self.onClose = onClose
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            MXLog.info("The app's browser was closed with Done")
            onClose()
        }
        
        // The page itself isn't logged: join pages carry the invite's code.
        func safariViewController(_ controller: SFSafariViewController, initialLoadDidRedirectTo URL: URL) {
            MXLog.info("The app's browser was redirected to \(URL.host() ?? "?")")
        }
        
        func safariViewControllerWillOpenInBrowser(_ controller: SFSafariViewController) {
            MXLog.info("The app's browser is handing the page to Safari")
        }
    }
}
