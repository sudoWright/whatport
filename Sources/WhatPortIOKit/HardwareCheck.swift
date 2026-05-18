import Foundation
import IOKit

// Checks hardware compatibility at launch.
public enum HardwareCheck {
    // Apple Silicon Macs have AppleTypeCPhy services.
    // Intel Macs use different IOKit classes and are not supported.
    public static func isAppleSilicon() -> Bool {
        let matching = IOServiceMatching("AppleTypeCPhy")
        var iter: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)
        guard kr == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iter) }

        let found = IOIteratorNext(iter) != 0
        return found
    }
}
