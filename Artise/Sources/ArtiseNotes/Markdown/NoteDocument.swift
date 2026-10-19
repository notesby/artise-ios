//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Markdown

/// A note's Markdown as blocks to draw: headings, paragraphs, lists and checklists, quotes, code, tables and links.
/// `[[wiki links]]` and `![[embeds]]` are understood, as in Obsidian and the Android app.
public struct NoteDocument: Equatable, Sendable {
    public let blocks: [NoteBlock]
    /// The page's header (`type`, `aliases`, `summary`), kept out of `blocks`.
    public let frontmatter: NoteFrontmatter?
    
    public init(markdown: String) {
        let (header, body) = NoteFrontmatter.split(markdown)
        frontmatter = header
        let document = Document(parsing: WikiLinkRewriter.rewrite(body))
        blocks = document.children.compactMap(Self.block)
    }
    
    private static func block(_ markup: Markup) -> NoteBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, text: inlines(heading.children))
        case let paragraph as Paragraph:
            return .paragraph(pieces(paragraph))
        case let list as UnorderedList:
            return .list(ordered: false, start: 1, items: list.listItems.map(item))
        case let list as OrderedList:
            return .list(ordered: true, start: Int(list.startIndex), items: list.listItems.map(item))
        case let quote as BlockQuote:
            return .quote(quote.children.compactMap(block))
        case let code as CodeBlock:
            return .code(code.code.trimmingTrailingWhitespace())
        case is ThematicBreak:
            return .divider
        case let table as Table:
            // Phones are narrow: each row reads as "cell · cell · cell", the header row in bold.
            let header = [Array(table.head.cells.map { inlines($0.children) })]
            let rows = table.body.rows.map { row in Array(row.cells.map { inlines($0.children) }) }
            return .table(rows: header + rows)
        case let html as HTMLBlock:
            return .html(html.rawHTML.trimmingTrailingWhitespace())
        default:
            // Anything else the parser may produce: show its text rather than nothing.
            let text = inlines(markup.children)
            return text.isEmpty ? nil : .paragraph([.text(text)])
        }
    }
    
    private static func item(_ item: ListItem) -> NoteListItem {
        let line = item.range.map { $0.lowerBound.line - 1 }
        let task: Bool? = switch item.checkbox {
        case .checked: true
        case .unchecked: false
        case nil: nil
        }
        return NoteListItem(task: task, line: line, blocks: item.children.compactMap(block))
    }
    
    /// A paragraph split around its embeds: runs of text, and the photos or files between them.
    /// Notes from Ari or Obsidian often mix both ("Hoy:\n![[foto.jpg]]").
    private static func pieces(_ paragraph: Paragraph) -> [NoteParagraphPiece] {
        var pieces: [NoteParagraphPiece] = []
        var run: [Markup] = []
        func endRun() {
            let text = inlines(run).trimmed()
            if !text.isEmpty {
                pieces.append(.text(text))
            }
            run = []
        }
        for child in paragraph.children {
            if let image = child as? Image, let source = image.source, let target = embedTarget(source) {
                endRun()
                pieces.append(.embed(target: target))
            } else {
                run.append(child)
            }
        }
        endRun()
        return pieces
    }
    
    private static func inlines(_ children: some Sequence<Markup>, inLink: Bool = false) -> [NoteInline] {
        children.flatMap { inline($0, inLink: inLink) }
    }
    
    private static func inline(_ markup: Markup, inLink: Bool) -> [NoteInline] {
        switch markup {
        case let text as Text:
            return inLink ? [.text(text.string)] : autolinked(text.string)
        case is SoftBreak:
            return [.text(" ")]
        case is LineBreak:
            return [.text("\n")]
        case let emphasis as Emphasis:
            return [.emphasis(inlines(emphasis.children, inLink: inLink))]
        case let strong as Strong:
            return [.strong(inlines(strong.children, inLink: inLink))]
        case let strikethrough as Strikethrough:
            return [.strikethrough(inlines(strikethrough.children, inLink: inLink))]
        case let code as InlineCode:
            return [.code(code.code)]
        case let link as Link:
            return [.link(classify(link.destination ?? ""), inlines(link.children, inLink: true))]
        case let image as Image:
            // An image inside a line of text shows as a link to the file.
            return [.link(classify(image.source ?? ""), [.text("🖼 ")] + inlines(image.children, inLink: true))]
        case let html as InlineHTML:
            return [.text(html.rawHTML)]
        default:
            return inlines(markup.children, inLink: inLink)
        }
    }
    
    private static let webAddress = try? NSRegularExpression(pattern: #"(?:https?://|www\.)[^\s<]+"#, options: .caseInsensitive)
    
    /// Web addresses typed as plain text ("https://…", "www.…") become tappable links, as GitHub's Markdown does:
    /// trailing punctuation stays text, and so does a closing parenthesis without its opening one.
    static func autolinked(_ text: String) -> [NoteInline] {
        guard let webAddress else { return [.text(text)] }
        var result: [NoteInline] = []
        var last = text.startIndex
        for match in webAddress.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard var range = Range(match.range, in: text) else { continue }
            while let character = text[range].last, isTrailingPunctuation(character, in: text[range]) {
                range = range.lowerBound..<text.index(before: range.upperBound)
            }
            if range.lowerBound > last {
                result.append(.text(String(text[last..<range.lowerBound])))
            }
            let address = String(text[range])
            result.append(.link(classify(address), [.text(address)]))
            last = range.upperBound
        }
        if last < text.endIndex {
            result.append(.text(String(text[last...])))
        }
        return result
    }
    
    private static func isTrailingPunctuation(_ character: Character, in address: Substring) -> Bool {
        if ".,;:!?'\"*_~".contains(character) {
            return true
        }
        return character == ")" && address.filter { $0 == ")" }.count > address.filter { $0 == "(" }.count
    }
    
    /// The photo or file an image destination points to: a `[[wiki]]` embed target, or a relative path.
    /// `nil` for web images.
    static func embedTarget(_ destination: String) -> String? {
        if let target = WikiLinkRewriter.target(of: destination) {
            return target
        }
        guard !destination.contains("://") else { return nil }
        var path = destination.removingPercentEncoding ?? destination
        if path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path
    }
    
    static func classify(_ destination: String) -> NoteLink {
        if let target = WikiLinkRewriter.target(of: destination) {
            return .note(target: target)
        }
        // A relative path ("Fotos/luna.jpg") is a file in the chat, not a web address.
        if !destination.hasPrefix("www."), !destination.hasPrefix("mailto:"), let target = embedTarget(destination) {
            return .note(target: target)
        }
        return .web(destination.hasPrefix("www.") ? "https://" + destination : destination)
    }
}

public indirect enum NoteBlock: Equatable, Sendable {
    case heading(level: Int, text: [NoteInline])
    case paragraph([NoteParagraphPiece])
    case list(ordered: Bool, start: Int, items: [NoteListItem])
    case quote([NoteBlock])
    case code(String)
    /// Rows of cells; the first row is the header.
    case table(rows: [[[NoteInline]]])
    case divider
    case html(String)
}

public enum NoteParagraphPiece: Equatable, Sendable {
    case text([NoteInline])
    /// A photo or file shown in place.
    case embed(target: String)
}

public struct NoteListItem: Equatable, Sendable {
    /// `true`/`false` for a checklist item (ticked or not), `nil` for a plain item.
    public let task: Bool?
    /// The item's line in the note (from 0), used to tick it.
    public let line: Int?
    public let blocks: [NoteBlock]
}

public indirect enum NoteInline: Equatable, Sendable {
    case text(String)
    case emphasis([NoteInline])
    case strong([NoteInline])
    case strikethrough([NoteInline])
    case code(String)
    case link(NoteLink, [NoteInline])
}

extension [NoteInline] {
    /// The plain text, for accessibility and tests.
    public var plainText: String {
        map { inline in
            switch inline {
            case .text(let text), .code(let text): text
            case .emphasis(let children), .strong(let children), .strikethrough(let children), .link(_, let children): children.plainText
            }
        }
        .joined()
    }
    
    /// Without the spaces and line breaks an embed leaves at the start or end of a run of text.
    func trimmed() -> [NoteInline] {
        var result = self
        if case .text(let first)? = result.first {
            let trimmed = String(first.drop { $0.isWhitespace })
            if trimmed.isEmpty {
                result.removeFirst()
            } else {
                result[0] = .text(trimmed)
            }
        }
        if case .text(let last)? = result.last {
            let trimmed = last.trimmingTrailingWhitespace()
            if trimmed.isEmpty {
                result.removeLast()
            } else {
                result[result.count - 1] = .text(trimmed)
            }
        }
        return result
    }
}

extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while result.last?.isWhitespace == true {
            result.removeLast()
        }
        return result
    }
}
