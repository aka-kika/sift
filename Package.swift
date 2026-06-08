// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sift",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sift", targets: ["Sift"])
    ],
    targets: [
        .executableTarget(
            name: "Sift",
            path: "Sources/AppAudit",
            exclude: ["AppAudit.entitlements"]
        ),
        .testTarget(
            name: "SiftTests",
            dependencies: ["Sift"],
            path: "Tests/AppAuditTests"
        )
    ]
)
