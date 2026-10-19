// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SplashLauncher",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(name: "SplashLauncher", resources: [.copy("Resources/Splash.icns")]),
        .testTarget(
            name: "SplashLauncherTests",
            dependencies: ["SplashLauncher"]
        ),
    ]
)
