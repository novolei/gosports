#!/usr/bin/env python
"""Builds the game's font files (all SIL Open Font License 1.1 - free for commercial use) from the originals in art_src/fonts/:

  Latin   display  Kanit ExtraBold Italic        -> assets/fonts/latin_display.ttf   (scores, banners, headlines: sporty italic)
  Latin   body     Rubik (variable, rounded)     -> assets/fonts/latin_body.ttf
  Chinese display  Noto Sans SC Black (wght 900) -> assets/fonts/cjk_display.ttf     (drawn slanted in code: FontVariation skew)
  Chinese body     Noto Sans SC Bold (wght 700)  -> assets/fonts/cjk_body.ttf

Every file is subset to the characters the game can show (everything in scripts/**/*.gd), which keeps the CJK fonts at a few
hundred KB instead of 10+ MB. Re-run after adding Chinese text:   python tools/make_fonts.py
Originals (download from https://github.com/google/fonts/tree/main/ofl): art_src/fonts/NotoSansSC[wght].ttf,
Kanit-ExtraBoldItalic.ttf, Rubik[wght].ttf (+ their OFL.txt).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

import subset_font

SRC = "art_src/fonts"
DST = "assets/fonts"


def subset_to(font: TTFont, dst: str, text: str, keep_variations=False) -> None:
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.hinting = False
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    subset.save_font(font, dst, opts)
    print("%-28s %7.1f KB" % (dst, os.path.getsize(dst) / 1024.0))


def main() -> None:
    text = subset_font.used_chars()
    os.makedirs(DST, exist_ok=True)
    noto = os.path.join(SRC, "NotoSansSC-VF.ttf")
    for wght, out in ((900, "cjk_display.ttf"), (700, "cjk_body.ttf")):
        f = TTFont(noto)
        f = instancer.instantiateVariableFont(f, {"wght": wght})
        subset_to(f, os.path.join(DST, out), text)
    subset_to(TTFont(os.path.join(SRC, "Kanit-ExtraBoldItalic.ttf")), os.path.join(DST, "latin_display.ttf"), text)
    subset_to(TTFont(os.path.join(SRC, "Rubik-VF.ttf")), os.path.join(DST, "latin_body.ttf"), text)


if __name__ == "__main__":
    main()
