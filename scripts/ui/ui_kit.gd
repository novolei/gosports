class_name UIKit
extends RefCounted
## Small helpers to build the bright, rounded, Switch-Sports-like UI from code.

const BLUE := Color("2fa8ff")
const BLUE_DARK := Color("1668c9")
const PINK := Color("ff4fa0")
const PINK_DARK := Color("c42473")
const YELLOW := Color("ffd33d")
const GREEN := Color("5bd65b")
const GREEN_DARK := Color("25963a")
const INK := Color("1b2a4a")
const WHITE := Color(1, 1, 1)
## reference-style menu palette: pale translucent pills, teal when selected, orange chevron cursor
const TEAL := Color("21c4a7")
const TEAL_DARK := Color("12806c")
const PALE := Color(0.80, 0.89, 0.91, 0.94)
const PALE_TXT := Color("1d6a70")
const CHEVRON := Color("f28c28")

static var _portraits := {}


static func team_color(team: int) -> Color:
	return BLUE if team == 0 else PINK


static func team_dark(team: int) -> Color:
	return BLUE_DARK if team == 0 else PINK_DARK


static func style_box(color: Color, radius := 24, border := 0, border_color := Color.WHITE, shadow := 0, margin := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = border_color
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_color = Color(0, 0, 0, 0.28)
		s.shadow_offset = Vector2(0, shadow * 0.45)
	if margin > 0:
		s.content_margin_left = margin
		s.content_margin_right = margin
		s.content_margin_top = margin * 0.5
		s.content_margin_bottom = margin * 0.5
	s.anti_aliasing = true
	return s


static func label(text: String, size := 32, color := Color.WHITE, outline := 0, outline_color := INK, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func portrait(id: String) -> Texture2D:
	if not _portraits.has(id):
		var p := "res://assets/portraits/%s.png" % id
		_portraits[id] = load(p) if ResourceLoader.exists(p) else null
	return _portraits[id]


static var _mask_mat: ShaderMaterial


static func _circle_mask() -> ShaderMaterial:
	if _mask_mat == null:
		_mask_mat = ShaderMaterial.new()
		_mask_mat.shader = load("res://shaders/ui_circle_mask.gdshader")
	return _mask_mat


## round avatar in the same soft style as the pause button: a fat white disc with a gentle shadow, a pastel inner disc in
## the team colour and the portrait masked by a smooth circle (no clip_children: that costs an extra pass on phones)
static func avatar(id: String, diameter: float, ring: Color, ring_w := 5) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(diameter, diameter)
	root.size = Vector2(diameter, diameter)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := maxf(float(ring_w) + 2.0, diameter * 0.07)
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", style_box(Color(1, 1, 1, 0.96), int(diameter / 2.0), 0, Color.WHITE, 8))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var inner := Panel.new()
	inner.position = Vector2(pad, pad)
	inner.size = Vector2(diameter - pad * 2.0, diameter - pad * 2.0)
	var tint := Color(ring.r * 0.32 + 0.68, ring.g * 0.32 + 0.68, ring.b * 0.32 + 0.68)
	inner.add_theme_stylebox_override("panel", style_box(tint, int(inner.size.x / 2.0), 3, Color(ring.r, ring.g, ring.b, 0.85)))
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inner)
	var tex := portrait(id)
	if tex:
		var inset := pad + 3.0
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE            # (before the texture, or its size becomes the minimum size)
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture = tex
		tr.position = Vector2(inset, inset)
		tr.size = Vector2(diameter - inset * 2.0, diameter - inset * 2.0)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.material = _circle_mask()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
	return root


## orange chevron that marks the selected menu entry
class _Chevron:
	extends Control
	var _t := 0.0

	func _process(dt: float) -> void:
		if visible:
			_t += dt
			queue_redraw()

	func _draw() -> void:
		var sway := sin(_t * 7.0) * 3.0
		var c := size * 0.5 + Vector2(sway, 0.0)
		var pts := PackedVector2Array([c + Vector2(-9, -17), c + Vector2(9, 0), c + Vector2(-9, 17)])
		draw_polyline(pts, Color.WHITE, 11.0, true)
		draw_polyline(pts, CHEVRON, 6.5, true)


## menu pill in the reference game's look: pale + teal text, teal + white text when selected (focus / hover), with an
## orange chevron. `color` is only a hint: UIKit.GREEN marks the primary action (always teal).
static func button(text: String, size := Vector2(360, 76), color := GREEN, font_size := 34) -> Button:
	var primary := color == GREEN
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	var rad := int(size.y * 0.5)
	var idle_txt := Color.WHITE if primary else PALE_TXT
	b.add_theme_color_override("font_color", idle_txt)
	for n in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(n, Color.WHITE)
	b.add_theme_constant_override("outline_size", 0)
	b.add_theme_color_override("font_outline_color", Color(TEAL_DARK.r, TEAL_DARK.g, TEAL_DARK.b, 0.5))
	var rest := TEAL if primary else PALE
	b.add_theme_stylebox_override("normal", style_box(rest, rad, 3, Color(1, 1, 1, 0.9), 8))
	b.add_theme_stylebox_override("hover", style_box(TEAL.lightened(0.06), rad, 4, Color.WHITE, 10))
	b.add_theme_stylebox_override("pressed", style_box(TEAL_DARK, rad, 3, Color.WHITE, 4))
	b.add_theme_stylebox_override("focus", style_box(TEAL.lightened(0.06), rad, 4, Color.WHITE, 10))
	b.add_theme_stylebox_override("hover_pressed", style_box(TEAL_DARK, rad, 3, Color.WHITE, 4))
	var chev := _Chevron.new()
	chev.size = Vector2(40, 48)
	chev.position = Vector2(-52.0, size.y * 0.5 - 24.0)
	chev.visible = false
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(chev)
	b.pivot_offset = size * 0.5
	var show_chev := func(on: bool):
		chev.visible = on
		b.add_theme_constant_override("outline_size", 6 if (on or primary) else 0)
	if primary:
		b.add_theme_constant_override("outline_size", 6)
	b.mouse_entered.connect(func(): _bump(b, 1.04); show_chev.call(true))
	b.focus_entered.connect(func(): _bump(b, 1.04); show_chev.call(true); Sfx.play("ui_hover", -8.0))
	b.mouse_exited.connect(func(): _bump(b, 1.0); if not b.has_focus(): show_chev.call(false))
	b.focus_exited.connect(func(): _bump(b, 1.0); show_chev.call(false))
	b.pressed.connect(func(): Sfx.play("ui_click", -2.0))
	return b


## on / off switch as a pill (teal "开" / pale "关") - the default CheckButton looks tiny in this theme
static func toggle_pill(initial: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = initial
	b.custom_minimum_size = Vector2(120, 54)
	b.add_theme_font_size_override("font_size", 28)
	b.text = "开" if initial else "关"
	b.add_theme_color_override("font_color", PALE_TXT)
	for n in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(n, Color.WHITE)
	b.add_theme_color_override("font_hover_color", TEAL_DARK)
	b.add_theme_stylebox_override("normal", style_box(PALE, 27, 3, Color(1, 1, 1, 0.9), 6))
	b.add_theme_stylebox_override("hover", style_box(Color(0.88, 0.95, 0.96), 27, 3, Color.WHITE, 8))
	b.add_theme_stylebox_override("pressed", style_box(TEAL, 27, 3, Color.WHITE, 4))
	b.add_theme_stylebox_override("hover_pressed", style_box(TEAL.lightened(0.06), 27, 3, Color.WHITE, 6))
	b.add_theme_stylebox_override("focus", style_box(Color(1, 1, 1, 0.0), 27, 4, CHEVRON, 0))
	b.toggled.connect(func(v):
		b.text = "开" if v else "关"
		Sfx.play("ui_click", -5.0)
		cb.call(v))
	return b


## "label ........ [开]" row
static func toggle_row(text: String, initial: bool, cb: Callable, label_w := 520, font := 30) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var l := label(text, font, INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(label_w, 0)
	h.add_child(l)
	h.add_child(toggle_pill(initial, cb))
	return h


static func _bump(c: Control, s: float) -> void:
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2(s, s), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func panel(color := Color(0.92, 0.96, 0.97, 0.92), radius := 36, shadow := 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style_box(color, radius, 0, Color.WHITE, shadow, 28))
	return p


## animated "pop in" for popups and banners
static func pop_in(c: Control, from := 0.4, dur := 0.28) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(from, from)
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate:a", 1.0, dur * 0.6)
