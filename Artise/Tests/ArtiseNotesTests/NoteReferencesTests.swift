//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

// The same cases as the Android app's NoteReferencesTest and NoteEmbedRemoverTest.

struct NoteReferencesTests {
    let paths = ["Recetas/Mole.md", "attachments/luna.jpg", "attachments/factura.pdf", "Viajes/2026/luna.jpg", "attachments/sol.png"]
    
    /// Shown photos, linked files and Markdown images count; notes and web addresses don't.
    @Test
    func whatCountsAsUsingAFile() {
        let note = "![[luna.jpg]]\nVer [[factura.pdf|la factura]] y [[Mole]].\n![](attachments/sol.png) [web](https://artise.co/x.png)"
        
        #expect(NoteReferences.filesUsed(in: note, paths: paths) == ["attachments/luna.jpg", "attachments/factura.pdf", "attachments/sol.png"])
    }
    
    /// The index says which notes use each file, each note once.
    @Test
    func indexOfUses() {
        let index = NoteReferences.index(notes: [("B.md", "![[luna.jpg]] ![[luna.jpg]]"), ("A.md", "[[luna.jpg]]"), ("C.md", "nada")], paths: paths)
        
        #expect(index == ["attachments/luna.jpg": ["A.md", "B.md"]])
    }
    
    /// Removing: a shown photo goes with its line, a link keeps its words, other files stay.
    @Test
    func removingAFileFromANote() {
        let note = "Hoy\n\n![[luna.jpg]]\n\nVer [[luna.jpg|la foto]] y [luna](attachments/luna.jpg).\n![[factura.pdf]]"
        
        #expect(NoteReferences.remove("attachments/luna.jpg", from: note, paths: paths) == "Hoy\n\nVer la foto y luna.\n![[factura.pdf]]")
        // A name that means another file here (the path is written out) is left alone.
        #expect(NoteReferences.remove("attachments/luna.jpg", from: "![[Viajes/2026/luna.jpg]]", paths: paths) == "![[Viajes/2026/luna.jpg]]")
    }
    
    /// Embeds resolve to the chat's files; notes and web images aren't embeds.
    @Test
    func embedsResolveToFiles() {
        #expect(NoteEmbeds.resolve("![[luna.jpg]] ![[Mole]] ![](https://x.mx/a.png)", paths: paths) == ["luna.jpg": "attachments/luna.jpg"])
    }
}

struct NoteEmbedRemoverTests {
    /// An embed on its own line goes with the gap next to it.
    @Test
    func anEmbedOnItsOwnLineGoesWithItsGap() {
        #expect(NoteEmbedRemover.remove("attachments/luna.jpg", from: "Hoy\n\n![[luna.jpg]]\n\nfin") == "Hoy\n\nfin")
        #expect(NoteEmbedRemover.remove("attachments/luna.jpg", from: "Hoy\n\n![[luna.jpg]]\n\n") == "Hoy\n\n")
        #expect(NoteEmbedRemover.remove("attachments/luna.jpg", from: "Hoy\n\n![[luna.jpg]]") == "Hoy")
    }
    
    /// Paths, sizes and embeds inside a sentence are removed too.
    @Test
    func pathsSizesAndEmbedsInsideText() {
        #expect(NoteEmbedRemover.remove("attachments/luna.jpg", from: "![[attachments/luna.jpg|300]]\n\nfin") == "fin")
        #expect(NoteEmbedRemover.remove("attachments/luna.jpg", from: "Mira ![[luna.jpg]] qué bonita") == "Mira qué bonita")
    }
    
    /// Other embeds and plain links stay.
    @Test
    func otherEmbedsAndLinksStay() {
        let content = "![[sol.jpg]]\n\nVer [[luna.jpg]]"
        #expect(NoteEmbedRemover.remove("attachments/luna.jpg", from: content) == content)
    }
}
