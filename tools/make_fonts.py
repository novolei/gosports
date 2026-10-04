#!/usr/bin/env python
"""Builds the game's font files from the originals in art_src/fonts/ (download from https://github.com/google/fonts/tree/main/ofl):

  Chinese  (primary)  assets/fonts/WenDaoChaoHei-2.ttf  文道潮黑 - the user's chosen Chinese face (a free font, shipped UNMODIFIED, so it
                      is not generated or subset here; from E:ackup\WenDaoChaoHei.zip).
  Chinese  (fallback) Noto Sans SC Bold (wght 700) -> assets/fonts/cjk_fallback.ttf  (OFL; glyphs the primary font lacks)
  Latin    text       Rubik (variable, weight 600)         -> assets/fonts/latin_body.ttf
  Latin    headlines  Kanit ExtraBold (upright)            -> assets/fonts/latin_display.ttf   (buttons, headers, scores)
  Latin    callouts   Kanit ExtraBold Italic               -> assets/fonts/latin_italic.ttf    (in-match flying text, logo)
  (art only)          Noto Sans SC Black -> art_src/fonts/build/cjk_display.ttf  (baked into the ad boards / logo, licence-clean)

Everything except WenDaoChaoHei-2.ttf is SIL OFL 1.1 and is subset to the characters the game can show (all of scripts/**/*.gd).
Re-run after adding Chinese text:   python tools/make_fonts.py
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
    os.makedirs(os.path.join(SRC, "build"), exist_ok=True)
    noto = os.path.join(SRC, "NotoSansSC-VF.ttf")
    f = instancer.instantiateVariableFont(TTFont(noto), {"wght": 700})
    subset_to(f, os.path.join(DST, "cjk_fallback.ttf"), text)
    f = instancer.instantiateVariableFont(TTFont(noto), {"wght": 900})
    subset_to(f, os.path.join(SRC, "build", "cjk_display.ttf"), text)
    subset_to(TTFont(os.path.join(SRC, "Kanit-ExtraBold.ttf")), os.path.join(DST, "latin_display.ttf"), text)
    subset_to(TTFont(os.path.join(SRC, "Kanit-ExtraBoldItalic.ttf")), os.path.join(DST, "latin_italic.ttf"), text)
    subset_to(TTFont(os.path.join(SRC, "Rubik-VF.ttf")), os.path.join(DST, "latin_body.ttf"), text)


if __name__ == "__main__":
    main()
