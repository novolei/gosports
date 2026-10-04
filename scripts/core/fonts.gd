class_name Fonts
extends RefCounted
## The game's typefaces:
##   Chinese   everywhere: assets/fonts/ui_font.ttf = 字魂趣圆黑 (heavy rounded; the user's pick), upright - never slanted.
##             Noto Sans SC Bold (OFL) behind it for any glyph it lacks.  NOTE: ui_font.ttf is a TRIAL version, commercial use
##             needs a licence from https://izihun.com/ (see docs section 28).
##   Latin     body    Rubik 600 (rounded, friendly)                     -> Fonts.body()
##             display Kanit ExtraBold, upright (buttons, headers, scores) -> Fonts.display()
##             italic  Kanit ExtraBold Italic (in-match flying text, logo) -> Fonts.display_italic()
## tools/make_fonts.py builds the OFL files; all are subset to the characters the game can show.

const DIR := "res://assets/fonts/"

static var _body: Font
static var _display: Font
static var _italic: Font
static var _cjk: Font


static func body() -> Font:
	if _body == null:
		var fv := FontVariation.new()
		fv.base_font = _file("latin_body.ttf")
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
		fv.fallbacks = [_cjk_font()]
		_body = fv
	return _body


static func display() -> Font:
	if _display == null:
		var fv := FontVariation.new()
		fv.base_font = _file("latin_display.ttf")
		fv.fallbacks = [_cjk_font()]
		_display = fv
	return _display


static func display_italic() -> Font:
	if _italic == null:
		var fv := FontVariation.new()
		fv.base_font = _file("latin_italic.ttf")
		fv.fallbacks = [_cjk_font()]
		_italic = fv
	return _italic


static func _file(name: String) -> FontFile:
	return load(DIR + name) as FontFile


## the Chinese face (+ the OFL fallback and the system font as the last resort)
static func _cjk_font() -> Font:
	if _cjk == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC", "Droid Sans Fallback", "sans-serif"])
		var fb := _file("cjk_fallback.ttf")
		fb.fallbacks = [sf]
		var primary := _file("ui_font.ttf") if ResourceLoader.exists(DIR + "ui_font.ttf") else null
		if primary != null:
			primary.fallbacks = [fb]
			_cjk = primary
		else:
			_cjk = fb
	return _cjk
