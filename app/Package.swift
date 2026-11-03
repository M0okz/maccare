// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacCare",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Cible C qui expose la frontière du moteur Rust (en-tête + modulemap).
        .target(name: "CMacCareCore"),
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "MacCareMaintenance", dependencies: ["CSQLite"]),
        // Protocole XPC partagé entre l'app et l'assistant privilégié.
        .target(name: "MacCareHelperProtocol"),
        .target(name: "CMacCareSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "CMacCarePowerUI", linkerSettings: [.linkedFramework("Foundation")]),
        .target(name: "MacCareBattery", dependencies: ["CMacCareSMC", "CMacCarePowerUI"]),
        // Assistant privilégié (démon root lancé par launchd, règles système fermées du moteur).
        .executableTarget(
            name: "MacCareHelper",
            dependencies: ["CMacCareCore", "MacCareHelperProtocol", "MacCareMaintenance", "MacCareBattery"],
            linkerSettings: [
                .linkedLibrary("maccare_core")
            ]
        ),
        // Application SwiftUI.
        .executableTarget(
            name: "MacCare",
            dependencies: ["CMacCareCore", "MacCareHelperProtocol", "MacCareMaintenance", "MacCareBattery", "CSQLite",
                           .product(name: "Sparkle", package: "Sparkle")],
            // La bibliothèque statique Rust est liée via le script app/build.sh
            // (-L core/target/release -lmaccare_core).
            linkerSettings: [
                .linkedLibrary("maccare_core"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(name: "MacCareBatteryTests", dependencies: ["MacCareBattery"]),
        .testTarget(name: "MacCareTests", dependencies: ["MacCare", "MacCareMaintenance", "MacCareHelperProtocol", "MacCareBattery"]),
    ]
)
