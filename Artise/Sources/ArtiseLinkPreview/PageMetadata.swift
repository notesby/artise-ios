//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What a page says about itself, from its Open Graph and Twitter tags, else its `<title>` and description; read
/// the same way as on Android.
public struct PageMetadata: Equatable, Sendable {
    static let maxTitle = 200
    static let maxDescription = 300
    
    public let title: String?
    public let description: String?
    public let siteName: String?
    /// An absolute URL.
    public let imageURL: String?
    
    public var isEmpty: Bool {
        title == nil && description == nil && imageURL == nil
    }
    
    public init(title: String?, description: String?, siteName: String?, imageURL: String?) {
        self.title = title
        self.description = description
        self.siteName = siteName
        self.imageURL = imageURL
    }
    
    /// From the page's bytes: its encoding comes from `charset` (the response's), else its own `<meta charset>`.
    public static func parse(_ data: Data, charset: String?, pageURL: URL) -> PageMetadata {
        parse(HTMLText.decode(data, charset: charset), pageURL: pageURL)
    }
    
    public static func parse(_ html: String, pageURL: URL) -> PageMetadata {
        let page = HTMLHead(html)
        let title = page.meta("og:title") ?? page.meta("twitter:title") ?? page.title
        let description = page.meta("og:description") ?? page.meta("twitter:description") ?? page.meta("description")
        let imageURL = ["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"]
            .lazy
            .compactMap { page.meta($0).flatMap { absolute($0, base: pageURL) } }
            .first ?? page.imageSourceLink.flatMap { absolute($0, base: pageURL) }
        return PageMetadata(title: clean(title, max: maxTitle),
                            description: clean(description, max: maxDescription),
                            siteName: clean(page.meta("og:site_name"), max: maxTitle),
                            imageURL: imageURL)
    }
    
    /// One line, without extra spaces, cut at `max` characters.
    static func clean(_ text: String?, max: Int) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return line.count <= max ? line : String(line.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
    
    private static func absolute(_ link: String, base: URL) -> String? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL,
              url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        return url.absoluteString
    }
}

/// The parts of a page's HTML a preview needs, found without a full HTML parser: `<meta>` tags, `<title>` and
/// `<link rel="image_src">`. Attributes may use either quote or none, in any order and case.
struct HTMLHead {
    private var metas: [String: String] = [:]
    private(set) var title: String?
    private(set) var imageSourceLink: String?
    
    init(_ html: String) {
        for tag in html.matches(of: /(?i)<meta\b[^>]*>/) {
            let attributes = Self.attributes(String(tag.output))
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"], metas[key] == nil else {
                continue
            }
            let text = HTMLText.unescape(content)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metas[key] = text
            }
        }
        if let match = html.firstMatch(of: /(?is)<title\b[^>]*>(.*?)<\/title>/) {
            title = HTMLText.unescape(String(match.output.1))
        }
        for tag in html.matches(of: /(?i)<link\b[^>]*>/) {
            let attributes = Self.attributes(String(tag.output))
            if attributes["rel"]?.lowercased() == "image_src", let href = attributes["href"] {
                imageSourceLink = HTMLText.unescape(href)
                break
            }
        }
    }
    
    /// The content of `<meta property=name>` or `<meta name=name>`.
    func meta(_ name: String) -> String? {
        metas[name]
    }
    
    static func attributes(_ tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        for match in tag.matches(of: /([A-Za-z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/) {
            let name = String(match.output.1).lowercased()
            let value = match.output.2 ?? match.output.3 ?? match.output.4 ?? ""
            if attributes[name] == nil {
                attributes[name] = String(value)
            }
        }
        return attributes
    }
}

enum HTMLText {
    private static let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                                                  "ndash": "–", "mdash": "—", "hellip": "…", "rsquo": "’", "lsquo": "‘",
                                                  "rdquo": "”", "ldquo": "“", "copy": "©", "reg": "®"]
    
    /// `&amp;` → `&`, `&#39;` → `'`, `&#x00E9;` → `é`; unknown entities are left as they are.
    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacing(/&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z]+);/) { match in
            let entity = String(match.output.1)
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                return UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            if entity.hasPrefix("#") {
                return UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            return named[entity.lowercased()] ?? String(match.output.0)
        }
    }
    
    /// The page's text in its encoding: the response's charset, else the page's `<meta charset>`, else UTF-8.
    static func decode(_ data: Data, charset: String?) -> String {
        let declared = charset ?? declaredCharset(data)
        if let declared, let encoding = encoding(named: declared), let text = String(data: data, encoding: encoding) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
    
    private static func declaredCharset(_ data: Data) -> String? {
        let start = String(decoding: data.prefix(4096), as: UTF8.self)
        return start.firstMatch(of: /(?i)<meta[^>]+charset\s*=\s*["']?([A-Za-z0-9_-]+)/).map { String($0.output.1) }
    }
    
    private static func encoding(named name: String) -> String.Encoding? {
        switch name.lowercased() {
        case "utf-8", "utf8": .utf8
        case "iso-8859-1", "latin1", "latin-1": .isoLatin1
        case "windows-1252", "cp1252": .windowsCP1252
        case "utf-16", "utf16": .utf16
        case "us-ascii", "ascii": .ascii
        default: nil
        }
    }
}
