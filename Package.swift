// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhatPort",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhatPort", targets: ["WhatPort"]),
        .library(name: "WhatPortCore", targets: ["WhatPortCore"]),
        .library(name: "WhatPortIOKit", targets: ["WhatPortIOKit"])
    ],
    targets: [
        .target(
            name: "WhatPortCore",
            path: "Sources/WhatPortCore"
        ),
        .target(
            name: "WhatPortIOKit",
            dependencies: ["WhatPortCore"],
            path: "Sources/WhatPortIOKit",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "WhatPort",
            dependencies: ["WhatPortCore", "WhatPortIOKit"],
            path: "Sources/WhatPort",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "WhatPortCoreTests",
            dependencies: ["WhatPortCore", "WhatPortIOKit"],
            path: "Tests/WhatPortCoreTests"
        )
    ]
)
