//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A link being edited in the link dialog: where it sits in the note, and whether it's new.
public struct LinkEditState: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let link: EditableLink
    public let isNew: Bool
}

/// The editor's behaviour, the same as the Android app's: typing, the toolbar, Enter in lists, taps on formatted
/// lines, `[[` suggestions, links, ticks, and undo/redo. The screen only shows it and passes events in.
public struct NoteEditorModel: Equatable, Sendable {
    /// A pause in typing this long starts a new undo step.
    public static let typingPause: TimeInterval = 1
    /// Undo reaches back this many steps.
    public static let maxUndoSteps = 100
    /// Between this phone's version and the other person's when combining: a plain line, clear in any language.
    public static let conflictSeparator = "\n\n———\n\n"
    
    public private(set) var text: String
    /// The selection, in UTF-16 offsets.
    public private(set) var selection: Range<Int>
    public private(set) var linkEdit: LinkEditState?
    public let isResolvingConflict: Bool
    
    private let original: String
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var lastTypingAt: Date?
    
    private struct Snapshot: Equatable, Sendable {
        let text: String
        let selection: Range<Int>
    }
    
    /// Editing a note's text, with the cursor at the end.
    public init(text: String) {
        self.text = text
        original = text
        selection = text.utf16Length..<text.utf16Length
        isResolvingConflict = false
    }
    
    /// Combining a conflict: this phone's version, a line, then the other person's.
    public init(mine: String?, theirs: String?) {
        let combined = [mine, theirs].compactMap { $0 }.joined(separator: Self.conflictSeparator)
        text = combined
        original = combined
        selection = combined.utf16Length..<combined.utf16Length
        isResolvingConflict = true
    }
    
    /// A combined text is unsaved from the start: the choice isn't made until it's saved.
    public var hasChanges: Bool {
        isResolvingConflict || text != original
    }
    
    public var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    public var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    /// The lines shown as written; every other line shows formatted.
    public var rawLines: ClosedRange<Int> {
        LivePreview.rawLines(in: text, selectionStart: selection.lowerBound, selectionEnd: selection.upperBound)
    }
    
    /// The `[[…` being typed, if the cursor is in one.
    public var openLink: OpenWikiLink? {
        selection.isEmpty ? WikiLinkSuggestions.openLink(in: text, cursor: selection.lowerBound) : nil
    }
    
    // MARK: - Events
    
    /// The text or selection changed in the text view. Returns the text and selection the view should show,
    /// which differ from what it sent when Enter continued a list or a tap ticked a checkbox.
    @discardableResult
    public mutating func viewChanged(text newText: String, selection newSelection: Range<Int>, now: Date) -> Bool {
        // Enter on a list line continues the list, or ends it on an empty item.
        if let continued = continuedList(newText: newText, newSelection: newSelection) {
            commit(continued.text, continued.start..<continued.end, isTyping: false, now: now)
            return true
        }
        // A tap on a formatted line: its checkbox ticks, its link opens the link dialog, anything else moves the cursor.
        if newText == text, newSelection.isEmpty, newSelection != selection {
            let line = newText.lineNumber(at: newSelection.lowerBound)
            if !rawLines.contains(line) {
                switch LivePreview.hit(in: newText, at: newSelection.lowerBound) {
                case .checkbox(let line):
                    // "[ ]" and "[x]" are the same length, so the cursor stays where it was.
                    if let ticked = ChecklistToggle.toggle(text, lineIndex: line) {
                        commit(ticked, selection, isTyping: false, now: now)
                    }
                    return true
                case .link(let start, let end, let link):
                    linkEdit = LinkEditState(start: start, end: end, link: link, isNew: false)
                    return true
                case nil:
                    break
                }
            }
        }
        commit(newText, newSelection, isTyping: true, now: now)
        return false
    }
    
    public mutating func format(_ action: FormatAction, now: Date) {
        if action == .webLink {
            let shown = text.utf16Slice(selection.lowerBound, selection.upperBound)
            linkEdit = LinkEditState(start: selection.lowerBound, end: selection.upperBound,
                                     link: EditableLink(isNote: false, target: "", shownText: shown), isNew: true)
            return
        }
        let edited = MarkdownFormatting.apply(action, to: text, start: selection.lowerBound, end: selection.upperBound)
        commit(edited.text, edited.start..<edited.end, isTyping: false, now: now)
    }
    
    public mutating func choose(_ suggestion: WikiLinkSuggestion, now: Date) {
        guard let link = openLink else { return }
        let completed = WikiLinkSuggestions.complete(text, link: link, cursor: selection.lowerBound, with: suggestion)
        commit(completed.text, completed.start..<completed.end, isTyping: false, now: now)
    }
    
    /// Ticks a checklist item from somewhere other than the text (the preview).
    public mutating func toggleTask(line: Int, now: Date) {
        if let ticked = ChecklistToggle.toggle(text, lineIndex: line) {
            commit(ticked, selection, isTyping: false, now: now)
        }
    }
    
    public mutating func saveLink(_ link: EditableLink, now: Date) {
        guard let edit = linkEdit else { return }
        replaceLink(edit, with: link.markdown, now: now)
    }
    
    /// Removes the link, keeping the words people saw.
    public mutating func removeLink(now: Date) {
        guard let edit = linkEdit else { return }
        replaceLink(edit, with: edit.link.label, now: now)
    }
    
    public mutating func dismissLinkEdit() {
        linkEdit = nil
    }
    
    /// Inserts text where the cursor is (an embed, for example) as a step of its own.
    public mutating func insert(_ inserted: String, now: Date) {
        let newText = text.replacingUTF16(selection.lowerBound, selection.upperBound, with: inserted)
        let cursor = selection.lowerBound + inserted.utf16Length
        commit(newText, cursor..<cursor, isTyping: false, now: now)
    }
    
    /// Moves the selection without changing the text or the undo history: the search's current match.
    public mutating func select(_ range: Range<Int>) {
        selection = Self.clamped(range, in: text)
    }
    
    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(text: text, selection: selection))
        restore(previous)
    }
    
    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(text: text, selection: selection))
        restore(next)
    }
    
    // MARK: - Private
    
    /// Applies a change, remembering the text before it for undo. Typing without a pause is one undo step;
    /// everything else (formatting, a tick, a link, a new list item) is a step of its own.
    private mutating func commit(_ newText: String, _ newSelection: Range<Int>, isTyping: Bool, now: Date) {
        if newText != text {
            let isNewStep = !isTyping || undoStack.isEmpty || lastTypingAt.map { now.timeIntervalSince($0) > Self.typingPause } ?? true
            if isNewStep {
                undoStack.append(Snapshot(text: text, selection: selection))
                if undoStack.count > Self.maxUndoSteps {
                    undoStack.removeFirst()
                }
            }
            lastTypingAt = isTyping ? now : nil
            redoStack.removeAll()
        }
        text = newText
        selection = Self.clamped(newSelection, in: newText)
    }
    
    private mutating func restore(_ snapshot: Snapshot) {
        text = snapshot.text
        selection = Self.clamped(snapshot.selection, in: snapshot.text)
        lastTypingAt = nil
    }
    
    private mutating func replaceLink(_ edit: LinkEditState, with replacement: String, now: Date) {
        let newText = text.replacingUTF16(edit.start, edit.end, with: replacement)
        let shift = replacement.utf16Length - (edit.end - edit.start)
        let newSelection: Range<Int>
        if edit.isNew {
            // A new link: the cursor goes right after it, ready to keep writing.
            let cursor = edit.start + replacement.utf16Length
            newSelection = cursor..<cursor
        } else {
            func moved(_ offset: Int) -> Int {
                offset >= edit.end ? offset + shift : min(offset, edit.start + replacement.utf16Length)
            }
            newSelection = moved(selection.lowerBound)..<max(moved(selection.lowerBound), moved(selection.upperBound))
        }
        linkEdit = nil
        commit(newText, newSelection, isTyping: false, now: now)
    }
    
    /// The new text is the old one plus one typed newline: the list continuation for it, or `nil`.
    private func continuedList(newText: String, newSelection: Range<Int>) -> EditedText? {
        guard newSelection.isEmpty, newText.utf16Length == text.utf16Length + 1 else { return nil }
        let cursor = newSelection.lowerBound
        guard cursor > 0, newText.utf16Unit(at: cursor - 1) == UInt16(UInt8(ascii: "\n")),
              newText.replacingUTF16(cursor - 1, cursor, with: "") == text else { return nil }
        return MarkdownFormatting.continueListOnEnter(text, cursor: cursor - 1)
    }
    
    private static func clamped(_ selection: Range<Int>, in text: String) -> Range<Int> {
        let length = text.utf16Length
        let lower = min(max(selection.lowerBound, 0), length)
        let upper = min(max(selection.upperBound, lower), length)
        return lower..<upper
    }
}
