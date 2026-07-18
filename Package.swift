// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mcp-snippetslab",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "mcp-snippetslab",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "mcp-snippetslabTests",
            dependencies: [
                "mcp-snippetslab",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ]
)
