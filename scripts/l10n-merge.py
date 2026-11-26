#!/usr/bin/env python3
"""Three-way merge of Resources/Localizable.xcstrings, key by key.

  scripts/l10n-merge.py BASE OURS THEIRS [PATH]

The merged catalog is written over OURS (the git merge-driver convention for %A).
Exit status 0: merged. 1: at least one key was changed on both sides in different ways
(or changed on one side and removed on the other); the keys are named on stderr and OURS
is left untouched. 2: a file could not be read.

Rules, per key of "strings" (and per top-level field such as "version"):
  - only one side differs from BASE: take that side (additions and removals included);
  - both sides equal: take it;
  - otherwise a conflict.
Order: when the keys of OURS are in code point order, as Xcode writes them, the result is too;
otherwise the keys keep the order of OURS and keys new in THEIRS follow. Formatting is the
catalog's own (two-space indent, UTF-8, final newline), so an unchanged catalog round-trips
byte for byte.
"""
import json
import sys

MISSING = object()


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def dump(catalog):
    return json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"


def merge_maps(base, ours, theirs, label, conflicts):
    merged = {}
    keys = list(ours)
    keys += [k for k in theirs if k not in ours]
    keys += [k for k in base if k not in ours and k not in theirs]
    for key in keys:
        b, o, t = base.get(key, MISSING), ours.get(key, MISSING), theirs.get(key, MISSING)
        if o == t:
            value = o
        elif o == b:
            value = t
        elif t == b:
            value = o
        else:
            conflicts.append(f"{label}{key!r}")
            value = o
        if value is not MISSING:
            merged[key] = value
    return merged


def merge(base, ours, theirs):
    conflicts = []
    strings = merge_maps(base.get("strings", {}), ours.get("strings", {}),
                         theirs.get("strings", {}), "", conflicts)
    top = merge_maps({k: v for k, v in base.items() if k != "strings"},
                     {k: v for k, v in ours.items() if k != "strings"},
                     {k: v for k, v in theirs.items() if k != "strings"}, "field ", conflicts)
    ours_keys = list(ours.get("strings", {}))
    if ours_keys == sorted(ours_keys):
        strings = {k: strings[k] for k in sorted(strings)}
    result = {}
    for k in ours:  # keep the top-level field order of OURS, "strings" in place
        if k == "strings":
            result[k] = strings
        elif k in top:
            result[k] = top[k]
    for k in top:
        result.setdefault(k, top[k])
    result.setdefault("strings", strings)
    return result, conflicts


def main(argv):
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        base, ours, theirs = (load(p) for p in argv[1:4])
    except (OSError, ValueError) as error:
        print(f"l10n-merge: {error}", file=sys.stderr)
        return 2
    result, conflicts = merge(base, ours, theirs)
    if conflicts:
        print("l10n-merge: changed differently on both sides, resolve by hand:", file=sys.stderr)
        for c in conflicts:
            print(f"  {c}", file=sys.stderr)
        return 1
    with open(argv[2], "w", encoding="utf-8") as f:
        f.write(dump(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
