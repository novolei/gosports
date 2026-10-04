class_name Fonts
extends RefCounted
## The game's two typefaces (all SIL OFL 1.1, subset by tools/make_fonts.py):
##   body    Rubik (rounded, friendly, variable weight 600) for Latin + Noto Sans SC Bold for Chinese
##   display Kanit ExtraBold Italic for Latin + Noto Sans SC Black drawn slanted for Chinese: the sporty broadcast look used by
##           big headlines, scores, banners and callouts (UIKit.label switches to it from 54 px up)

const DIR := "res://assets/fonts/"
const SKEW := -0.2

static var _body: Font
static var _display: Font


static func body() -> Font:
	if _body == null:
		_body = _make_body()
	return _body


static func display() -> Font:
	if _display == null:
		_display = _make_display()
	return _display


static func _file(name: String) -> FontFile:
	return load(DIR + name) as FontFile


static func _make_body() -> Font:
	var cjk := _file("cjk_body.ttf")
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC", "Droid Sans Fallback", "sans-serif"])
	cjk.fallbacks = [sf]
	var fv := FontVariation.new()
	fv.base_font = _file("latin_body.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	fv.fallbacks = [cjk]
	return fv


static func _make_display() -> Font:
	var cjk := FontVariation.new()
	cjk.base_font = _file("cjk_display.ttf")
	cjk.variation_transform = Transform2D(Vector2(1, 0), Vector2(SKEW, 1), Vector2.ZERO)
	var fv := FontVariation.new()
	fv.base_font = _file("latin_display.ttf")
	fv.fallbacks = [cjk, body()]
	return fv
