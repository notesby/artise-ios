//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

/// Documents in the chat: the first-page thumbnail Ari sends with a PDF, and what the notes copy opens in.
@MainActor
struct ArtiseDocumentPreviewsTests {
    /// A file with `thumbnail_url` carries its thumbnail; the file itself is unchanged.
    @Test
    func aPlainThumbnailIsCarried() throws {
        let built = try buildFileItem(thumbnail: MediaSource.fromUrl(url: "mxc://artise.co/thumb"))
        let item = try #require(built)
        
        #expect(item.content.thumbnailSource?.url == URL(string: "mxc://artise.co/thumb"))
        #expect(item.content.thumbnailSource?.mimeType == "image/png")
        #expect(item.content.source?.url == URL(string: "mxc://artise.co/file"))
        #expect(item.content.filename == "INV-2026-004.pdf")
    }
    
    /// In an encrypted chat the thumbnail is `thumbnail_file`: the same shape as the file, decrypted the same way
    /// by the media provider, so the item carries it as an encrypted source.
    @Test
    func anEncryptedThumbnailIsCarried() throws {
        let json = """
        {"file": {"url": "mxc://artise.co/encrypted-thumb", "v": "v2", "iv": "AAAAAAAAAAAAAAAAAAAAAA",
                  "hashes": {"sha256": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"},
                  "key": {"kty": "oct", "key_ops": ["encrypt", "decrypt"], "alg": "A256CTR", "k": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "ext": true}}}
        """
        let built = try buildFileItem(thumbnail: MediaSource.fromJson(json: json))
        let item = try #require(built)
        
        #expect(item.content.thumbnailSource?.url == URL(string: "mxc://artise.co/encrypted-thumb"))
        #expect(item.content.thumbnailSource?.underlyingSource.toJson().contains("\"key\"") == true)
    }
    
    /// Without a thumbnail there's none: the icon shows as before.
    @Test
    func noThumbnailMeansNone() throws {
        let built = try buildFileItem(thumbnail: nil)
        let item = try #require(built)
        
        #expect(item.content.thumbnailSource == nil)
    }
    
    /// A file with `co.artise.note` knows its notes path; without it there's nothing to open from the notes.
    @Test
    func theNotesPathComesFromTheEvent() throws {
        let builtWithPath = try buildFileItem(thumbnail: nil, notePath: "business/documents/invoices/INV-2026-004.pdf")
        let withPath = try #require(builtWithPath)
        #expect(withPath.properties.artiseFields?.notePath == "business/documents/invoices/INV-2026-004.pdf")
        
        let builtWithout = try buildFileItem(thumbnail: nil, notePath: nil)
        let without = try #require(builtWithout)
        #expect(without.properties.artiseFields?.notePath == nil)
    }
    
    /// Where each kind of file opens: notes in their reading view, PDFs in the viewer, CSVs as a table, Office files
    /// as the server's PDF; photos and anything else in Quick Look, or from the chat, in their folder.
    @Test
    func filesOpenByTheirKind() {
        let room = "!r:artise.co"
        #expect(ArtiseNoteDocument.route(roomID: room, path: "Recetas/Mole.md") == .note(roomID: room, path: "Recetas/Mole.md"))
        #expect(ArtiseNoteDocument.route(roomID: room, path: "notas.TXT") == .note(roomID: room, path: "notas.TXT"))
        #expect(ArtiseNoteDocument.route(roomID: room, path: "docs/Factura.pdf") == .pdf(roomID: room, path: "docs/Factura.pdf"))
        #expect(ArtiseNoteDocument.route(roomID: room, path: "lista.csv") == .table(roomID: room, path: "lista.csv"))
        #expect(ArtiseNoteDocument.route(roomID: room, path: "Contrato.docx") == .office(roomID: room, path: "Contrato.docx"))
        #expect(ArtiseNoteDocument.route(roomID: room, path: "Ventas.xlsx") == .office(roomID: room, path: "Ventas.xlsx"))
        #expect(ArtiseNoteDocument.route(roomID: room, path: "attachments/luna.JPG") == nil)
        #expect(ArtiseNoteDocument.route(roomID: room, path: "nota de voz.m4a") == nil)
        #expect(ArtiseNoteDocument.route(roomID: room, path: "sin-extension") == nil)
        #expect(ArtiseNoteDocument.hasPicture("a.pdf"))
        #expect(ArtiseNoteDocument.hasPicture("a.pptx"))
        #expect(ArtiseNoteDocument.hasPicture("luna.jpg"))
        #expect(!ArtiseNoteDocument.hasPicture("a.csv"))
    }
    
    private func buildFileItem(thumbnail: MediaSource?, notePath: String? = nil) throws -> FileRoomTimelineItem? {
        let ownUserID = "@ana:artise.co"
        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))
        let info = FileInfo(mimetype: "application/pdf",
                            size: 48213,
                            thumbnailInfo: thumbnail == nil ? nil : ThumbnailInfo(height: 512, width: 396, mimetype: "image/png", size: 31877),
                            thumbnailSource: thumbnail)
        let file = try FileMessageContent(filename: "INV-2026-004.pdf",
                                          caption: nil,
                                          formattedCaption: nil,
                                          source: MediaSource.fromUrl(url: "mxc://artise.co/file"),
                                          info: info)
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: .file(content: file),
                                                                                               body: "INV-2026-004.pdf",
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        let noteField = notePath.map { #", "co.artise.note": "\#($0)""# } ?? ""
        let json = #"{"type": "m.room.message", "content": {"msgtype": "m.file", "body": "INV-2026-004.pdf"\#(noteField)}}"#
        let event = EventTimelineItem(configuration: .init(sender: "@ari:artise.co", content: content, artiseOriginalJSON: json))
        return factory.buildTimelineItem(for: EventTimelineItemProxy(item: event, uniqueID: .init("0")), isDM: false) as? FileRoomTimelineItem
    }
}
