import SwiftUI

struct PhotoAdjustmentsPanel: View {
    @Binding var adjustments: PhotoAdjustments
    let language: String
    let isEnhancing: Bool
    @Binding var comparingOriginal: Bool
    let onAutomatic: () -> Void
    let onReset: () -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var expanded: Set<Group> = [.light]

    private let pine = Color(red: 0.14, green: 0.31, blue: 0.23)

    private enum Group: CaseIterable {
        case light, color, monochrome, detail, curves, levels, selectiveColor

        var title: (italian: String, english: String) {
            switch self {
            case .light: ("Luce", "Light")
            case .color: ("Colore", "Color")
            case .monochrome: ("Bianco e nero", "Black & White")
            case .detail: ("Dettagli", "Detail")
            case .curves: ("Curve", "Curves")
            case .levels: ("Livelli", "Levels")
            case .selectiveColor: ("Colore selettivo", "Selective Color")
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

        let italian: String
        let english: String
        let keyPath: WritableKeyPath<PhotoAdjustments, Double>
        let range: ClosedRange<Double>
        let format: Format

        var id: WritableKeyPath<PhotoAdjustments, Double> { keyPath }

        init(_ italian: String, _ english: String, _ keyPath: WritableKeyPath<PhotoAdjustments, Double>,
             _ range: ClosedRange<Double> = -1...1, format: Format = .percent) {
            self.italian = italian
            self.english = english
            self.keyPath = keyPath
            self.range = range
            self.format = format
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            Toggle(tr("Confronta con l’originale", "Compare with original"), isOn: $comparingOriginal)
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
                    Text(tr("Migliora in automatico", "Auto Enhance"))
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
            .accessibilityValue(isEnhancing ? tr("In corso", "In progress") : "")
            .help(tr("Regola automaticamente luce e colore", "Automatically adjust light and color"))

            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(adjustments == PhotoAdjustments() && !isEnhancing)
            .accessibilityLabel(tr("Ripristina regolazioni", "Reset adjustments"))
            .help(tr("Ripristina regolazioni", "Reset adjustments"))
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
        } label: {
            Text(tr(group.title.italian, group.title.english))
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.vertical, 4)
    }

    private func controls(in group: Group) -> [Control] {
        switch group {
        case .light:
            [Control("Brillantezza", "Brilliance", \.brilliance),
             Control("Esposizione", "Exposure", \.exposure, -2...2, format: .exposure),
             Control("Luci", "Highlights", \.highlights),
             Control("Ombre", "Shadows", \.shadows),
             Control("Luminosità", "Brightness", \.brightness),
             Control("Contrasto", "Contrast", \.contrast),
             Control("Punto di nero", "Black Point", \.blackPoint)]
        case .color:
            [Control("Saturazione", "Saturation", \.saturation),
             Control("Vividezza", "Vibrance", \.vibrance),
             Control("Temperatura", "Warmth", \.warmth),
             Control("Tinta", "Tint", \.tint)]
        case .monochrome:
            [Control("Intensità", "Intensity", \.monochrome, 0...1),
             Control("Toni neutri", "Neutrals", \.monochromeNeutrals),
             Control("Tonalità", "Tone", \.monochromeTone),
             Control("Grana", "Grain", \.monochromeGrain, 0...1)]
        case .detail:
            [Control("Definizione", "Definition", \.definition, 0...1),
             Control("Nitidezza", "Sharpness", \.sharpness, 0...1),
             Control("Riduzione disturbo", "Noise Reduction", \.noiseReduction, 0...1),
             Control("Vignettatura", "Vignette", \.vignette, 0...1)]
        case .curves:
            [Control("Ombre", "Shadows", \.curveShadows),
             Control("Mezzitoni", "Midtones", \.curveMidtones),
             Control("Luci", "Highlights", \.curveHighlights)]
        case .levels:
            [Control("Nero", "Black", \.levelsBlack, 0...0.45),
             Control("Bianco", "White", \.levelsWhite, 0.55...1),
             Control("Gamma", "Gamma", \.levelsGamma, 0.4...2.5, format: .gamma)]
        case .selectiveColor:
            [Control("Tonalità", "Hue", \.selectiveHue, format: .hue),
             Control("Saturazione", "Saturation", \.selectiveSaturation),
             Control("Luminosità", "Lightness", \.selectiveLightness)]
        }
    }

    private func slider(_ control: Control) -> some View {
        let title = tr(control.italian, control.english)
        let value = display(adjustments[keyPath: control.keyPath], format: control.format)
        return HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: 93, alignment: .leading)
                .accessibilityHidden(true)

            Slider(value: Binding(
                get: { adjustments[keyPath: control.keyPath] },
                set: { setValue($0, at: control.keyPath) }
            ), in: control.range, step: control.format.step, onEditingChanged: onEditingChanged)
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
        .accessibilityLabel(tr("Intervallo di colore", "Color range"))
    }

    private func colorName(_ choice: PhotoAdjustments.SelectiveColor) -> String {
        switch choice {
        case .red: tr("Rosso", "Red")
        case .orange: tr("Arancione", "Orange")
        case .yellow: tr("Giallo", "Yellow")
        case .green: tr("Verde", "Green")
        case .cyan: tr("Ciano", "Cyan")
        case .blue: tr("Blu", "Blue")
        case .magenta: tr("Magenta", "Magenta")
        }
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

    private func tr(_ italian: String, _ english: String) -> String {
        language.hasPrefix("it") ? italian : english
    }
}
