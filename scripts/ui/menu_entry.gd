class_name MenuEntry
extends Button
## Big list entry in the style of the reference game's title / options menus: a (slightly tilted) pill with a glyph badge on
## the left, a bold title, a small subtitle, and an optional tag on the right. Selected (hover / focus) = teal with diagonal
## stripes and an orange chevron; otherwise dark slate ("dark" variant, main menu) or pale glass ("pale" variant, option lists).

signal chosen

const SLATE := Color(0.25, 0.34, 0.40)
const PALE := Color(0.82, 0.90, 0.93)
const TEAL := Color(0.08, 0.70, 0.66)

var variant := "dark"
var title := ""
var subtitle := ""
var tag := ""
var glyph_kind := "ball"
var tilt := 0.0                     # degrees; the reference tilts the main entries about -3.5
var title_size := 40
var _bg: ColorRect
var _title_l: Label
var _sub_l: Label
var _tag_l: Label
var _tag_bg: Panel
var _glyph: Control
var _chev: Control
var _sel := false
var _mark := false                  # chosen (stays teal even when not focused)
var _press := false
var _t := 0.0
var _badge: Control = null


func build(p_title: String, p_sub: String, p_glyph: String, p_size: Vector2, p_variant := "dark", p_tag := "", p_tilt := 0.0, p_title_size := 40) -> MenuEntry:
	title = p_title
	subtitle = p_sub
	glyph_kind = p_glyph
	variant = p_variant
	tag = p_tag
	tilt = p_tilt
	title_size = p_title_size
	custom_minimum_size = p_size
	size = p_size
	focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(st, empty)
	pivot_offset = p_size * 0.5
	rotation = deg_to_rad(-tilt)
	# background pill
	_bg = GW.pill_bg(p_size, p_size.y * 0.5, SLATE if variant == "dark" else PALE, 0.0)
	_bg.show_behind_parent = true
	add_child(_bg)
	# glyph badge
	var gd := p_size.y * 0.62
	_glyph = GW.glyph(glyph_kind, gd, Color("2f6f78") if variant == "dark" else Color("3a8d94"))
	_glyph.position = Vector2(p_size.y * 0.2, (p_size.y - gd) * 0.5)
	add_child(_glyph)
	var tx := p_size.y * 0.2 + gd + 18.0
	_title_l = UIKit.label(title, title_size, Color.WHITE, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_title_l.position = Vector2(tx, p_size.y * (0.08 if subtitle != "" else 0.0))
	_title_l.size = Vector2(p_size.x - tx - (200.0 if tag != "" else 40.0), p_size.y * (0.58 if subtitle != "" else 1.0))
	add_child(_title_l)
	if subtitle != "":
		_sub_l = UIKit.label(subtitle, int(float(title_size) * 0.58), Color(0.78, 0.9, 0.94), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		_sub_l.position = Vector2(tx, p_size.y * 0.58)
		_sub_l.size = Vector2(p_size.x - tx - (190.0 if tag != "" else 40.0), p_size.y * 0.34)
		_sub_l.clip_text = true
		add_child(_sub_l)
	if tag != "":
		_tag_bg = Panel.new()
		_tag_bg.size = Vector2(120, p_size.y * 0.36)
		_tag_bg.position = Vector2(p_size.x - 150.0, p_size.y * 0.5 - _tag_bg.size.y * 0.5 + p_size.y * 0.12)
		_tag_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tag_bg.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.1, 0.2, 0.26, 0.35), int(_tag_bg.size.y * 0.5)))
		add_child(_tag_bg)
		_tag_l = UIKit.label(tag, int(float(title_size) * 0.55), Color.WHITE)
		_tag_l.size = _tag_bg.size
		_tag_bg.add_child(_tag_l)
	# orange chevron to the left of the selected entry
	_chev = Control.new()
	_chev.size = Vector2(40, 56)
	_chev.position = Vector2(-46.0, p_size.y * 0.5 - 28.0)
	_chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chev.visible = false
	_chev.draw.connect(func():
		var c := _chev.size * 0.5 + Vector2(sin(_t * 7.0) * 3.0, 0.0)
		var pts := PackedVector2Array([c + Vector2(-9, -18), c + Vector2(9, 0), c + Vector2(-9, 18)])
		_chev.draw_polyline(pts, Color.WHITE, 12.0, true)
		_chev.draw_polyline(pts, UIKit.CHEVRON, 7.0, true))
	add_child(_chev)
	mouse_entered.connect(func(): _set_sel(true))
	mouse_exited.connect(func(): _set_sel(has_focus()))
	focus_entered.connect(func(): _set_sel(true); Sfx.play("ui_hover", -8.0))
	focus_exited.connect(func(): _set_sel(false))
	button_down.connect(func(): _press = true; _refresh())
	button_up.connect(func(): _press = false; _refresh())
	pressed.connect(func(): Sfx.play("ui_click", -2.0); chosen.emit())
	resized.connect(func(): GW.pill_set(_bg, size))
	_refresh()
	return self


## a red dot with "!" (new unlocks)
func add_badge() -> void:
	if _badge != null:
		return
	_badge = Control.new()
	_badge.position = Vector2(size.x - 44.0, -12.0)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := Panel.new()
	d.size = Vector2(38, 38)
	d.add_theme_stylebox_override("panel", UIKit.style_box(Color("ff3b4f"), 19, 4, Color.WHITE, 4))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(d)
	var l := UIKit.label("!", 26, Color.WHITE)
	l.size = d.size
	_badge.add_child(l)
	add_child(_badge)


func _process(dt: float) -> void:
	if _sel:
		_t += dt
		_chev.queue_redraw()


func mark(on: bool) -> void:
	_mark = on
	_refresh()


func _set_sel(on: bool) -> void:
	if on == _sel:
		return
	_sel = on
	_chev.visible = on
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.035, 1.035) if on else Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh()


func _refresh() -> void:
	var m: ShaderMaterial = _bg.material
	if _sel or _press or _mark:
		m.set_shader_parameter("base_col", TEAL.darkened(0.12) if _press else TEAL)
		m.set_shader_parameter("stripes", 1.0 if (_sel or _press) else 0.45)
		m.set_shader_parameter("lift", 1.0 if _press else 0.0)
		_title_l.add_theme_color_override("font_color", Color.WHITE)
		_title_l.add_theme_constant_override("outline_size", 6)
		_title_l.add_theme_color_override("font_outline_color", Color(0.02, 0.35, 0.36, 0.7))
		if _sub_l != null:
			_sub_l.add_theme_color_override("font_color", Color(0.9, 1.0, 0.98))
	else:
		m.set_shader_parameter("base_col", SLATE if variant == "dark" else PALE)
		m.set_shader_parameter("stripes", 0.0)
		m.set_shader_parameter("lift", 0.0)
		var dark := variant == "dark"
		_title_l.add_theme_color_override("font_color", Color.WHITE if dark else UIKit.PALE_TXT)
		_title_l.add_theme_constant_override("outline_size", 0)
		if _sub_l != null:
			_sub_l.add_theme_color_override("font_color", Color(0.78, 0.9, 0.94) if dark else Color(0.35, 0.5, 0.56))
	if _glyph != null:
		(_glyph as GW._Glyph).disc = Color("0b6f6a") if (_sel or _press or _mark) else (Color("2f6f78") if variant == "dark" else Color("3a8d94"))
		_glyph.queue_redraw()
