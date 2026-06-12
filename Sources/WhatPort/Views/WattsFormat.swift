import Foundation

enum WattsFormat {
    // Two decimals under 1 W (stable width for the list column), one decimal
    // at 1 W or above with a trailing ".0" dropped, always a space before the
    // unit. 0.55 -> "0.55 W", 7.8 -> "7.8 W", 100 -> "100 W".
    static func string(_ watts: Double) -> String {
        if watts < 1 {
            return String(format: "%.2f W", watts)
        }
        // Check the FORMATTED value for a whole number, not the raw one:
        // 7.96 formats to "8.0", which must render as "8 W".
        let formatted = String(format: "%.1f", watts)
        if formatted.hasSuffix(".0") {
            return "\(formatted.dropLast(2)) W"
        }
        return "\(formatted) W"
    }
}
