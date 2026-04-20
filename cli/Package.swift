// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sbx-ui",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SBXCore", targets: ["SBXCore"]),
        .executable(name: "sbx-ui-cli", targets: ["sbx-ui-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SBXCore",
            path: "SBXCore",
            sources: [
                "Models/DomainTypes.swift",
                "Models/ReleaseChannel.swift",
                "Services/SbxServiceProtocol.swift",
                "Services/RealSbxService.swift",
                "Services/CliExecutor.swift",
                "Services/SbxOutputParser.swift",
                "Services/ServiceFactory.swift",
                "Services/LinuxShims.swift",
                "Services/EditorDocumentProvider.swift",
                "Services/EditorPath.swift",
            ],
            swiftSettings: [
                .define("SBX_SPM"),
            ]
        ),
        .executableTarget(
            name: "sbx-ui-cli",
            dependencies: [
                "SBXCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/sbx-ui-cli"
        ),
        .testTarget(
            name: "SBXCoreTests",
            dependencies: ["SBXCore"],
            path: "Tests/SBXCoreTests"
        ),
        .testTarget(
            name: "CLIE2ETests",
            dependencies: ["SBXCore", "sbx-ui-cli"],
            path: "Tests/CLIE2ETests"
        ),
    ]
)
