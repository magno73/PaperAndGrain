import AppKit
import SwiftUI

/// Paper & Grain › About and Help › Paper & Grain Help.
struct AboutHelpCommands: Commands, Localizing {
    let language: String
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(tr("About Paper & Grain")) { AboutPanel.show(language: language) }
        }
        CommandGroup(replacing: .help) {
            Button(tr("Paper & Grain Help")) { openWindow(id: HelpView.windowID) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

@MainActor
enum AboutPanel {
    static let author = "Marco Magnocavallo"
    static let email = "marco@magno.me"
    static let repository = "https://github.com/magno73/PaperAndGrain"

    static func show(language: String) {
        func tr(_ key: String) -> String { L10n.string(key, language: language) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 4
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: tr("Travel photobooks, from album to print.") + "\n\n",
            attributes: base)
        credits.append(NSAttributedString(string: author + "\n", attributes: base.merging([
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        ]) { $1 }))
        credits.append(NSAttributedString(string: email + "\n\n", attributes: base.merging([
            .link: URL(string: "mailto:" + email) as Any
        ]) { $1 }))
        credits.append(NSAttributedString(string: tr("Source code under the PolyForm Noncommercial License: noncommercial use") + "\n",
                                          attributes: base))
        credits.append(NSAttributedString(string: "github.com/magno73/PaperAndGrain\n\n", attributes: base.merging([
            .link: URL(string: repository) as Any
        ]) { $1 }))
        credits.append(NSAttributedString(
            string: tr("Film-emulation LUTs by abpy, CC BY-NC-SA 4.0."),
            attributes: base.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Paper & Grain",
            .credits: credits,
        ])
    }
}

/// A short guide to the app, in the interface language. Keep it in step with the README.
struct HelpView: View, Localizing {
    static let windowID = "help"
    let language: String

    private struct Topic: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let lines: [String]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Paper & Grain Help"))
                        .font(.system(size: 30, design: .serif))
                    Text(tr("From album to printed photobook, in five steps."))
                        .foregroundStyle(.secondary)
                }
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(topic.title, systemImage: topic.symbol)
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                        ForEach(Array(topic.lines.enumerated()), id: \.offset) { _, line in
                            Text(.init(line))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Divider()
                Text(.init(tr("Questions or problems: [%1$@](mailto:%1$@) · [Source on GitHub](%2$@)",
                              AboutPanel.email, AboutPanel.repository)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 480, idealHeight: 720)
    }

    private var topics: [Topic] {
        [
            Topic(id: "start", symbol: "1.circle", title: tr("Create the book"), lines: [
                tr("**File › New Book from Photos** picks an album; **New Book from Files** uses Finder. Choose the size, then the book template: paper, type and margins."),
                tr("Change the template any time with **Style** in the toolbar."),
            ]),
            Topic(id: "pages", symbol: "2.circle", title: tr("Lay out pages"), lines: [
                tr("Drag photos from the **Photo Library** at the bottom onto the page. On a photo it replaces it without a hidden crop; on an empty slot it fills it. The library menu has **Stack Similar Photos**, which groups near-duplicates; **Compare…** and **Use This One** pick the best."),
                tr("**Layout** picks the page layout. Drag the **Pages** thumbnails to reorder; ← → and ↑ ↓ move between pages and spreads."),
                tr("Right-click an object for crop, adjustments and **Bring to Front / Send to Back**. Double-click a photo to crop it."),
                tr("⇧-click or ⌘-click selects several objects, and a drag on blank paper draws a selection rectangle. Drag one of them to move them all; **Arrange › Align** and **Distribute** line them up."),
                tr("When you move or resize, guides snap photos and text to other objects and to the page edges, so a photo reaches the edge with no gap. Drag further to pull it away, or hold ⌥ to move freely."),
            ]),
            Topic(id: "text", symbol: "3.circle", title: tr("Write"), lines: [
                tr("**Insert › Text Box** or **Page Heading**. Double-click to type on the page."),
                tr("Text is checked for spelling as you type, in Italian or English: a red underline marks a possible mistake, and **Edit › Spelling and Grammar** has the system’s options. **Issues** also lists possible misspellings; **Ignore in This Book** or **Learn Spelling** on a row stops it. **Settings** can turn the list off."),
                tr("The **Text** tab of the inspector sets font, size, color, alignment, line spacing, and the box background and border."),
                tr("Select a photo and type its **Caption** at the top of the **Photo** tab; it follows the photo onto every page. **Position** puts it below, above or on the photo for this page. Double-click a caption on the page to edit it; **Photo › Caption Photos on This Page** writes place and date."),
            ]),
            Topic(id: "photos", symbol: "4.circle", title: tr("Finish the photos"), lines: [
                tr("Select a photo: the **Photo** tab has **Adjust** (with **Auto Enhance**) and **Film**, which changes only that photo."),
                tr("For the whole book tick **Change the whole book**, or use the **Film** tab with no photo selected."),
            ]),
            Topic(id: "print", symbol: "5.circle", title: tr("Print"), lines: [
                tr("**Book & Print** sets size, bleed, margins and the cover with spine. **Export PDF** runs the preflight check and offers print profiles. **View › Show Print Guides** draws the safe margin (dashed) and the bleed on the canvas."),
                tr("**Print service** in **Book & Print** picks a printer’s product and size: it sets bleed and margins, adds the product’s checks to **Issues** and its export to **Export PDF**. The catalog has Pixartprinting, Saal Digital, Peecho, WhiteWall, Lulu and Mixam. Check the printer’s current requirements before ordering."),
                tr("The **Issues** button in the toolbar (⇧⌘I) checks the book as you work: problems that would stop the export, then warnings. Click a row to go to the page and select the photo or text. For a photo whose file is missing, **Relink…** on its row chooses a replacement file."),
                tr("An orange or red triangle in the corner of a photo means a low print resolution: make the photo smaller or use a larger original."),
                tr("Always check sizes and color with your print shop before ordering."),
            ]),
            Topic(id: "keys", symbol: "keyboard", title: tr("Handy shortcuts"), lines: [
                tr("⌃⌘S pages · ⌥⌘I inspector · ⌥⌘L photo library · ⌘1 / ⌘2 single or two-page view · ⌘+ ⌘− ⌘0 zoom · ⌥⌘↩ browse the book · ⇧⌘I issues"),
                tr("⇧⌘N new page · ⌘D duplicate page · ⌘[ ⌘] previous and next page · ⌥⌘C crop · ⌥⌘E enhance · ⇧⌘F / ⇧⌘B front / back"),
            ]),
        ]
    }
}
