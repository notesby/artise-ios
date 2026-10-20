//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

struct NoteFrontmatterTests {
    /// The header's type, aliases (inline or as a list) and summary are read, quotes dropped, and the body is what's left.
    @Test
    func headerFieldsAreRead() {
        let inline = "---\ntype: person\naliases: [Mamá, \"Mother\"]\nsummary: 'Ana, Hector''s mother'\n---\nVive en Monterrey"
        let listed = "---\ntype: place\naliases:\n  - La casa\n  - Casa de Ana\n---\n\n# Casa"
        
        let (header, body) = NoteFrontmatter.split(inline)
        #expect(header == NoteFrontmatter(type: "person", aliases: ["Mamá", "Mother"], summary: "Ana, Hector''s mother"))
        #expect(body == "Vive en Monterrey")
        #expect(NoteFrontmatter.split(listed).header == NoteFrontmatter(type: "place", aliases: ["La casa", "Casa de Ana"], summary: nil))
        #expect(NoteFrontmatter.split(listed).body == "\n# Casa")
    }
    
    /// A note that doesn't start with `---`, or never closes it, has no header and keeps every line.
    @Test
    func notesWithoutAHeaderAreUntouched() {
        #expect(NoteFrontmatter.split("Hola\n---\ntype: x\n---").header == nil)
        #expect(NoteFrontmatter.split("---\ntype: person\nsin cierre").header == nil)
        #expect(NoteFrontmatter.split("---\ntype: person\nsin cierre").body == "---\ntype: person\nsin cierre")
        #expect(NoteFrontmatter.split("").header == nil)
    }
    
    /// The document keeps the header apart, so its first line doesn't become a heading, and an empty header shows no fields.
    @Test
    func theDocumentKeepsTheHeaderApart() {
        let document = NoteDocument(markdown: "---\ntype: person\naliases: [Mamá]\n---\nVive en Monterrey")
        
        #expect(document.frontmatter?.type == "person")
        #expect(document.frontmatter?.hasFields == true)
        #expect(document.blocks == [.paragraph([.text([.text("Vive en Monterrey")])])])
        #expect(NoteDocument(markdown: "---\ncreated: 2026\n---\nHola").frontmatter?.hasFields == false)
    }
}
