// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TutorCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TutorCore", targets: ["TutorCore"])
    ],
    targets: [
        .target(name: "TutorCore", path: "Sources/TutorCore"),
        .testTarget(name: "TutorCoreTests", dependencies: ["TutorCore"], path: "Tests/TutorCoreTests")
    ]
)
