//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

struct NoteEditorModelTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    
    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }
    
    /// Typing without a pause is one undo step; after a pause, a new step starts.
    @Test
    func typingGroupsIntoUndoSteps() {
        var model = NoteEditorModel(text: "")
        model.viewChanged(text: "p", selection: 1..<1, now: at(0))
        model.viewChanged(text: "pa", selection: 2..<2, now: at(0.3))
        model.viewChanged(text: "pan", selection: 3..<3, now: at(0.6))
        model.viewChanged(text: "pan y", selection: 5..<5, now: at(3))
        
        model.undo()
        #expect(model.text == "pan")
        model.undo()
        #expect(model.text == "")
        #expect(!model.canUndo)
        
        model.redo()
        model.redo()
        #expect(model.text == "pan y")
        #expect(!model.canRedo)
    }
    
    /// Formatting is a step of its own, and a new change clears what could be redone.
    @Test
    func formattingIsItsOwnStep() {
        var model = NoteEditorModel(text: "pan")
        model.viewChanged(text: "pan", selection: 0..<3, now: at(0))
        model.format(.bold, now: at(0.1))
        #expect(model.text == "**pan**")
        #expect(model.selection == 2..<5)
        
        model.undo()
        #expect(model.text == "pan")
        model.viewChanged(text: "pan!", selection: 4..<4, now: at(5))
        #expect(!model.canRedo)
    }
    
    /// Enter on a list item continues the list, and the text view gets the new text back.
    @Test
    func enterContinuesTheList() {
        var model = NoteEditorModel(text: "- leche")
        
        let changed = model.viewChanged(text: "- leche\n", selection: 8..<8, now: at(0))
        
        #expect(changed)
        #expect(model.text == "- leche\n- ")
        #expect(model.selection == 10..<10)
    }
    
    /// A tap on the checkbox of a formatted line ticks it instead of moving the cursor.
    @Test
    func tappingABoxTicksIt() {
        var model = NoteEditorModel(text: "intro\n- [ ] pan")
        model.viewChanged(text: model.text, selection: 0..<0, now: at(0))
        
        let changed = model.viewChanged(text: model.text, selection: 8..<8, now: at(1))
        
        #expect(changed)
        #expect(model.text == "intro\n- [x] pan")
        #expect(model.selection == 0..<0)
    }
    
    /// A tap on the line being edited only moves the cursor, so the Markdown can be edited by hand.
    @Test
    func tapsOnTheRawLineMoveTheCursor() {
        var model = NoteEditorModel(text: "- [ ] pan")
        
        model.viewChanged(text: model.text, selection: 3..<3, now: at(0))
        
        #expect(model.text == "- [ ] pan")
        #expect(model.selection == 3..<3)
    }
    
    /// A tap on a link's text opens the link dialog; saving writes the new link and keeps the cursor around it.
    @Test
    func tappingALinkEditsIt() {
        var model = NoteEditorModel(text: "intro\nVer [[Súper]] hoy")
        model.viewChanged(text: model.text, selection: 0..<0, now: at(0))
        
        model.viewChanged(text: model.text, selection: 14..<14, now: at(1))
        #expect(model.linkEdit?.link == EditableLink(isNote: true, target: "Súper", shownText: ""))
        
        model.saveLink(EditableLink(isNote: true, target: "Súper", shownText: "la lista"), now: at(2))
        #expect(model.text == "intro\nVer [[Súper|la lista]] hoy")
        #expect(model.linkEdit == nil)
    }
    
    /// Removing a link keeps the words people saw.
    @Test
    func removingALinkKeepsItsWords() {
        var model = NoteEditorModel(text: "x\n[web](https://artise.co)")
        model.viewChanged(text: model.text, selection: 0..<0, now: at(0))
        model.viewChanged(text: model.text, selection: 4..<4, now: at(1))
        
        model.removeLink(now: at(2))
        
        #expect(model.text == "x\nweb")
    }
    
    /// The web link button opens the dialog with the selected words; saving puts the cursor after the link.
    @Test
    func newWebLinks() {
        var model = NoteEditorModel(text: "ver tienda")
        model.viewChanged(text: model.text, selection: 4..<10, now: at(0))
        model.format(.webLink, now: at(1))
        #expect(model.linkEdit?.link.shownText == "tienda")
        
        model.saveLink(EditableLink(isNote: false, target: "https://tienda.mx", shownText: "tienda"), now: at(2))
        
        #expect(model.text == "ver [tienda](https://tienda.mx)")
        #expect(model.selection == 31..<31)
    }
    
    /// Typing "[[" opens suggestions; choosing one completes the link.
    @Test
    func choosingASuggestionCompletesTheLink() {
        var model = NoteEditorModel(text: "")
        model.viewChanged(text: "Ver [[sú", selection: 8..<8, now: at(0))
        #expect(model.openLink?.query == "sú")
        
        model.choose(WikiLinkSuggestion(name: "Súper", path: "Súper.md", linkText: "Súper"), now: at(1))
        
        #expect(model.text == "Ver [[Súper]]")
        #expect(model.openLink == nil)
    }
    
    /// Combining a conflict starts with both versions and counts as a change until it's saved.
    @Test
    func combiningStartsWithBothVersions() {
        let model = NoteEditorModel(mine: "- leche", theirs: "- pan")
        
        #expect(model.text == "- leche\n\n———\n\n- pan")
        #expect(model.hasChanges)
        #expect(model.isResolvingConflict)
    }
    
    /// An unchanged note has nothing to save; undoing every change brings it back to unchanged.
    @Test
    func changesAreTracked() {
        var model = NoteEditorModel(text: "pan")
        #expect(!model.hasChanges)
        model.viewChanged(text: "pan y", selection: 5..<5, now: at(0))
        #expect(model.hasChanges)
        model.undo()
        #expect(!model.hasChanges)
    }
    
    /// A layout change replaces the text in one step that undo takes back.
    @Test
    func replacingTheTextIsOneUndoStep() {
        var model = NoteEditorModel(text: "a\nb")
        
        model.replaceText("b\na", now: .now)
        
        #expect(model.text == "b\na")
        #expect(model.hasChanges)
        model.undo()
        #expect(model.text == "a\nb")
    }
}
