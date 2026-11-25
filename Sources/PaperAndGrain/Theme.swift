import AppKit
import SwiftUI

/// Semantic colors for the app's chrome. Book pages keep the colors of their template;
/// everything around them follows the system appearance and Increase Contrast.
enum Theme {
    /// Brand accent (pine). Used for selection, primary actions and focus.
    static let accent = dynamic(light: 0x23503B, dark: 0x4E9A73,
                                lightContrast: 0x163828, darkContrast: 0x6CC294)
    /// Primary text on chrome.
    static let ink = dynamic(light: 0x222A22, dark: 0xE9E7E0)
    /// Secondary text. Meets 4.5:1 on `panel` in both appearances.
    static let muted = dynamic(light: 0x4F584F, dark: 0xA9ACA4)
    /// Text fields and editable surfaces inside panels.
    static let field = dynamic(light: 0xFBF9F3, dark: 0x2B2D29)
    /// Inspector and tray surfaces when glass is not available.
    static let panel = dynamic(light: 0xF3F2EB, dark: 0x242622)
    /// The navigator column on macOS 14 and 15.
    static let sidebar = dynamic(light: 0xECEBE3, dark: 0x202220)
    /// Hairlines between panes.
    static let edge = dynamic(light: 0xD3D4CA, dark: 0x3A3D37)
    /// The light table under the book: neutral so photos read true.
    static let table = dynamic(light: 0xE4E2DB, dark: 0x1A1B19)
    /// Destructive actions.
    static let destructive = dynamic(light: 0x9C4329, dark: 0xE27E62)
    /// Alignment guides on the canvas.
    static let guide = Color(red: 0.81, green: 0.13, blue: 0.39)
    /// The welcome window's editorial background and title.
    static let welcome = dynamic(light: 0xF6F1E5, dark: 0x1D201D)
    static let welcomeInk = dynamic(light: 0x24392C, dark: 0xEAE3D2)

    private static func dynamic(light: UInt32, dark: UInt32,
                                lightContrast: UInt32? = nil, darkContrast: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua,
                                                    .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            switch match {
            case .darkAqua?: return color(dark)
            case .accessibilityHighContrastDarkAqua?: return color(darkContrast ?? dark)
            case .accessibilityHighContrastAqua?: return color(lightContrast ?? light)
            default: return color(light)
            }
        })
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// A floating panel: Liquid Glass on macOS 26 and later, a material on earlier systems.
    @ViewBuilder func floatingPanel(cornerRadius: CGFloat = 18) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.edge.opacity(0.7), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        }
    }

    /// A small floating control bar over the canvas (view controls, selection actions).
    @ViewBuilder func floatingCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.edge.opacity(0.7), lineWidth: 0.5).allowsHitTesting(false) }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        }
    }

    /// The prominent toolbar action: tinted glass on macOS 26, a prominent bordered button before.
    @ViewBuilder func prominentToolbarButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
