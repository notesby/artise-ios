//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

struct LivePreviewTests {
    /// Bold text shows bold, and its ** marks are hidden.
    @Test
    func boldHidesItsMarks() {
        #expect(LivePreview.runs(for: "**pan**", rawLines: nil) == [PreviewRun(0, 2, .hidden), PreviewRun(2, 5, .bold), PreviewRun(5, 7, .hidden)])
    }
    
    /// A heading's # is hidden and its text styled by level (### and deeper share level 3).
    @Test
    func headingsHideTheirHashes() {
        #expect(LivePreview.runs(for: "# Mole", rawLines: nil) == [PreviewRun(0, 2, .hidden), PreviewRun(2, 6, .heading(level: 1))])
        #expect(LivePreview.runs(for: "#### Nota", rawLines: nil).contains(PreviewRun(5, 9, .heading(level: 3))))
    }
    
    /// A checklist item draws a box over "- [x] ", and a ticked item's text is dimmed.
    @Test
    func checklistItemsDrawABox() {
        #expect(LivePreview.runs(for: "- [x] leche", rawLines: nil) == [PreviewRun(0, 6, .glyph(.checkbox(checked: true))), PreviewRun(6, 11, .dim)])
        #expect(LivePreview.runs(for: "  - [ ] pan", rawLines: nil) == [PreviewRun(2, 8, .glyph(.checkbox(checked: false)))])
    }
    
    /// The line being edited shows as written; the others stay formatted.
    @Test
    func rawLinesShowAsWritten() {
        let runs = LivePreview.runs(for: "**a**\n**b**", rawLines: 0...0)
        #expect(runs.allSatisfy { $0.start >= 6 })
        #expect(runs.contains(PreviewRun(8, 9, .bold)))
    }
    
    /// A wiki link shows only its shown text (or the note's name), as a link; an embed gets its mark.
    @Test
    func wikiLinksShowTheirLabel() {
        #expect(LivePreview.runs(for: "[[Recetas/Mole|el mole]]", rawLines: nil)
            == [PreviewRun(0, 15, .hidden), PreviewRun(15, 22, .link), PreviewRun(22, 24, .hidden)])
        #expect(LivePreview.runs(for: "[[Recetas/Mole]]", rawLines: nil)
            == [PreviewRun(0, 10, .hidden), PreviewRun(10, 14, .link), PreviewRun(14, 16, .hidden)])
        #expect(LivePreview.runs(for: "![[foto.jpg]]", rawLines: nil).first == PreviewRun(0, 1, .glyph(.embed)))
    }
    
    /// The cursor anywhere in a code block or table shows the whole block raw.
    @Test
    func codeBlocksAndTablesShowRawAsAWhole() {
        let text = "intro\n```\nlet a = 1\n```\nfin"
        #expect(LivePreview.rawLines(in: text, selectionStart: 12, selectionEnd: 12) == 1...3)
        let table = "| a | b |\n| --- | --- |\n| 1 | 2 |"
        #expect(LivePreview.rawLines(in: table, selectionStart: 30, selectionEnd: 30) == 0...2)
    }
    
    /// Outside the cursor, fences disappear and the code shows in the code style.
    @Test
    func fencesHideAndCodeIsStyled() {
        #expect(LivePreview.runs(for: "```\nx\n```", rawLines: nil) == [PreviewRun(0, 3, .hidden), PreviewRun(4, 5, .code), PreviewRun(6, 9, .hidden)])
    }
    
    /// Taps on a checkbox tick it; taps on a link's text open it for editing.
    @Test
    func tapsLandOnBoxesAndLinks() {
        #expect(LivePreview.hit(in: "uno\n- [ ] pan", at: 6) == .checkbox(line: 1))
        #expect(LivePreview.hit(in: "Ver [[Súper|la lista]]", at: 14)
            == .link(start: 4, end: 22, link: EditableLink(isNote: true, target: "Súper", shownText: "la lista")))
        #expect(LivePreview.hit(in: "[mapa](https://maps.mx)", at: 2)
            == .link(start: 0, end: 23, link: EditableLink(isNote: false, target: "https://maps.mx", shownText: "mapa")))
        #expect(LivePreview.hit(in: "nada aquí", at: 2) == nil)
    }
    
    /// A link edited in the dialog is written back as Markdown, and removing it leaves the words people saw.
    @Test
    func editableLinksRoundTrip() {
        #expect(EditableLink(isNote: true, target: "Súper", shownText: "").markdown == "[[Súper]]")
        #expect(EditableLink(isNote: true, target: "Súper", shownText: "la lista").markdown == "[[Súper|la lista]]")
        #expect(EditableLink(isNote: false, target: "https://a.mx", shownText: "").markdown == "https://a.mx")
        #expect(EditableLink(isNote: false, target: "https://a.mx", shownText: "tienda").markdown == "[tienda](https://a.mx)")
        #expect(EditableLink(isNote: true, target: "Recetas/Mole#Salsa", shownText: "").label == "Mole")
    }
}

/// The same cases as the Android app's LivePreviewTest, on what people see.
struct LivePreviewAndroidTests {
    let note = "# Súper\n- [ ] leche\n- [x] **pan** integral\nVer [[Recetas/Mole|el mole]] y [web](https://artise.co)"
    
    func shown(_ text: String, _ raw: ClosedRange<Int>?) -> String {
        LivePreview.visibleText(text, runs: LivePreview.runs(for: text, rawLines: raw))
    }
    
    /// Lines away from the cursor show formatted with their marks hidden; the cursor's line shows as written.
    @Test
    func otherLinesAreFormattedAndTheCursorLineIsRaw() {
        #expect(shown(note, 1...1) == "Súper\n- [ ] leche\n☑ pan integral\nVer el mole y web")
        #expect(shown(note, 2...2) == "Súper\n☐ leche\n- [x] **pan** integral\nVer el mole y web")
    }
    
    /// Code blocks hide their fences until the cursor is inside; then the whole block shows raw.
    @Test
    func codeBlocks() {
        let text = "Antes\n```\nx = 1\n```\nDespués"
        #expect(shown(text, 0...0) == "Antes\n\nx = 1\n\nDespués")
        #expect(LivePreview.rawLines(in: text, selectionStart: 10, selectionEnd: 10) == 1...3)
    }
    
    /// Tables show as rows; with the cursor in one row, the whole table shows raw.
    @Test
    func tables() {
        let text = "| Paso | Tiempo |\n| --- | --- |\n| Freír | 10 |\nFin"
        #expect(shown(text, 3...3) == text)
        #expect(LivePreview.rawLines(in: text, selectionStart: 34, selectionEnd: 34) == 0...2)
        #expect(LivePreview.runs(for: text, rawLines: 3...3).contains(PreviewRun(0, 17, .bold)))
    }
    
    /// Lists, quotes and headings show clean markers; italics and inline code lose their marks.
    @Test
    func otherFormatting() {
        #expect(shown("## Plan\n- uno\n> cita\n*nota* y `code`\n1. primero", 4...4) == "Plan\n• uno\n▍ cita\nnota y code\n1. primero")
    }
    
    /// Web addresses typed as plain text show as links, and their text isn't changed.
    @Test
    func bareWebAddresses() {
        let text = "Compras en https://tienda.mx/ofertas. Y www.artise.co\nfin"
        #expect(shown(text, 1...1) == text)
        #expect(LivePreview.runs(for: text, rawLines: 1...1).contains(PreviewRun(11, 36, .link)))
        #expect(LivePreview.hit(in: text, at: 20) == .link(start: 11, end: 36, link: EditableLink(isNote: false, target: "https://tienda.mx/ofertas", shownText: "")))
    }
    
    /// An address inside [text](address) is part of that link, not a second one.
    @Test
    func addressesInMarkdownLinksAreNotSeparateLinks() {
        #expect(shown("[web](https://artise.co)", 1...1) == "web")
    }
}
