import AppKit
import SwiftUI

/// A row of one-click book colors followed by the system color picker.
struct ColorSwatches: View {
    let colors: [UInt32]
    let selected: UInt32
    let label: String
    let onSelect: (UInt32) -> Void

    private let pine = Theme.accent

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Self.unique(colors), id: \.self) { value in
                let active = value == selected
                Button { onSelect(value) } label: {
                    Circle()
                        .fill(Color(cgColor: EditorialStyle.color(value)))
                        .overlay { Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5) }
                        .padding(active ? 2.5 : 0)
                        .overlay { Circle().strokeBorder(active ? pine : .clear, lineWidth: 1.5) }
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: "#%06X", value))
                .accessibilityAddTraits(active ? .isSelected : [])
                .help(String(format: "#%06X", value))
            }
            ColorPicker(label, selection: Binding(
                get: { Color(cgColor: EditorialStyle.color(selected)) },
                set: { color in if let value = Self.rgb(color) { onSelect(value) } }
            ), supportsOpacity: false)
            .labelsHidden()
            .help(label)
        }
    }

    static func unique(_ colors: [UInt32]) -> [UInt32] {
        var seen = Set<UInt32>()
        return colors.filter { seen.insert($0).inserted }
    }

    static func rgb(_ color: Color) -> UInt32? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (UInt32((rgb.redComponent * 255).rounded()) << 16)
            | (UInt32((rgb.greenComponent * 255).rounded()) << 8)
            | UInt32((rgb.blueComponent * 255).rounded())
    }
}
