import AppKit
import SwiftUI

/// Paper & Grain › About and Help › Paper & Grain Help.
struct AboutHelpCommands: Commands {
    let language: String
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(s("Informazioni su Paper & Grain", "About Paper & Grain")) { AboutPanel.show(language: language) }
        }
        CommandGroup(replacing: .help) {
            Button(s("Aiuto di Paper & Grain", "Paper & Grain Help")) { openWindow(id: HelpView.windowID) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }

    private func s(_ italian: String, _ english: String) -> String { language.hasPrefix("it") ? italian : english }
}

@MainActor
enum AboutPanel {
    static let author = "Marco Magnocavallo"
    static let email = "marco@magno.me"
    static let repository = "https://github.com/magno73/PaperAndGrain"

    static func show(language: String) {
        let italian = language.hasPrefix("it")
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 4
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: italian ? "Fotolibri di viaggio, dall’album alla stampa.\n\n" : "Travel photobooks, from album to print.\n\n",
            attributes: base)
        credits.append(NSAttributedString(string: author + "\n", attributes: base.merging([
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        ]) { $1 }))
        credits.append(NSAttributedString(string: email + "\n\n", attributes: base.merging([
            .link: URL(string: "mailto:" + email) as Any
        ]) { $1 }))
        credits.append(NSAttributedString(string: italian ? "Codice sorgente con licenza PolyForm Noncommercial: uso non commerciale\n" : "Source code under the PolyForm Noncommercial License: noncommercial use\n",
                                          attributes: base))
        credits.append(NSAttributedString(string: "github.com/magno73/PaperAndGrain\n\n", attributes: base.merging([
            .link: URL(string: repository) as Any
        ]) { $1 }))
        credits.append(NSAttributedString(
            string: italian ? "LUT di emulazione pellicola di abpy, CC BY-NC-SA 4.0." : "Film-emulation LUTs by abpy, CC BY-NC-SA 4.0.",
            attributes: base.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Paper & Grain",
            .credits: credits,
        ])
    }
}

/// A short guide to the app, in the interface language. Keep it in step with the README.
struct HelpView: View {
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
                    Text(s("Aiuto di Paper & Grain", "Paper & Grain Help"))
                        .font(.system(size: 30, design: .serif))
                    Text(s("Dall’album al fotolibro stampato, in cinque passi.",
                           "From album to printed photobook, in five steps."))
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
                Text(.init(s("Domande o problemi: [\(AboutPanel.email)](mailto:\(AboutPanel.email)) · [Codice su GitHub](\(AboutPanel.repository))",
                             "Questions or problems: [\(AboutPanel.email)](mailto:\(AboutPanel.email)) · [Source on GitHub](\(AboutPanel.repository))")))
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
            Topic(id: "start", symbol: "1.circle", title: s("Crea il libro", "Create the book"), lines: [
                s("**File › Nuovo libro da Foto** sceglie un album; **Nuovo libro da file** usa il Finder. Scegli il formato e poi il modello del libro: carta, caratteri e margini.",
                  "**File › New Book from Photos** picks an album; **New Book from Files** uses Finder. Choose the size, then the book template: paper, type and margins."),
                s("Il modello si cambia quando vuoi da **Stile** nella barra.", "Change the template any time with **Style** in the toolbar."),
            ]),
            Topic(id: "pages", symbol: "2.circle", title: s("Impagina", "Lay out pages"), lines: [
                s("Trascina le foto dalla **Fototeca** in basso sulla pagina. Su una foto la sostituisce senza ritagliarla di nascosto; su uno spazio vuoto lo riempie.",
                  "Drag photos from the **Photo Library** at the bottom onto the page. On a photo it replaces it without a hidden crop; on an empty slot it fills it."),
                s("**Impagina** sceglie il modello della pagina. Trascina le miniature delle **Pagine** per riordinarle; ← → e ↑ ↓ si spostano fra pagine e doppie.",
                  "**Layout** picks the page layout. Drag the **Pages** thumbnails to reorder; ← → and ↑ ↓ move between pages and spreads."),
                s("Tasto destro su un elemento: ritaglio, regolazioni e **Porta in primo piano / in fondo**. Doppio clic su una foto per ritagliarla.",
                  "Right-click an object for crop, adjustments and **Bring to Front / Send to Back**. Double-click a photo to crop it."),
                s("Spostando o ridimensionando, le guide agganciano foto e testi agli altri elementi e ai bordi della pagina, così una foto arriva al bordo senza lasciare spazi. Trascina oltre per staccarla, o tieni premuto ⌥ per muoverti liberamente.",
                  "When you move or resize, guides snap photos and text to other objects and to the page edges, so a photo reaches the edge with no gap. Drag further to pull it away, or hold ⌥ to move freely."),
            ]),
            Topic(id: "text", symbol: "3.circle", title: s("Scrivi", "Write"), lines: [
                s("**Inserisci › Box di testo** o **Titolo di pagina**. Doppio clic per scrivere nella pagina.",
                  "**Insert › Text Box** or **Page Heading**. Double-click to type on the page."),
                s("La scheda **Testo** dell’ispettore regola carattere, dimensione, colore, allineamento, interlinea, sfondo e bordo del box.",
                  "The **Text** tab of the inspector sets font, size, color, alignment, line spacing, and the box background and border."),
            ]),
            Topic(id: "photos", symbol: "4.circle", title: s("Rifinisci le foto", "Finish the photos"), lines: [
                s("Seleziona una foto: la scheda **Foto** ha **Regola** (anche **Migliora in automatico**) e **Pellicola**, che cambia solo quella foto.",
                  "Select a photo: the **Photo** tab has **Adjust** (with **Auto Enhance**) and **Film**, which changes only that photo."),
                s("Per tutto il libro spunta **Cambia in tutto il libro**, oppure usa la scheda **Pellicola** senza foto selezionate.",
                  "For the whole book tick **Change the whole book**, or use the **Film** tab with no photo selected."),
            ]),
            Topic(id: "print", symbol: "5.circle", title: s("Stampa", "Print"), lines: [
                s("**Libro e stampa** imposta formato, abbondanza, margini e copertina con dorso. **Esporta PDF** offre la verifica prestampa e i profili di stampa.",
                  "**Book & Print** sets size, bleed, margins and the cover with spine. **Export PDF** runs the preflight check and offers print profiles."),
                s("Controlla sempre misure e colori con la tipografia prima di ordinare.",
                  "Always check sizes and color with your print shop before ordering."),
            ]),
            Topic(id: "keys", symbol: "keyboard", title: s("Scorciatoie utili", "Handy shortcuts"), lines: [
                s("⌃⌘S pagine · ⌥⌘I ispettore · ⌥⌘L fototeca · ⌘1 / ⌘2 pagina singola o doppia · ⌘+ ⌘− ⌘0 zoom · ⌥⌘↩ sfoglia il libro",
                  "⌃⌘S pages · ⌥⌘I inspector · ⌥⌘L photo library · ⌘1 / ⌘2 single or two-page view · ⌘+ ⌘− ⌘0 zoom · ⌥⌘↩ browse the book"),
                s("⇧⌘N nuova pagina · ⌘[ ⌘] pagina precedente e successiva · ⌥⌘C ritaglia · ⌥⌘E migliora · ⇧⌘F / ⇧⌘B primo piano / in fondo",
                  "⇧⌘N new page · ⌘[ ⌘] previous and next page · ⌥⌘C crop · ⌥⌘E enhance · ⇧⌘F / ⇧⌘B front / back"),
            ]),
        ]
    }

    private func s(_ italian: String, _ english: String) -> String { language.hasPrefix("it") ? italian : english }
}
