//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

// The same cases as the Android app's WikiLinkSuggestionsTest.

struct WikiLinkSuggestionsTests {
    let paths = ["Súper.md", "Recetas/Mole.md", "Viejo/Mole.md", "Recetas/Sopa.md", "Fotos/luna.jpg"]
    
    /// Typing "[[mo" at the end of a line opens a link with query "mo".
    @Test
    func openLinkIsFoundAtTheCursor() {
        let text = "Ver [[mo"
        #expect(WikiLinkSuggestions.openLink(in: text, cursor: text.utf16.count) == OpenWikiLink(start: 6, query: "mo"))
    }
    
    /// A finished link, a heading or shown text, or a link on an earlier line doesn't trigger suggestions.
    @Test
    func closedLinksAndOtherLinesAreIgnored() {
        #expect(WikiLinkSuggestions.openLink(in: "[[Súper]] y", cursor: 11) == nil)
        #expect(WikiLinkSuggestions.openLink(in: "[[Súper#Lác", cursor: 11) == nil)
        #expect(WikiLinkSuggestions.openLink(in: "[[Súper|la", cursor: 10) == nil)
        #expect(WikiLinkSuggestions.openLink(in: "[[Sú\nhola", cursor: 9) == nil)
    }
    
    /// Suggestions ignore accents, put names starting with the query first, and skip photos and the note itself.
    @Test
    func suggestionsMatchNames() {
        let names = WikiLinkSuggestions.suggestions(for: "s", notePaths: paths, currentPath: "Recetas/Sopa.md").map(\.name)
        #expect(names == ["Súper", "Mole"])
        #expect(WikiLinkSuggestions.suggestions(for: "super", notePaths: paths, currentPath: nil).map(\.path) == ["Súper.md"])
        #expect(WikiLinkSuggestions.suggestions(for: "luna", notePaths: paths, currentPath: nil).isEmpty)
    }
    
    /// A name used in two folders is linked by path with the name shown, so the link points at the right note and reads the same.
    @Test
    func duplicateNamesLinkByPath() {
        let moles = WikiLinkSuggestions.suggestions(for: "mole", notePaths: paths, currentPath: nil)
        #expect(moles.map(\.linkText) == ["Recetas/Mole|Mole", "Viejo/Mole|Mole"])
        #expect(moles.map(\.detail) == ["Recetas", "Viejo"])
        #expect(WikiLinkSuggestions.suggestions(for: "sopa", notePaths: paths, currentPath: nil).map(\.linkText) == ["Sopa"])
    }
    
    /// A page is found by any of its aliases, and the link keeps the alias as the shown text: `[[Ana|Mamá]]`.
    @Test
    func aliasesAreSuggestedWithTheirPage() {
        let ana = NotesPage(path: "people/Ana.md", title: "Ana", type: "person", folder: "people", aliases: ["Mamá", "Mother"],
                            summary: "Hector's mother", isNote: true)
        let index = PageIndex(paths: ["people/Ana.md", "Súper.md"], pages: [ana])
        
        let suggestions = WikiLinkSuggestions.suggestions(for: "ma", index: index, currentPath: nil)
        
        #expect(suggestions.map(\.name) == ["Mamá"])
        #expect(suggestions.first?.linkText == "Ana|Mamá")
        #expect(suggestions.first?.detail == "Ana")
        #expect(WikiLinkSuggestions.suggestions(for: "an", index: index, currentPath: nil).map(\.linkText) == ["Ana"])
    }
    
    /// Two pages with one title show their folder and summary, and link by path; a photo with a page is suggested after notes.
    @Test
    func sharedTitlesShowWhatTellsThemApart() {
        let pages = [NotesPage(path: "people/Ana.md", title: "Ana", type: "person", folder: "people", aliases: ["Mamá"], summary: "Hector's mother", isNote: true),
                     NotesPage(path: "clients/Ana.md", title: "Ana", type: "client", folder: "clients", aliases: [], summary: "Buys cakes", isNote: true),
                     NotesPage(path: "Fotos/ana.jpg", title: "ana.jpg", type: "image", folder: "Fotos", aliases: [], summary: "", isNote: false)]
        let index = PageIndex(paths: ["people/Ana.md", "clients/Ana.md", "Fotos/ana.jpg"], pages: pages)
        
        let suggestions = WikiLinkSuggestions.suggestions(for: "ana", index: index, currentPath: nil)
        
        #expect(suggestions.map(\.linkText) == ["clients/Ana|Ana", "people/Ana|Ana", "ana.jpg"])
        #expect(suggestions.map(\.detail) == ["clients · Buys cakes", "people · Hector's mother", nil])
        #expect(WikiLinkSuggestions.suggestions(for: "mam", index: index, currentPath: nil).map(\.linkText) == ["people/Ana|Mamá"])
    }
    
    /// Choosing a suggestion completes the link and puts the cursor after "]]", swallowing a "]]" already typed.
    @Test
    func completingInsertsTheLink() throws {
        let suggestion = WikiLinkSuggestion(name: "Súper", path: "Súper.md", linkText: "Súper")
        let text = "Ver [[sú y más"
        let link = try #require(WikiLinkSuggestions.openLink(in: text, cursor: 8))
        #expect(WikiLinkSuggestions.complete(text, link: link, cursor: 8, with: suggestion) == EditedText(text: "Ver [[Súper]] y más", start: 13, end: 13))
        
        let typed = "Ver [[sú]]"
        let typedLink = try #require(WikiLinkSuggestions.openLink(in: typed, cursor: 8))
        #expect(WikiLinkSuggestions.complete(typed, link: typedLink, cursor: 8, with: suggestion).text == "Ver [[Súper]]")
    }
}
