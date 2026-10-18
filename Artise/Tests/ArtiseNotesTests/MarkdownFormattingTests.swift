//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

// The same cases as the Android app's MarkdownFormattingTest.

struct MarkdownFormattingTests {
    func apply(_ action: FormatAction, _ text: String, _ start: Int, _ end: Int? = nil) -> EditedText {
        MarkdownFormatting.apply(action, to: text, start: start, end: end ?? start)
    }
    
    /// Bold wraps the selection and keeps it selected; pressing again removes it.
    @Test
    func boldTogglesAroundASelection() {
        let bold = apply(.bold, "comprar pan hoy", 8, 11)
        #expect(bold == EditedText(text: "comprar **pan** hoy", start: 10, end: 13))
        #expect(apply(.bold, bold.text, bold.start, bold.end) == EditedText(text: "comprar pan hoy", start: 8, end: 11))
    }
    
    /// With no selection, an empty pair is inserted and the cursor goes between, ready to type.
    @Test
    func wrapWithACursorInsertsAPair() {
        #expect(apply(.italic, "hola ", 5) == EditedText(text: "hola **", start: 6, end: 6))
        #expect(apply(.strikethrough, "", 0) == EditedText(text: "~~~~", start: 2, end: 2))
    }
    
    /// Italic inside bold text adds its own marker instead of removing half of the bold one.
    @Test
    func italicDoesNotEatBold() {
        #expect(apply(.italic, "**pan**", 2, 5).text == "***pan***")
    }
    
    /// The heading button cycles # → ## → ### → none on the cursor's line.
    @Test
    func headingCycles() {
        let h1 = apply(.heading, "intro\nMole", 8)
        #expect(h1 == EditedText(text: "intro\n# Mole", start: 10, end: 10))
        let h2 = apply(.heading, h1.text, h1.start)
        #expect(h2.text == "intro\n## Mole")
        let h3 = apply(.heading, h2.text, h2.start)
        #expect(h3.text == "intro\n### Mole")
        #expect(apply(.heading, h3.text, h3.start).text == "intro\nMole")
    }
    
    /// A list applies to every selected line, numbered in order, and blank lines stay blank.
    @Test
    func listsApplyToSelectedLines() {
        let text = "leche\npan\n\nhuevos"
        #expect(apply(.numberedList, text, 0, text.utf16.count).text == "1. leche\n2. pan\n\n3. huevos")
        #expect(apply(.checklist, "leche\npan", 0, 9).text == "- [ ] leche\n- [ ] pan")
    }
    
    /// Pressing the same list button again removes it; another list kind replaces it.
    @Test
    func listsToggleAndSwitch() {
        #expect(apply(.bulletList, "- leche\n- pan", 0, 13).text == "leche\npan")
        #expect(apply(.checklist, "- leche", 3).text == "- [ ] leche")
        #expect(apply(.quote, "1. leche", 4).text == "> leche")
    }
    
    /// With a cursor, a list button changes only its line and keeps the cursor on the same word.
    @Test
    func listWithACursorKeepsItsPlace() {
        #expect(apply(.bulletList, "uno\ndos", 5) == EditedText(text: "uno\n- dos", start: 7, end: 7))
    }
    
    /// The link button types "[[" so the note suggestions appear.
    @Test
    func noteLinkOpensSuggestions() {
        #expect(apply(.noteLink, "Ver ", 4) == EditedText(text: "Ver [[", start: 6, end: 6))
    }
    
    /// Enter continues a list: same bullet, next number, a new unticked checkbox, keeping indentation.
    @Test
    func enterContinuesLists() {
        #expect(MarkdownFormatting.continueListOnEnter("- leche", cursor: 7) == EditedText(text: "- leche\n- ", start: 10, end: 10))
        #expect(MarkdownFormatting.continueListOnEnter("3. pan", cursor: 6)?.text == "3. pan\n4. ")
        #expect(MarkdownFormatting.continueListOnEnter("- [x] leche", cursor: 11)?.text == "- [x] leche\n- [ ] ")
        #expect(MarkdownFormatting.continueListOnEnter("  - sub", cursor: 7)?.text == "  - sub\n  - ")
    }
    
    /// Enter on an empty item ends the list; ordinary lines are left to the normal newline.
    @Test
    func enterOnAnEmptyItemEndsTheList() {
        #expect(MarkdownFormatting.continueListOnEnter("- leche\n- ", cursor: 10) == EditedText(text: "- leche\n", start: 8, end: 8))
        #expect(MarkdownFormatting.continueListOnEnter("hola", cursor: 4) == nil)
    }
    
    /// Offsets are UTF-16, like iOS text views: an emoji before the selection counts as two.
    @Test
    func offsetsAreUTF16() {
        #expect(apply(.bold, "🥑 pan", 3, 6) == EditedText(text: "🥑 **pan**", start: 5, end: 8))
    }
}
