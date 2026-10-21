// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Markup",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Software updates, in the app bundle only (see Updater.swift).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Markdown conversion, kept free of AppKit so it can be unit tested.
        .target(name: "MarkupCore"),
        .executableTarget(
            name: "Markup",
            dependencies: ["MarkupCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // The app bundle has Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                // There is no app bundle, so embed Info.plist in the executable.
                // NSDocumentController reads the document types from it.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", Context.packageDirectory + "/Info.plist",
                ]),
                // `swift run` has no app bundle to take the icon from, so debug
                // builds embed the artwork too (see DevelopmentIcon.swift).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__markup_icon",
                    "-Xlinker", Context.packageDirectory + "/img/Markup.png",
                ], .when(configuration: .debug)),
            ]
        ),
        .testTarget(name: "MarkupCoreTests", dependencies: ["MarkupCore"]),
        .testTarget(name: "MarkupTests", dependencies: ["Markup"]),
    ]
)
