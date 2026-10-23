//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Everything that can go wrong with notes, following the Notes API's error codes.
public enum NotesError: Error, Equatable, Sendable {
    /// No valid sign-in, even after asking for a fresh OpenID token.
    case unauthorized(String)
    /// Not a member of the chat, or it has no notes.
    case noChat(String)
    /// A hidden path, outside the chat's folder, or not a note type.
    case badPath(String)
    case notFound(String)
    /// Creating a file that's already there.
    case exists(String, current: ServerCopy?)
    /// Changed on the server meanwhile, and the same lines were edited.
    case conflict(String, current: ServerCopy?)
    /// Deleted on the server meanwhile.
    case deleted(String)
    /// Over 1 MB for a note, 50 MB for a file.
    case tooBig(String)
    /// Notes use this photo or file; take it out of them first.
    case inUse(String, usedBy: [String])
    /// A folder isn't empty: deleting it needs a confirmation.
    case notEmpty(String, files: Int, folders: Int)
    /// A photo or document: use the raw endpoints.
    case notANote(String)
    /// A kind of file with no preview (an Office file, audio…).
    case noPreview(String)
    /// A file that couldn't be read for a preview.
    case unreadable(String)
    /// A kind of file with no text to search.
    case noText(String)
    /// Not an Office file, or a server without the conversion: there's no PDF of it to read.
    case noPDF(String)
    /// Not a chart file.
    case noChart(String)
    /// A chart file with a mistake: the message says what, in the server's words.
    case badChart(String)
    /// A note that isn't a dashboard.
    case noDashboard(String)
    /// A kind of file that can't be exported in that format.
    case noExport(String)
    /// The server can't draw right now. Safe to retry later.
    case unavailable(String)
    /// No connection, or the request didn't complete. Safe to retry later.
    case network(String)
    /// Anything the contract doesn't name, such as a 500, or an answer the app can't read.
    case server(status: Int, message: String)
    
    /// A short description for logs. It never includes note text or tokens.
    public var message: String {
        switch self {
        case .unauthorized(let message), .noChat(let message), .badPath(let message), .notFound(let message),
             .exists(let message, _), .conflict(let message, _), .deleted(let message), .tooBig(let message),
             .inUse(let message, _), .notEmpty(let message, _, _), .notANote(let message), .noPreview(let message),
             .unreadable(let message), .noText(let message), .noPDF(let message), .noChart(let message), .badChart(let message),
             .noDashboard(let message), .noExport(let message), .unavailable(let message), .network(let message), .server(_, let message):
            message
        }
    }
}
