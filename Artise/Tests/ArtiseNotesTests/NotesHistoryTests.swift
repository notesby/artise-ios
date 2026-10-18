//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

struct ChangeLabelTests {
    func author(_ who: String?, _ how: String?, _ detail: String = "", by: String = "Ana") -> ChangeAuthor {
        ChangeAuthor(who: who, how: how, detail: detail, by: by)
    }
    
    /// Each way a change is made gets its own words, naming the person when the server says who.
    @Test
    func labelsByHow() {
        #expect(ChangeLabel(author("Ana", "ari")) == .text(key: "screen_notes_change_ari", arguments: ["Ana"]))
        #expect(ChangeLabel(author("Ana", "automation", "#3")) == .text(key: "screen_notes_change_automation", arguments: ["Ana", "#3"]))
        #expect(ChangeLabel(author(nil, "ari_own", by: "Ari")) == .text(key: "screen_notes_change_ari_own", arguments: []))
        #expect(ChangeLabel(author(nil, "sync", by: "synced device")) == .text(key: "screen_notes_change_sync", arguments: []))
    }
    
    /// Without a name, or for a kind this app doesn't know, the server's plain name is shown.
    @Test
    func fallsBackToThePlainName() {
        #expect(ChangeLabel(author(nil, "app", by: "Ana")) == .plain("Ana"))
        #expect(ChangeLabel(author("Ana", "something_new", by: "Ana")) == .plain("Ana"))
        #expect(ChangeLabel(author("Ana", nil, by: "Ana")) == .plain("Ana"))
        #expect(ChangeLabel.tidy("Ari, Ana's automation ") == "Ari, Ana's automation")
    }
}

struct HistoryTests {
    /// Changes are read with their files; unknown kinds read as modified; pages say whether more exist.
    @Test
    func changesAreRead() async throws {
        let server = FakeNotesServer()
        let body = #"{"changes": [{"commit": "c1", "at": "2026-09-29T18:02:11-06:00", "message": "app: edit Súper.md", "by": "Ana", "who": "Ana", "how": "app", "detail": "", "files": [{"path": "Súper.md", "change": "modified"}, {"path": "b.md", "change": "renamed", "from": "a.md"}, {"path": "x.md", "change": "teleported"}]}], "more": true}"#
        server.state.withLock { $0.failNext["changes", default: []].append((200, body)) }
        let tokens = CountingTokenProvider()
        let api = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
        
        let page = try await api.changes(roomID: FakeNotesServer.roomID, before: "c0")
        
        #expect(page.more)
        #expect(page.changes.first?.files.map(\.change) == [.modified, .renamed, .modified])
        #expect(page.changes.first?.files[1].from == "a.md")
        #expect(server.requests.last?.query == ["limit": "50", "before": "c0"])
    }
    
    /// History is grouped by day in the phone's time zone.
    @Test
    func groupedByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City") ?? .gmt
        let times = ["2026-09-29T23:00:00-06:00", "2026-09-29T08:00:00-06:00", "2026-09-28T23:59:00-06:00"]
        
        let groups = HistoryDays.grouped(times, at: { $0 }, calendar: calendar)
        
        #expect(groups.map(\.items.count) == [2, 1])
    }
}
