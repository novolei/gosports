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


## round avatar with a coloured ring
static func avatar(id: String, diameter: float, ring: Color, ring_w := 5) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(diameter, diameter)
	root.size = Vector2(diameter, diameter)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", style_box(Color(ring.r * 0.5 + 0.5, ring.g * 0.5 + 0.5, ring.b * 0.5 + 0.5), int(diameter / 2.0), ring_w, Color.WHITE, 6))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var clip := Panel.new()
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.offset_left = ring_w
	clip.offset_top = ring_w
	clip.offset_right = -ring_w
	clip.offset_bottom = -ring_w
	clip.add_theme_stylebox_override("panel", style_box(Color(ring.r * 0.35 + 0.65, ring.g * 0.35 + 0.65, ring.b * 0.35 + 0.65), int(diameter / 2.0)))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clip)
	var tex := portrait(id)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(tr)
	return root


## chunky rounded button with hover / press feedback
static func button(text: String, size := Vector2(360, 76), color := GREEN, font_size := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	var dark := color.darkened(0.25)
	var n := style_box(color, 38, 0, Color.WHITE, 10)
	var h := style_box(color.lightened(0.14), 38, 4, Color.WHITE, 12)
	var p := style_box(dark, 38, 0, Color.WHITE, 4)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", style_box(color.lightened(0.1), 38, 5, YELLOW, 12))
	b.pivot_offset = size * 0.5
	b.mouse_entered.connect(func(): _bump(b, 1.05))
	b.focus_entered.connect(func(): _bump(b, 1.05); Sfx.play("ui_hover", -8.0))
	b.mouse_exited.connect(func(): _bump(b, 1.0))
	b.focus_exited.connect(func(): _bump(b, 1.0))
	b.pressed.connect(func(): Sfx.play("ui_click", -2.0))
	return b


static func _bump(c: Control, s: float) -> void:
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2(s, s), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func panel(color := Color(1, 1, 1, 0.92), radius := 36, shadow := 14) -> PanelContainer:
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
