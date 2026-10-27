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
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                // SwiftPM stamps the binary with the deployment target as its SDK
                // (14.0), so macOS 26 drew Sift in its old style: a full-height
                // sidebar with divider lines and a separate gray top bar
                // (Kika, 28 Oct). Stamping SDK 26 opts into the macOS 26 window.
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "14.0", "-Xlinker", "26.0"])
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
