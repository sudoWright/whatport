import Foundation

extension Bundle {
    /// Locates the SwiftPM-generated resource bundle ("WhatPort_WhatPort.bundle")
    /// across the layouts WhatPort actually runs in.
    ///
    /// SwiftPM's generated `Bundle.module` only checks two locations: a path
    /// relative to the running executable's bundle, and a `.build` path that is
    /// hardcoded at compile time. In a packaged, signed .app the resources live
    /// in `Contents/Resources/`, which `Bundle.module` never inspects, so it
    /// traps at launch on any machine that lacks the original build directory.
    /// This resolver checks the .app's Resources first, then the
    /// executable-relative location used during `swift build` development.
    static nonisolated let whatPortResources: Bundle = {
        let bundleName = "WhatPort_WhatPort.bundle"
        let searchURLs = [
            Bundle.main.resourceURL,  // packaged .app: Contents/Resources
            Bundle.main.bundleURL     // swift build: beside the executable
        ].compactMap { $0 }

        for base in searchURLs {
            let candidate = base.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        // Degrade to the main bundle so callers get "resource not found"
        // rather than crashing if the resource bundle is ever missing.
        return .main
    }()
}
