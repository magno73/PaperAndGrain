import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    // MARK: Browse

    func openBrowser() {
        guard !book.pages.isEmpty else { return }
        finishCrop()
        endInlineTextEditing()
        editorInput.target = .none
        if coverSide == .front { browsingSpread = 0; return }
        if coverSide == .back { browsingSpread = navigatorSpreads.count + 1; return }
        let position = navigatorSpreads.firstIndex { $0.pages.contains { $0.id == page?.id } } ?? 0
        browsingSpread = position + 1
    }

    func bookBrowser(start position: Int) -> some View {
        let spreads = navigatorSpreads
        let last = spreads.count + 1
        let position = min(max(position, 0), last)
        let pageSize = book.format.pageSize
        let label: String = switch position {
        case 0: coverName(.front)
        case last: coverName(.back)
        default: spreadNumber(spreads[position - 1].pages)
        }
        return ZStack {
            Rectangle().fill(Color(white: 0.07)).ignoresSafeArea()
            GeometryReader { geometry in
                let wide = position != 0 && position != last
                let artboard = CGSize(width: pageSize.width * (wide ? 2 : 1), height: pageSize.height)
                let scale = min((geometry.size.width - 140) / artboard.width, (geometry.size.height - 120) / artboard.height)
                let size = CGSize(width: artboard.width * max(scale, 0.1), height: artboard.height * max(scale, 0.1))
                Group {
                    if position == 0 {
                        coverCanvas(.front, scale: size.width / pageSize.width, thumbnail: true)
                    } else if position == last {
                        coverCanvas(.back, scale: size.width / pageSize.width, thumbnail: true)
                    } else {
                        let spread = spreads[position - 1]
                        HStack(spacing: 0) {
                            if spread.blankLeft {
                                Color(cgColor: EditorialStyle.color(book.editorialStyle.paper))
                                    .frame(width: size.width / 2, height: size.height)
                            }
                            ForEach(spread.pages) { leaf in
                                let pages: CGFloat = leaf.effectiveLayout == .fullSpread ? 2 : 1
                                mini(leaf, small: false)
                                    .frame(width: size.width / 2 * pages, height: size.height)
                            }
                        }
                        .frame(width: size.width, height: size.height, alignment: spread.pages.count == 1 && !spread.blankLeft
                               && spread.pages.first?.effectiveLayout != .fullSpread ? .trailing : .center)
                    }
                }
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 20)
                .id(position)
                .transition(.opacity)
            }
            VStack {
                HStack {
                    Spacer()
                    Button(tr("Done")) { browsingSpread = nil }
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.large)
                }
                Spacer()
                HStack(spacing: 18) {
                    Button {
                        browsingSpread = max(0, position - 1)
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 28, height: 22)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(position == 0)
                    .accessibilityLabel(tr("Previous Spread"))
                    Text(label)
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 110)
                    Button {
                        browsingSpread = min(last, position + 1)
                    } label: {
                        Image(systemName: "chevron.right").frame(width: 28, height: 22)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(position == last)
                    .accessibilityLabel(tr("Next Spread"))
                }
                .controlSize(.large)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .floatingCapsule()
            }
            .padding(20)
            .environment(\.colorScheme, .dark)
        }
        .animation(.easeInOut(duration: 0.2), value: position)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Browse the Book"))
    }
}
