//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// Edits a note's Markdown with live preview. Saving stores it on the phone at once and sends it in the background.
/// With `resolveEditID`, it combines the two versions of a conflict, and saving that becomes the chosen version.
struct NoteEditorScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    var resolveEditID: Int64?
    let onDone: () -> Void
    
    @State private var model = NoteEditorModel(text: "")
    /// The chat's files and pages, for `[[` suggestions and the link dialog.
    @State private var index = PageIndex.empty
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var showsSaveChanges = false
    /// Finding words in the text, unsaved edits included: the matches and the one the view is on.
    @State private var isSearching = false
    @State private var query = ""
    @State private var matches: [Range<Int>] = []
    @State private var cursor = SearchCursor(count: 0)
    
    var body: some View {
        ElementNavigationStack {
            VStack(spacing: 0) {
                if model.isResolvingConflict {
                    Text(ArtiseNotesL10n.text("screen_notes_editor_combine_hint"))
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isSearching {
                    NoteSearchBar(query: $query, status: searchStatus, onNext: nextMatch, onPrevious: previousMatch) {
                        isSearching = false
                        query = ""
                    }
                }
                if isLoaded {
                    NoteTextView(model: $model, highlights: matches, currentHighlight: currentMatch)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    suggestions
                    HStack(spacing: 0) {
                        NoteAttachMenu(service: service, roomID: roomID, model: $model)
                            .padding(.leading, 8)
                        NoteFormatBar(model: $model)
                    }
                    .background(.compound.bgSubtleSecondary)
                }
            }
            .background(.compound.bgCanvasDefault)
            .navigationTitle(NotesFolderEntries.noteName(path))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: isEditingLink) {
                if let edit = model.linkEdit {
                    NoteLinkEditSheet(edit: edit, index: index, model: $model)
                }
            }
            .confirmationDialog(L10n.dialogUnsavedChangesTitle, isPresented: $showsSaveChanges, titleVisibility: .visible) {
                Button(L10n.actionSave) { save() }
                Button(L10n.actionDiscard, role: .destructive, action: onDone)
            } message: {
                Text(L10n.dialogUnsavedChangesDescriptionIos)
            }
        }
        .interactiveDismissDisabled(model.hasChanges)
        .onAppear { ArtiseAnalyticsClient.shared.screen(.noteEditor) }
        .onChange(of: query) { _, _ in search(keepingPlace: false) }
        .onChange(of: model.text) { _, _ in search(keepingPlace: true) }
        .task { await load() }
    }
    
    // MARK: - Finding words
    
    private var currentMatch: Range<Int>? {
        cursor.index.flatMap { matches.indices.contains($0) ? matches[$0] : nil }
    }
    
    private var searchStatus: NoteSearchStatus {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return .idle
        }
        guard let position = cursor.position else { return .none }
        return .found(position: position, total: matches.count)
    }
    
    /// Finds the words as they're typed; while the text changes under a search, the place is kept when it can be.
    private func search(keepingPlace: Bool) {
        let found = DocumentSearch.ranges(of: query, in: model.text)
        let previous = cursor.index
        matches = found
        cursor = SearchCursor(count: found.count)
        if keepingPlace, let previous, previous < found.count {
            for _ in 0..<previous {
                cursor.next()
            }
        } else if !keepingPlace {
            goToCurrentMatch()
        }
    }
    
    private func nextMatch() {
        cursor.next()
        goToCurrentMatch()
    }
    
    private func previousMatch() {
        cursor.previous()
        goToCurrentMatch()
    }
    
    private func goToCurrentMatch() {
        if let currentMatch {
            model.select(currentMatch)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.actionCancel) {
                if model.hasChanges {
                    showsSaveChanges = true
                } else {
                    onDone()
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionSave) {
                if model.hasChanges {
                    save()
                } else {
                    onDone()
                }
            }
            .disabled(!isLoaded || isSaving)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { isSearching.toggle() } label: {
                CompoundIcon(\.search)
            }
            .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_find"))
            .disabled(!isLoaded)
            
            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_undo"))
            .disabled(!model.canUndo)
            
            Button { model.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_redo"))
            .disabled(!model.canRedo)
        }
    }
    
    /// Notes, pages and files that fit the `[[…` being typed, in a row above the formatting bar. An alias shows the
    /// page it names; a name two notes share shows each one's folder and summary.
    @ViewBuilder
    private var suggestions: some View {
        if let link = model.openLink {
            let matches = WikiLinkSuggestions.suggestions(for: link.query, index: index, currentPath: path)
            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matches) { suggestion in
                            Button { model.choose(suggestion, now: .now) } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(suggestion.name)
                                        .font(.compound.bodyMD)
                                    if let detail = suggestion.detail {
                                        Text(detail)
                                            .font(.compound.bodyXS)
                                            .foregroundStyle(.compound.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, suggestion.detail == nil ? 8 : 4)
                                .background(.compound.bgSubtleSecondary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel([suggestion.name, suggestion.detail].compactMap { $0 }.joined(separator: ", "))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(.compound.bgCanvasDefault)
            }
        }
    }
    
    private var isEditingLink: Binding<Bool> {
        Binding(get: { model.linkEdit != nil },
                set: { isShown in
                    if !isShown {
                        model.dismissLinkEdit()
                    }
                })
    }
    
    private func load() async {
        let repository = service.repository
        if let resolveEditID {
            let edit = try? await repository.edits(roomID: roomID).first { $0.id == resolveEditID }
            model = NoteEditorModel(mine: edit?.content, theirs: edit?.serverCopy?.content)
        } else {
            model = await NoteEditorModel(text: (try? repository.file(roomID: roomID, path: path)?.content) ?? "")
        }
        let files = await (try? repository.files(roomID: roomID)) ?? []
        index = await PageIndex(paths: files.map(\.path), pages: (try? repository.pages(roomID: roomID)) ?? [])
        isLoaded = true
    }
    
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let repository = service.repository
        let text = model.text
        Task {
            if let resolveEditID {
                try? await repository.resolveConflict(roomID: roomID, editID: resolveEditID, content: text)
            } else {
                try? await repository.editNote(roomID: roomID, path: path, content: text)
            }
            repository.syncInBackground(roomID: roomID)
            onDone()
        }
    }
}

/// The formatting buttons, above the keyboard: each writes the Markdown and toggles off when pressed again.
private struct NoteFormatBar: View {
    @Binding var model: NoteEditorModel
    
    private let buttons: [(FormatAction, String, String)] = [
        (.bold, "bold", "a11y_notes_format_bold"),
        (.italic, "italic", "a11y_notes_format_italic"),
        (.strikethrough, "strikethrough", "a11y_notes_format_strikethrough"),
        (.heading, "textformat.size", "a11y_notes_format_heading"),
        (.checklist, "checklist", "a11y_notes_format_checklist"),
        (.bulletList, "list.bullet", "a11y_notes_format_bullets"),
        (.numberedList, "list.number", "a11y_notes_format_numbers"),
        (.quote, "text.quote", "a11y_notes_format_quote"),
        (.noteLink, "link", "a11y_notes_format_link"),
        (.webLink, "globe", "a11y_notes_format_web_link")
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(buttons.indices, id: \.self) { index in
                    let (action, symbol, label) = buttons[index]
                    Button { model.format(action, now: .now) } label: {
                        Image(systemName: symbol)
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.compound.iconPrimary)
                    .accessibilityLabel(ArtiseNotesL10n.text(label))
                }
            }
            .padding(.horizontal, 8)
        }
        .background(.compound.bgSubtleSecondary)
    }
}

/// Edits a link: the note or web address, and the text to show. Removing it keeps the words people saw.
/// A note typed by one of its other names is written as Obsidian does: "Mamá" becomes `[[Ana|Mamá]]`.
private struct NoteLinkEditSheet: View {
    let edit: LinkEditState
    let index: PageIndex
    @Binding var model: NoteEditorModel
    
    @State private var target = ""
    @State private var shownText = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    TextField(edit.link.isNote ? ArtiseNotesL10n.text("screen_notes_link_edit_note") : ArtiseNotesL10n.text("screen_notes_link_edit_address"),
                              text: $target)
                        .textInputAutocapitalization(edit.link.isNote ? .sentences : .never)
                        .keyboardType(edit.link.isNote ? .default : .URL)
                        .autocorrectionDisabled(!edit.link.isNote)
                    TextField(ArtiseNotesL10n.text("screen_notes_link_edit_text"), text: $shownText)
                }
                
                if !edit.isNew {
                    Section {
                        if !edit.link.isNote, let url = URL(string: Self.webAddress(edit.link.target)) {
                            Button(ArtiseNotesL10n.text("screen_notes_link_edit_open")) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Button(ArtiseNotesL10n.text("screen_notes_link_edit_remove"), role: .destructive) {
                            model.removeLink(now: .now)
                            dismiss()
                        }
                    }
                }
            }
            .compoundList()
            .navigationTitle(ArtiseNotesL10n.text("screen_notes_link_edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionSave) {
                        model.saveLink(link, now: .now)
                        dismiss()
                    }
                    .disabled(target.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            target = edit.link.target
            shownText = edit.link.shownText
        }
    }
    
    private var link: EditableLink {
        guard edit.link.isNote, let written = index.written(target) else {
            return EditableLink(isNote: edit.link.isNote, target: target, shownText: shownText)
        }
        let shown = shownText.trimmingCharacters(in: .whitespaces)
        return EditableLink(isNote: true, target: written.target, shownText: shown.isEmpty ? written.shownText : shown)
    }
    
    private static func webAddress(_ target: String) -> String {
        target.contains("://") ? target : "https://" + target
    }
}
