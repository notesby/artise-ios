// swift-tools-version: 6.2
//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import PackageDescription

let package = Package(name: "Artise",
                      platforms: [.iOS(.v18), .macOS(.v15)],
                      products: [
                          .library(name: "ArtiseCore", targets: ["ArtiseCore"])
                      ],
                      targets: [
                          .target(name: "ArtiseCore"),
                          .testTarget(name: "ArtiseCoreTests", dependencies: ["ArtiseCore"])
                      ])
