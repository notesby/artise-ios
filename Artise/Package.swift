// swift-tools-version: 6.2
//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import PackageDescription

let package = Package(name: "Artise",
                      defaultLocalization: "en",
                      platforms: [.iOS(.v18), .macOS(.v15)],
                      products: [
                          .library(name: "ArtiseCore", targets: ["ArtiseCore"]),
                          .library(name: "ArtiseNotes", targets: ["ArtiseNotes"])
                      ],
                      dependencies: [
                          .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.9.0")
                      ],
                      targets: [
                          .target(name: "ArtiseCore"),
                          .target(name: "ArtiseNotes",
                                  dependencies: ["ArtiseCore", .product(name: "Markdown", package: "swift-markdown")]),
                          .testTarget(name: "ArtiseCoreTests", dependencies: ["ArtiseCore"]),
                          .testTarget(name: "ArtiseNotesTests", dependencies: ["ArtiseNotes"])
                      ])
