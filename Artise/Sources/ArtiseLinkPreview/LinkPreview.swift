//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A shared link's preview, as it travels inside a message (MSC4095, `com.beeper.linkpreviews`): the sender's phone
/// read the page, so the people receiving it never contact the website and the server never sees the link.
public struct LinkPreview: Hashable, Sendable {
    public let url: String
    public let title: String?
    public let description: String?
    public let siteName: String?
    public let image: LinkPreviewImage?
    
    /// What the card shows above the title: the site's name, else its address ("example.com").
    public var siteLabel: String {
        siteName ?? LinkFinder.host(of: url).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? url
    }
}

/// The page's picture, uploaded with the message.
public struct LinkPreviewImage: Hashable, Sendable {
    public let mxcURL: String
    /// The media source JSON (`{"file": …}`) when the picture is encrypted, `nil` when it's plain.
    public let encryptedSourceJSON: String?
    public let width: Int?
    public let height: Int?
}

/// A preview read while typing, before sending: its picture is still only on this phone.
public struct DraftLinkPreview: Equatable, Sendable {
    public let url: String
    public let title: String?
    public let description: String?
    public let siteName: String?
    public let image: DraftLinkPreviewImage?
    
    public init(url: String, title: String?, description: String?, siteName: String?, image: DraftLinkPreviewImage?) {
        self.url = url
        self.title = title
        self.description = description
        self.siteName = siteName
        self.image = image
    }
    
    public var siteLabel: String {
        LinkPreview(url: url, title: title, description: description, siteName: siteName, image: nil).siteLabel
    }
}

/// A JPEG, already made small enough to send.
public struct DraftLinkPreviewImage: Equatable, Sendable {
    public let data: Data
    public let width: Int
    public let height: Int
    
    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

/// The preview's picture once uploaded: plain, or `encryption` for an encrypted chat.
public struct UploadedImage: Sendable {
    public let mxcURL: String
    public let width: Int
    public let height: Int
    public let size: Int
    public let encryption: EncryptedAttachment?
    
    public init(mxcURL: String, width: Int, height: Int, size: Int, encryption: EncryptedAttachment?) {
        self.mxcURL = mxcURL
        self.width = width
        self.height = height
        self.size = size
        self.encryption = encryption
    }
}
