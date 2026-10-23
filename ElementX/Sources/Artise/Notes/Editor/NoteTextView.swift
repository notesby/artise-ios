//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// The editor's text: a UITextView showing the note's Markdown with live preview. Every change goes through
/// `NoteEditorModel`, and the text is restyled from `LivePreview` runs; the Markdown itself never changes for looks.
struct NoteTextView: UIViewRepresentable {
    @Binding var model: NoteEditorModel
    /// What a search found, in UTF-16 offsets, and the match it's on: shown over the text, the current one stronger.
    var highlights: [Range<Int>] = []
    var currentHighlight: Range<Int>?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(model: $model)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage()
        let layoutManager = NotePreviewLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        
        let textView = UITextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.keyboardDismissMode = .interactive
        textView.autocapitalizationType = .sentences
        textView.adjustsFontForContentSizeCategory = true
        textView.typingAttributes = NotePreviewStyle.baseAttributes
        context.coordinator.show(model, in: textView)
        DispatchQueue.main.async { textView.becomeFirstResponder() }
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.model = $model
        let searchChanged = context.coordinator.highlights != highlights || context.coordinator.currentHighlight != currentHighlight
        context.coordinator.highlights = highlights
        context.coordinator.currentHighlight = currentHighlight
        // Changes from outside the text view (toolbar, undo, a suggestion, the link dialog, the search).
        if searchChanged || textView.text != model.text || textView.selectedRange != NSRange(model.selection) {
            context.coordinator.show(model, in: textView)
        }
        if searchChanged, let currentHighlight {
            textView.scrollRangeToVisible(NSRange(currentHighlight))
        }
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        var model: Binding<NoteEditorModel>
        var highlights: [Range<Int>] = []
        var currentHighlight: Range<Int>?
        private var isUpdating = false
        
        init(model: Binding<NoteEditorModel>) {
            self.model = model
        }
        
        func show(_ model: NoteEditorModel, in textView: UITextView) {
            isUpdating = true
            defer { isUpdating = false }
            if textView.text != model.text {
                textView.text = model.text
            }
            let selection = NSRange(model.selection)
            if textView.selectedRange != selection {
                textView.selectedRange = selection
            }
            NotePreviewStyle.apply(LivePreview.runs(for: model.text, rawLines: model.rawLines), to: textView.textStorage)
            NotePreviewStyle.highlight(highlights, current: currentHighlight, in: textView.textStorage)
            textView.typingAttributes = NotePreviewStyle.baseAttributes
        }
        
        func textViewDidChange(_ textView: UITextView) {
            report(textView)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            report(textView)
        }
        
        private func report(_ textView: UITextView) {
            guard !isUpdating, let selection = Range(textView.selectedRange) else { return }
            var updated = model.wrappedValue
            updated.viewChanged(text: textView.text, selection: selection, now: .now)
            model.wrappedValue = updated
            // While the keyboard composes text (dictation, predictions), restyling would interrupt it.
            guard textView.markedTextRange == nil else { return }
            // Restyle at once: the cursor's line shows raw and the line it left shows formatted.
            show(updated, in: textView)
        }
    }
}

/// How live preview styles look in UIKit, with Compound's colours and the system text styles Compound uses.
nonisolated enum NotePreviewStyle {
    /// Marks the characters a glyph is drawn over.
    static let glyphKey = NSAttributedString.Key("co.artise.notes.previewGlyph")
    
    static var bodyFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }
    
    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        // Generous line spacing: notes are read on phones, often by older family members.
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 6
        return [.font: bodyFont, .foregroundColor: UIColor.compound.textPrimary, .paragraphStyle: paragraph]
    }
    
    /// Marks what a search found, the current match stronger, over whatever style the text has.
    static func highlight(_ ranges: [Range<Int>], current: Range<Int>?, in storage: NSTextStorage) {
        guard !ranges.isEmpty else { return }
        storage.beginEditing()
        for range in ranges {
            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            guard NSMaxRange(nsRange) <= storage.length else { continue }
            let isCurrent = range == current
            storage.addAttribute(.backgroundColor, value: isCurrent ? NoteFindHighlight.current : NoteFindHighlight.match, range: nsRange)
        }
        storage.endEditing()
    }
    
    static func apply(_ runs: [PreviewRun], to storage: NSTextStorage) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: whole)
        // Text styles first, then hidden marks and glyphs, which win where they overlap.
        for run in runs where !run.isMarker {
            style(run, in: storage)
        }
        for run in runs where run.isMarker {
            style(run, in: storage)
        }
        storage.endEditing()
    }
    
    private static func style(_ run: PreviewRun, in storage: NSTextStorage) {
        let range = NSRange(location: run.start, length: run.end - run.start)
        guard range.location >= 0, NSMaxRange(range) <= storage.length else { return }
        switch run.style {
        case .heading(let level):
            let style: UIFont.TextStyle = switch level {
            case 1: .title1
            case 2: .title2
            default: .title3
            }
            storage.addAttribute(.font, value: font(style, traits: level == 3 ? [] : .traitBold, weight: level == 3 ? .semibold : nil), range: range)
        case .bold:
            addTraits(.traitBold, in: range, of: storage)
        case .italic:
            addTraits(.traitItalic, in: range, of: storage)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .code:
            storage.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize * 0.9, weight: .regular), range: range)
            storage.addAttribute(.backgroundColor, value: UIColor.compound.bgSubtleSecondary, range: range)
        case .link:
            storage.addAttribute(.foregroundColor, value: UIColor.compound.textLinkExternal, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .dim:
            storage.addAttribute(.foregroundColor, value: UIColor.compound.textSecondary, range: range)
        case .hidden:
            // Still there, so the Markdown is untouched, but too small and clear to see.
            storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.01), range: range)
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
        case .glyph(let glyph):
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
            storage.addAttribute(glyphKey, value: NotePreviewGlyph(glyph), range: range)
            if glyph == .embed {
                // The "!" alone is too narrow for the icon drawn over it.
                storage.addAttribute(.kern, value: 18, range: range)
            }
        }
    }
    
    private static func font(_ style: UIFont.TextStyle, traits: UIFontDescriptor.SymbolicTraits, weight: UIFont.Weight?) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        if let weight {
            return UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
    
    private static func addTraits(_ traits: UIFontDescriptor.SymbolicTraits, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let current = (value as? UIFont) ?? bodyFont
            let combined = current.fontDescriptor.symbolicTraits.union(traits)
            guard let descriptor = current.fontDescriptor.withSymbolicTraits(combined) else { return }
            storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: current.pointSize), range: subrange)
        }
    }
}

private nonisolated extension PreviewRun {
    var isMarker: Bool {
        switch style {
        case .hidden, .glyph: true
        default: false
        }
    }
}

/// A glyph to draw, stored in the text's attributes.
final nonisolated class NotePreviewGlyph: NSObject {
    let glyph: PreviewGlyph
    
    init(_ glyph: PreviewGlyph) {
        self.glyph = glyph
    }
}

/// Draws the preview's glyphs (checkboxes, bullets, quote bars, rules, the embed icon) over the invisible
/// Markdown marks they stand for. Taps there still land on those marks, which is how ticking works.
final nonisolated class NotePreviewLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(NotePreviewStyle.glyphKey, in: characters) { value, range, _ in
            guard let glyph = (value as? NotePreviewGlyph)?.glyph else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            draw(glyph, in: rect, containerWidth: container.size.width - container.lineFragmentPadding * 2 + origin.x)
        }
    }
    
    private func draw(_ glyph: PreviewGlyph, in rect: CGRect, containerWidth: CGFloat) {
        let size = NotePreviewStyle.bodyFont.pointSize
        switch glyph {
        case .checkbox(let checked):
            let configuration = UIImage.SymbolConfiguration(pointSize: size * 1.25, weight: .regular)
            let name = checked ? "checkmark.square.fill" : "square"
            let color = checked ? UIColor.compound.iconAccentTertiary : UIColor.compound.iconSecondary
            guard let image = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
            image.draw(at: CGPoint(x: rect.minX, y: rect.midY - image.size.height / 2))
        case .bullet:
            drawText("•", at: CGPoint(x: rect.minX, y: rect.minY), color: UIColor.compound.textSecondary)
        case .quoteBar:
            UIColor.compound.borderInteractiveSecondary.setFill()
            UIBezierPath(rect: CGRect(x: rect.minX + 2, y: rect.minY, width: 3, height: rect.height)).fill()
        case .rule:
            UIColor.compound.borderInteractiveSecondary.setFill()
            UIBezierPath(rect: CGRect(x: rect.minX, y: rect.midY, width: max(containerWidth - rect.minX, rect.width), height: 1)).fill()
        case .embed:
            let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
            guard let image = UIImage(systemName: "photo", withConfiguration: configuration)?
                .withTintColor(UIColor.compound.iconSecondary, renderingMode: .alwaysOriginal) else { return }
            image.draw(at: CGPoint(x: rect.minX, y: rect.midY - image.size.height / 2))
        }
    }
    
    private func drawText(_ text: String, at point: CGPoint, color: UIColor) {
        NSAttributedString(string: text, attributes: [.font: NotePreviewStyle.bodyFont, .foregroundColor: color]).draw(at: point)
    }
}
