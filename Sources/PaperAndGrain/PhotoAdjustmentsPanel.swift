import SwiftUI

struct PhotoAdjustmentsPanel: View, Localizing {
    @Binding var adjustments: PhotoAdjustments
    let language: String
    let isEnhancing: Bool
    @Binding var comparingOriginal: Bool
    let onAutomatic: () -> Void
    let onReset: () -> Void
    let onEditingChanged: (Bool) -> Void

    /// Everything starts closed: opening a photo should not build dozens of sliders at once.
    @State private var expanded: Set<Group> = []

    private let pine = Theme.accent

    private enum Group: CaseIterable {
        case light, color, monochrome, detail, curves, levels, selectiveColor

        /// The English title, which is also the catalog key.
        var title: String {
            switch self {
            case .light: "Light"
            case .color: "Color"
            case .monochrome: "Black & White"
            case .detail: "Detail"
            case .curves: "Curves"
            case .levels: "Levels"
            case .selectiveColor: "Selective Color"
            }
        }
    }

    private struct Control: Identifiable {
        enum Format {
            case percent, exposure, gamma, hue

            var step: Double {
                switch self {
                case .percent, .gamma: 0.01
                case .exposure: 0.05
                case .hue: 1.0 / 45
                }
            }
        }

        /// The English name, which is also the catalog key.
        let title: String
        let keyPath: WritableKeyPath<PhotoAdjustments, Double>
        let range: ClosedRange<Double>
        let format: Format

        var id: WritableKeyPath<PhotoAdjustments, Double> { keyPath }

        init(_ title: String, _ keyPath: WritableKeyPath<PhotoAdjustments, Double>,
             _ range: ClosedRange<Double> = -1...1, format: Format = .percent) {
            self.title = title
            self.keyPath = keyPath
            self.range = range
            self.format = format
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            Toggle(tr("Compare with original"), isOn: $comparingOriginal)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Group.allCases, id: \.self) { group in
                    Divider()
                    section(group)
                }
            }
        }
        .controlSize(.small)
        .tint(pine)
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            Button(action: onAutomatic) {
                Label {
                    Text(tr("Auto Enhance"))
                } icon: {
                    if isEnhancing {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isEnhancing)
            .accessibilityValue(isEnhancing ? tr("In progress") : "")
            .help(tr("Automatically adjust light and color"))

            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(adjustments == PhotoAdjustments() && !isEnhancing)
            .accessibilityLabel(tr("Reset adjustments"))
            .help(tr("Reset adjustments"))
        }
    }

    private func section(_ group: Group) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(group) },
            set: { isExpanded in
                if isExpanded { expanded.insert(group) }
                else { expanded.remove(group) }
            }
        )) {
            if expanded.contains(group) {
                VStack(alignment: .leading, spacing: 4) {
                    if group == .curves { curveGuide }
                    if group == .selectiveColor { colorChoices }
                    ForEach(controls(in: group)) { control in
                        slider(control)
                            .disabled(group == .monochrome && control.keyPath != \PhotoAdjustments.monochrome
                                      && adjustments.monochrome == 0)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 3)
            }
        } label: {
            Text(tr(group.title))
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.vertical, 4)
    }

    private func controls(in group: Group) -> [Control] {
        switch group {
        case .light:
            [Control("Brilliance", \.brilliance),
             Control("Exposure", \.exposure, -2...2, format: .exposure),
             Control("Highlights", \.highlights),
             Control("Shadows", \.shadows),
             Control("Brightness", \.brightness),
             Control("Contrast", \.contrast),
             Control("Black Point", \.blackPoint)]
        case .color:
            [Control("Saturation", \.saturation),
             Control("Vibrance", \.vibrance),
             Control("Warmth", \.warmth),
             Control("Tint", \.tint)]
        case .monochrome:
            [Control("Intensity", \.monochrome, 0...1),
             Control("Neutrals", \.monochromeNeutrals),
             Control("Tone", \.monochromeTone),
             Control("Grain", \.monochromeGrain, 0...1)]
        case .detail:
            [Control("Definition", \.definition, 0...1),
             Control("Sharpness", \.sharpness, 0...1),
             Control("Noise Reduction", \.noiseReduction, 0...1),
             Control("Vignette", \.vignette, 0...1)]
        case .curves:
            [Control("Shadows", \.curveShadows),
             Control("Midtones", \.curveMidtones),
             Control("Highlights", \.curveHighlights)]
        case .levels:
            [Control("Black", \.levelsBlack, 0...0.45),
             Control("White", \.levelsWhite, 0.55...1),
             Control("Gamma", \.levelsGamma, 0.4...2.5, format: .gamma)]
        case .selectiveColor:
            [Control("Hue", \.selectiveHue, format: .hue),
             Control("Saturation", \.selectiveSaturation),
             Control("Lightness", \.selectiveLightness)]
        }
    }

    private func slider(_ control: Control) -> some View {
        let title = tr(control.title)
        let value = display(adjustments[keyPath: control.keyPath], format: control.format)
        return HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: 93, alignment: .leading)
                .accessibilityHidden(true)

            // No `step:` here: on macOS it becomes one tick mark per step, and AppKit rebuilds
            // hundreds of tick rectangles per slider whenever the panel appears or goes away.
            Slider(value: Binding(
                get: { adjustments[keyPath: control.keyPath] },
                set: { setValue(Self.quantized($0, step: control.format.step, in: control.range), at: control.keyPath) }
            ), in: control.range, onEditingChanged: onEditingChanged)
                .accessibilityLabel(title)
                .accessibilityValue(value)

            Text(value)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var curveGuide: some View {
        let points = adjustments.curvePoints
        return Canvas { context, size in
            let inset: CGFloat = 5
            let width = size.width - 2 * inset
            let height = size.height - 2 * inset
            func position(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: inset + x * width, y: inset + (1 - y) * height)
            }

            var grid = Path()
            for point in points {
                grid.move(to: position(point.x, 0))
                grid.addLine(to: position(point.x, 1))
                grid.move(to: position(0, point.x))
                grid.addLine(to: position(1, point.x))
            }
            context.stroke(grid, with: .color(pine.opacity(0.18)), lineWidth: 0.5)

            var identity = Path()
            identity.move(to: position(0, 0))
            identity.addLine(to: position(1, 1))
            context.stroke(identity, with: .color(pine.opacity(0.38)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            var curve = Path()
            curve.addLines(points.map { position($0.x, $0.y) })
            context.stroke(curve, with: .color(pine), lineWidth: 1.5)
        }
        .frame(height: 58)
        .background(pine.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }

    private var colorChoices: some View {
        HStack(spacing: 4) {
            ForEach(PhotoAdjustments.SelectiveColor.allCases) { choice in
                let title = colorName(choice)
                let selected = adjustments.selectiveColor == choice
                Button {
                    setValue(choice, at: \.selectiveColor)
                } label: {
                    Circle()
                        .fill(Color(hue: choice.hue / 360, saturation: 0.72, brightness: 0.78))
                        .frame(width: 13, height: 13)
                        .padding(3)
                        .background {
                            Circle().strokeBorder(selected ? pine : .clear, lineWidth: 1.5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(title)
            }
        }
        .padding(.bottom, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Color range"))
    }

    private func colorName(_ choice: PhotoAdjustments.SelectiveColor) -> String {
        switch choice {
        case .red: tr("Red")
        case .orange: tr("Orange")
        case .yellow: tr("Yellow")
        case .green: tr("Green")
        case .cyan: tr("Cyan")
        case .blue: tr("Blue")
        case .magenta: tr("Magenta")
        }
    }

    static func quantized(_ value: Double, step: Double, in range: ClosedRange<Double>) -> Double {
        guard step > 0, value.isFinite else { return value }
        let snapped = range.lowerBound + ((value - range.lowerBound) / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    private func setValue<Value: Equatable>(_ value: Value, at keyPath: WritableKeyPath<PhotoAdjustments, Value>) {
        guard adjustments[keyPath: keyPath] != value else { return }
        comparingOriginal = false
        adjustments[keyPath: keyPath] = value
    }

    private func display(_ value: Double, format: Control.Format) -> String {
        let style = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: language))
        switch format {
        case .percent:
            return value.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: language)))
        case .exposure:
            return value.formatted(style.precision(.fractionLength(2))) + " EV"
        case .gamma:
            return value.formatted(style.precision(.fractionLength(2)))
        case .hue:
            return (value * 45).formatted(style.precision(.fractionLength(0))) + "°"
        }
    }
}
