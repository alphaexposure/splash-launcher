// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SplashLauncher",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        // The icon file is packaged into the .app by Scripts/build-app.zsh, not as a SwiftPM
        // resource: SwiftPM's resource-bundle lookup varies between Swift versions and crashed
        // released builds.
        .executableTarget(name: "SplashLauncher", exclude: ["Resources/Splash.icns"]),
        .testTarget(
            name: "SplashLauncherTests",
            dependencies: ["SplashLauncher"]
        ),
    ]
)
