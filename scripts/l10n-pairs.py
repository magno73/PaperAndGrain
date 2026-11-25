#!/usr/bin/env python3
"""Italian/English interface string pairs: extract, compare, check.

  scripts/l10n-pairs.py sources [--json]   pairs written inline in Sources/ (the pre-catalog form)
  scripts/l10n-pairs.py catalog [--json]   pairs stored in Resources/Localizable.xcstrings
  scripts/l10n-pairs.py diff BASELINE      every pair of BASELINE must exist in the catalog
  scripts/l10n-pairs.py check              no inline pair left in Sources/ outside L10n.swift

A pair is (Italian, English). Interpolations `\\(expr)` and format specifiers (`%@`, `%1$lld`, `%.0f`)
are both normalised to `{}`, so `"\\(n) foto"` and `"%lld foto"` compare equal. Plural variations in the
catalog are expanded into their `one` and `other` forms; the `one` form is also compared with `1` in
place of the count, which is how the sources wrote the singular (`n == 1 ? "1 foto" : ...`).

The baseline was taken from the sources before the migration (scripts/l10n-pairs-baseline.json).
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.environ.get("L10N_SOURCES", os.path.join(ROOT, "Sources", "PaperAndGrain"))
CATALOG = os.environ.get("L10N_CATALOG", os.path.join(ROOT, "Resources", "Localizable.xcstrings"))


# ---------------------------------------------------------------- Swift lexer

class Tok:
    __slots__ = ("kind", "text", "value", "line", "start", "end", "parts")

    def __init__(self, kind, text, line, start, end, value=None, parts=None):
        self.kind, self.text, self.line, self.start, self.end = kind, text, line, start, end
        self.value, self.parts = value, parts

    def __repr__(self):
        return f"{self.kind}:{self.text!r}"


def lex_string(src, i):
    """Lexes a string literal at src[i] ('"' or '#'). Returns (end, value, parts).
    `value` keeps interpolations as `\\(source)`; `parts` lists the interpolated sources."""
    hashes = 0
    while src[i] == "#":
        hashes += 1
        i += 1
    multi = src.startswith('"""', i)
    i += 3 if multi else 1
    close = ('"""' if multi else '"') + "#" * hashes
    esc = "\\" + "#" * hashes
    out, parts = [], []
    while True:
        if src.startswith(close, i):
            i += len(close)
            break
        if src.startswith(esc, i):
            j = i + len(esc)
            c = src[j]
            if c == "(":
                depth, k = 1, j + 1
                while depth:
                    ch = src[k]
                    if ch == '"' or (ch == "#" and src[k:k + 2] in ('#"',)):
                        k, _, _ = lex_string(src, k)
                        continue
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                    k += 1
                expr = src[j + 1:k - 1]
                parts.append(expr.strip())
                out.append("\\(" + expr.strip() + ")")
                i = k
                continue
            mapping = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0", "r": "\r"}
            if c == "u":
                end = src.index("}", j)
                out.append(chr(int(src[j + 2:end], 16)))
                i = end + 1
                continue
            if c == "\n" and multi:
                i = j + 1
                continue
            out.append(mapping.get(c, c))
            i = j + 1
            continue
        out.append(src[i])
        i += 1
    value = "".join(out)
    if multi:
        lines = value.split("\n")
        if lines and lines[0].strip() == "":
            lines = lines[1:]
        indent = len(lines[-1]) if lines and lines[-1].strip() == "" else 0
        if lines and lines[-1].strip() == "":
            lines = lines[:-1]
        value = "\n".join(l[indent:] for l in lines)
    return i, value, parts


def lex(src):
    toks, i, line, n = [], 0, 1, len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
        elif src.startswith("/*", i):
            j = src.index("*/", i) + 2
            line += src.count("\n", i, j)
            i = j
        elif c == '"' or (c == "#" and re.match(r'#+"', src[i:])):
            j, value, parts = lex_string(src, i)
            toks.append(Tok("str", src[i:j], line, i, j, value, parts))
            line += src.count("\n", i, j)
            i = j
        elif c.isalpha() or c == "_" or c == "$":
            m = re.match(r"[A-Za-z_$][A-Za-z0-9_]*", src[i:])
            toks.append(Tok("id", m.group(0), line, i, i + len(m.group(0))))
            i += len(m.group(0))
        elif c.isdigit():
            m = re.match(r"[0-9][0-9_.]*", src[i:])
            toks.append(Tok("num", m.group(0), line, i, i + len(m.group(0))))
            i += len(m.group(0))
        else:
            for op in ("==", "!=", "...", "..<", "->", "&&", "||", "?.", "??"):
                if src.startswith(op, i):
                    toks.append(Tok("op", op, line, i, i + len(op)))
                    i += len(op)
                    break
            else:
                toks.append(Tok("op", c, line, i, i + 1))
                i += 1
    return toks


# ---------------------------------------------------------------- source pairs

# Expressions that test the interface language right before `? "it" : "en"`.
LANGUAGE_TESTS = [
    ["italian"], ["isItalian"],
    ["language", "==", '"it"'],
    ["AppError", ".", "interfaceLanguage", "==", '"it"'],
    ["language", ".", "hasPrefix", "(", '"it"', ")"],
    ["language", ".", "lowercased", "(", ")", ".", "hasPrefix", "(", '"it"', ")"],
]
TWO_ARG_CALLS = {"tr", "s"}
# Italian literal -> English literal, for pairs the patterns above cannot see.
MANUAL_FRAGMENTS = {
    ("AppErrors.swift", "Importata 1 foto. "): "Imported 1 photo. ",
    ("AppErrors.swift", "Importate \\(imported) foto. "): "Imported \\(imported) photos. ",
    ("AppErrors.swift", "1 immagine non era disponibile"): "1 image was unavailable",
    ("AppErrors.swift", "\\(failed) immagini non erano disponibili"): "\\(failed) images were unavailable",
}


def text(tok):
    return tok.text


def matches_before(toks, i, pattern):
    """True when toks[i - len(pattern):i] spell `pattern`."""
    if i < len(pattern):
        return False
    seg = toks[i - len(pattern):i]
    if [text(t) for t in seg] != pattern:
        return False
    before = toks[i - len(pattern) - 1] if i > len(pattern) else None
    return not (before and before.text == ".")  # `self.italian` is a field, not the test


def string_run(toks, i):
    """A string literal, or literals joined with `+`, starting at toks[i]. Returns (value, parts, end)."""
    if i >= len(toks) or toks[i].kind != "str":
        return None
    value, parts, j = toks[i].value, list(toks[i].parts), i + 1
    while j + 1 < len(toks) and toks[j].text == "+" and toks[j + 1].kind == "str":
        value += toks[j + 1].value
        parts += toks[j + 1].parts
        j += 2
    return value, parts, j


def load_catalog():
    with open(CATALOG, encoding="utf-8") as f:
        return json.load(f)


def catalog_unit(entry, lang):
    unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit")
    return unit["value"] if unit else None


def source_pairs(catalog=None):
    """Every (Italian, English) pair spelled out in the Swift sources."""
    catalog = catalog if catalog is not None else load_catalog()
    strings = catalog["strings"]
    pairs = []

    def add(path, tok, it, en, kind, key=None):
        pairs.append({"file": os.path.basename(path), "line": tok.line, "kind": kind,
                      "it": it, "en": en, **({"key": key} if key else {})})

    def from_catalog(key, fallback_en, fallback_it):
        entry = strings.get(key)
        if entry:
            return catalog_unit(entry, "it") or fallback_it, catalog_unit(entry, "en") or key
        return fallback_it, fallback_en

    for name in sorted(os.listdir(SOURCES)):
        if not name.endswith(".swift") or name == "L10n.swift":
            continue
        path = os.path.join(SOURCES, name)
        toks = lex(open(path, encoding="utf-8").read())
        tuple_table = any(t.text == "italian" for t in toks) and any(t.text == "english" for t in toks)
        consumed = set()
        for i, t in enumerate(toks):
            nxt = toks[i + 1] if i + 1 < len(toks) else None
            # tr("it", "en") / s("it", "en") / Self.s(...) / AppError.s(...)
            if t.kind == "id" and t.text in TWO_ARG_CALLS and nxt and nxt.text == "(":
                a = string_run(toks, i + 2)
                if a and a[2] < len(toks) and toks[a[2]].text == ",":
                    b = string_run(toks, a[2] + 1)
                    if b and toks[b[2]].text == ")":
                        add(path, t, a[0], b[0], "call")
                        consumed.update(range(i + 2, b[2]))
                        continue
            # libraryLabel("key", "it", "en"): the catalog value wins when the key exists.
            if t.text == "libraryLabel" and nxt and nxt.text == "(" and toks[i + 2].kind == "str" \
                    and toks[i + 4].kind == "str":
                key = "editor.photo_library." + toks[i + 2].value
                it, en = from_catalog(key, toks[i + 6].value, toks[i + 4].value)
                add(path, t, it, en, "catalog", key)
                consumed.update(range(i + 2, i + 7))
                continue
            # localized("key", fallback: …)
            if t.text == "localized" and nxt and nxt.text == "(" and toks[i + 2].kind == "str":
                key = toks[i + 2].value
                fb = toks[i + 6] if toks[i + 4].text == "fallback" else None
                if fb is not None and fb.kind == "str":
                    it, en = from_catalog(key, fb.value, fb.value)
                    add(path, t, it, en, "catalog", key)
                    consumed.add(i + 2)
                    consumed.add(i + 6)
                elif key in strings:
                    entry = strings[key]
                    add(path, t, catalog_unit(entry, "it"), catalog_unit(entry, "en"), "catalog", key)
                    consumed.add(i + 2)
                continue
            # <language test> ? "it" : "en"
            if t.text == "?" and any(matches_before(toks, i, p) for p in LANGUAGE_TESTS):
                a = string_run(toks, i + 1)
                if a and a[2] < len(toks) and toks[a[2]].text == ":":
                    b = string_run(toks, a[2] + 1)
                    if b and not (a[0] == "it" and b[0] == "en"):
                        add(path, t, a[0], b[0], "ternary")
                        consumed.update(range(i + 1, b[2]))
                continue
            # italian: "…", english: "…" (either order)
            if t.text in ("italian", "english") and nxt and nxt.text == ":" and i + 2 < len(toks) \
                    and toks[i + 2].kind == "str" and toks[i + 3].text == "," \
                    and toks[i + 4].text in ("italian", "english") and toks[i + 4].text != t.text \
                    and toks[i + 5].text == ":" and toks[i + 6].kind == "str":
                first, second = toks[i + 2].value, toks[i + 6].value
                it, en = (first, second) if t.text == "italian" else (second, first)
                add(path, t, it, en, "labelled")
                consumed.update((i + 2, i + 6))
                continue
            # Positional tables: Control("it", "en", …), Topic("key", "en", "it", …)
            if t.text == "Control" and nxt and nxt.text == "(" and toks[i + 2].kind == "str" \
                    and toks[i + 4].kind == "str":
                add(path, t, toks[i + 2].value, toks[i + 4].value, "table")
                consumed.update((i + 2, i + 4))
                continue
            if t.text == "Topic" and nxt and nxt.text == "(" and toks[i + 2].kind == "str" \
                    and toks[i + 4].kind == "str" and toks[i + 6].kind == "str":
                add(path, t, toks[i + 6].value, toks[i + 4].value, "table")
                consumed.update((i + 2, i + 4, i + 6))
                continue
            # ("it", "en") tuples in files that declare (italian:, english:) tuple types.
            if tuple_table and t.text == "(" and i not in consumed and nxt and nxt.kind == "str" \
                    and toks[i + 2].text == "," and toks[i + 3].kind == "str" and toks[i + 4].text == ")" \
                    and not (i > 0 and toks[i - 1].kind == "id"):
                add(path, t, nxt.value, toks[i + 3].value, "tuple")
                consumed.update((i + 1, i + 3))
                continue
        # Bilingual literals: "Italiano / English" written in one string (print preflight).
        for i, t in enumerate(toks):
            if t.kind == "str" and i not in consumed and " / " in t.value and name == "BookPDF.swift":
                for chunk in t.value.split(" · "):
                    sides = chunk.strip().split(" / ")
                    if len(sides) == 2 and sides[0] and sides[1]:
                        add(path, t, sides[0].strip(), sides[1].strip(), "bilingual")
            if t.kind == "str" and i not in consumed and name == "BookPDF.swift" and " / " not in t.value:
                chunks = t.value.split(" · ")
                if len(chunks) == 2 and all(re.search(r"[A-Za-z]{3}", c) for c in chunks):
                    add(path, t, chunks[0], chunks[1], "bilingual")
        # Count-dependent fragments composed around a language choice (AppError.someImagesUnavailable).
        for i, t in enumerate(toks):
            if t.kind == "str" and (name, t.value) in MANUAL_FRAGMENTS:
                add(path, t, t.value, MANUAL_FRAGMENTS[(name, t.value)], "fragment")
    return pairs


# ---------------------------------------------------------------- catalog pairs

def variations(entry, lang):
    """All forms of a localization: [(form, value)]; `form` is '' for a plain string."""
    loc = entry.get("localizations", {}).get(lang)
    if not loc:
        return []
    if "stringUnit" in loc:
        return [("", loc["stringUnit"]["value"])]
    out = []

    def walk(node, prefix):
        if "stringUnit" in node:
            out.append((prefix, node["stringUnit"]["value"]))
        for kind, cases in node.get("variations", {}).items():
            for case, sub in cases.items():
                walk(sub, (prefix + "/" if prefix else "") + case)
        for sub in node.get("substitutions", {}).values():
            walk(sub, prefix)

    walk(loc, "")
    return out


def catalog_pairs(catalog=None):
    catalog = catalog if catalog is not None else load_catalog()
    pairs = []
    for key, entry in sorted(catalog["strings"].items()):
        en = dict(variations(entry, "en")) or {"": key}
        it = dict(variations(entry, "it"))
        for form, value in it.items():
            pairs.append({"key": key, "form": form, "it": value, "en": en.get(form, en.get("", key))})
    return pairs


# ---------------------------------------------------------------- comparison

PLACEHOLDER = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)|%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dfgisux]")


def normalise(value):
    return PLACEHOLDER.sub("{}", value)


def singular(value):
    """The `one` form with the count written out, as the sources did."""
    return re.sub(r"%(?:\d+\$)?(?:ll|l)?d", "1", value)


def diff(baseline_path):
    baseline = json.load(open(baseline_path, encoding="utf-8"))["pairs"]
    after = catalog_pairs()
    have = set()
    for p in after:
        have.add((normalise(p["it"]), normalise(p["en"])))
        if p["form"].endswith("one") or p["form"].endswith("zero"):
            have.add((normalise(singular(p["it"])), normalise(singular(p["en"]))))
    composed = json.load(open(baseline_path, encoding="utf-8")).get("composed", {})
    unique = {}
    for p in baseline:
        unique.setdefault((normalise(p["it"]), normalise(p["en"])), p)
    missing, explained = [], []
    for pair, p in sorted(unique.items()):
        if pair in have:
            continue
        reason = composed.get(p["en"])
        (explained if reason else missing).append((p, reason))
    print(f"baseline: {len(baseline)} occurrences, {len(unique)} distinct pairs")
    print(f"catalog:  {len(catalog_strings())} keys, {len(after)} pairs (plural forms expanded)")
    print(f"found:    {len(unique) - len(missing) - len(explained)}")
    for p, reason in explained:
        print(f"composed: {p['file']}:{p['line']} {p['en']!r} / {p['it']!r}: {reason}")
    for p, _ in missing:
        print(f"MISSING:  {p['file']}:{p['line']} {p['en']!r} / {p['it']!r}")
    return 1 if missing else 0


def catalog_strings():
    return load_catalog()["strings"]


def collisions(pairs):
    """English texts that need more than one Italian translation."""
    by_en = {}
    for p in pairs:
        by_en.setdefault(normalise(p["en"]), {}).setdefault(normalise(p["it"]), []).append(f"{p['file']}:{p['line']}")
    return {en: its for en, its in by_en.items() if len(its) > 1}


INLINE = [
    (re.compile(r'\b(tr|s)\(\s*"(?:[^"\\]|\\.)*"\s*,\s*"(?:[^"\\]|\\.)*"\s*\)'), "two-language call"),
    (re.compile(r'(italian|isItalian|"it"\)?)\s*\?\s*"'), "ternary choosing by language"),
    (re.compile(r'hasPrefix\("it"\)'), "hasPrefix(\"it\")"),
    (re.compile(r'==\s*"it"'), "== \"it\""),
    (re.compile(r'\b(italian|english):\s*"'), "italian:/english: literal"),
]


def check():
    found = 0
    for name in sorted(os.listdir(SOURCES)):
        if not name.endswith(".swift") or name == "L10n.swift":
            continue
        for number, line in enumerate(open(os.path.join(SOURCES, name), encoding="utf-8"), 1):
            for pattern, label in INLINE:
                if pattern.search(line):
                    print(f"{name}:{number}: {label}: {line.strip()}")
                    found += 1
    print(f"{found} inline pairs outside L10n.swift")
    return 1 if found else 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    mode = argv[1]
    if mode == "sources":
        pairs = source_pairs()
        if "--json" in argv:
            json.dump({"pairs": pairs}, sys.stdout, ensure_ascii=False, indent=1)
            print()
        else:
            for p in pairs:
                print(f"{p['file']}:{p['line']} [{p['kind']}] {p['en']!r} -> {p['it']!r}")
            print(f"{len(pairs)} occurrences, {len({(p['it'], p['en']) for p in pairs})} distinct pairs")
            for en, its in sorted(collisions(pairs).items()):
                print(f"collision {en!r}: " + "; ".join(f"{it!r} at {', '.join(at)}" for it, at in its.items()))
        return 0
    if mode == "catalog":
        pairs = catalog_pairs()
        if "--json" in argv:
            json.dump({"pairs": pairs}, sys.stdout, ensure_ascii=False, indent=1)
            print()
        else:
            for p in pairs:
                print(f"{p['key']} {p['form']} {p['en']!r} -> {p['it']!r}")
            print(f"{len(pairs)} pairs")
        return 0
    if mode == "diff":
        return diff(argv[2])
    if mode == "check":
        return check()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
