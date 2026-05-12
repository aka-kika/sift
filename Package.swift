// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppAudit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AppAudit", targets: ["AppAudit"])
    ],
    targets: [
        .executableTarget(
            name: "AppAudit",
            path: "Sources/AppAudit",
            exclude: ["AppAudit.entitlements"]
        ),
        .testTarget(
            name: "AppAuditTests",
            dependencies: ["AppAudit"],
            path: "Tests/AppAuditTests"
        )
    ]
)
