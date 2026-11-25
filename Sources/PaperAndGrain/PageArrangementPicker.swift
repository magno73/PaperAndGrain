import SwiftUI

struct PageArrangementPicker: View {
    let selection: PageArrangement?
    let language: String
    var pageSize = CGSize(width: 4, height: 3)
    let onSelect: (PageArrangement?) -> Void

    @State private var isPresented = false
    @State private var fullBleedGroup = false

    private let pine = Color(red: 0.14, green: 0.31, blue: 0.23)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        let current = Self.name(selection, language: language)
        return Button {
            fullBleedGroup = selection?.isFullBleed == true
            isPresented = true
        } label: {
            HStack(spacing: 9) {
                PageArrangementDiagram(arrangement: selection, pageSize: pageSize)
                    .frame(width: 35, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Modello di pagina", "Page Template"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(current)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 3)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(pine)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pine.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(pine.opacity(0.24)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Modello di pagina", "Page Template"))
        .accessibilityValue(current)
        .help(tr("Scegli un modello per la pagina", "Choose a page template"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            choices
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("Modelli di pagina", "Page Templates"))
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Picker(tr("Tipo di modello", "Template group"), selection: $fullBleedGroup) {
                Text(tr("Con margini", "With margins")).tag(false)
                Text(tr("Al vivo", "Full bleed")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            LazyVGrid(columns: columns, spacing: 7) {
                if !fullBleedGroup {
                    tile(nil)
                    tile(.fullSpread)
                }
                ForEach(PageArrangement.allCases.filter { $0.isFullBleed == fullBleedGroup }) { tile($0) }
            }
        }
        .padding(12)
        .frame(width: 350)
    }

    private func tile(_ arrangement: PageArrangement?) -> some View {
        let active = selection == arrangement
        let name = Self.name(arrangement, language: language)
        return Button {
            isPresented = false
            if !active { onSelect(arrangement) }
        } label: {
            VStack(spacing: 3) {
                PageArrangementDiagram(arrangement: arrangement, pageSize: pageSize)
                    .frame(height: 44)
                Text(name)
                    .font(.system(size: 10, weight: active ? .semibold : .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 26)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .background(active ? pine.opacity(0.10) : Color.secondary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(active ? pine : .secondary.opacity(0.2),
                                                               lineWidth: active ? 1.5 : 0.65)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    static func name(_ arrangement: PageArrangement?, language: String) -> String {
        let title: (italian: String, english: String) = switch arrangement {
        case nil: ("Automatico", "Automatic")
        case .fullBleed: ("Foto al vivo", "Full bleed")
        case .fullSpread: ("Due pagine", "Full Spread")
        case .twoAcross: ("Due affiancate", "Two across")
        case .twoStacked: ("Due in verticale", "Two stacked")
        case .fourGrid: ("Griglia a quattro", "Four-photo grid")
        case .heroAboveTwo: ("Grande sopra, due sotto", "Large above two")
        case .twoAboveHero: ("Due sopra, grande sotto", "Two above large")
        case .textAbovePhoto: ("Testo sopra la foto", "Text above photo")
        case .photoAboveText: ("Foto sopra il testo", "Photo above text")
        case .textBesidePhoto: ("Testo accanto alla foto", "Text beside photo")
        case .textOverPhoto: ("Testo sulla foto", "Text over photo")
        case .textOnly: ("Solo testo", "Text only")
        case .bleedTwoAcross: ("Due affiancate al vivo", "Two across, full bleed")
        case .bleedTwoStacked: ("Due in verticale al vivo", "Two stacked, full bleed")
        case .bleedThreeAcross: ("Tre affiancate al vivo", "Three across, full bleed")
        case .bleedFourGrid: ("Griglia di quattro al vivo", "Four-photo grid, full bleed")
        case .bleedHeroAboveTwo: ("Grande sopra, due sotto al vivo", "Large above two, full bleed")
        }
        return language.hasPrefix("it") ? title.italian : title.english
    }

    private func tr(_ italian: String, _ english: String) -> String {
        language.hasPrefix("it") ? italian : english
    }
}

private struct PageArrangementDiagram: View {
    let arrangement: PageArrangement?
    let pageSize: CGSize

    private let paper = Color(red: 0.98, green: 0.97, blue: 0.93)
    private let photo = Color(white: 0.65)
    private let ink = Color(red: 0.25, green: 0.29, blue: 0.25)

    var body: some View {
        Canvas { context, size in
            guard size.width > 2, size.height > 2 else { return }
            let bookRatio = pageSize.width / pageSize.height * (arrangement == .fullSpread ? 2 : 1)
            let ratio = bookRatio.isFinite && bookRatio > 0 ? bookRatio : 4.0 / 3
            let width = min(size.width - 2, (size.height - 2) * ratio)
            let height = width / ratio
            let page = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                              width: width, height: height)
            let outline = Path(page)
            context.fill(outline, with: .color(paper))
            if let arrangement {
                let shortSide = min(width, height)
                let inset = shortSide * 0.10
                let geometry = arrangement.geometry(in: page, inside: page.insetBy(dx: inset, dy: inset),
                                                    gap: shortSide * 0.07)

                let tones = [0.56, 0.72, 0.64, 0.50]
                for (index, slot) in geometry.photos.enumerated() {
                    let fill = arrangement.isFullBleed ? Color(white: tones[index % tones.count]) : photo
                    context.fill(Path(slot), with: .color(fill))
                }
                if let background = geometry.storyBackground {
                    context.fill(Path(background), with: .color(paper.opacity(0.9)))
                }
                if let story = geometry.story {
                    context.stroke(storyLines(in: story), with: .color(ink),
                                   style: StrokeStyle(lineWidth: 0.85, lineCap: .round))
                }
            } else {
                let icon = Text(Image(systemName: "rectangle.3.group"))
                    .font(.system(size: min(14, width * 0.49, height * 0.49), weight: .medium))
                    .foregroundColor(ink)
                context.draw(icon, at: CGPoint(x: page.midX, y: page.midY))
            }
            context.stroke(outline, with: .color(ink.opacity(0.5)), lineWidth: 0.7)
            if arrangement == .fullSpread {
                let fold = Path { path in
                    path.move(to: CGPoint(x: page.midX, y: page.minY))
                    path.addLine(to: CGPoint(x: page.midX, y: page.maxY))
                }
                context.stroke(fold, with: .color(ink.opacity(0.65)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
            }
        }
        .accessibilityHidden(true)
    }

    private func storyLines(in rect: CGRect) -> Path {
        guard rect.width > 1, rect.height > 1 else { return Path() }
        let fractions: [CGFloat] = [0.66, 0.95, 0.83, 0.92, 0.88, 0.96, 0.62]
        let count = min(fractions.count, max(2, Int(rect.height / 3)))
        let step = min(3.5, rect.height / CGFloat(count))
        return Path { path in
            for index in 0..<count {
                let y = rect.minY + (CGFloat(index) + 0.5) * step
                path.move(to: CGPoint(x: rect.minX + 0.5, y: y))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * fractions[index], y: y))
            }
        }
    }
}
