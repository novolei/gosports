class_name GW
extends RefCounted
## Game-style UI pieces that avoid the "web page" look: slanted ribbons with outlined type, slanted boards with a gloss
## and a hard shadow, long pill rows (label left, control right) instead of cards, chunky sliders. Everything is drawn
## once into a CanvasItem (no per-frame work, no clip_children, no extra render passes) so it is cheap on phones.

const SKEW := 0.22                     # horizontal shear (tan of the slant angle)


# ------------------------------------------------------------------ slanted shapes
## parallelogram with chamfered corners; `size` is the bounding box, the slant leans to the right at the top
static func slant_poly(size: Vector2, skew := SKEW, bevel := 14.0) -> PackedVector2Array:
	var s := skew * size.y
	var b := minf(bevel, size.y * 0.3)
	return PackedVector2Array([
		Vector2(s + b, 0.0), Vector2(size.x - b, 0.0), Vector2(size.x, b * 0.6),
		Vector2(size.x - s, size.y - b * 0.6), Vector2(size.x - s - b, size.y),
		Vector2(b, size.y), Vector2(0.0, size.y - b * 0.6), Vector2(s, b * 0.6),
	])


class _Board:
	extends Control
	var fill := Color(0.92, 0.96, 0.97, 0.96)
	var rim := Color.WHITE
	var skew := GW.SKEW
	var shadow := true
	var gloss := false
	var bevel := 16.0

	func _draw() -> void:
		var inner := size - Vector2(8, 10)
		var poly := GW.slant_poly(inner, skew, bevel)
		if shadow:
			var sh := PackedVector2Array()
			for p in poly:
				sh.append(p + Vector2(4, 7))
			draw_colored_polygon(sh, Color(0.03, 0.12, 0.25, 0.2))
		var body := PackedVector2Array()
		for p in poly:
			body.append(p + Vector2(4, 2))
		draw_colored_polygon(body, fill)
		if gloss:
			# lighter top third, clipped by the slant (just a thinner parallelogram inside)
			var gh := inner.y * 0.42
			var g := GW.slant_poly(Vector2(inner.x - 22.0, gh), skew * inner.y / gh * 0.98, 8.0)
			var gp := PackedVector2Array()
			for p in g:
				gp.append(p + Vector2(15, 8))
			draw_colored_polygon(gp, Color(1, 1, 1, 0.22 if fill.v > 0.6 else 0.09))
		var line := PackedVector2Array(body)
		line.append(body[0])
		draw_polyline(line, rim, 3.0, true)


## slanted board with gloss and hard shadow; add children on top of it
static func board(size: Vector2, fill := Color(0.92, 0.96, 0.97, 0.96), rim := Color.WHITE, skew := SKEW) -> Control:
	var b := _Board.new()
	b.size = size
	b.custom_minimum_size = size
	b.fill = fill
	b.rim = rim
	b.skew = skew
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


class _Ribbon:
	extends Control
	var col := UIKit.TEAL
	var tail := true

	func _draw() -> void:
		var h := size.y
		var poly := GW.slant_poly(Vector2(size.x - 10.0, h - 8.0), 0.3, 10.0)
		var sh := PackedVector2Array()
		for p in poly:
			sh.append(p + Vector2(6, 7))
		draw_colored_polygon(sh, Color(0.03, 0.12, 0.25, 0.22))
		var body := PackedVector2Array()
		for p in poly:
			body.append(p + Vector2(5, 3))
		draw_colored_polygon(body, col)
		var top := PackedVector2Array()
		for p in GW.slant_poly(Vector2(size.x - 34.0, (h - 8.0) * 0.45), 0.6, 6.0):
			top.append(p + Vector2(17, 8))
		draw_colored_polygon(top, Color(1, 1, 1, 0.07))
		var line := PackedVector2Array(body)
		line.append(body[0])
		draw_polyline(line, Color.WHITE, 3.0, true)


## big outlined title on a slanted colour ribbon (page headers, popup titles)
static func ribbon(text: String, width := 520.0, height := 92.0, col := UIKit.TEAL, font_size := 54) -> Control:
	var r := _Ribbon.new()
	r.size = Vector2(width, height)
	r.custom_minimum_size = r.size
	r.col = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, font_size, Color.WHITE, 14, col.darkened(0.5))
	l.position = Vector2(10, -2)
	l.size = Vector2(width - 20.0, height - 8.0)
	r.add_child(l)
	return r


# ------------------------------------------------------------------ pill rows
## "label ........ [control]" as ONE long pill: no card, no separators
static func row_pill(label_text: String, control: Control, width := 760.0, height := 70.0, label_w := 340.0) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(width, height)
	p.size = p.custom_minimum_size
	p.add_theme_stylebox_override("panel", UIKit.style_box(UIKit.PALE, int(height * 0.5), 3, Color(1, 1, 1, 0.9), 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(label_text, 30, UIKit.PALE_TXT, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.position = Vector2(height * 0.5 + 6.0, 0)
	l.size = Vector2(label_w, height)
	p.add_child(l)
	var cs := control.get_combined_minimum_size()
	control.position = Vector2(width - cs.x - 18.0, (height - cs.y) * 0.5)
	p.add_child(control)
	return p


static var _tex_cache := {}


static func _disc(d: int, col: Color, rim: Color) -> Texture2D:
	var key := "%d|%s|%s" % [d, col.to_html(), rim.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := float(d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) + 0.5 - r, float(y) + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			if a <= 0.0:
				continue
			var c := rim if dist > r - 5.0 else col
			# soft highlight in the upper left
			var hl := clampf(1.0 - Vector2(float(x) - r * 0.65, float(y) - r * 0.6).length() / (r * 0.7), 0.0, 1.0) * 0.35
			c = c.lerp(Color.WHITE, hl if dist <= r - 5.0 else 0.0)
			c.a = a
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


## chunky slider: thick pill track filled in teal, big white knob
static func slider(value: float, cb: Callable, width := 360.0) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(width, 48)
	s.size = s.custom_minimum_size
	var track := UIKit.style_box(Color(0.72, 0.8, 0.84), 12, 2, Color(1, 1, 1, 0.9))
	var fill := UIKit.style_box(UIKit.TEAL, 12)
	var fill_hi := UIKit.style_box(UIKit.TEAL.lightened(0.1), 12)
	for sb in [track, fill, fill_hi]:
		(sb as StyleBoxFlat).content_margin_top = 12.0
		(sb as StyleBoxFlat).content_margin_bottom = 12.0
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	var knob := _disc(44, Color.WHITE, UIKit.TEAL)
	var knob_hi := _disc(48, Color(1.0, 0.98, 0.9), UIKit.CHEVRON)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob_hi)
	s.add_theme_icon_override("grabber_disabled", knob)
	s.add_theme_constant_override("center_grabber", 0)
	s.value_changed.connect(func(v): cb.call(v))
	return s


## big outlined heading without any box
static func heading(text: String, size := 64, col := Color.WHITE) -> Label:
	return UIKit.label(text, size, col, 16, Color(0.05, 0.2, 0.45, 0.95))


class _BallBadge:
	extends Control
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, sin(_t * 3.2) * 4.0)
		var r: float = minf(size.x, size.y) * 0.5 - 6.0
		draw_circle(c + Vector2(0, r * 0.2 + 10.0), r * 0.9, Color(0, 0, 0, 0.16))
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r - 4.0, Color(1.0, 0.86, 0.26))
		var seam := Color(0.2, 0.42, 0.92)
		draw_arc(c + Vector2(-r * 0.77, r * 0.23), r * 0.92, -1.0, 0.5, 16, seam, 5.0, true)
		draw_arc(c + Vector2(r * 0.77, r * 0.23), r * 0.92, PI - 0.5, PI + 1.0, 16, seam, 5.0, true)
		draw_arc(c + Vector2(0, -r * 0.92), r * 0.77, 0.5, PI - 0.5, 16, seam, 5.0, true)
		draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.2, Color(1, 1, 1, 0.5))


## bobbing volleyball emblem
static func ball_badge(d := 120.0) -> Control:
	var b := _BallBadge.new()
	b.size = Vector2(d, d)
	b.custom_minimum_size = b.size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


# ================================================================== Switch-Sports-style pills and frosted panels
const PILL_PAD := 18.0
static var _pill_shader: Shader
static var _frost_shader: Shader


## ColorRect carrying the pill shader; `size` is the pill, the rect is PILL_PAD larger on every side (shadow lives there).
## Add it as the FIRST child (or with show_behind_parent) and place it at (-PILL_PAD, -PILL_PAD).
static func pill_bg(size: Vector2, radius := -1.0, base := Color(0.82, 0.9, 0.93), stripes := 0.0) -> ColorRect:
	if _pill_shader == null:
		_pill_shader = load("res://shaders/ui_pill.gdshader")
	var r := ColorRect.new()
	r.color = Color.WHITE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = _pill_shader
	r.material = m
	pill_set(r, size, radius, base, stripes)
	return r


static func pill_set(r: ColorRect, size: Vector2, radius := -1.0, base := Color(-1, 0, 0), stripes := -1.0) -> void:
	var m: ShaderMaterial = r.material
	r.position = Vector2(-PILL_PAD, -PILL_PAD)
	r.size = size + Vector2(PILL_PAD, PILL_PAD) * 2.0
	m.set_shader_parameter("rect_size", size)
	m.set_shader_parameter("pad", PILL_PAD)
	if radius >= 0.0:
		m.set_shader_parameter("radius", minf(radius, minf(size.x, size.y) * 0.5))
	else:
		m.set_shader_parameter("radius", minf(size.x, size.y) * 0.5)
	if base.r >= 0.0:
		m.set_shader_parameter("base_col", base)
	if stripes >= 0.0:
		m.set_shader_parameter("stripes", stripes)


## frosted-glass panel (blurred scene + pale tint). Returns a holder Control of `size`; add content to it.
static func frost(size: Vector2, radius := 36.0, tint := Color(0.9, 0.96, 0.97), amount := 0.62) -> Control:
	if OS.has_feature("mobile") or (Game.main != null and Game.main.dev.has("flatfrost")):
		# phones: no blur (hint_screen_texture copies the back buffer every frame = ~8 ms of GPU on the test phone);
		# the lightly flat style makes a plain translucent pale panel look right anyway
		var holder_m := Control.new()
		holder_m.size = size
		holder_m.custom_minimum_size = size
		holder_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pn := Panel.new()
		pn.size = size
		pn.add_theme_stylebox_override("panel", UIKit.style_box(Color(tint.r, tint.g, tint.b, 0.8 + 0.16 * amount), int(radius), 3, Color.WHITE, 6))
		pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder_m.add_child(pn)
		return holder_m
	if _frost_shader == null:
		_frost_shader = load("res://shaders/ui_frost.gdshader")
	var holder := Control.new()
	holder.size = size
	holder.custom_minimum_size = size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = Color.WHITE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = _frost_shader
	m.set_shader_parameter("rect_size", size)
	m.set_shader_parameter("pad", 22.0)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tint_amount", amount)
	m.set_shader_parameter("lod", 2.4 if OS.has_feature("mobile") else 3.0)
	r.material = m
	r.position = Vector2(-22, -22)
	r.size = size + Vector2(44, 44)
	holder.add_child(r)
	return holder


## small round glyph badge used in front of menu entries: dark teal / slate disc with a white pictogram
class _Glyph:
	extends Control
	var kind := "ball"
	var disc := Color("2f7f86")
	var ink := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.18))
		draw_circle(c, r, disc)
		draw_arc(c, r - 3.0, 0.0, TAU, 40, Color(1, 1, 1, 0.22), 2.0, true)
		var s := r * 0.52
		match kind:
			"ball":
				draw_arc(c, s, 0.0, TAU, 28, ink, 3.2, true)
				draw_arc(c + Vector2(-s * 0.95, s * 0.2), s * 0.95, -0.9, 0.6, 12, ink, 3.0, true)
				draw_arc(c + Vector2(s * 0.95, s * 0.2), s * 0.95, PI - 0.6, PI + 0.9, 12, ink, 3.0, true)
				draw_arc(c + Vector2(0, -s * 0.95), s * 0.8, 0.6, PI - 0.6, 12, ink, 3.0, true)
			"cup":
				var pts := PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.8), c + Vector2(s * 0.8, -s * 0.8), c + Vector2(s * 0.55, s * 0.1), c + Vector2(0, s * 0.45), c + Vector2(-s * 0.55, s * 0.1)])
				draw_colored_polygon(pts, ink)
				draw_arc(c + Vector2(-s * 0.8, -s * 0.35), s * 0.4, PI * 0.5, PI * 1.5, 10, ink, 3.0, true)
				draw_arc(c + Vector2(s * 0.8, -s * 0.35), s * 0.4, -PI * 0.5, PI * 0.5, 10, ink, 3.0, true)
				draw_rect(Rect2(c + Vector2(-s * 0.15, s * 0.4), Vector2(s * 0.3, s * 0.35)), ink)
				draw_rect(Rect2(c + Vector2(-s * 0.6, s * 0.72), Vector2(s * 1.2, s * 0.22)), ink)
			"target":
				for k in 3:
					draw_arc(c, s * (1.0 - 0.32 * float(k)), 0.0, TAU, 24, ink, 3.0, true)
				draw_circle(c, s * 0.14, ink)
			"star":
				var star := PackedVector2Array()
				for i in 10:
					var rr := s * (1.05 if i % 2 == 0 else 0.45)
					var a := -PI * 0.5 + TAU * float(i) / 10.0
					star.append(c + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(star, ink)
			"bulb":
				draw_arc(c + Vector2(0, -s * 0.2), s * 0.62, PI * 0.78, PI * 2.22, 20, ink, 3.2, true)
				draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.4), Vector2(s * 0.6, s * 0.2)), ink)
				draw_rect(Rect2(c + Vector2(-s * 0.22, s * 0.68), Vector2(s * 0.44, s * 0.14)), ink)
			"gear":
				draw_arc(c, s * 0.62, 0.0, TAU, 24, ink, 3.2, true)
				for i in 8:
					var a2 := TAU * float(i) / 8.0
					draw_line(c + Vector2(cos(a2), sin(a2)) * s * 0.7, c + Vector2(cos(a2), sin(a2)) * s * 1.0, ink, 4.0, true)
				draw_circle(c, s * 0.2, ink)
			"door":
				draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.9), Vector2(s * 1.0, s * 1.8)), ink, false, 3.0)
				draw_line(c + Vector2(s * 0.05, 0), c + Vector2(s * 0.95, 0), ink, 3.2, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.95, 0), c + Vector2(s * 0.6, -s * 0.3), c + Vector2(s * 0.6, s * 0.3)]), ink)
			"keys":
				for i in 3:
					draw_rect(Rect2(c + Vector2(-s * 0.9 + s * 0.65 * float(i), -s * 0.3), Vector2(s * 0.5, s * 0.6)), ink, false, 2.6)
			"speaker":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.9, -s * 0.3), c + Vector2(-s * 0.4, -s * 0.3), c + Vector2(s * 0.1, -s * 0.8), c + Vector2(s * 0.1, s * 0.8), c + Vector2(-s * 0.4, s * 0.3), c + Vector2(-s * 0.9, s * 0.3)]), ink)
				draw_arc(c + Vector2(s * 0.1, 0), s * 0.5, -0.9, 0.9, 10, ink, 3.0, true)
				draw_arc(c + Vector2(s * 0.1, 0), s * 0.9, -0.9, 0.9, 12, ink, 3.0, true)
			"eye":
				draw_arc(c + Vector2(0, s * 0.5), s * 1.0, PI * 1.2, PI * 1.8, 14, ink, 3.2, true)
				draw_arc(c + Vector2(0, -s * 0.5), s * 1.0, PI * 0.2, PI * 0.8, 14, ink, 3.2, true)
				draw_circle(c, s * 0.28, ink)
			"globe":
				draw_arc(c, s, 0.0, TAU, 28, ink, 3.0, true)
				draw_arc(c, s * 0.5, PI * 0.5, PI * 1.5, 14, ink, 2.6, true)
				draw_arc(c, s * 0.5, -PI * 0.5, PI * 0.5, 14, ink, 2.6, true)
				draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), ink, 2.6, true)
			"person":
				draw_arc(c + Vector2(0, -s * 0.45), s * 0.32, 0.0, TAU, 16, ink, 3.2, true)
				draw_arc(c + Vector2(0, s * 0.85), s * 0.7, PI + 0.4, TAU - 0.4, 14, ink, 3.2, true)


static func glyph(kind: String, d := 64.0, disc := Color("2f7f86")) -> Control:
	var g := _Glyph.new()
	g.kind = kind
	g.disc = disc
	g.size = Vector2(d, d)
	g.custom_minimum_size = g.size
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## page header like the reference's "Match Settings": glyph + outlined title, a thin white line with a dot at its end
static func header(text: String, glyph_kind: String, width := 900.0, size := 56) -> Control:
	var h := Control.new()
	h.custom_minimum_size = Vector2(width, 96)
	h.size = h.custom_minimum_size
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := glyph(glyph_kind, 70.0, Color(0.2, 0.55, 0.6, 0.9))
	g.position = Vector2(0, 2)
	h.add_child(g)
	var t := UIKit.label(text, size, Color.WHITE, 14, Color(0.05, 0.2, 0.34, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	t.position = Vector2(88, -2)
	t.size = Vector2(width - 90.0, 80)
	h.add_child(t)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.92)
	line.position = Vector2(0, 80)
	line.size = Vector2(width - 14.0, 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	var dot := Panel.new()
	dot.position = Vector2(width - 18.0, 77)
	dot.size = Vector2(10, 10)
	dot.add_theme_stylebox_override("panel", UIKit.style_box(Color.WHITE, 5))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	return h


## "label   <  [Normal] Strong Powerhouse  >" row on a pale bar with a teal underline (the reference's CPU Strength row);
## the chosen option is a teal capsule, the others plain text; the orange arrows step through the options.
static func option_row(title: String, options: Array, idx: int, cb: Callable, width := 920.0, opt_w := 150.0) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(width, 80)
	row.size = row.custom_minimum_size
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := Panel.new()
	bar.size = Vector2(width, 72)
	bar.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.78, 0.88, 0.9, 0.7), 20))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var line := ColorRect.new()
	line.color = Color(UIKit.TEAL.r, UIKit.TEAL.g, UIKit.TEAL.b, 0.9)
	line.position = Vector2(8, 72)
	line.size = Vector2(width - 16.0, 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var l := UIKit.label(title, 30, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.position = Vector2(34, 0)
	l.size = Vector2(300, 72)
	row.add_child(l)
	var state := {"i": idx}
	var btns: Array = []
	var apply := func():
		for k in btns.size():
			var b: Button = btns[k]
			var on: bool = k == int(state["i"])
			b.add_theme_stylebox_override("normal", UIKit.style_box(UIKit.TEAL, 28, 3, Color.WHITE, 4) if on else StyleBoxEmpty.new())
			for n in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(n, Color.WHITE if on else UIKit.PALE_TXT)
	var total := opt_w * float(options.size())
	var x0 := width - total - 90.0
	for k in options.size():
		var b := Button.new()
		b.text = String(options[k])
		b.position = Vector2(x0 + 44.0 + opt_w * float(k), 8)
		b.size = Vector2(opt_w - 4.0, 56)
		b.custom_minimum_size = b.size
		b.add_theme_font_size_override("font_size", 28)
		var empty := StyleBoxEmpty.new()
		for st in ["hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, empty)
		b.add_theme_stylebox_override("focus", UIKit.style_box(Color(1, 1, 1, 0), 28, 4, UIKit.CHEVRON))
		var ki := k
		b.pressed.connect(func():
			state["i"] = ki
			apply.call()
			Sfx.play("ui_click", -4.0)
			cb.call(ki))
		row.add_child(b)
		btns.append(b)
	var step := func(dir: int):
		var ni := clampi(int(state["i"]) + dir, 0, options.size() - 1)
		if ni != int(state["i"]):
			state["i"] = ni
			apply.call()
			Sfx.play("ui_click", -4.0)
			cb.call(ni)
	for dir in [-1, 1]:
		var ab := Button.new()
		ab.flat = true
		ab.focus_mode = Control.FOCUS_NONE
		ab.text = "◀" if dir < 0 else "▶"
		ab.size = Vector2(48, 56)
		ab.position = Vector2(x0 if dir < 0 else x0 + 44.0 + total, 8)
		ab.add_theme_font_size_override("font_size", 30)
		for n in ["font_color", "font_hover_color", "font_pressed_color"]:
			ab.add_theme_color_override(n, UIKit.CHEVRON)
		var d: int = dir
		ab.pressed.connect(func(): step.call(d))
		row.add_child(ab)
	apply.call()
	return row


## label + chunky slider on a pale bar (same look as option_row)
static func slider_row(title: String, value: float, cb: Callable, width := 904.0) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(width, 80)
	row.size = row.custom_minimum_size
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := Panel.new()
	bar.size = Vector2(width, 72)
	bar.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.78, 0.88, 0.9, 0.7), 20))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var line := ColorRect.new()
	line.color = Color(UIKit.TEAL.r, UIKit.TEAL.g, UIKit.TEAL.b, 0.9)
	line.position = Vector2(8, 72)
	line.size = Vector2(width - 16.0, 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var l := UIKit.label(title, 30, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.position = Vector2(34, 0)
	l.size = Vector2(300, 72)
	row.add_child(l)
	var sl := slider(value, cb, width - 400.0)
	sl.position = Vector2(340, 12)
	row.add_child(sl)
	return row
