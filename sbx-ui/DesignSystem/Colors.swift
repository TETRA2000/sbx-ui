import SwiftUI

extension Color {
    // Surface hierarchy (The Technical Monolith)
    static let surfaceLowest = Color(red: 0x0E / 255.0, green: 0x0E / 255.0, blue: 0x0E / 255.0)       // #0E0E0E
    static let surface = Color(red: 0x13 / 255.0, green: 0x13 / 255.0, blue: 0x13 / 255.0)              // #131313
    static let surfaceContainer = Color(red: 0x1C / 255.0, green: 0x1B / 255.0, blue: 0x1B / 255.0)     // #1C1B1B
    static let surfaceContainerHigh = Color(red: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x2A / 255.0) // #2A2A2A
    static let surfaceContainerHighest = Color(red: 0x35 / 255.0, green: 0x35 / 255.0, blue: 0x34 / 255.0) // #353534

    // Accent colors
    static let accent = Color(red: 0xAD / 255.0, green: 0xC6 / 255.0, blue: 0xFF / 255.0)              // #ADC6FF
    static let secondary = Color(red: 0x4E / 255.0, green: 0xDE / 255.0, blue: 0xA3 / 255.0)            // #4EDEA3
    static let error = Color(red: 0xF2 / 255.0, green: 0xB8 / 255.0, blue: 0xB5 / 255.0)               // #F2B8B5
}
