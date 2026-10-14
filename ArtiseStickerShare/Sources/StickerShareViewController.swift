//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import UniformTypeIdentifiers

/// "Artise sticker" in other apps' share menus, as on Android: the shared picture is handed to Artise, which shows it
/// and saves it to the signed-in account's stickers.
///
/// The extension only copies the picture into the app group and opens Artise with
/// `<bundle ID>:/artise-sticker?file=<name>`; the account's session stays in the app.
final class StickerShareViewController: UIViewController {
    /// Matches `ArtiseStickers.shareURLPath` and `ArtiseStickers.shareFolder` in the app.
    private static let urlPath = "artise-sticker"
    private static let folder = "ArtiseStickers"
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            if let url = await handOver() {
                openApp(url)
            }
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    /// Copies the first shared picture into the app group, and returns the URL that opens it in Artise.
    private func handOver() async -> URL? {
        guard let provider = (extensionContext?.inputItems.first as? NSExtensionItem)?.attachments?
            .first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
            let appGroup = Bundle.main.object(forInfoDictionaryKey: "appGroupIdentifier") as? String,
            let baseBundleIdentifier = Bundle.main.object(forInfoDictionaryKey: "baseBundleIdentifier") as? String,
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        let type = provider.registeredContentTypes.first { $0.conforms(to: .image) } ?? .image
        guard let data = await withCheckedContinuation({ (continuation: CheckedContinuation<Data?, Never>) in
            // No async variant: this call returns a Progress.
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in continuation.resume(returning: data) }
        }) else {
            return nil
        }
        let name = UUID().uuidString + "." + (type.preferredFilenameExtension ?? "img")
        let folder = container.appending(path: Self.folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appending(path: name))
        } catch {
            return nil
        }
        var components = URLComponents()
        components.scheme = baseBundleIdentifier
        components.path = "/" + Self.urlPath
        components.queryItems = [URLQueryItem(name: "file", value: name)]
        return components.url
    }
    
    /// Extensions can't open URLs themselves; the app behind the share sheet can (as Element's share extension does).
    private func openApp(_ url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url)
                return
            }
            responder = current.next
        }
    }
}
