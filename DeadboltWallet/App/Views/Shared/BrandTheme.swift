import SwiftUI

/// Deadbolt brand design system colors.
/// Palette rooted in "Terminal Dark" aesthetic with high-energy industrial accent.
enum Brand {
    // MARK: - Primary Palette
    static let onyxBlack = Color(red: 0, green: 0, blue: 0)                           // #000000
    static let pureWhite = Color(red: 1, green: 1, blue: 1)                            // #FFFFFF

    // MARK: - Functional Palette (UI States)
    static let solarFlare = Color(red: 0xF8/255, green: 0x70/255, blue: 0x40/255)     // #F87040 — Awaiting Approval
    static let steelGray = Color(red: 0x70/255, green: 0x70/255, blue: 0x70/255)      // #707070 — Locked/Inactive
    static let cryptoGreen = Color(red: 0x2E/255, green: 0xCC/255, blue: 0x71/255)    // #2ECC71 — Signed/Success

    // MARK: - Derived Colors
    static let cardBackground = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.1)
    static let subtleText = Color.white.opacity(0.5)
}

// MARK: - macOS Sheet Safe-Area Fix

#if os(macOS)
struct SheetToolbarFix: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
                .toolbar(.hidden, for: .windowToolbar)
                .ignoresSafeArea()
        }
    }
}

extension View {
    func sheetToolbarFix() -> some View {
        modifier(SheetToolbarFix())
    }
}
#else
extension View {
    func sheetToolbarFix() -> some View { self }
}
#endif
