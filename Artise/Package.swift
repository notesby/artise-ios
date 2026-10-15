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
                          .library(name: "ArtiseNotes", targets: ["ArtiseNotes"]),
                          .library(name: "ArtiseStickers", targets: ["ArtiseStickers"]),
                          .library(name: "ArtiseLinkPreview", targets: ["ArtiseLinkPreview"]),
                          .library(name: "ArtiseWorkspaces", targets: ["ArtiseWorkspaces"])
                      ],
                      dependencies: [
                          .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.9.0")
                      ],
                      targets: [
                          .target(name: "ArtiseCore"),
                          .target(name: "ArtiseNotes",
                                  dependencies: ["ArtiseCore", .product(name: "Markdown", package: "swift-markdown")]),
                          .target(name: "ArtiseStickers",
                                  dependencies: ["ArtiseCore"],
                                  resources: [.copy("Resources/Starter")]),
                          .target(name: "ArtiseLinkPreview"),
                          .target(name: "ArtiseWorkspaces", dependencies: ["ArtiseCore"]),
                          .testTarget(name: "ArtiseCoreTests", dependencies: ["ArtiseCore"]),
                          .testTarget(name: "ArtiseNotesTests", dependencies: ["ArtiseNotes"]),
                          .testTarget(name: "ArtiseStickersTests", dependencies: ["ArtiseStickers"]),
                          .testTarget(name: "ArtiseLinkPreviewTests", dependencies: ["ArtiseLinkPreview"]),
                          .testTarget(name: "ArtiseWorkspacesTests", dependencies: ["ArtiseWorkspaces"])
                      ])
