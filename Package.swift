// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MatTerm",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "MatTerm", targets: ["MatTerm"])
    ],
    targets: [
        .executableTarget(
            name: "MatTerm",
            path: "Sources/MatTerm"
        )
    ]
)
