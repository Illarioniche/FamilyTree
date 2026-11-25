// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FamilyTree",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FamilyTreeCore", targets: ["FamilyTreeCore"]),
        .executable(name: "FamilyTree", targets: ["FamilyTreeApp"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite3"])]),
        .target(name: "FamilyTreeCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "FamilyTreeApp", dependencies: ["FamilyTreeCore"]),
        .testTarget(name: "FamilyTreeCoreTests", dependencies: ["FamilyTreeCore"])
    ],
    swiftLanguageModes: [.v5]
)
