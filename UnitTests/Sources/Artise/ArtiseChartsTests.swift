//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ElementX
import Foundation
import SwiftUI
import Testing
import UIKit

/// Charts and dashboards in the app: their words in each language, the share sentence, the editor's helpers.
@MainActor
struct ArtiseChartsTests {
    static let languages = ["en", "es", "pt"]
    
    /// Every problem the checks can find reads as a sentence in each language, never as its key.
    @Test
    func everyProblemHasItsWords() {
        let texts = [ChartProblemText.text(.title), ChartProblemText.text(.titleTooLong), ChartProblemText.text(.unknownType("radar")),
                     ChartProblemText.text(.compareNotKPI), ChartProblemText.text(.badColor("blue")), ChartProblemText.text(.source),
                     ChartProblemText.text(.columns), ChartProblemText.text(.names), ChartProblemText.text(.noRows),
                     ChartProblemText.text(.tooManyRows(501)), ChartProblemText.text(.rowLength(row: 2, expected: 3)),
                     ChartProblemText.text(.tooManySeries(9)), ChartProblemText.text(.unknownSeries("X")),
                     ChartProblemText.text(.oneSeries(type: "pie", count: 2)), ChartProblemText.text(.negative(type: "pie")),
                     ChartProblemText.text(.tooBig),
                     DashboardProblemRow.text(.themeAccent("blue")), DashboardProblemRow.text(.themePalette),
                     DashboardProblemRow.text(.themeMode("dim")), DashboardProblemRow.text(.nestedColumns(line: 1)),
                     DashboardProblemRow.text(.unclosedColumns(line: 1)), DashboardProblemRow.text(.missingChart(ref: "a.chart", line: 1)),
                     DashboardProblemRow.text(.tooManyCharts(25))]
        for text in texts {
            #expect(!text.contains("screen_notes_"), "\(text)")
        }
        #expect(ChartProblemText.text(.notANumber(row: 2, column: "Ventas", value: "mucho")).contains("mucho"))
    }
    
    /// The new texts are there in English, Spanish and Portuguese.
    @Test
    func theTextsAreInEveryLanguage() {
        let keys = ["screen_notes_share", "screen_notes_ask_link", "screen_notes_ask_link_note", "screen_notes_chart_as_of",
                    "screen_notes_chart_failed", "screen_notes_new_chart", "screen_notes_new_dashboard", "screen_notes_dashboard_layout",
                    "screen_notes_dashboard_theme", "screen_notes_chart_type_kpi", "screen_notes_chart_period_last_6_months",
                    "screen_notes_readonly", "a11y_notes_exporting"]
        for language in Self.languages {
            for key in keys {
                #expect(ArtiseNotesL10n.text(key, language: language) != key, "\(language): \(key)")
            }
        }
        #expect(ArtiseNotesL10n.text("screen_notes_chart_problem_series", language: "es") == "Máximo 8 series por gráfica; divídela.")
    }
    
    /// "Ask Ari for a link" names Ari, so it answers in a chat with other people too, in the app's language.
    @Test
    func theLinkRequestNamesAri() {
        #expect(String(format: ArtiseNotesL10n.text("screen_notes_ask_link_message", language: "es"), "Ventas") == "Ari, comparte «Ventas» con un enlace")
        #expect(String(format: ArtiseNotesL10n.text("screen_notes_ask_link_message", language: "en"), "Ventas") == "Ari, share “Ventas” with a link")
        #expect(String(format: ArtiseNotesL10n.text("screen_notes_ask_link_message", language: "pt"), "Ventas") == "Ari, compartilhe “Ventas” com um link")
    }
    
    /// Every chart type has a picture in the type picker.
    @Test
    func everyTypeHasASymbol() {
        let symbols = [NoteChartEditorScreen.symbol(.bar), NoteChartEditorScreen.symbol(.line), NoteChartEditorScreen.symbol(.area),
                       NoteChartEditorScreen.symbol(.pie), NoteChartEditorScreen.symbol(.donut), NoteChartEditorScreen.symbol(.stacked),
                       NoteChartEditorScreen.symbol(.kpi), NoteChartEditorScreen.symbol(.table)]
        for symbol in symbols {
            #expect(UIImage(systemName: symbol) != nil, "\(symbol)")
        }
    }
    
    /// Ari's picture of a chart becomes a card only where notes are; here (no notes) it stays a picture.
    @Test
    func aChartPictureIsACardOnlyWithNotes() throws {
        let json = #"{"content":{"msgtype":"m.image","body":"ventas.png","co.artise.note":"charts/ventas.chart"}}"#
        let fields = try #require(ArtiseMessageFields.read(eventJSON: json))
        
        #expect(fields.notePath == "charts/ventas.chart")
        #expect(ArtiseDocumentCardsView.chartCard(fields) == nil)
    }
    
    /// The editor's helpers: where a line starts, a text block's summary, a picked colour's hex, the day a chart was read.
    @Test
    func editorHelpers() throws {
        #expect(NoteEditorScreen.offset(ofLine: 2, in: "ab\nñ\nc") == 5)
        #expect(NoteEditorScreen.offset(ofLine: 0, in: "ab") == 0)
        #expect(DashboardLayoutEditor.summary(of: 0...2, in: "## Ventas\n\n- uno\nfuera") == "Ventas\nuno")
        #expect(try ChartColorHex.hex(#require(Color(artiseHex: "#22408A"))) == "#22408A")
        #expect(NoteChartScreen.day("no es fecha") == "no es fecha")
        #expect(NoteChartScreen.day("2026-10-23") != "2026-10-23")
    }
}
