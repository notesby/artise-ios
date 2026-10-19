//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A note on the map: `x` and `y` in 0…1, `degree` = how many notes it's linked with.
public struct MapNode: Equatable, Sendable {
    public let path: String
    public let name: String
    public let x: Double
    public let y: Double
    public let degree: Int
    /// A person, place or thing with a page of its own: drawn apart from plain notes.
    public let isPage: Bool
}

/// The notes of a chat and the links between them, placed on a unit square.
public struct NotesMapModel: Equatable, Sendable {
    public let nodes: [MapNode]
    /// Pairs of indexes into `nodes`; each link once, whichever note it's written in.
    public let edges: [MapEdge]
    
    public init(nodes: [MapNode], edges: [MapEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct MapEdge: Equatable, Hashable, Sendable {
    public let from: Int
    public let to: Int
    
    public init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }
}

/// Builds the map from the notes on the phone, so it works offline and includes edits not sent yet, as the Android
/// app does. Links are read like on the note screen: `[[wiki links]]`, embedded notes and Markdown links to notes,
/// by name, title or alias; a link several notes answer to joins nothing, as on the server.
public enum NotesMapBuilder {
    public static func build(_ files: [LocalFile], pages: [NotesPage] = []) -> NotesMapModel {
        let notes = files.filter { $0.isNote && $0.path.hasSuffix(".md") }.sorted { $0.path.lowercased() < $1.path.lowercased() }
        let paths = notes.map(\.path)
        let pageIndex = PageIndex(paths: paths, pages: pages.filter(\.isNote))
        let index = Dictionary(uniqueKeysWithValues: paths.enumerated().map { ($1, $0) })
        var edges: [MapEdge] = []
        var seen: Set<MapEdge> = []
        for (from, note) in notes.enumerated() {
            for target in linkTargets(note.content ?? "") {
                guard case .file(let resolved) = pageIndex.resolve(target), let to = index[resolved], to != from else { continue }
                let edge = MapEdge(from: min(from, to), to: max(from, to))
                if seen.insert(edge).inserted {
                    edges.append(edge)
                }
            }
        }
        let positions = ForceLayout.layout(count: notes.count, edges: edges)
        var degrees = [Int](repeating: 0, count: notes.count)
        for edge in edges {
            degrees[edge.from] += 1
            degrees[edge.to] += 1
        }
        let nodes = notes.enumerated().map { index, note in
            MapNode(path: note.path, name: pageIndex.title(of: note.path), x: positions[index].x, y: positions[index].y,
                    degree: degrees[index], isPage: pageIndex.isPage(note.path))
        }
        return NotesMapModel(nodes: nodes, edges: edges)
    }
    
    /// What each link in the note points to. Photos don't resolve to notes, so they drop out later.
    static func linkTargets(_ markdown: String) -> [String] {
        var targets: [String] = []
        func visit(_ inlines: [NoteInline]) {
            for inline in inlines {
                switch inline {
                case .link(.note(let target), let children):
                    targets.append(target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target)
                    visit(children)
                case .link(.web, let children), .emphasis(let children), .strong(let children), .strikethrough(let children):
                    visit(children)
                case .text, .code:
                    break
                }
            }
        }
        func visit(_ blocks: [NoteBlock]) {
            for block in blocks {
                switch block {
                case .heading(_, let text):
                    visit(text)
                case .paragraph(let pieces):
                    for piece in pieces {
                        switch piece {
                        case .text(let inlines): visit(inlines)
                        case .embed(let target): targets.append(target)
                        }
                    }
                case .list(_, _, let items):
                    items.forEach { visit($0.blocks) }
                case .quote(let blocks):
                    visit(blocks)
                case .table(let rows):
                    rows.forEach { $0.forEach(visit) }
                case .code, .divider, .html:
                    break
                }
            }
        }
        visit(NoteDocument(markdown: markdown).blocks)
        return targets
    }
}

/// A small force-directed layout (Fruchterman–Reingold): linked notes pull together, all notes push apart.
/// It starts from a fixed spiral, so the same notes always give the same map. Positions are in 0…1.
enum ForceLayout {
    static let iterations = 250
    static let gravity = 0.6
    static let margin = 0.12
    
    static func layout(count: Int, edges: [MapEdge]) -> [(x: Double, y: Double)] {
        guard count > 1 else { return count == 1 ? [(0.5, 0.5)] : [] }
        // Golden-angle spiral: evenly spread, deterministic.
        var positions = (0..<count).map { index -> (x: Double, y: Double) in
            let radius = ((Double(index) + 0.5) / Double(count)).squareRoot() * 0.5
            let angle = Double(index) * 2.3999631
            return (0.5 + radius * cos(angle), 0.5 + radius * sin(angle))
        }
        let k = (1 / Double(count)).squareRoot()
        var temperature = 0.1
        for _ in 0..<iterations {
            var displacement = [(x: Double, y: Double)](repeating: (0, 0), count: count)
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = max((dx * dx + dy * dy).squareRoot(), 0.001)
                    let force = k * k / distance
                    displacement[i].x += dx / distance * force
                    displacement[i].y += dy / distance * force
                    displacement[j].x -= dx / distance * force
                    displacement[j].y -= dy / distance * force
                }
            }
            for edge in edges {
                let dx = positions[edge.from].x - positions[edge.to].x
                let dy = positions[edge.from].y - positions[edge.to].y
                let distance = max((dx * dx + dy * dy).squareRoot(), 0.001)
                let force = distance * distance / k
                displacement[edge.from].x -= dx / distance * force
                displacement[edge.from].y -= dy / distance * force
                displacement[edge.to].x += dx / distance * force
                displacement[edge.to].y += dy / distance * force
            }
            // A gentle pull to the middle: notes with no links would otherwise drift far out, and fitting them on
            // screen would squeeze the linked notes into an unreadable pile.
            for i in 0..<count {
                displacement[i].x -= (positions[i].x - 0.5) * gravity
                displacement[i].y -= (positions[i].y - 0.5) * gravity
            }
            for i in 0..<count {
                let length = max((displacement[i].x * displacement[i].x + displacement[i].y * displacement[i].y).squareRoot(), 0.001)
                let step = min(length, temperature)
                positions[i].x += displacement[i].x / length * step
                positions[i].y += displacement[i].y / length * step
            }
            temperature *= 0.98
        }
        return normalized(positions)
    }
    
    /// Scales the layout to fill 0.12…0.88, keeping its proportions: names under the dots near the edges still fit.
    static func normalized(_ positions: [(x: Double, y: Double)]) -> [(x: Double, y: Double)] {
        let xs = positions.map(\.x)
        let ys = positions.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        let width = (xs.max() ?? 0) - minX
        let height = (ys.max() ?? 0) - minY
        let span = max(max(width, height), 0.0001)
        let offsetX = (span - width) / 2
        let offsetY = (span - height) / 2
        return positions.map { position in
            (margin + (position.x - minX + offsetX) / span * (1 - 2 * margin),
             margin + (position.y - minY + offsetY) / span * (1 - 2 * margin))
        }
    }
}

/// How the map is zoomed and moved. A point at `base` (unzoomed, in screen points) is drawn at
/// `center + (base - center) * scale + pan`, where `center` is the middle of the map.
public struct MapViewport: Equatable, Sendable {
    public static let minScale = 0.5
    public static let maxScale = 6.0
    /// How much the zoom buttons and a double tap zoom in or out.
    public static let step = 1.6
    /// The whole map, as first shown.
    public static let reset = MapViewport()
    
    public var scale = 1.0
    public var panX = 0.0
    public var panY = 0.0
    
    public init(scale: Double = 1, panX: Double = 0, panY: Double = 0) {
        self.scale = scale
        self.panX = panX
        self.panY = panY
    }
    
    public var isReset: Bool {
        self == .reset
    }
    
    public func toScreen(x: Double, y: Double, centerX: Double, centerY: Double) -> (x: Double, y: Double) {
        (centerX + (x - centerX) * scale + panX, centerY + (y - centerY) * scale + panY)
    }
    
    /// Zooms by `factor` keeping the point under the focus (between the fingers) where it is.
    public func zoomed(by factor: Double, focusX: Double, focusY: Double, centerX: Double, centerY: Double) -> MapViewport {
        let newScale = min(max(scale * factor, Self.minScale), Self.maxScale)
        let applied = newScale / scale
        // The point under the focus, relative to the center, before the zoom is (focus - center - pan) / scale;
        // after it, it must still be under the focus: pan' = focus - center - (focus - center - pan) * applied.
        let fromCenterX = focusX - centerX
        let fromCenterY = focusY - centerY
        return MapViewport(scale: newScale, panX: fromCenterX - (fromCenterX - panX) * applied, panY: fromCenterY - (fromCenterY - panY) * applied)
    }
    
    public func panned(byX dx: Double, y dy: Double) -> MapViewport {
        MapViewport(scale: scale, panX: panX + dx, panY: panY + dy)
    }
}
