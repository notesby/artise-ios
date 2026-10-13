//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Which photos and files each note uses: shown (`![[luna.jpg]]`, `![foto](luna.jpg)`) or linked (`[[factura.pdf]]`,
/// `[factura](factura.pdf)`). A name finds the file the same way the note view does, so what counts as "used" here is
/// what people see. The same as the Android app.
public enum NoteReferences {
    // Both "![[x]]" and "[[x]]"; the part after | or # is the shown text or a heading.
    private static let wiki = NSRegularExpression.make(#"!?\[\[([^\[\]|#\n]+)((?:[|#][^\]\n]*)?)\]\]"#)
    // Both "![alt](x)" and "[text](x)".
    private static let markdown = NSRegularExpression.make(#"(!?)\[([^\]\n]*)\]\(<?([^)>\s]+)>?\)"#)
    
    /// The files `text` uses, among `paths` (notes themselves don't count).
    public static func filesUsed(in text: String, paths: [String]) -> Set<String> {
        let wikiTargets = wiki.matches(in: text).map { $0.group(1, in: text).trimmingCharacters(in: .whitespaces) }
        let markdownTargets = markdown.matches(in: text).map { $0.group(3, in: text) }
            .filter { !$0.contains("://") && !$0.hasPrefix("mailto:") }
            .map(decode)
        return Set((wikiTargets + markdownTargets).compactMap { NoteLinkResolver.resolve($0, in: paths) }.filter { !$0.hasSuffix(".md") })
    }
    
    /// For each note given as (path, text), the files it uses: file path → the notes using it, sorted.
    public static func index(notes: [(path: String, text: String)], paths: [String]) -> [String: [String]] {
        var users: [String: Set<String>] = [:]
        for note in notes {
            for file in filesUsed(in: note.text, paths: paths) {
                users[file, default: []].insert(note.path)
            }
        }
        return users.mapValues { $0.sorted() }
    }
    
    /// The text without any use of `path`: shown copies go (with their line when alone on it), links keep the words
    /// people read. `paths` tells what each name means, so a same-named file elsewhere is left alone.
    public static func remove(_ path: String, from text: String, paths: [String]) -> String {
        func isIt(_ target: String) -> Bool {
            NoteLinkResolver.resolve(target, in: paths) == path
        }
        var result = text
        // Shown copies first, with the embed remover, which tidies the empty line left behind.
        let shownNames = Set(wiki.matches(in: text)
            .filter { text.utf16Slice($0.range.location, $0.range.location + 1) == "!" }
            .map { $0.group(1, in: text).trimmingCharacters(in: .whitespaces) }
            .filter(isIt))
        for name in shownNames {
            result = NoteEmbedRemover.remove(name, from: result)
        }
        result = replace(markdown, in: result) { match, text in
            let bang = match.group(1, in: text)
            guard isIt(decode(match.group(3, in: text))) else { return nil }
            return bang == "!" ? "" : match.group(2, in: text)
        }
        result = replace(wiki, in: result) { match, text in
            let whole = match.group(0, in: text)
            let name = match.group(1, in: text).trimmingCharacters(in: .whitespaces)
            guard !whole.hasPrefix("!"), isIt(name) else { return nil }
            // [[factura.pdf|la factura]] → "la factura"; [[factura.pdf]] → "factura.pdf".
            let rest = match.group(2, in: text)
            return rest.hasPrefix("|") ? String(rest.dropFirst()) : NotesFolderEntries.fileName(name)
        }
        return result
    }
    
    static func decode(_ target: String) -> String {
        var path = target.removingPercentEncoding ?? target
        if path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path
    }
    
    /// Replaces each match with what `replacement` returns, or leaves it when that's `nil`.
    static func replace(_ regex: NSRegularExpression, in text: String, _ replacement: (NSTextCheckingResult, String) -> String?) -> String {
        var result = text
        for match in regex.matches(in: text).reversed() {
            if let new = replacement(match, text) {
                result = result.replacingUTF16(match.range.location, match.end, with: new)
            }
        }
        return result
    }
}

/// Finds the photos and files a note shows, and which of the chat's files they are.
public enum NoteEmbeds {
    private static let wikiEmbed = NSRegularExpression.make(#"!\[\[([^\[\]|#\n]+)(?:[|#][^\]\n]*)?\]\]"#)
    private static let markdownImage = NSRegularExpression.make(#"!\[[^\]\n]*\]\(<?([^)>\s]+)>?\)"#)
    
    /// Each embed's target, as written, mapped to the file it resolves to (notes aren't embeds here).
    public static func resolve(_ text: String, paths: [String]) -> [String: String] {
        let targets = wikiEmbed.matches(in: text).map { $0.group(1, in: text).trimmingCharacters(in: .whitespaces) }
            + markdownImage.matches(in: text).map { $0.group(1, in: text) }.filter { !$0.contains("://") }.map(NoteReferences.decode)
        var result: [String: String] = [:]
        for target in targets where result[target] == nil {
            if let path = NoteLinkResolver.resolve(target, in: paths), !path.hasSuffix(".md") {
                result[target] = path
            }
        }
        return result
    }
}

/// Takes a photo or file out of a note's text, when its upload is cancelled or it's deleted.
public enum NoteEmbedRemover {
    /// The text without the embeds of `path` (`![[foto.jpg]]`, `![[attachments/foto.jpg|300]]`). An embed alone on
    /// its line goes with that line and one blank line next to it, so no gap is left where the photo was.
    public static func remove(_ path: String, from text: String) -> String {
        let names = Set([path, NotesFolderEntries.fileName(path)]).map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let embed = NSRegularExpression.make(#"!\[\[(?:"# + names + #")(?:\|[^\]\n]*)?\]\]"#)
        guard embed.firstMatch(in: text) != nil else { return text }
        var lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard embed.firstMatch(in: line) != nil else {
                index += 1
                continue
            }
            let without = embed.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: line.utf16Length), withTemplate: "")
            if without.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.remove(at: index)
                if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.remove(at: index)
                } else if index > 0, lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.remove(at: index - 1)
                    index -= 1
                }
            } else {
                lines[index] = without.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression).trimmingTrailingWhitespace()
                index += 1
            }
        }
        return lines.joined(separator: "\n")
    }
}
