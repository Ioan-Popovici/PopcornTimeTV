// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "PopcornKit",
    platforms: [
        .iOS(.v26), .tvOS(.v26), .macOS(.v26)
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
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
