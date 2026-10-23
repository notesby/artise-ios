//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// What find marks in a note as it reads: every match by the run of text it's in (`NoteReadingFind`'s slots), and the
/// current one.
struct NoteFindMarks: Equatable {
    var ranges: [[Int]: [Range<Int>]] = [:]
    var current: NoteReadingMatch?
    
    init(matches: [NoteReadingMatch] = [], current: NoteReadingMatch? = nil) {
        ranges = Dictionary(grouping: matches, by: \.slot).mapValues { $0.map(\.range) }
        self.current = current
    }
    
    /// A run of text with its matches marked.
    func marked(_ text: AttributedString, slot: [Int]) -> AttributedString {
        guard let found = ranges[slot] else { return text }
        return NoteFindHighlight.apply(to: text, ranges: found, current: current?.slot == slot ? current?.range : nil)
    }
}

extension EnvironmentValues {
    @Entry var noteFindMarks = NoteFindMarks()
}

/// Shows a note: headings, paragraphs, lists and checklists, quotes, code, tables, links and embeds,
/// drawn like the Android app. Nothing opens by itself: links go to `onLink`, checkboxes to `onToggle`.
/// Each block and run of text has its place in the note (`NoteReadingFind`'s slot) as its id, so find can mark
/// matches and scroll to them.
struct NoteMarkdownView: View {
    let document: NoteDocument
    let onLink: (NoteLink) -> Void
    /// Ticks the checklist item on a line of the note; `nil` makes checklists read-only.
    let onToggle: ((Int) -> Void)?
    let embed: (String) -> AnyView
    
    var body: some View {
        NoteBlocksView(blocks: document.blocks, actions: actions)
            .environment(\.openURL, OpenURLAction { url in
                onLink(NoteLinkURL.link(from: url))
                return .handled
            })
            .tint(.compound.textLinkExternal)
    }
    
    private var actions: NoteBlockActions {
        NoteBlockActions(onToggle: onToggle, embed: embed)
    }
}

private struct NoteBlockActions {
    let onToggle: ((Int) -> Void)?
    let embed: (String) -> AnyView
}

private struct NoteBlocksView: View {
    let blocks: [NoteBlock]
    var prefix: [Int] = []
    let actions: NoteBlockActions
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(blocks.indices, id: \.self) { index in
                NoteBlockView(block: blocks[index], slot: prefix + [index], actions: actions)
                    .id(prefix + [index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NoteBlockView: View {
    let block: NoteBlock
    let slot: [Int]
    let actions: NoteBlockActions
    
    @Environment(\.noteFindMarks) private var marks
    
    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(marks.marked(NoteInlineText.attributed(text), slot: slot))
                .font(headingFont(level))
                .foregroundStyle(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let pieces):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pieces.indices, id: \.self) { index in
                    switch pieces[index] {
                    case .text(let inlines):
                        NoteBodyText(inlines: inlines, slot: slot + [index])
                            .id(slot + [index])
                    case .embed(let target):
                        actions.embed(target)
                    }
                }
            }
        case .list(let ordered, let start, let items):
            NoteListView(ordered: ordered, start: start, items: items, slot: slot, actions: actions)
        case .quote(let blocks):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(.compound.borderInteractiveSecondary)
                    .frame(width: 3)
                NoteBlocksView(blocks: blocks, prefix: slot, actions: actions)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let code):
            ScrollView(.horizontal) {
                Text(marks.marked(AttributedString(code), slot: slot))
                    .font(.compound.bodyMD.monospaced())
                    .foregroundStyle(.compound.textPrimary)
                    .padding(12)
            }
            .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 8))
        case .table(let rows):
            // Phones are narrow: each row reads as "cell · cell · cell", the header row in bold.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows.indices, id: \.self) { index in
                    Text(marks.marked(NoteInlineText.attributed(NoteReadingFind.row(rows[index])), slot: slot + [index]))
                        .font(index == 0 ? .compound.bodyLGSemibold : .compound.bodyLG)
                        .foregroundStyle(.compound.textPrimary)
                        .id(slot + [index])
                }
            }
        case .divider:
            Divider()
        case .html(let html):
            NoteBodyText(inlines: [.text(html)], slot: slot)
        }
    }
    
    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .compound.headingLGBold
        case 2: .compound.headingMDBold
        case 3: .compound.headingSMSemibold
        default: .compound.bodyLGSemibold
        }
    }
}

/// Body text with generous line spacing: notes are read on phones, often by older family members.
private struct NoteBodyText: View {
    let inlines: [NoteInline]
    let slot: [Int]
    
    @Environment(\.noteFindMarks) private var marks
    
    var body: some View {
        Text(marks.marked(NoteInlineText.attributed(inlines), slot: slot))
            .font(.compound.bodyLG)
            .lineSpacing(8)
            .foregroundStyle(.compound.textPrimary)
    }
}

private struct NoteListView: View {
    let ordered: Bool
    let start: Int
    let items: [NoteListItem]
    let slot: [Int]
    let actions: NoteBlockActions
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                HStack(alignment: item.task == nil ? .firstTextBaseline : .center, spacing: 8) {
                    if let checked = item.task {
                        checkbox(checked: checked, line: item.line)
                    } else {
                        Text(ordered ? "\(start + index)." : "•")
                            .font(.compound.bodyLG)
                            .foregroundStyle(.compound.textSecondary)
                            .frame(width: 28, alignment: .leading)
                    }
                    NoteBlocksView(blocks: item.blocks, prefix: slot + [index], actions: actions)
                }
            }
        }
    }
    
    /// A full-size checkbox (44 points to tap); read-only where the note can't be changed.
    @ViewBuilder
    private func checkbox(checked: Bool, line: Int?) -> some View {
        let image = Image(systemName: checked ? "checkmark.square.fill" : "square")
            .font(.title2)
            .foregroundStyle(checked ? Color.compound.iconAccentTertiary : Color.compound.iconSecondary)
            .frame(width: 44, height: 44)
        if let line, let onToggle = actions.onToggle {
            Button { onToggle(line) } label: { image }
                .buttonStyle(.plain)
                .accessibilityAddTraits(checked ? .isSelected : [])
        } else {
            image
        }
    }
}

/// Note links travel through SwiftUI's link handling as `artise-note:` URLs.
enum NoteLinkURL {
    static func url(for link: NoteLink) -> URL? {
        switch link {
        case .note(let target): URL(string: WikiLinkRewriter.destination(target))
        case .web(let address): URL(string: address)
        }
    }
    
    static func link(from url: URL) -> NoteLink {
        if let target = WikiLinkRewriter.target(of: url.absoluteString) {
            return .note(target: target)
        }
        return .web(url.absoluteString)
    }
}

/// A run of inline Markdown as text SwiftUI can draw: bold, italics, strikethrough, code and links.
enum NoteInlineText {
    static func attributed(_ inlines: [NoteInline]) -> AttributedString {
        inlines.reduce(into: AttributedString()) { result, inline in
            result += attributed(inline)
        }
    }
    
    private static func attributed(_ inline: NoteInline) -> AttributedString {
        switch inline {
        case .text(let text):
            return AttributedString(text)
        case .emphasis(let children):
            return styled(children, .emphasized)
        case .strong(let children):
            return styled(children, .stronglyEmphasized)
        case .strikethrough(let children):
            return styled(children, .strikethrough)
        case .code(let code):
            var text = AttributedString(code)
            text.inlinePresentationIntent = .code
            text.backgroundColor = Color.compound.bgSubtleSecondary
            return text
        case .link(let link, let children):
            var text = attributed(children)
            text.link = NoteLinkURL.url(for: link)
            text.underlineStyle = .single
            return text
        }
    }
    
    private static func styled(_ children: [NoteInline], _ intent: InlinePresentationIntent) -> AttributedString {
        var text = attributed(children)
        for run in text.runs {
            let existing = run.inlinePresentationIntent ?? []
            text[run.range].inlinePresentationIntent = existing.union(intent)
        }
        return text
    }
}
