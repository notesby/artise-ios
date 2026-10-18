//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseLinkPreview
import ImageIO
import MatrixRustSDK
import SwiftUI
import UniformTypeIdentifiers

/// Link previews built on the sender's phone, as in the Android app: while someone types a link, the phone reads the
/// page; the preview then travels inside the message (MSC4095), with its picture encrypted in encrypted chats. The
/// people receiving it never contact the website, and the server never sees the link.
@MainActor
final class ArtiseLinkPreviews {
    static let shared = ArtiseLinkPreviews()
    
    // Enough for any page's <head>; the rest isn't needed.
    private static let maxPageBytes = 1024 * 1024
    private static let maxImageBytes = 8 * 1024 * 1024
    private nonisolated static let maxImageSide = 800
    private nonisolated static let minImageSide = 48
    private nonisolated static let jpegQuality = 0.8
    // A browser's, so pages answer as they would to the person; "Artise" says who's asking.
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 Artise"
    
    private var client: (any ClientProtocol)?
    private var pending: Pending?
    
    // No cookies, no cache: reading a page for a preview leaves nothing behind.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    
    var isAvailable: Bool {
        client != nil
    }
    
    /// Called when an account's session is ready, and with `nil` when it's gone.
    func configure(with userSession: UserSessionProtocol?) {
        client = (userSession?.clientProxy as? ClientProxy)?.client
        pending = nil
    }
    
    // MARK: - Reading pages
    
    /// Reads the page at `url`: its title, description and picture. `nil` when there's nothing to preview.
    func fetch(_ url: String) async -> DraftLinkPreview? {
        guard let pageURL = URL(string: url) else { return nil }
        do {
            let (data, response) = try await get(pageURL, accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5", limit: Self.maxPageBytes)
            guard response.mimeType.map({ $0.contains("html") }) ?? true else { return nil }
            let finalURL = response.url ?? pageURL
            let metadata = PageMetadata.parse(data, charset: response.textEncodingName, pageURL: finalURL)
            guard !metadata.isEmpty else { return nil }
            var image: DraftLinkPreviewImage?
            if let imageURL = metadata.imageURL.flatMap(URL.init(string:)) {
                image = try? await downloadImage(imageURL, referer: finalURL)
            }
            return DraftLinkPreview(url: url, title: metadata.title, description: metadata.description, siteName: metadata.siteName, image: image)
        } catch {
            // The link itself is the person's content: it isn't logged.
            MXLog.info("Link preview not available: \(type(of: error))")
            return nil
        }
    }
    
    private func get(_ url: URL, accept: String, referer: URL? = nil, limit: Int) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(Locale.preferredLanguages.prefix(2).joined(separator: ",") + ",en;q=0.5", forHTTPHeaderField: "Accept-Language")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                break
            }
        }
        return (data, response)
    }
    
    /// The page's picture, at most 800 px, as a JPEG.
    private func downloadImage(_ url: URL, referer: URL) async throws -> DraftLinkPreviewImage? {
        let (data, _) = try await get(url, accept: "image/*", referer: referer, limit: Self.maxImageBytes)
        return await Task.detached { Self.jpeg(from: data) }.value
    }
    
    private nonisolated static func jpeg(from data: Data) -> DraftLinkPreviewImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width >= minImageSide, height >= minImageSide else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxImageSide]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return DraftLinkPreviewImage(data: jpeg as Data, width: image.width, height: image.height)
    }
    
    // MARK: - Sending
    
    /// The preview shown in a chat's composer, waiting for the message it goes with.
    private struct Pending {
        let timeline: ObjectIdentifier
        let preview: DraftLinkPreview
        let isEncrypted: () -> Bool
    }
    
    /// The composer of the chat whose live timeline is `timeline` shows `preview` (or none any more).
    func setPending(_ preview: DraftLinkPreview?, timeline: AnyObject, isEncrypted: @escaping () -> Bool) {
        pending = preview.map { Pending(timeline: ObjectIdentifier(timeline), preview: $0, isEncrypted: isEncrypted) }
    }
    
    /// The JSON to add to `message`'s content when it's sent on `timeline` with the link its composer previewed;
    /// `nil` for any other message. The picture is uploaded first, encrypted in encrypted chats; if that fails,
    /// the preview goes without it.
    func takeExtraContent(message: String, timeline: AnyObject) async -> String? {
        guard let pending, pending.timeline == ObjectIdentifier(timeline),
              LinkFinder.firstLink(message) == pending.preview.url else {
            return nil
        }
        self.pending = nil
        var uploaded: UploadedImage?
        if let image = pending.preview.image, let client {
            do {
                uploaded = try await upload(image, encrypted: pending.isEncrypted(), client: client)
            } catch {
                MXLog.error("Link preview picture not uploaded; sending the preview without it: \(error)")
            }
        }
        return LinkPreviewContent.build(pending.preview, image: uploaded)
    }
    
    private func upload(_ image: DraftLinkPreviewImage, encrypted: Bool, client: any ClientProtocol) async throws -> UploadedImage {
        if encrypted {
            let encryption = try AttachmentEncryption.encrypt(image.data)
            let url = try await client.uploadMedia(mimeType: "application/octet-stream", data: encryption.data, progressWatcher: nil)
            return UploadedImage(mxcURL: url, width: image.width, height: image.height, size: image.data.count, encryption: encryption)
        }
        let url = try await client.uploadMedia(mimeType: "image/jpeg", data: image.data, progressWatcher: nil)
        return UploadedImage(mxcURL: url, width: image.width, height: image.height, size: image.data.count, encryption: nil)
    }
}

/// A preview received inside a message, kept with the timeline item.
nonisolated struct ArtiseMessageLinkPreview: Hashable {
    let preview: LinkPreview
    
    /// The preview inside a text message's event; the event's JSON is only read when the text has a link.
    static func read(body: String, eventJSON: () -> String?) -> ArtiseMessageLinkPreview? {
        guard body.localizedCaseInsensitiveContains("http") || body.localizedCaseInsensitiveContains("www."),
              let json = eventJSON(),
              let preview = LinkPreviewContent.read(json) else {
            return nil
        }
        return ArtiseMessageLinkPreview(preview: preview)
    }
    
    /// Where the card's picture comes from: the plain mxc URL, or the encrypted file.
    var imageSource: MediaSourceProxy? {
        guard let image = preview.image else { return nil }
        if let json = image.encryptedSourceJSON {
            return (try? MediaSource.fromJson(json: json)).map { MediaSourceProxy(source: $0, mimeType: "image/jpeg") }
        }
        return URL(string: image.mxcURL).flatMap { try? MediaSourceProxy(url: $0, mimeType: "image/jpeg") }
    }
}
