// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftStreamingMarkdown",
  defaultLocalization: "en",
  platforms: [.iOS(.v16), .macOS(.v14)],
  products: [
    .library(
      name: "SwiftStreamingMarkdown",
      targets: ["SwiftStreamingMarkdown"])
  ],
  dependencies: [
    .package(url: "https://github.com/ordo-one/equatable", exact: "1.4.1"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.3"),
    .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3"),
    .package(url: "https://github.com/appstefan/highlightswift", revision: "99c431b38a1444a5fd6a4978307fbbefe3a7af53"),
    .package(url: "https://github.com/WroughtMind/SwiftMath", revision: "62b4ccad3faf21806525cc3788f097858b99628f"),
    .package(url: "https://github.com/markiv/SwiftUI-Shimmer", exact: "1.5.1")
  ],
  targets: [
    .target(
      name: "SwiftStreamingMarkdown",
      dependencies: [
        .product(name: "Equatable", package: "equatable"),
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "HighlightSwift", package: "highlightswift"),
        .product(name: "SwiftMath", package: "SwiftMath"),
        .product(name: "Shimmer", package: "SwiftUI-Shimmer")
      ],
      path: "Sources/MarkdownText",
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "SwiftStreamingMarkdownTests",
      dependencies: [
        "SwiftStreamingMarkdown",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
      ],
      path: "Tests/MarkdownTextTests",
      resources: [
        .process("Resources")
      ])
  ]
)
