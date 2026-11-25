#!/usr/bin/env python3
"""One-time rewrite of inline Italian/English pairs into String Catalog lookups.

  scripts/l10n-migrate.py FILE.swift [...]   rewrite the plain pairs of these files and add them to the catalog

Rewrites, for literals without interpolation:
  tr("Pagina", "Page") / s("Pagina", "Page")        -> tr("Page")
  <language test> ? "Pagina" : "Page"               -> tr("Page")
  libraryLabel("date", "Data", "Date")             -> tr("Date")
  localized("editor.lut.choose", fallback: "…")    -> tr("Choose LUT")  (English value of the old key)
and adds each pair to Resources/Localizable.xcstrings (key = English text, both languages translated).
Pairs whose English text needs another Italian translation elsewhere get the explicit key in KEYS.
Interpolated strings, tables and model types are converted by hand. Kept for the record of the migration.
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("pairs", os.path.join(HERE, "l10n-pairs.py"))
pairs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pairs)

# (English, Italian) -> (explicit key, comment). One English text, more than one Italian translation.
KEYS = {
    ("All", "Tutti"): ("fonts.all", "Font browser filter: every typeface (masculine plural in Italian)."),
    ("Arrange", "Disposizione"): ("inspector.arrange", "Inspector section that orders the objects of a page (noun)."),
    ("Back", "In fondo"): ("layers.back", "Layer order: the object drawn behind the others."),
    ("Front", "In primo piano"): ("layers.front", "Layer order: the object drawn above the others."),
    ("Box", "Riquadro"): ("inspector.box_frame", "Inspector: the frame of a text box (background and border)."),
    ("Edit Text", "Modifica testo"): ("layers.edit_text", "Layers list and its context menu: edit the text of a box."),
    ("Full bleed", "Al vivo"): ("arrangement.bleed_group", "Page template chooser: group of full-bleed templates."),
    ("Hide Photo Library", "Nascondi la fototeca"): ("toolbar.hide_photo_library", "Toolbar button that hides the photo library."),
    ("Show Photo Library", "Mostra la fototeca"): ("toolbar.show_photo_library", "Toolbar button that shows the photo library."),
    ("Landscape", "Orizzontali"): ("format.shape.landscape", "Book size group: landscape formats (plural in Italian)."),
    ("Portrait", "Verticali"): ("format.shape.portrait", "Book size group: portrait formats (plural in Italian)."),
    ("Square", "Quadrati"): ("format.shape.square", "Book size group: square formats (plural in Italian)."),
    ("Square", "Quadrata"): ("photo.orientation.square", "Photo orientation in the library and inspector (feminine, la foto)."),
    ("Move Story Group", "Sposta blocco di testo"): ("canvas.move_story_group", "Undo action name and accessibility: move the title, story and background together."),
    ("Page Heading", "Titolo della pagina"): ("inspector.page_heading", "Inspector: the heading field of the page."),
    ("Remove from Page", "Rimuovi dalla pagina"): ("canvas.remove_box_from_page", "Context menu of a text box on the canvas."),
}

CALLS = {"tr", "s"}


def load_catalog():
    with open(pairs.CATALOG, encoding="utf-8") as f:
        return json.load(f)


def save_catalog(catalog):
    with open(pairs.CATALOG, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def add_entry(catalog, key, en, it, comment=None):
    entry = {"extractionState": "manual", "localizations": {"en": unit(en), "it": unit(it)}}
    if comment:
        entry["comment"] = comment
    old = catalog["strings"].get(key)
    if old and old.get("localizations", {}).get("it", {}).get("stringUnit", {}).get("value") not in (None, it):
        raise SystemExit(f"conflict for {key!r}: {old['localizations']['it']['stringUnit']['value']!r} vs {it!r}")
    catalog["strings"][key] = entry


def swift_literal(value):
    out = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + out + '"'


def rewrite(path, catalog):
    src = open(path, encoding="utf-8").read()
    toks = pairs.lex(src)
    edits = []  # (start, end, replacement)
    strings = catalog["strings"]

    def plain(run):
        return run and not run[1]

    def replacement(it, en):
        key = KEYS.get((en, it))
        if key:
            add_entry(catalog, key[0], en, it, key[1])
            return f"tr({swift_literal(en)}, key: {swift_literal(key[0])})"
        add_entry(catalog, en, en, it)
        return f"tr({swift_literal(en)})"

    i = 0
    while i < len(toks):
        t = toks[i]
        nxt = toks[i + 1] if i + 1 < len(toks) else None
        prev = toks[i - 1] if i else None
        if t.kind == "id" and t.text in CALLS and nxt and nxt.text == "(" and not (prev and prev.text == "."):
            a = pairs.string_run(toks, i + 2)
            if plain(a) and toks[a[2]].text == ",":
                b = pairs.string_run(toks, a[2] + 1)
                if plain(b) and toks[b[2]].text == ")":
                    edits.append((t.start, toks[b[2]].end, replacement(a[0], b[0])))
                    i = b[2] + 1
                    continue
        if t.text == "libraryLabel" and nxt and nxt.text == "(" and prev and prev.text != "func":
            key = "editor.photo_library." + toks[i + 2].value
            entry = strings.get(key)
            it = entry["localizations"]["it"]["stringUnit"]["value"] if entry else toks[i + 4].value
            en = entry["localizations"]["en"]["stringUnit"]["value"] if entry else toks[i + 6].value
            edits.append((t.start, toks[i + 7].end, replacement(it, en)))
            i += 8
            continue
        if t.text == "localized" and nxt and nxt.text == "(" and prev and prev.text != "func" \
                and toks[i + 2].kind == "str" and toks[i + 4].text == "fallback":
            key = toks[i + 2].value
            entry = strings[key]
            it = entry["localizations"]["it"]["stringUnit"]["value"]
            en = entry["localizations"]["en"]["stringUnit"]["value"]
            depth, j = 0, i + 1
            while True:
                if toks[j].text == "(":
                    depth += 1
                elif toks[j].text == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            edits.append((t.start, toks[j].end, replacement(it, en)))
            i = j + 1
            continue
        if t.text == "?":
            for pattern in pairs.LANGUAGE_TESTS:
                if pairs.matches_before(toks, i, pattern):
                    a = pairs.string_run(toks, i + 1)
                    if plain(a) and toks[a[2]].text == ":":
                        b = pairs.string_run(toks, a[2] + 1)
                        if plain(b) and not (a[0] == "it" and b[0] == "en"):
                            start = toks[i - len(pattern)].start
                            edits.append((start, toks[b[2] - 1].end, replacement(a[0], b[0])))
                    break
        i += 1
    for start, end, text in sorted(edits, reverse=True):
        src = src[:start] + text + src[end:]
    open(path, "w", encoding="utf-8").write(src)
    return len(edits)


def plural(one, other):
    return {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}


def substituted(value, **subs):
    """A string unit whose `%#@name@` placeholders are plural substitutions: name=(argNum, one, other)."""
    return {"stringUnit": {"state": "translated", "value": value},
            "substitutions": {name: {"argNum": num, "formatSpecifier": "lld", **plural(one, other)}
                              for name, (num, one, other) in subs.items()}}


# Format strings converted by hand: key -> (English localization, Italian localization, comment).
MANUAL = {
    "%lld selected": (plural("%lld selected", "%lld selected"), plural("%lld selezionata", "%lld selezionate"),
                      "Album picker: photos selected for the new book."),
    "%lld pages": (plural("%lld page", "%lld pages"), plural("%lld pagina", "%lld pagine"),
                   "Page count of a book (toolbar subtitle, navigator, recent books)."),
    "%lld photos waiting for a slot.": (plural("%lld photo waiting for a slot.", "%lld photos waiting for a slot."),
                                        plural("%lld foto in attesa di un riquadro.", "%lld foto in attesa di un riquadro."),
                                        None),
    "%lld photos have their own look and won’t change.": (
        plural("%lld photo has its own look and won’t change.", "%lld photos have their own look and won’t change."),
        plural("%lld foto ha un look proprio e non cambia.", "%lld foto hanno un look proprio e non cambiano."), None),
    "%1$lld photos · %2$lld unused": (
        substituted("%#@photos@ · %#@unused@", photos=(1, "%arg photo", "%arg photos"), unused=(2, "%arg unused", "%arg unused")),
        substituted("%#@photos@ · %#@unused@", photos=(1, "%arg foto", "%arg foto"), unused=(2, "%arg non usata", "%arg non usate")),
        "Photo library header: photos in the book, and how many are not placed on a page."),
    "and %lld more problems to fix": (plural("and %lld more problem to fix", "and %lld more problems to fix"),
                                      plural("e un altro problema da correggere", "e altri %lld problemi da correggere"),
                                      "Export preflight, after the first six blockers."),
    "and %lld more warnings": (plural("and %lld more warning", "and %lld more warnings"),
                               plural("e un altro avviso", "e altri %lld avvisi"),
                               "Export preflight, after the first six warnings."),
    "Analysis failed for %lld photos. You can retry from the editor.": (
        plural("Analysis failed for %lld photo. You can retry from the editor.",
               "Analysis failed for %lld photos. You can retry from the editor."),
        plural("Analisi non riuscita per %lld foto. Puoi riprovare dall’editor.",
               "Analisi non riuscita per %lld foto. Puoi riprovare dall’editor."), None),
    "Imported %lld photos.": (plural("Imported %lld photo.", "Imported %lld photos."),
                              plural("Importata %lld foto.", "Importate %lld foto."), None),
    "%lld images were unavailable": (plural("%lld image was unavailable", "%lld images were unavailable"),
                                     plural("%lld immagine non era disponibile", "%lld immagini non erano disponibili"),
                                     "Followed by a period, or by a colon and the file names."),
    "Follows the book look (%@). A choice here applies to this photo only.": (
        unit("Follows the book look (%@). A choice here applies to this photo only."),
        unit("Segue il look del libro (%@). Una scelta qui vale solo per questa foto."), "The argument is the book's film look."),
    "“%@” was never saved to a file. The draft will be moved to the Trash.": (
        unit("“%@” was never saved to a file. The draft will be moved to the Trash."),
        unit("«%@» non è mai stato salvato in un file. La bozza verrà spostata nel Cestino."), "The argument is the book title."),
    "Questions or problems: [%1$@](mailto:%1$@) · [Source on GitHub](%2$@)": (
        unit("Questions or problems: [%1$@](mailto:%1$@) · [Source on GitHub](%2$@)"),
        unit("Domande o problemi: [%1$@](mailto:%1$@) · [Codice su GitHub](%2$@)"),
        "Help window footer, in Markdown: %1$@ is the email address, %2$@ the repository URL."),
    "Low print resolution: %1$lld ppi, target %2$lld ppi. Make the photo smaller or use a larger original.": (
        unit("Low print resolution: %1$lld ppi, target %2$lld ppi. Make the photo smaller or use a larger original."),
        unit("Risoluzione bassa per la stampa: %1$lld ppi, obiettivo %2$lld ppi. Rimpicciolisci la foto o usa un originale più grande."),
        "Badge on a placed photo: its resolution and the book's target."),
    "Print: %@": (unit("Print: %@"), unit("Stampa: %@"), "Photo inspector: print resolution, such as “300 ppi”."),
    "Print: %1$@, below the recommended %2$lld ppi": (
        unit("Print: %1$@, below the recommended %2$lld ppi"), unit("Stampa: %1$@, sotto i %2$lld ppi consigliati"), None),
    "%@ was moved, renamed or is no longer available. Use Save As to keep your changes in another place.": (
        unit("%@ was moved, renamed or is no longer available. Use Save As to keep your changes in another place."),
        unit("%@ è stato spostato, rinominato o non è più disponibile. Usa Salva con nome per conservare le modifiche in un’altra posizione."),
        "The argument is the quoted book title, or “The book”."),
    "%@ was saved by a newer version of Paper & Grain. It is open read-only and changes will not be saved. Update the app to edit it.": (
        unit("%@ was saved by a newer version of Paper & Grain. It is open read-only and changes will not be saved. Update the app to edit it."),
        unit("%@ è stato salvato con una versione più recente di Paper & Grain. È aperto in sola lettura: le modifiche non verranno salvate. Aggiorna l’app per modificarlo."),
        "The argument is the quoted book title, or “This book”."),
    "%@ is in a read-only location. Changes will not be saved until you use Save As to copy it somewhere else.": (
        unit("%@ is in a read-only location. Changes will not be saved until you use Save As to copy it somewhere else."),
        unit("%@ si trova in una posizione in sola lettura. Le modifiche non verranno salvate finché non usi Salva con nome per copiarlo altrove."),
        "The argument is the quoted book title, or “This book”."),
    "%@ can’t be opened: its manifest.json file is damaged or does not describe a book.": (
        unit("%@ can’t be opened: its manifest.json file is damaged or does not describe a book."),
        unit("Impossibile aprire %@: il file manifest.json è danneggiato o non descrive un libro."),
        "The argument is the quoted package name, or error.damaged_book."),
    "The book": (unit("The book"), unit("Il libro"), "Subject of an error message when the book has no title."),
    "This book": (unit("This book"), unit("Questo libro"), "Subject of an error message when the book has no title."),
    "error.damaged_book": (unit("The book"), unit("il libro"),
                           "Stands for an untitled package in the damaged-manifest error; lowercase in Italian, where it follows “Impossibile aprire”."),
    "Kodachrome": (unit("Kodachrome"), unit("Kodachrome"), "Book template name; a proper name, not translated."),
    "Full bleed": (unit("Full bleed"), unit("Foto al vivo"), "Page template name: one photo to the page edges."),
    "“%@”": (unit("“%@”"), unit("«%@»"), "A book or file name in quotation marks."),
    "“%@” is unavailable or not in a readable format.": (
        unit("“%@” is unavailable or not in a readable format."),
        unit("«%@» non è disponibile o non è in un formato leggibile."), "The argument is a file name."),
    "Photo unavailable — %@": (unit("Photo unavailable — %@"), unit("Foto non disponibile — %@"),
                               "PDF export error; the argument is the photo name or identifier."),
    "Text overflows on page %lld": (unit("Text overflows on page %lld"), unit("Il testo eccede lo spazio a pagina %lld"),
                                    "PDF export error."),
}


def add_manual(catalog):
    for key, (en, it, comment) in MANUAL.items():
        entry = {"extractionState": "manual", "localizations": {"en": en, "it": it}}
        if comment:
            entry["comment"] = comment
        catalog["strings"][key] = entry


def sync(catalog):
    """Adds every source literal that is the English side of a baseline pair and has no catalog entry."""
    baseline = json.load(open(os.path.join(HERE, "l10n-pairs-baseline.json"), encoding="utf-8"))["pairs"]
    italian = {}
    for p in baseline:
        italian.setdefault(p["en"], set()).add(p["it"])
    keys_with_italian = {}
    for key, entry in catalog["strings"].items():
        keys_with_italian[key] = entry
    added = []
    for name in sorted(os.listdir(pairs.SOURCES)):
        if not name.endswith(".swift"):
            continue
        for t in pairs.lex(open(os.path.join(pairs.SOURCES, name), encoding="utf-8").read()):
            if t.kind != "str" or t.parts or t.value in catalog["strings"] or t.value not in italian:
                continue
            options = italian[t.value]
            if len(options) > 1:
                print(f"{name}:{t.line}: {t.value!r} has several Italian translations {sorted(options)}: give it a key")
                continue
            add_entry(catalog, t.value, t.value, next(iter(options)))
            added.append(t.value)
    print(f"sync: {len(added)} entries added")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    catalog = load_catalog()
    if argv[1] == "sync":
        add_manual(catalog)
        sync(catalog)
        save_catalog(catalog)
        return 0
    if argv[1] == "prune":
        literals = set()
        for name in os.listdir(pairs.SOURCES):
            if name.endswith(".swift"):
                literals.update(t.value for t in pairs.lex(open(os.path.join(pairs.SOURCES, name), encoding="utf-8").read())
                                if t.kind == "str")
        unused = sorted(key for key in catalog["strings"] if key not in literals)
        for key in unused:
            del catalog["strings"][key]
        print(f"prune: {len(unused)} unused keys removed: {', '.join(unused)}")
        save_catalog(catalog)
        return 0
    for path in argv[1:]:
        print(f"{os.path.basename(path)}: {rewrite(path, catalog)} pairs")
    save_catalog(catalog)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
