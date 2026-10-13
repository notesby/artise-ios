//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The notes texts, from the `ArtiseNotes` string table (imported from the Android app, same keys).
enum ArtiseNotesL10n {
    static let title = text("screen_notes_title")
    static let chatsEmpty = text("screen_notes_chats_empty")
    static let offline = text("screen_notes_offline")
    static let syncFailed = text("screen_notes_sync_failed")
    static let syncPartial = text("screen_notes_sync_partial")
    static let privacyTitle = text("screen_notes_privacy_title")
    static let privacyBody = text("screen_notes_privacy_body")
    static let privacyOK = text("screen_notes_privacy_ok")
    static let folderEmpty = text("screen_notes_folder_empty")
    static let folderIsEmpty = text("screen_notes_folder_is_empty")
    static let unsent = text("screen_notes_unsent")
    static let notDownloaded = text("screen_notes_not_downloaded")
    static let attachmentMissing = text("screen_notes_attachment_missing")
    static let attachmentUnavailable = text("screen_notes_attachment_unavailable")
    static let missingNoteCreate = text("screen_notes_missing_note_create")
    
    /// "3 notes" / "3 notas".
    static func folderCount(_ notes: Int) -> String {
        String.localizedStringWithFormat(text("screen_notes_folder_count"), notes)
    }
    
    /// "2 files" / "2 archivos".
    static func folderFileCount(_ files: Int) -> String {
        String.localizedStringWithFormat(text("screen_notes_folder_file_count"), files)
    }
    
    private static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "ArtiseNotes", bundle: .main, comment: "")
    }
}
