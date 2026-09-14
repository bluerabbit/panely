// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Panely",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // MultitouchSupport.framework の構造体定義。公開ヘッダが無いため C で固定し、
        // Swift 側の構造体レイアウト推測に頼らない。
        .target(
            name: "CMultitouch",
            path: "Sources/CMultitouch"
        ),
        // 検証用 CLI。MultitouchSupport からタッチフレームが取れるかを確かめる。
        .executableTarget(
            name: "mt-spike",
            dependencies: ["CMultitouch"],
            path: "Sources/mt-spike"
        ),
        // 本体。Layout/ と Gesture/ は AppKit に依存しない純粋ロジックで、テストから @testable import する。
        .executableTarget(
            name: "Panely",
            dependencies: ["CMultitouch"],
            path: "Sources/Panely"
        ),
        .testTarget(
            name: "PanelyTests",
            dependencies: ["Panely"],
            path: "Tests/PanelyTests"
        ),
    ]
)
