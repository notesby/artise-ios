//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Foundation

/// The notes texts, from the `ArtiseNotes` string table (imported from the Android app, same keys).
enum ArtiseNotesL10n {
    static var title: String {
        text("screen_notes_title")
    }
    
    static var chatsEmpty: String {
        text("screen_notes_chats_empty")
    }
    
    static var offline: String {
        text("screen_notes_offline")
    }
    
    static var syncFailed: String {
        text("screen_notes_sync_failed")
    }
    
    static var syncPartial: String {
        text("screen_notes_sync_partial")
    }
    
    static var privacyTitle: String {
        text("screen_notes_privacy_title")
    }
    
    static var privacyBody: String {
        text("screen_notes_privacy_body")
    }
    
    static var privacyOK: String {
        text("screen_notes_privacy_ok")
    }
    
    static var folderEmpty: String {
        text("screen_notes_folder_empty")
    }
    
    static var folderIsEmpty: String {
        text("screen_notes_folder_is_empty")
    }
    
    static var unsent: String {
        text("screen_notes_unsent")
    }
    
    static var notDownloaded: String {
        text("screen_notes_not_downloaded")
    }
    
    static var attachmentMissing: String {
        text("screen_notes_attachment_missing")
    }
    
    static var attachmentUnavailable: String {
        text("screen_notes_attachment_unavailable")
    }
    
    static var missingNoteCreate: String {
        text("screen_notes_missing_note_create")
    }
    
    /// "3 notes" / "3 notas".
    static func folderCount(_ notes: Int) -> String {
        String.localizedStringWithFormat(text("screen_notes_folder_count"), notes)
    }
    
    /// "2 files" / "2 archivos".
    static func folderFileCount(_ files: Int) -> String {
        String.localizedStringWithFormat(text("screen_notes_folder_file_count"), files)
    }
    
    /// A page's type as people read it: "person" → "Persona"; a type the app doesn't know shows as written.
    static func pageType(_ type: String) -> String {
        let key = "screen_notes_page_type_" + type.lowercased()
        let text = NSLocalizedString(key, tableName: "ArtiseNotes", bundle: .main, comment: "")
        return text == key ? type.prefix(1).uppercased() + type.dropFirst() : text
    }
    
    /// "3 of 12" / "3 de 12": where the current match is among all of them.
    static func findCount(_ position: Int, of total: Int) -> String {
        String(format: text("screen_notes_find_count"), position, total)
    }
    
    /// Texts that say "Ari" use the workspace's assistant name.
    static func text(_ key: String) -> String {
        let text = NSLocalizedString(key, tableName: "ArtiseNotes", bundle: .main, comment: "")
        return ArtiseWorkspaces.shared.branding?.naming(text) ?? text
    }
    
    /// The text in one of the app's languages ("en", "es", "pt"), for tests.
    static func text(_ key: String, language: String) -> String {
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return NSLocalizedString(key, tableName: "ArtiseNotes", bundle: bundle, comment: "")
    }
}
