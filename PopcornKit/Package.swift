// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PopcornKit",
    platforms: [
        .iOS(.v18), .tvOS(.v18), .macOS(.v15)
    ],
    products: [
        .library(name: "PopcornKit", targets: ["PopcornKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", from: "5.0.2"),
        .package(url: "https://github.com/tristanhimmelman/ObjectMapper", from: "4.4.3"),
    ],
    targets: [
        .target(
            name: "PopcornKit",
            dependencies: ["SwiftyJSON", "ObjectMapper"],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
