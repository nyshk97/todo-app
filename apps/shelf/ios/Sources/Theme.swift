import SwiftUI

enum Theme {
    // Backgrounds
    static let bgPage = Color(red: 0.031, green: 0.035, blue: 0.039)       // #08090a
    static let bgPanel = Color(red: 0.059, green: 0.063, blue: 0.067)      // #0f1011
    static let bgSurface = Color(red: 0.098, green: 0.102, blue: 0.106)    // #191a1b
    static let bgElevated = Color(red: 0.157, green: 0.157, blue: 0.173)   // #28282c

    // Text
    static let textPrimary = Color(red: 0.969, green: 0.973, blue: 0.973)  // #f7f8f8
    static let textSecondary = Color(red: 0.816, green: 0.839, blue: 0.878) // #d0d6e0
    static let textTertiary = Color(red: 0.541, green: 0.561, blue: 0.596) // #8a8f98
    static let textQuaternary = Color(red: 0.384, green: 0.400, blue: 0.427) // #62666d

    // Borders
    static let borderSubtle = Color.white.opacity(0.05)
    static let borderStandard = Color.white.opacity(0.08)
    static let borderSolid = Color(red: 0.137, green: 0.145, blue: 0.165) // #23252a

    // Accents
    static let orange = Color(red: 0.961, green: 0.620, blue: 0.043)      // #f59e0b
    static let red = Color(red: 0.937, green: 0.267, blue: 0.267)         // #ef4444
    static let green = Color(red: 0.153, green: 0.651, blue: 0.267)       // #27a644
    static let accentBright = Color(red: 0.306, green: 0.522, blue: 1.0)  // #4e85ff
}
