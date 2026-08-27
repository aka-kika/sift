// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sift",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sift", targets: ["Sift"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Sift",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/AppAudit",
            exclude: ["AppAudit.entitlements"],
            linkerSettings: [
                // Sparkle.framework is embedded by Scripts/package_app.sh into
                // Contents/Frameworks; the binary must look for it there.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "SiftTests",
            dependencies: ["Sift"],
            path: "Tests/AppAuditTests",
            linkerSettings: [
                // The test bundle has no Contents/Frameworks; point it at the SwiftPM
                // artifact so Sparkle loads under `swift test`.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker",
                              Context.packageDirectory + "/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"])
            ]
        )
    ]
)
