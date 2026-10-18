//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// How a stretch of a note looks in the editor's live preview.
public enum PreviewStyle: Equatable, Sendable {
    case heading(level: Int)
    case bold
    case italic
    case strikethrough
    case code
    case link
    /// Secondary text: ticked items, quotes, list numbers, table pipes.
    case dim
    /// Markdown marks that don't show (`**`, `[[`, the ``` lines…).
    case hidden
    /// Marks drawn as something else: the characters stay, invisible, and the glyph is drawn over them.
    case glyph(PreviewGlyph)
}

public enum PreviewGlyph: Equatable, Sendable {
    /// ☐ / ☑ for a checklist item: larger than the text, so it's easy to see and tap.
    case checkbox(checked: Bool)
    /// • for a bullet.
    case bullet
    /// ▍ for a quote.
    case quoteBar
    /// ──── for a horizontal rule.
    case rule
    /// 🖼 before an embedded photo or file, so it isn't mistaken for text.
    case embed
    
    /// The glyph as text, the same characters the Android app draws.
    public var text: String {
        switch self {
        case .checkbox(let checked): checked ? "☑ " : "☐ "
        case .bullet: "• "
        case .quoteBar: "▍ "
        case .rule: "────────"
        case .embed: "🖼 "
        }
    }
}

/// A style over a UTF-16 range of the note (`start..<end`).
public struct PreviewRun: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let style: PreviewStyle
    
    public init(_ start: Int, _ end: Int, _ style: PreviewStyle) {
        self.start = start
        self.end = end
        self.style = style
    }
}

/// A link as the link dialog edits it: `[[note]]` when `isNote`, otherwise `[text](address)`.
public struct EditableLink: Equatable, Sendable {
    public let isNote: Bool
    /// The note (heading included) for `[[…]]`, or the web address.
    public let target: String
    /// The text shown instead of the target, or empty for none.
    public let shownText: String
    
    public init(isNote: Bool, target: String, shownText: String) {
        self.isNote = isNote
        self.target = target
        self.shownText = shownText
    }
    
    /// The Markdown for this link.
    public var markdown: String {
        let target = target.trimmingCharacters(in: .whitespaces)
        let shown = shownText.trimmingCharacters(in: .whitespaces)
        if isNote {
            return shown.isEmpty ? "[[\(target)]]" : "[[\(target)|\(shown)]]"
        }
        // A web address with no text of its own is written as is: it shows as a link anyway.
        return shown.isEmpty ? target : "[\(shown)](\(target))"
    }
    
    /// What remains when the link is removed: the text people saw.
    public var label: String {
        if !shownText.trimmingCharacters(in: .whitespaces).isEmpty {
            return shownText
        }
        guard isNote else { return target }
        let withoutHeading = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
        return NotesFolderEntries.fileName(withoutHeading)
    }
}

/// Something on a formatted line that a tap acts on instead of placing the cursor.
public enum LivePreviewHit: Equatable, Sendable {
    /// The checkbox of the checklist item on this line (from 0).
    case checkbox(line: Int)
    /// A link over `start..<end` of the note.
    case link(start: Int, end: Int, link: EditableLink)
}

/// Obsidian-style live preview for the editor, as in the Android app: every line shows formatted, with its
/// Markdown marks hidden, except the lines being edited, which show exactly as written. A code block or table
/// the cursor is in shows raw as a whole. The text itself never changes; only how it's drawn.
public enum LivePreview {
    private static let heading = NSRegularExpression.make(#"^(#{1,6}) "#)
    private static let checklist = NSRegularExpression.make(#"^(\s*)([-*+]) \[([ xX])\] "#)
    private static let bullet = NSRegularExpression.make(#"^(\s*)([-*+]) "#)
    private static let numbered = NSRegularExpression.make(#"^(\s*)(\d+[.)]) "#)
    private static let quote = NSRegularExpression.make(#"^(\s*)> ?"#)
    private static let rule = NSRegularExpression.make(#"^\s*([-*_])(\s*\1){2,}\s*$"#)
    private static let fence = NSRegularExpression.make(#"^\s{0,3}(```|~~~)"#)
    private static let tableRow = NSRegularExpression.make(#"^\s*\|.*\|\s*$"#)
    private static let tableSeparator = NSRegularExpression.make(#"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$"#)
    
    private static let inlineCode = NSRegularExpression.make(#"`([^`\n]+)`"#)
    private static let wikiLink = NSRegularExpression.make(#"(!?)\[\[([^\[\]\n]+)\]\]"#)
    private static let markdownLink = NSRegularExpression.make(#"\[([^\[\]\n]+)\]\(([^()\s]+)\)"#)
    /// A web address typed as plain text; trailing punctuation isn't part of it.
    private static let bareURL = NSRegularExpression.make(#"(?<![\w/(<\[])(?:https?://|www\.)[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'"]"#)
    private static let bold = NSRegularExpression.make(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
    private static let strike = NSRegularExpression.make(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let italicStar = NSRegularExpression.make(#"(?<!\*)\*(?=[^\s*])([^*\n]+?)(?<=\S)\*(?!\*)"#)
    private static let italicUnderscore = NSRegularExpression.make(#"(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#)
    
    /// The lines shown raw for this selection: the selected lines, grown to a whole code block or table.
    public static func rawLines(in text: String, selectionStart: Int, selectionEnd: Int) -> ClosedRange<Int> {
        let lines = text.components(separatedBy: "\n")
        let first = text.lineNumber(at: min(selectionStart, selectionEnd))
        let last = text.lineNumber(at: max(selectionStart, selectionEnd))
        let touched = blocks(of: lines).filter { $0.lowerBound <= last && $0.upperBound >= first }
        let lower = min(touched.map(\.lowerBound).min() ?? first, first)
        let upper = max(touched.map(\.upperBound).max() ?? last, last)
        return lower...upper
    }
    
    /// The styles to draw the note with, leaving `rawLines` as written.
    public static func runs(for text: String, rawLines: ClosedRange<Int>?) -> [PreviewRun] {
        var builder = Builder()
        let lines = text.components(separatedBy: "\n")
        let blocks = blocks(of: lines)
        var lineStart = 0
        for (index, line) in lines.enumerated() {
            let lineEnd = lineStart + line.utf16Length
            let block = blocks.first { $0.contains(index) }
            if rawLines?.contains(index) == true {
                // Shown as written.
            } else if let block, fence.firstMatch(in: lines[block.lowerBound]) != nil {
                codeLine(&builder, lineStart, lineEnd, isFence: index == block.lowerBound || index == block.upperBound)
            } else if let block {
                tableLine(&builder, line, lineStart, lineEnd, isHeader: index == block.lowerBound)
            } else {
                formattedLine(&builder, line, lineStart, lineEnd)
            }
            lineStart = lineEnd + 1
        }
        return builder.runs
    }
    
    /// What a tap at `offset` (in the note) lands on, for a line that was showing formatted.
    public static func hit(in text: String, at offset: Int) -> LivePreviewHit? {
        let lineNumber = text.lineNumber(at: offset)
        let lineStart = text.lineStart(containing: offset)
        let line = text.utf16Slice(lineStart, text.lineEnd(containing: offset))
        let column = offset - lineStart
        if let match = checklist.firstMatch(in: line) {
            let markerStart = match.range(at: 1).length
            if column >= markerStart, column < match.end {
                return .checkbox(line: lineNumber)
            }
        }
        for match in wikiLink.matches(in: line) {
            let label = wikiLabelRange(match, in: line)
            if column >= label.start, column < label.end {
                let inner = match.group(2, in: line)
                let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                let link = EditableLink(isNote: true, target: parts[0], shownText: parts.count > 1 ? parts[1] : "")
                return .link(start: lineStart + match.range.location, end: lineStart + match.end, link: link)
            }
        }
        let markdownLinks = markdownLink.matches(in: line)
        for match in markdownLinks {
            let labelStart = match.range.location + 1
            if column >= labelStart, column < labelStart + match.range(at: 1).length {
                let link = EditableLink(isNote: false, target: match.group(2, in: line), shownText: match.group(1, in: line))
                return .link(start: lineStart + match.range.location, end: lineStart + match.end, link: link)
            }
        }
        for match in bareURL.matches(in: line) {
            // Inside a [text](address) link, the address belongs to that link, handled above.
            if markdownLinks.contains(where: { NSLocationInRange(match.range.location, $0.range) }) {
                continue
            }
            if column >= match.range.location, column < match.end {
                let link = EditableLink(isNote: false, target: match.group(0, in: line), shownText: "")
                return .link(start: lineStart + match.range.location, end: lineStart + match.end, link: link)
            }
        }
        return nil
    }
    
    /// The text as the preview shows it: hidden marks left out and glyphs written as characters.
    /// Read aloud by VoiceOver, and used by tests to check what people see.
    public static func visibleText(_ text: String, runs: [PreviewRun]) -> String {
        let units = Array(text.utf16)
        var hidden = [Bool](repeating: false, count: units.count)
        var glyphs: [Int: (end: Int, glyph: PreviewGlyph)] = [:]
        for run in runs {
            switch run.style {
            case .hidden:
                for index in run.start..<min(run.end, units.count) {
                    hidden[index] = true
                }
            case .glyph(let glyph):
                glyphs[run.start] = (run.end, glyph)
            default:
                break
            }
        }
        var output: [UInt16] = []
        var index = 0
        while index < units.count {
            if let (end, glyph) = glyphs[index] {
                output += Array(glyph.text.utf16)
                index = end
            } else {
                if !hidden[index] {
                    output.append(units[index])
                }
                index += 1
            }
        }
        return String(decoding: output, as: UTF16.self)
    }
    
    // MARK: - Blocks
    
    /// Code blocks (fence to fence) and tables (a header row, then a separator row), as line ranges.
    private static func blocks(of lines: [String]) -> [ClosedRange<Int>] {
        var blocks: [ClosedRange<Int>] = []
        var index = 0
        while index < lines.count {
            if fence.firstMatch(in: lines[index]) != nil {
                let end = (index + 1..<lines.count).first { fence.firstMatch(in: lines[$0]) != nil } ?? lines.count - 1
                blocks.append(index...end)
                index = end + 1
            } else if tableRow.firstMatch(in: lines[index]) != nil, index + 1 < lines.count, tableSeparator.firstMatch(in: lines[index + 1]) != nil {
                var end = index + 1
                while end + 1 < lines.count, tableRow.firstMatch(in: lines[end + 1]) != nil {
                    end += 1
                }
                blocks.append(index...end)
                index = end + 1
            } else {
                index += 1
            }
        }
        return blocks
    }
    
    private static func codeLine(_ builder: inout Builder, _ start: Int, _ end: Int, isFence: Bool) {
        // The ``` lines disappear; the code between shows in the code style.
        builder.add(start, end, isFence ? .hidden : .code)
    }
    
    private static func tableLine(_ builder: inout Builder, _ line: String, _ start: Int, _ end: Int, isHeader: Bool) {
        builder.add(start, end, .code)
        if isHeader {
            builder.add(start, end, .bold)
        }
        if tableSeparator.firstMatch(in: line) != nil {
            builder.add(start, end, .dim)
            return
        }
        for (offset, unit) in line.utf16.enumerated() where unit == UInt16(UInt8(ascii: "|")) {
            builder.add(start + offset, start + offset + 1, .dim)
        }
    }
    
    // MARK: - Lines
    
    private static func formattedLine(_ builder: inout Builder, _ line: String, _ start: Int, _ end: Int) {
        if let match = heading.firstMatch(in: line) {
            builder.add(start, start + match.end, .hidden)
            let level = min(match.range(at: 1).length, 3)
            builder.add(start + match.end, end, .heading(level: level))
            inline(&builder, line, start, start + match.end, end)
            return
        }
        if let match = checklist.firstMatch(in: line) {
            let indent = match.range(at: 1).length
            let checked = !match.group(3, in: line).trimmingCharacters(in: .whitespaces).isEmpty
            builder.add(start + indent, start + match.end, .glyph(.checkbox(checked: checked)))
            if checked {
                builder.add(start + match.end, end, .dim)
            }
            inline(&builder, line, start, start + match.end, end)
            return
        }
        if let match = bullet.firstMatch(in: line) {
            builder.add(start + match.range(at: 1).length, start + match.end, .glyph(.bullet))
            inline(&builder, line, start, start + match.end, end)
            return
        }
        if let match = numbered.firstMatch(in: line) {
            builder.add(start, start + match.end, .dim)
            inline(&builder, line, start, start + match.end, end)
            return
        }
        if rule.firstMatch(in: line) != nil {
            builder.add(start, end, .glyph(.rule))
            return
        }
        if let match = quote.firstMatch(in: line) {
            builder.add(start + match.range(at: 1).length, start + match.end, .glyph(.quoteBar))
            builder.add(start + match.end, end, .dim)
            builder.add(start + match.end, end, .italic)
            inline(&builder, line, start, start + match.end, end)
            return
        }
        inline(&builder, line, start, start, end)
    }
    
    /// Inline formatting between `from` and `to` (offsets in the note), the line starting at `lineStart`.
    private static func inline(_ builder: inout Builder, _ line: String, _ lineStart: Int, _ from: Int, _ to: Int) {
        var index = from
        let patterns = [inlineCode, wikiLink, markdownLink, bareURL, bold, strike, italicStar, italicUnderscore]
        while index < to {
            let column = index - lineStart
            var found: (NSRegularExpression, NSTextCheckingResult)?
            for pattern in patterns {
                if let match = pattern.match(in: line, at: column), lineStart + match.end <= to {
                    found = (pattern, match)
                    break
                }
            }
            guard let (pattern, match) = found else {
                index += 1
                continue
            }
            let matchStart = lineStart + match.range.location
            let matchEnd = lineStart + match.end
            if pattern === inlineCode {
                builder.add(matchStart, matchStart + 1, .hidden)
                builder.add(matchStart + 1, matchEnd - 1, .code)
                builder.add(matchEnd - 1, matchEnd, .hidden)
            } else if pattern === wikiLink {
                let label = wikiLabelRange(match, in: line)
                let isEmbed = match.range(at: 1).length > 0
                if isEmbed {
                    // An embedded photo or file is marked so it isn't mistaken for text.
                    builder.add(matchStart, matchStart + 1, .glyph(.embed))
                    builder.add(matchStart + 1, lineStart + label.start, .hidden)
                } else {
                    builder.add(matchStart, lineStart + label.start, .hidden)
                }
                builder.add(lineStart + label.start, lineStart + label.end, .link)
                builder.add(lineStart + label.end, matchEnd, .hidden)
            } else if pattern === bareURL {
                builder.add(matchStart, matchEnd, .link)
            } else if pattern === markdownLink {
                let labelEnd = matchStart + 1 + match.range(at: 1).length
                builder.add(matchStart, matchStart + 1, .hidden)
                builder.add(matchStart + 1, labelEnd, .link)
                builder.add(labelEnd, matchEnd, .hidden)
            } else {
                let marker = pattern === bold || pattern === strike ? 2 : 1
                let style: PreviewStyle = pattern === bold ? .bold : pattern === strike ? .strikethrough : .italic
                builder.add(matchStart, matchStart + marker, .hidden)
                builder.add(matchStart + marker, matchEnd - marker, style)
                inline(&builder, line, lineStart, matchStart + marker, matchEnd - marker)
                builder.add(matchEnd - marker, matchEnd, .hidden)
            }
            index = matchEnd
        }
    }
    
    /// Where a wiki link's visible text sits in its line: the shown text, else the note's name without folder or heading.
    private static func wikiLabelRange(_ match: NSTextCheckingResult, in line: String) -> (start: Int, end: Int) {
        let innerStart = match.range.location + match.range(at: 1).length + 2
        let inner = match.group(2, in: line)
        if let pipe = inner.range(of: "|") {
            let pipeOffset = inner[..<pipe.lowerBound].utf16.count
            return (innerStart + pipeOffset + 1, innerStart + inner.utf16Length)
        }
        let target = inner.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? inner
        let nameStart = target.range(of: "/", options: .backwards).map { target[..<$0.upperBound].utf16.count } ?? 0
        return (innerStart + nameStart, innerStart + target.utf16Length)
    }
    
    private struct Builder {
        var runs: [PreviewRun] = []
        
        mutating func add(_ start: Int, _ end: Int, _ style: PreviewStyle) {
            if end > start {
                runs.append(PreviewRun(start, end, style))
            }
        }
    }
}
