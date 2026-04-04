import SwiftUI

extension Font {
    // UI text - Inter
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

    // Code and metrics - JetBrains Mono
    static func code(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrainsMono-Regular", size: size).weight(weight)
    }

    // Labels - Space Grotesk
    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("SpaceGrotesk-Medium", size: size).weight(weight)
    }
}
