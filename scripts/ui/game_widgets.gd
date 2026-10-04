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
	var gloss := true
	var bevel := 16.0

	func _draw() -> void:
		var inner := size - Vector2(8, 10)
		var poly := GW.slant_poly(inner, skew, bevel)
		if shadow:
			var sh := PackedVector2Array()
			for p in poly:
				sh.append(p + Vector2(4, 12))
			draw_colored_polygon(sh, Color(0.03, 0.12, 0.25, 0.28))
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
		draw_polyline(line, rim, 4.0, true)


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
			sh.append(p + Vector2(7, 10))
		draw_colored_polygon(sh, Color(0.03, 0.12, 0.25, 0.3))
		var body := PackedVector2Array()
		for p in poly:
			body.append(p + Vector2(5, 3))
		draw_colored_polygon(body, col)
		var top := PackedVector2Array()
		for p in GW.slant_poly(Vector2(size.x - 34.0, (h - 8.0) * 0.45), 0.6, 6.0):
			top.append(p + Vector2(17, 8))
		draw_colored_polygon(top, Color(1, 1, 1, 0.2))
		var line := PackedVector2Array(body)
		line.append(body[0])
		draw_polyline(line, Color.WHITE, 4.0, true)


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
