//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// The long-press actions in a folder, as in the Android app: rename, move and delete notes, photos, files and
/// folders, and make new folders. They need a connection (except deleting a note), and say why when they can't.
@MainActor
@Observable
final class NotesFolderActionsModel {
    let service: ArtiseNotesService
    let roomID: String
    
    /// The chat's files and folders, to check names and list where things can move.
    var paths: [String] = []
    var folders: [String] = []
    
    var renaming: NotesFolderEntry?
    var newName = ""
    var moving: NotesFolderEntry?
    var deleting: NotesFolderEntry?
    /// A folder that turned out not to be empty: what's inside, before deleting it all.
    var deletingNotEmpty: (path: String, files: Int, folders: Int)?
    /// A photo or file notes use: which ones, before taking it out of them.
    var deletingInUse: (path: String, usedBy: [String])?
    var isNamingFolder = false
    var folderName = ""
    /// A folder's "Move to… / New folder…": the entry to move into it.
    var movingIntoNewFolder: NotesFolderEntry?
    var problem: String?
    
    init(service: ArtiseNotesService, roomID: String) {
        self.service = service
        self.roomID = roomID
    }
    
    // MARK: - Names
    
    func path(of entry: NotesFolderEntry) -> String {
        switch entry {
        case .folder(_, let path, _, _), .note(_, let path, _), .file(_, let path, _, _): path
        }
    }
    
    func name(of entry: NotesFolderEntry) -> String {
        switch entry {
        case .folder(let name, _, _, _), .note(let name, _, _), .file(let name, _, _, _): name
        }
    }
    
    var renameProblem: String? {
        guard let renaming, !newName.isEmpty else { return nil }
        guard case .folder = renaming else {
            return text(for: NoteNames.renameProblem(path(of: renaming), to: newName, existingPaths: paths + folders))
        }
        if newName.contains("/") || NoteNames.folderProblem(newName) != nil {
            return text(for: .invalid)
        }
        let target = NoteNames.renamedFolder(path(of: renaming), to: newName)
        let isTaken = target.caseInsensitiveCompare(path(of: renaming)) != .orderedSame
            && (paths + folders).contains { $0.caseInsensitiveCompare(target) == .orderedSame }
        return isTaken ? ArtiseNotesL10n.text("screen_notes_folder_problem_exists") : nil
    }
    
    var folderNameProblem: String? {
        guard !folderName.isEmpty else { return nil }
        if NoteNames.folderProblem(folderName) != nil {
            return ArtiseNotesL10n.text("screen_notes_name_invalid")
        }
        let path = NoteNames.folderPath(folderName)
        return (paths + folders).contains { $0.caseInsensitiveCompare(path) == .orderedSame } ? ArtiseNotesL10n.text("screen_notes_folder_problem_exists") : nil
    }
    
    private func text(for problem: NoteNameProblem?) -> String? {
        switch problem {
        case .invalid: ArtiseNotesL10n.text("screen_notes_name_invalid")
        case .exists: ArtiseNotesL10n.text("screen_notes_file_problem_exists")
        case nil: nil
        }
    }
    
    // MARK: - Actions
    
    func startRename(_ entry: NotesFolderEntry) {
        newName = name(of: entry)
        renaming = entry
    }
    
    func rename() {
        guard let entry = renaming else { return }
        let from = path(of: entry)
        let name = newName
        renaming = nil
        perform {
            if case .folder = entry {
                try await $0.moveFolder(roomID: self.roomID, from: from, to: NoteNames.renamedFolder(from, to: name))
            } else {
                try await $0.moveFile(roomID: self.roomID, from: from, to: NoteNames.renamedPath(from, to: name))
            }
        }
    }
    
    func move(_ entry: NotesFolderEntry, to folder: String) {
        let from = path(of: entry)
        moving = nil
        perform {
            if case .folder = entry {
                try await $0.moveFolder(roomID: self.roomID, from: from, to: NoteNames.movedPath(from, to: folder))
            } else {
                try await $0.moveFile(roomID: self.roomID, from: from, to: NoteNames.movedPath(from, to: folder))
            }
        }
    }
    
    func createFolder(in parent: String) {
        let path = NoteNames.movedPath(NoteNames.folderPath(folderName), to: parent)
        let entry = movingIntoNewFolder
        isNamingFolder = false
        movingIntoNewFolder = nil
        perform {
            try await $0.createFolder(roomID: self.roomID, path: path)
            if let entry {
                await MainActor.run { self.move(entry, to: path) }
            }
        }
    }
    
    func delete(_ entry: NotesFolderEntry) {
        deleting = nil
        let path = path(of: entry)
        switch entry {
        case .note:
            // Works offline: the deletion is queued and sent with the next sync.
            perform {
                try await $0.deleteFile(roomID: self.roomID, path: path)
                $0.syncInBackground(roomID: self.roomID)
            }
        case .file:
            deleteMedia(path, removeFromNotes: false)
        case .folder:
            deleteFolder(path, recursive: false)
        }
    }
    
    func deleteMedia(_ path: String, removeFromNotes: Bool) {
        deletingInUse = nil
        perform {
            do {
                try await $0.deleteMedia(roomID: self.roomID, path: path, removeFromNotes: removeFromNotes)
            } catch let NotesError.inUse(_, usedBy) {
                await MainActor.run { self.deletingInUse = (path, usedBy) }
            }
        }
    }
    
    func deleteFolder(_ path: String, recursive: Bool) {
        deletingNotEmpty = nil
        perform {
            do {
                try await $0.deleteFolder(roomID: self.roomID, path: path, recursive: recursive)
            } catch let NotesError.notEmpty(_, files, folders) {
                await MainActor.run { self.deletingNotEmpty = (path, files, folders) }
            }
        }
    }
    
    private func perform(_ action: @escaping (NotesRepository) async throws -> Void) {
        let repository = service.repository
        Task {
            do {
                try await action(repository)
            } catch {
                problem = Self.message(for: error)
            }
        }
    }
    
    static func message(for error: Error) -> String {
        let key = switch error as? NotesError {
        case .network: "screen_notes_file_problem_offline"
        case .conflict: "screen_notes_file_problem_unsent"
        case .exists: "screen_notes_file_problem_exists"
        case .notFound, .deleted: "screen_notes_file_problem_gone"
        default: "screen_notes_file_problem_failed"
        }
        return ArtiseNotesL10n.text(key)
    }
}

extension NotesFolderActionsModel {
    /// The long-press menu for a row.
    @ViewBuilder
    func menu(for entry: NotesFolderEntry) -> some View {
        Button { self.startRename(entry) } label: {
            Label(ArtiseNotesL10n.text("screen_notes_rename"), icon: \.edit)
        }
        Button { self.moving = entry } label: {
            Label(ArtiseNotesL10n.text("screen_notes_file_move"), icon: \.folder)
        }
        Button(role: .destructive) { self.deleting = entry } label: {
            Label(ArtiseNotesL10n.text("screen_notes_delete"), icon: \.delete)
        }
    }
}

/// The dialogs the folder actions show.
struct NotesFolderActionsDialogs: ViewModifier {
    @Bindable var model: NotesFolderActionsModel
    /// The folder shown, where new folders go.
    let folder: String
    
    func body(content: Content) -> some View {
        content
            .alert(ArtiseNotesL10n.text("screen_notes_rename"), isPresented: isShown(\.renaming)) {
                TextField(ArtiseNotesL10n.text("screen_notes_new_note_placeholder"), text: $model.newName)
                Button(ArtiseNotesL10n.text("screen_notes_rename")) { model.rename() }
                    .disabled(model.newName.trimmingCharacters(in: .whitespaces).isEmpty || model.renameProblem != nil)
                Button(L10n.actionCancel, role: .cancel) { }
            } message: {
                Text(model.renameProblem ?? "")
            }
            .alert(ArtiseNotesL10n.text("screen_notes_new_folder"), isPresented: $model.isNamingFolder) {
                TextField(ArtiseNotesL10n.text("screen_notes_folder_name_placeholder"), text: $model.folderName)
                Button(ArtiseNotesL10n.text("screen_notes_folder_create")) { model.createFolder(in: folder) }
                    .disabled(model.folderName.trimmingCharacters(in: .whitespaces).isEmpty || model.folderNameProblem != nil)
                Button(L10n.actionCancel, role: .cancel) { model.movingIntoNewFolder = nil }
            } message: {
                Text(model.folderNameProblem ?? ArtiseNotesL10n.text("screen_notes_folder_name_hint"))
            }
            .confirmationDialog(deleteTitle, isPresented: isShown(\.deleting), titleVisibility: .visible) {
                Button(ArtiseNotesL10n.text("screen_notes_delete"), role: .destructive) {
                    if let entry = model.deleting {
                        model.delete(entry)
                    }
                }
            } message: {
                Text(deleteMessage)
            }
            .confirmationDialog(deleteTitle(model.deletingNotEmpty?.path), isPresented: isShown(\.deletingNotEmpty), titleVisibility: .visible) {
                Button(ArtiseNotesL10n.text("screen_notes_delete"), role: .destructive) {
                    if let folder = model.deletingNotEmpty {
                        model.deleteFolder(folder.path, recursive: true)
                    }
                }
            } message: {
                Text(notEmptyMessage)
            }
            .confirmationDialog(inUseTitle, isPresented: isShown(\.deletingInUse), titleVisibility: .visible) {
                Button(ArtiseNotesL10n.text("screen_notes_media_remove_and_delete"), role: .destructive) {
                    if let file = model.deletingInUse {
                        model.deleteMedia(file.path, removeFromNotes: true)
                    }
                }
            } message: {
                Text(inUseMessage)
            }
            .sheet(isPresented: isShown(\.moving)) {
                if let entry = model.moving {
                    NotesMoveSheet(model: model, entry: entry)
                }
            }
            .alert(model.problem ?? "", isPresented: isShown(\.problem)) {
                Button(L10n.actionOk) { }
            }
    }
    
    private func isShown<Value>(_ keyPath: ReferenceWritableKeyPath<NotesFolderActionsModel, Value?>) -> Binding<Bool> {
        Binding(get: { model[keyPath: keyPath] != nil },
                set: {
                    if !$0 {
                        model[keyPath: keyPath] = nil
                    }
                })
    }
    
    private var deleteTitle: String {
        deleteTitle(model.deleting.map(model.path(of:)))
    }
    
    private func deleteTitle(_ path: String?) -> String {
        String(format: ArtiseNotesL10n.text("screen_notes_file_delete_title"), NotesFolderEntries.noteName(path ?? ""))
    }
    
    private var deleteMessage: String {
        switch model.deleting {
        case .note: ArtiseNotesL10n.text("screen_notes_file_delete_note_message")
        case .file: ArtiseNotesL10n.text("screen_notes_file_delete_file_message")
        case .folder(_, _, let notes, let files) where notes + files == 0: ArtiseNotesL10n.text("screen_notes_folder_delete_empty_message")
        case .folder(_, _, let notes, let files):
            String(format: ArtiseNotesL10n.text("screen_notes_folder_delete_message"), Self.counts(notes: notes, files: files, folders: 0))
        case nil: ""
        }
    }
    
    private var notEmptyMessage: String {
        guard let folder = model.deletingNotEmpty else { return "" }
        return String(format: ArtiseNotesL10n.text("screen_notes_folder_delete_message"), Self.counts(notes: 0, files: folder.files, folders: folder.folders))
    }
    
    private var inUseTitle: String {
        String(format: ArtiseNotesL10n.text("screen_notes_media_in_use_title"), NotesFolderEntries.fileName(model.deletingInUse?.path ?? ""))
    }
    
    private var inUseMessage: String {
        let notes = model.deletingInUse?.usedBy.map(NotesFolderEntries.noteName).joined(separator: "\n") ?? ""
        return String(format: ArtiseNotesL10n.text("screen_notes_media_in_use_message"), notes)
    }
    
    /// "2 notes, 3 files and 1 folder", leaving out what isn't there.
    static func counts(notes: Int, files: Int, folders: Int) -> String {
        var parts: [String] = []
        if notes > 0 {
            parts.append(String.localizedStringWithFormat(ArtiseNotesL10n.text("screen_notes_folder_delete_notes"), notes))
        }
        if files > 0 {
            parts.append(String.localizedStringWithFormat(ArtiseNotesL10n.text("screen_notes_folder_delete_files"), files))
        }
        if folders > 0 {
            parts.append(String.localizedStringWithFormat(ArtiseNotesL10n.text("screen_notes_folder_delete_folders"), folders))
        }
        return ListFormatter.localizedString(byJoining: parts)
    }
}

/// "Move to…": the chat's folders (and the top level), or a new folder.
private struct NotesMoveSheet: View {
    let model: NotesFolderActionsModel
    let entry: NotesFolderEntry
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    destination(name: ArtiseNotesL10n.text("screen_notes_file_move_top_level"), folder: "")
                    ForEach(destinations, id: \.self) { folder in
                        destination(name: folder, folder: folder)
                    }
                }
                Section {
                    ListRow(label: .default(title: ArtiseNotesL10n.text("screen_notes_file_move_new_folder"), icon: \.plus),
                            kind: .button {
                                model.movingIntoNewFolder = entry
                                model.folderName = ""
                                dismiss()
                                model.isNamingFolder = true
                            })
                }
            }
            .compoundList()
            .navigationTitle(String(format: ArtiseNotesL10n.text("screen_notes_file_move_title"), model.name(of: entry)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { dismiss() }
                }
            }
        }
    }
    
    /// Every folder except where the entry is now and, for a folder, itself and what's inside it.
    private var destinations: [String] {
        let path = model.path(of: entry)
        return model.folders.filter { folder in
            if case .folder = entry, folder == path || folder.hasPrefix(path + "/") {
                return false
            }
            return true
        }
    }
    
    private func destination(name: String, folder: String) -> some View {
        let isCurrent = NotesFolderEntries.parentFolder(of: model.path(of: entry)) == folder
        return ListRow(label: .default(title: name, description: isCurrent ? ArtiseNotesL10n.text("screen_notes_file_move_here") : nil, icon: \.folder),
                       kind: .button {
                           dismiss()
                           model.move(entry, to: folder)
                       })
                       .disabled(isCurrent)
    }
}
