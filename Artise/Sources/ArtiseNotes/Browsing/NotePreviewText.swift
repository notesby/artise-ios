//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A note's first lines as a list shows them under its name: the words without the Markdown marks or the header,
/// so a recipe reads "Ingredientes: chiles, chocolate" rather than "---" or "## Ingredientes".
public enum NotePreviewText {
    public static let maxLines = 2
    public static let maxCharacters = 120
    
    /// The first `lines` lines with words in them, joined with " · "; `nil` for an empty note or one not downloaded.
    public static func firstLines(of content: String?, lines: Int = maxLines) -> String? {
        guard let content else { return nil }
        var kept: [String] = []
        for rawLine in NoteFrontmatter.split(content).body.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = plain(String(rawLine))
            guard !line.isEmpty else { continue }
            kept.append(line)
            if kept.count == lines {
                break
            }
        }
        guard !kept.isEmpty else { return nil }
        let joined = kept.joined(separator: " · ")
        guard joined.count > maxCharacters else { return joined }
        return String(joined.prefix(maxCharacters)).trimmingCharacters(in: .whitespaces) + "…"
    }
    
    /// One line without its marks: headings, bullets, checkboxes, quotes, emphasis and links keep their words;
    /// a rule or a fence line is nothing.
    static func plain(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: #"^(#{1,6}\s+|>\s*|[-*+]\s+|\d+[.)]\s+)+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\[( |x|X)\]\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"!?\[\[[^\]|]*\|([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"!?\[\[([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[*_`~]"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespaces)
        return text.allSatisfy { "-=".contains($0) } ? "" : text
    }
}
