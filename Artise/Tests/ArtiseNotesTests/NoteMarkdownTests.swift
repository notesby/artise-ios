//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

// The same cases as the Android app's NoteLinksTest, ChecklistToggleTest and NoteMarkdownParserTest.

struct NoteLinksTests {
    let paths = ["Súper.md", "Recetas/Mole.md", "Viejo/Recetas/Mole.md", "Fotos/luna.jpg", "Listas/Súper.md"]
    
    /// `[[target#heading|shown text]]` splits into its three parts; the label falls back to the note's name.
    @Test
    func wikiLinkPartsAreParsed() {
        #expect(WikiLink.parse("Recetas/Mole#Salsa|el mole") == WikiLink(target: "Recetas/Mole", heading: "Salsa", shownText: "el mole"))
        #expect(WikiLink.parse("Recetas/Mole").label == "Mole")
    }
    
    /// A bare name finds the note in any folder, preferring the shallowest one, as Obsidian does.
    @Test
    func bareNameFindsTheNoteInAnyFolder() {
        #expect(NoteLinkResolver.resolve("Mole", in: paths) == "Recetas/Mole.md")
    }
    
    /// An exact path wins over a same-named note elsewhere.
    @Test
    func exactPathWins() {
        #expect(NoteLinkResolver.resolve("Listas/Súper", in: paths) == "Listas/Súper.md")
        #expect(NoteLinkResolver.resolve("Súper", in: paths) == "Súper.md")
    }
    
    /// People type without accents or capitals; "super" still finds "Súper.md".
    @Test
    func caseAndAccentsAreIgnored() {
        #expect(NoteLinkResolver.resolve("super", in: paths) == "Súper.md")
    }
    
    /// Links to files keep their extension: `![[luna.jpg]]` finds the photo.
    @Test
    func filesWithAnExtensionResolve() {
        #expect(NoteLinkResolver.resolve("luna.jpg", in: paths) == "Fotos/luna.jpg")
    }
    
    /// A dot inside a name ("Sr. Pérez") doesn't make it a file: the note is still found.
    @Test
    func dotsInNamesStillFindNotes() {
        #expect(NoteLinkResolver.resolve("Sr. Pérez", in: ["Contactos/Sr. Pérez.md"]) == "Contactos/Sr. Pérez.md")
    }
    
    /// A link to a note that doesn't exist yet resolves to nothing, so the app can offer to create it.
    @Test
    func missingNoteResolvesToNil() {
        #expect(NoteLinkResolver.resolve("Leche", in: paths) == nil)
    }
    
    /// Wiki links become Markdown links the parser understands, with the target recoverable from the destination.
    @Test
    func wikiLinksAreRewrittenToMarkdownLinks() {
        let rewritten = WikiLinkRewriter.rewrite("Ver [[Recetas/Mole#Salsa|el mole]] y [[Súper]].")
        
        #expect(rewritten == "Ver [el mole](<\(WikiLinkRewriter.destination("Recetas/Mole"))>) y [Súper](<\(WikiLinkRewriter.destination("Súper"))>).")
        #expect(WikiLinkRewriter.target(of: WikiLinkRewriter.destination("Mis notas/Súper")) == "Mis notas/Súper")
    }
    
    /// Code shows links literally: nothing inside `inline code` or fenced blocks is rewritten.
    @Test
    func codeIsLeftAlone() {
        let lines = WikiLinkRewriter.rewrite("Escribe `[[Nota]]` así.\n```\n[[Nota]]\n```\n[[Nota]]").components(separatedBy: "\n")
        
        #expect(lines[0] == "Escribe `[[Nota]]` así.")
        #expect(lines[2] == "[[Nota]]")
        #expect(lines[4].hasPrefix("[Nota](<"))
    }
    
    /// An embed stays an embed: "![[luna.jpg]]" becomes an image the reading view can show.
    @Test
    func embedsBecomeImages() {
        #expect(WikiLinkRewriter.rewrite("![[luna.jpg]]") == "![luna.jpg](<\(WikiLinkRewriter.destination("luna.jpg"))>)")
    }
    
    /// Ordinary web links are not note links.
    @Test
    func webLinksAreNotNoteTargets() {
        #expect(WikiLinkRewriter.target(of: "https://artise.co") == nil)
    }
}

struct ChecklistToggleTests {
    let note = "# Súper\n- [ ] leche\n- [x] pan\n  - [ ] integral\n1. [ ] pagar\n- normal"
    
    /// Tapping an unticked item ticks it, and a ticked one unticks, changing only that line.
    @Test
    func itemsFlipOnTheirLineOnly() {
        #expect(ChecklistToggle.toggle(note, lineIndex: 1) == note.replacingOccurrences(of: "- [ ] leche", with: "- [x] leche"))
        #expect(ChecklistToggle.toggle(note, lineIndex: 2) == note.replacingOccurrences(of: "- [x] pan", with: "- [ ] pan"))
    }
    
    /// Nested and numbered checklist items work too; a capital X counts as ticked.
    @Test
    func nestedNumberedAndCapitalItems() {
        #expect(ChecklistToggle.toggle(note, lineIndex: 3)?.contains("  - [x] integral") == true)
        #expect(ChecklistToggle.toggle(note, lineIndex: 4)?.contains("1. [x] pagar") == true)
        #expect(ChecklistToggle.toggle("- [X] listo", lineIndex: 0) == "- [ ] listo")
    }
    
    /// Lines that aren't checklist items, or lines that don't exist, change nothing.
    @Test
    func otherLinesAreRefused() {
        #expect(ChecklistToggle.toggle(note, lineIndex: 0) == nil)
        #expect(ChecklistToggle.toggle(note, lineIndex: 5) == nil)
        #expect(ChecklistToggle.toggle(note, lineIndex: 42) == nil)
    }
    
    /// Each parsed item knows its line in the note as written, even after [[links]] are rewritten.
    @Test
    func parsedItemsKnowTheirLine() {
        let document = NoteDocument(markdown: "Ver [[Mole]]\n\n- [ ] leche\n- [ ] [[Pan]]")
        
        guard case let .list(_, _, items) = document.blocks.last else {
            Issue.record("Expected a list")
            return
        }
        #expect(items.map(\.line) == [2, 3])
    }
}

struct NoteDocumentTests {
    /// Checklists keep their ticked state, as families use notes for shopping lists.
    @Test
    func checklistsKeepTheirState() {
        guard case let .list(_, _, items) = NoteDocument(markdown: "- [x] leche\n- [ ] pan").blocks.first else {
            Issue.record("Expected a list")
            return
        }
        #expect(items.map(\.task) == [true, false])
    }
    
    /// Wiki links arrive as links the view can route back to a note.
    @Test
    func wikiLinksBecomeNoteLinks() {
        let blocks = NoteDocument(markdown: "Ver [[Recetas/Mole|el mole]]").blocks
        
        #expect(blocks == [.paragraph([.text([.text("Ver "), .link(.note(target: "Recetas/Mole"), [.text("el mole")])])])])
    }
    
    /// A web address typed as plain text becomes a link the reading view can open.
    @Test
    func plainWebAddressesBecomeLinks() {
        let blocks = NoteDocument(markdown: "Ver https://tienda.mx/ofertas hoy").blocks
        
        guard case let .paragraph(pieces) = blocks.first, case let .text(inlines) = pieces.first else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(inlines.contains(.link(.web("https://tienda.mx/ofertas"), [.text("https://tienda.mx/ofertas")])))
    }
    
    /// Tables are recognised, so they're drawn as rows rather than raw pipes.
    @Test
    func tablesAreParsed() {
        let blocks = NoteDocument(markdown: "| a | b |\n| --- | --- |\n| 1 | 2 |").blocks
        
        #expect(blocks == [.table(rows: [[[.text("a")], [.text("b")]], [[.text("1")], [.text("2")]]])])
    }
    
    /// A photo embedded in a paragraph shows in place, with the text around it kept.
    @Test
    func embedsSplitTheirParagraph() {
        let blocks = NoteDocument(markdown: "Hoy:\n![[foto.jpg]]\nqué bonito").blocks
        
        #expect(blocks == [.paragraph([.text([.text("Hoy:")]), .embed(target: "foto.jpg"), .text([.text("qué bonito")])])])
    }
    
    /// Headings, quotes, code and dividers come through as their own blocks.
    @Test
    func blockKindsAreRecognised() {
        let blocks = NoteDocument(markdown: "# Título\n\n> cita\n\n```\ncódigo\n```\n\n---").blocks
        
        #expect(blocks == [.heading(level: 1, text: [.text("Título")]),
                           .quote([.paragraph([.text([.text("cita")])])]),
                           .code("código"),
                           .divider])
    }
    
    /// A relative path is a file in the chat; "www." is the web.
    @Test
    func linksAreClassified() {
        #expect(NoteDocument.classify("Fotos/luna.jpg") == .note(target: "Fotos/luna.jpg"))
        #expect(NoteDocument.classify("www.artise.co") == .web("https://www.artise.co"))
        #expect(NoteDocument.classify("https://artise.co") == .web("https://artise.co"))
    }
}

struct AutolinkTests {
    /// Trailing punctuation and an unmatched ")" stay outside the link, as on GitHub.
    @Test
    func punctuationAfterAnAddressIsText() {
        #expect(NoteDocument.autolinked("(ver www.artise.co).") == [.text("(ver "), .link(.web("https://www.artise.co"), [.text("www.artise.co")]), .text(").")])
        #expect(NoteDocument.autolinked("sin enlaces") == [.text("sin enlaces")])
    }
    
    /// An address that's already a link's text isn't linked twice.
    @Test
    func linkTextIsNotLinkedAgain() {
        let blocks = NoteDocument(markdown: "[https://a.mx](https://b.mx)").blocks
        
        #expect(blocks == [.paragraph([.text([.link(.web("https://b.mx"), [.text("https://a.mx")])])])])
    }
}
