//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Where a tap on a link in a note goes.
public enum NoteLink: Equatable, Sendable {
    /// Another note or a file in the chat, named as written in `[[…]]`: "Súper", "Recetas/Mole", "foto.jpg".
    case note(target: String)
    /// A web address.
    case web(String)
}

/// The parts of an Obsidian link: `[[target#heading|shown text]]`.
public struct WikiLink: Equatable, Sendable {
    public let target: String
    public let heading: String?
    public let shownText: String?
    
    /// What the reader sees: the shown text, else the note's name without its folder.
    public var label: String {
        if let shownText {
            return shownText
        }
        let name = target.split(separator: "/").last.map(String.init) ?? target
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
    
    /// Parses the text between `[[` and `]]`.
    public static func parse(_ inner: String) -> WikiLink {
        let aliasParts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let headingParts = aliasParts[0].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        func clean(_ part: Substring?) -> String? {
            guard let part else { return nil }
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return WikiLink(target: headingParts[0].trimmingCharacters(in: .whitespaces),
                        heading: clean(headingParts.count > 1 ? headingParts[1] : nil),
                        shownText: clean(aliasParts.count > 1 ? aliasParts[1] : nil))
    }
}

/// Finds the file a `[[link]]` points to, the way Obsidian and the Notes API do: an exact path first
/// (with or without `.md`), else a note with that name in any folder, the shortest path winning.
/// Case and accents are ignored, since people type "super" for "Súper".
public enum NoteLinkResolver {
    public static func resolve(_ target: String, in paths: [String]) -> String? {
        var wanted = target.trimmingCharacters(in: .whitespaces)
        if wanted.hasPrefix("/") {
            wanted.removeFirst()
        }
        guard !wanted.isEmpty else { return nil }
        // "luna.jpg" names a file; "Sr. Pérez" is still a note, so only a short trailing extension counts.
        let candidates = hasExtension(wanted) ? [wanted] : [wanted + ".md", wanted]
        let byKey = Dictionary(grouping: paths, by: matchKey)
        for candidate in candidates {
            if let match = byKey[matchKey(candidate)]?.min(by: { $0.count < $1.count }) {
                return match
            }
        }
        // `[[Mole]]` finds `Recetas/Mole.md`: match on the file name alone.
        let nameKeys = Set(candidates.map { matchKey(fileName($0)) })
        return paths
            .filter { nameKeys.contains(matchKey(fileName($0))) }
            .min { lhs, rhs in
                let (lhsDepth, rhsDepth) = (lhs.filter { $0 == "/" }.count, rhs.filter { $0 == "/" }.count)
                return lhsDepth == rhsDepth ? lhs.count < rhs.count : lhsDepth < rhsDepth
            }
    }
    
    static func hasExtension(_ name: String) -> Bool {
        name.range(of: #"\.[A-Za-z0-9]{1,5}$"#, options: .regularExpression) != nil
    }
    
    static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
    
    static func matchKey(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }
}

/// Turns `[[Note]]` and `![[photo.jpg]]` into ordinary Markdown links with the `artise-note:` scheme,
/// so a standard Markdown parser can read notes. Code blocks and `inline code` are left untouched,
/// and lines stay as they are, so line numbers still match the note.
public enum WikiLinkRewriter {
    public static let scheme = "artise-note:"
    
    private static let wikiLink = try? NSRegularExpression(pattern: #"!?\[\[([^\[\]\n]+)\]\]"#)
    private static let fence = try? NSRegularExpression(pattern: #"^\s{0,3}(```|~~~)"#)
    
    public static func rewrite(_ markdown: String) -> String {
        var inFence = false
        return markdown.components(separatedBy: "\n").map { line in
            if matches(fence, line) {
                inFence.toggle()
                return line
            }
            return inFence ? line : rewriteOutsideInlineCode(line)
        }
        .joined(separator: "\n")
    }
    
    /// The link destination for a target, decoded again with `target(of:)`.
    public static func destination(_ target: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let ascii = CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127))
        return scheme + (target.addingPercentEncoding(withAllowedCharacters: allowed.intersection(ascii)) ?? target)
    }
    
    /// The note target of a destination made by `destination(_:)`, or `nil` for any other link.
    public static func target(of destination: String) -> String? {
        guard destination.hasPrefix(scheme) else { return nil }
        return String(destination.dropFirst(scheme.count)).removingPercentEncoding
    }
    
    // Backticks split a line into text (even parts) and code spans (odd parts); only text is rewritten.
    private static func rewriteOutsideInlineCode(_ line: String) -> String {
        line.components(separatedBy: "`").enumerated().map { index, part in
            index % 2 == 1 ? part : rewriteLinks(part)
        }
        .joined(separator: "`")
    }
    
    private static func rewriteLinks(_ text: String) -> String {
        guard let wikiLink else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var result = ""
        var last = text.startIndex
        for match in wikiLink.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            // "![[photo.jpg]]" embeds: it becomes an image, so the note shows the photo itself.
            let embed = text[whole].hasPrefix("!") ? "!" : ""
            let link = WikiLink.parse(String(text[inner]))
            let label = link.label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            result += "\(embed)[\(label)](<\(destination(link.target))>)"
            last = whole.upperBound
        }
        result += text[last...]
        return result
    }
    
    private static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// Ticks and unticks checklist items in a note's Markdown: `- [ ] pan` ⇄ `- [x] pan`.
public enum ChecklistToggle {
    private static let task = try? NSRegularExpression(pattern: #"^(\s*(?:[-*+]|\d+[.)]) \[)([ xX])(\])"#)
    
    /// The Markdown with the checklist item on `lineIndex` (from 0) flipped, or `nil` if that line isn't one.
    public static func toggle(_ markdown: String, lineIndex: Int) -> String? {
        var lines = markdown.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex), let task else { return nil }
        let line = lines[lineIndex]
        guard let match = task.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let markRange = Range(match.range(at: 2), in: line) else { return nil }
        let mark = line[markRange].trimmingCharacters(in: .whitespaces).isEmpty ? "x" : " "
        lines[lineIndex] = line.replacingCharacters(in: markRange, with: mark)
        return lines.joined(separator: "\n")
    }
}
