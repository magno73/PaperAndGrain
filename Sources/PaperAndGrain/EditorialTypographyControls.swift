import AppKit
import SwiftUI

struct EditorialTypographyControls: View {
    @Binding var style: EditorialTextStyle?
    let inherited: EditorialTextStyle
    let language: String
    var updatesSizeWhileTyping = false
    var sampleText = ""
    /// The template's ink for this text; enables the color and line spacing rows when set.
    var defaultInk: UInt32? = nil
    /// Book colors offered as one-click swatches next to the system color picker.
    var palette: [UInt32] = []

    @State private var sizeDraft: String?
    @State private var lineDraft: Double?
    @State private var sizeBeforeEditing: Double?
    @State private var showingFonts = false
    @FocusState private var editingSize: Bool

    private let pine = Theme.accent

    var body: some View {
        if defaultInk == nil {
            VStack(alignment: .leading, spacing: 6) {
                fontControl
                HStack(spacing: 5) {
                    sizeControl
                    Spacer(minLength: 2)
                    alignmentControl
                    resetControl
                }
            }
            .controlSize(.small)
        } else {
            formatPanel
        }
    }

    /// The full Format panel: font, size and color, then paragraph alignment and spacing.
    private var formatPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                rowTitle(tr("Carattere", "Font"))
                fontControl
                HStack(spacing: 8) {
                    sizeControl
                    Spacer(minLength: 4)
                    colorControl
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                rowTitle(tr("Allineamento", "Alignment"))
                alignmentSegments
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    rowTitle(tr("Interlinea", "Line Spacing"))
                    Spacer()
                    Text(lineSpacingLabel)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { lineDraft ?? style?.normalizedLineSpacing ?? inherited.normalizedLineSpacing ?? 1 },
                    set: { lineDraft = ($0 * 20).rounded() / 20 }
                ), in: EditorialTextStyle.lineSpacingRange) { editing in
                    if !editing, let draft = lineDraft {
                        lineDraft = nil
                        set(\.lineSpacing, to: abs(draft - 1) < 0.001 ? nil : draft)
                    }
                }
                .accessibilityLabel(tr("Interlinea", "Line Spacing"))
                .accessibilityValue(lineSpacingLabel)
            }
            HStack {
                Spacer()
                Button(tr("Ripristina stile del modello", "Reset to Template Style")) {
                    sizeDraft = nil
                    lineDraft = nil
                    editingSize = false
                    style = nil
                }
                .disabled(style == nil || style == EditorialTextStyle())
            }
        }
        .controlSize(.small)
    }

    private func rowTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private var lineSpacingLabel: String {
        let value = lineDraft ?? style?.normalizedLineSpacing ?? inherited.normalizedLineSpacing ?? 1
        return value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: language))) + "×"
    }

    private var resolvedInk: UInt32 { style?.color ?? inherited.color ?? defaultInk ?? 0x222222 }

    private var colorControl: some View {
        let colors = Array(NSOrderedSet(array: ([defaultInk].compactMap { $0 } + palette).map(NSNumber.init(value:))))
            .compactMap { ($0 as? NSNumber)?.uint32Value }
        return HStack(spacing: 5) {
            ForEach(colors, id: \.self) { value in
                let active = value == resolvedInk
                Button {
                    set(\.color, to: value == defaultInk ? nil : value)
                } label: {
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
                .help(value == defaultInk ? tr("Colore del modello", "Template color") : String(format: "#%06X", value))
            }
            ColorPicker(tr("Colore del testo", "Text Color"), selection: Binding(
                get: { Color(cgColor: EditorialStyle.color(resolvedInk)) },
                set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    let value = (UInt32((rgb.redComponent * 255).rounded()) << 16)
                        | (UInt32((rgb.greenComponent * 255).rounded()) << 8)
                        | UInt32((rgb.blueComponent * 255).rounded())
                    set(\.color, to: value == defaultInk ? nil : value)
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .help(tr("Colore del testo", "Text Color"))
        }
    }

    private var alignmentSegments: some View {
        Picker(tr("Allineamento", "Alignment"), selection: Binding(
            get: { style?.alignment ?? inherited.alignment ?? .left },
            set: { set(\.alignment, to: $0) }
        )) {
            ForEach(EditorialAlignment.allCases) { alignment in
                let info = alignmentInfo(alignment)
                Image(systemName: info.icon).accessibilityLabel(info.label).tag(alignment)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private var fontControl: some View {
        let label = tr("Carattere", "Font")
        let name = EditorialFontBrowser.displayName(style?.fontName ?? inherited.fontName, language: language)
        return Button { showingFonts.toggle() } label: {
            HStack(spacing: 6) {
                if defaultInk == nil {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(name)
                    .font(defaultInk == nil ? nil : .custom(style?.fontName ?? inherited.fontName ?? "Georgia", size: 13))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .accessibilityValue(name)
        .help(name)
        .popover(isPresented: $showingFonts, arrowEdge: .bottom) {
            EditorialFontBrowser(selected: style?.fontName, inherited: inherited.fontName,
                                 sampleText: sampleText, language: language) { font in
                showingFonts = false
                set(\.fontName, to: font)
            }
        }
    }

    private var sizeControl: some View {
        let label = tr("Dimensione carattere", "Font Size")
        let reference = tr("Da 6 a 120 punti. Cancella il valore per usare la dimensione ereditata.",
                           "6 to 120 points. Clear the value to use the inherited size.")
        return HStack(spacing: 2) {
            sizeButton("minus", tr("Riduci dimensione carattere", "Decrease Font Size"), step: -1)
            TextField(label, text: Binding(get: { sizeDraft ?? formattedSize }, set: { draft in
                sizeDraft = draft
                if updatesSizeWhileTyping { applySize(draft) }
            }))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($editingSize)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 42)
                .onSubmit {
                    commitSize()
                    editingSize = false
                }
                .onChange(of: editingSize) { wasEditing, isEditing in
                    if isEditing { sizeBeforeEditing = style?.pointSize }
                    if wasEditing && !isEditing { commitSize() }
                }
                .onExitCommand {
                    if updatesSizeWhileTyping { set(\.pointSize, to: sizeBeforeEditing) }
                    sizeDraft = nil
                    editingSize = false
                }
                .help(reference)
                .accessibilityHint(reference)
            Text("pt")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            sizeButton("plus", tr("Aumenta dimensione carattere", "Increase Font Size"), step: 1)
        }
    }

    private func sizeButton(_ symbol: String, _ label: String, step: Double) -> some View {
        let range = EditorialTextStyle.pointSizeRange
        return Button {
            commitSize()
            editingSize = false
            let next = min(range.upperBound, max(range.lowerBound, effectiveSize + step))
            set(\.pointSize, to: next)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 19, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sizeDraft == nil && (step < 0 ? effectiveSize <= range.lowerBound : effectiveSize >= range.upperBound))
        .accessibilityLabel(label)
        .help(label)
    }

    private var alignmentControl: some View {
        let resolved = style?.alignment ?? inherited.alignment ?? .left
        return HStack(spacing: 0) {
            ForEach(EditorialAlignment.allCases) { alignment in
                let info = alignmentInfo(alignment)
                let active = alignment == resolved
                Button { set(\.alignment, to: alignment) } label: {
                    Image(systemName: info.icon)
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? pine : Color.secondary)
                        .frame(width: 23, height: 22)
                        .background(active ? pine.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(info.label)
                .accessibilityAddTraits(active ? .isSelected : [])
                .help(info.label)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Allineamento", "Alignment"))
        .contextMenu {
            Button(tr("Usa allineamento ereditato", "Use Inherited Alignment")) { set(\.alignment, to: nil) }
                .disabled(style?.alignment == nil)
        }
    }

    private var resetControl: some View {
        let label = tr("Ripristina impostazioni ereditate", "Reset to Inherited Settings")
        return Button {
            sizeDraft = nil
            editingSize = false
            style = nil
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11))
                .frame(width: 23, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(style == nil || style == EditorialTextStyle())
        .accessibilityLabel(label)
        .help(label)
    }

    private var effectiveSize: Double {
        style?.normalizedSize ?? inherited.normalizedSize ?? 12
    }

    private var formattedSize: String {
        effectiveSize.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
            .locale(Locale(identifier: language)))
    }

    private func commitSize() {
        guard let draft = sizeDraft else { return }
        sizeDraft = nil
        applySize(draft)
    }

    private func applySize(_ draft: String) {
        let entry = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.isEmpty {
            set(\.pointSize, to: nil)
        } else if entry != formattedSize {
            let separator = Locale(identifier: language).decimalSeparator ?? "."
            guard let number = Double(entry.replacingOccurrences(of: separator, with: ".")), number.isFinite else { return }
            let range = EditorialTextStyle.pointSizeRange
            let size = min(range.upperBound, max(range.lowerBound, number))
            if style?.pointSize != nil || size != effectiveSize { set(\.pointSize, to: size) }
        }
    }

    private func set<Value>(_ key: WritableKeyPath<EditorialTextStyle, Value?>, to value: Value?) {
        var updated = style ?? EditorialTextStyle()
        updated[keyPath: key] = value
        let next: EditorialTextStyle? = updated == EditorialTextStyle() ? nil : updated
        if next != style { style = next }
    }

    private func alignmentInfo(_ alignment: EditorialAlignment) -> (icon: String, label: String) {
        switch alignment {
        case .left: ("text.alignleft", tr("Allinea a sinistra", "Align Left"))
        case .center: ("text.aligncenter", tr("Centra", "Center"))
        case .right: ("text.alignright", tr("Allinea a destra", "Align Right"))
        case .justified: ("text.justify", tr("Giustifica", "Justify"))
        }
    }

    private func tr(_ italian: String, _ english: String) -> String {
        language.hasPrefix("it") ? italian : english
    }
}
