//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A formatting button in the editor's toolbar.
public enum FormatAction: CaseIterable, Sendable {
    case bold
    case italic
    case strikethrough
    case heading
    case bulletList
    case numberedList
    case checklist
    case quote
    case noteLink
    /// Opens the link dialog for a new web link; the selected text becomes its text.
    case webLink
}

/// Text with a selection, in UTF-16 offsets: `start == end` is a cursor.
public struct EditedText: Equatable, Sendable {
    public let text: String
    public let start: Int
    public let end: Int
    
    public init(text: String, start: Int, end: Int) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// The Markdown each toolbar button writes, so people get formatting without learning the syntax.
/// Every button toggles: pressing it again on formatted text removes the formatting. The same as the Android app.
public enum MarkdownFormatting {
    public static func apply(_ action: FormatAction, to text: String, start: Int, end: Int) -> EditedText {
        let from = min(max(min(start, end), 0), text.utf16Length)
        let to = min(max(max(start, end), 0), text.utf16Length)
        switch action {
        case .bold: return toggleWrap(text, from, to, marker: "**")
        case .italic: return toggleWrap(text, from, to, marker: "*")
        case .strikethrough: return toggleWrap(text, from, to, marker: "~~")
        case .heading: return cycleHeading(text, from, to)
        case .bulletList: return toggleLinePrefix(text, from, to, kind: .bullet)
        case .numberedList: return toggleLinePrefix(text, from, to, kind: .numbered)
        case .checklist: return toggleLinePrefix(text, from, to, kind: .checklist)
        case .quote: return toggleLinePrefix(text, from, to, kind: .quote)
        // "[[" opens the note suggestions; choosing one completes the link.
        case .noteLink: return EditedText(text: text.replacingUTF16(from, to, with: "[["), start: from + 2, end: from + 2)
        // It needs an address first: the editor opens the link dialog, and the text changes when it's saved.
        case .webLink: return EditedText(text: text, start: from, end: to)
        }
    }
    
    /// What Enter does on a list or quote line: continue it ("- ", the next number, an unticked "- [ ] "),
    /// or, on an item left empty, end the list by clearing its marker. `nil` for ordinary lines.
    /// `cursor` is where the newline is being typed.
    public static func continueListOnEnter(_ text: String, cursor: Int) -> EditedText? {
        let lineStart = text.lineStart(containing: cursor)
        let line = text.utf16Slice(lineStart, cursor)
        guard let kind = LineKind.of(line) else { return nil }
        let prefixLength = LineKind.prefixLength(line)
        if line.utf16Slice(from: prefixLength).trimmingCharacters(in: .whitespaces).isEmpty {
            // An empty item: Enter ends the list.
            return EditedText(text: text.replacingUTF16(lineStart, cursor, with: ""), start: lineStart, end: lineStart)
        }
        let indent = String(line.prefix { $0 == " " })
        let next: String
        if kind == .numbered {
            let number = NSRegularExpression.make(#"\d+"#).firstMatch(in: line).flatMap { Int($0.group(0, in: line)) } ?? 0
            next = indent + "\(number + 1). "
        } else {
            next = indent + kind.prefix(number: 1)
        }
        let inserted = "\n" + next
        let cursorAfter = cursor + inserted.utf16Length
        return EditedText(text: text.replacingUTF16(cursor, cursor, with: inserted), start: cursorAfter, end: cursorAfter)
    }
    
    /// The marker around the selection, or removed if already there; with no selection, an empty pair to type into.
    private static func toggleWrap(_ text: String, _ from: Int, _ to: Int, marker: String) -> EditedText {
        let length = marker.utf16Length
        var wrapped = from >= length && to + length <= text.utf16Length
            && text.utf16Slice(from - length, from) == marker && text.utf16Slice(to, to + length) == marker
        // "*" inside "**": the italic button shouldn't eat half of a bold marker.
        if wrapped, marker == "*", text.utf16Unit(at: from - length - 1) == star || text.utf16Unit(at: to + length) == star {
            wrapped = false
        }
        if wrapped {
            let removed = text.replacingUTF16(to, to + length, with: "").replacingUTF16(from - length, from, with: "")
            return EditedText(text: removed, start: from - length, end: to - length)
        }
        let added = text.utf16Slice(0, from) + marker + text.utf16Slice(from, to) + marker + text.utf16Slice(from: to)
        return EditedText(text: added, start: from + length, end: to + length)
    }
    
    /// No heading → # → ## → ### → no heading, on the line with the cursor.
    private static func cycleHeading(_ text: String, _ from: Int, _ to: Int) -> EditedText {
        let lineStart = text.lineStart(containing: from)
        let level = text.utf16Slice(from: lineStart).prefix { $0 == "#" }.count
        let hasSpace = text.utf16Unit(at: lineStart + level) == UInt16(UInt8(ascii: " "))
        let oldPrefix = level > 0 && hasSpace ? level + 1 : 0
        let newPrefix = switch oldPrefix == 0 ? 0 : level {
        case 0: "# "
        case 1: "## "
        case 2: "### "
        default: ""
        }
        let newText = text.replacingUTF16(lineStart, lineStart + oldPrefix, with: newPrefix)
        let shift = newPrefix.utf16Length - oldPrefix
        return EditedText(text: newText, start: max(from + shift, lineStart), end: max(to + shift, lineStart))
    }
    
    /// Lists and quotes apply to every line the selection touches; if they all have it already, it's removed.
    private static func toggleLinePrefix(_ text: String, _ from: Int, _ to: Int, kind: LineKind) -> EditedText {
        let firstLineStart = text.lineStart(containing: from)
        let lastLineEnd = text.lineEnd(containing: to)
        let lines = text.utf16Slice(firstLineStart, lastLineEnd).components(separatedBy: "\n")
        let allHaveIt = lines.allSatisfy { LineKind.of($0) == kind }
        var number = 0
        let newLines = lines.map { line -> String in
            let body = line.utf16Slice(from: LineKind.prefixLength(line))
            if allHaveIt {
                return body
            }
            // Blank lines inside a selection stay blank rather than becoming empty items.
            if line.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 {
                return line
            }
            number += 1
            return kind.prefix(number: number) + body
        }
        let newBlock = newLines.joined(separator: "\n")
        let newText = text.replacingUTF16(firstLineStart, lastLineEnd, with: newBlock)
        if from == to {
            // The cursor stays at the same place in the line's text.
            let shift = newLines[0].utf16Length - lines[0].utf16Length
            let cursor = min(max(from + shift, firstLineStart), firstLineStart + newLines[0].utf16Length)
            return EditedText(text: newText, start: cursor, end: cursor)
        }
        return EditedText(text: newText, start: firstLineStart, end: firstLineStart + newBlock.utf16Length)
    }
    
    private static let star = UInt16(UInt8(ascii: "*"))
}

/// The kinds of line the toolbar writes, recognised by their Markdown prefix.
enum LineKind {
    case bullet
    case numbered
    case checklist
    case quote
    
    private static let checklistPrefix = NSRegularExpression.make(#"^\s*[-*+] \[[ xX]\] "#)
    private static let bulletPrefix = NSRegularExpression.make(#"^\s*[-*+] "#)
    private static let numberedPrefix = NSRegularExpression.make(#"^\s*\d+[.)] "#)
    private static let quotePrefix = NSRegularExpression.make(#"^\s*> ?"#)
    
    func prefix(number: Int) -> String {
        switch self {
        case .bullet: "- "
        case .numbered: "\(number). "
        case .checklist: "- [ ] "
        case .quote: "> "
        }
    }
    
    static func of(_ line: String) -> LineKind? {
        if checklistPrefix.firstMatch(in: line) != nil {
            return .checklist
        }
        if bulletPrefix.firstMatch(in: line) != nil {
            return .bullet
        }
        if numberedPrefix.firstMatch(in: line) != nil {
            return .numbered
        }
        if quotePrefix.firstMatch(in: line) != nil {
            return .quote
        }
        return nil
    }
    
    /// The length of the list or quote marker at the start of the line, indentation included; 0 if none.
    static func prefixLength(_ line: String) -> Int {
        for prefix in [checklistPrefix, bulletPrefix, numberedPrefix, quotePrefix] {
            if let match = prefix.firstMatch(in: line) {
                return match.range.length
            }
        }
        return 0
    }
}
