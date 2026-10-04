#!/usr/bin/env python
"""Shrink a CJK font to the characters this game can actually show (a full CJK font is 5-20 MB, the subset ~200-400 KB).

    python tools/subset_font.py <input.ttf|otf> <output.ttf>

Characters = every glyph used in scripts/**/*.gd (the Chinese source strings and the English table) + printable ASCII +
common punctuation + the full width forms that appear in the HUD. Re-run it whenever you add Chinese text.
Needs: pip install fonttools brotli
"""
import glob
import sys

from fontTools import subset


def used_chars() -> str:
    chars = set(chr(c) for c in range(0x20, 0x7F))
    chars.update("·•×÷→←↑↓⇄◀▶★✓—–…「」『』（）【】《》，。！？：；、“”‘’％＋－＝～　")
    for path in glob.glob("scripts/**/*.gd", recursive=True):
        with open(path, encoding="utf-8") as f:
            chars.update(f.read())
    chars.discard("\n")
    chars.discard("\r")
    chars.discard("\t")
    return "".join(sorted(chars))


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    src, dst = sys.argv[1], sys.argv[2]
    text = used_chars()
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.hinting = False
    font = subset.load_font(src, opts)
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    subset.save_font(font, dst, opts)
    print("kept %d characters -> %s" % (len(text), dst))


if __name__ == "__main__":
    main()
