class_name Callout
extends Control
## HUD "flying text" in the sports-broadcast style: slanted display face, a two-colour glossy fill with a one-off sheen sweep, a thick
## dark outline and a soft drop shadow, optional tiny sparkle burst. Built from three plain Labels (shadow / outline / fill) so the
## gradient never leaks onto the outline. The node's origin is the CENTRE of the text, so scaling pops from the middle.
##
## The HUD keeps callouts in a calm lane above the net (see HUD.say) instead of floating them over the ball and the players.

static var _shader: Shader
static var _star: Texture2D

var fill_mat: ShaderMaterial
var size_px := Vector2.ZERO


static func make(text: String, font_size: int, top: Color, bottom: Color, outline: Color, thick := -1) -> Callout:
	if _shader == null:
		_shader = load("res://shaders/ui_text_fancy.gdshader")
	var c := Callout.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ow := thick if thick > 0 else maxi(int(float(font_size) * 0.2), 6)
	var layers := []
	for i in 3:
		var l := Label.new()
		l.text = text
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", Fonts.display_italic())
		l.add_theme_font_size_override("font_size", font_size)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		layers.append(l)
	var shadow: Label = layers[0]
	var rim: Label = layers[1]
	var fill: Label = layers[2]
	var sc := Color(outline.r * 0.35, outline.g * 0.35, outline.b * 0.4, 0.5)
	shadow.add_theme_color_override("font_color", sc)
	shadow.add_theme_constant_override("outline_size", ow + 2)
	shadow.add_theme_color_override("font_outline_color", sc)
	rim.add_theme_color_override("font_color", outline)
	rim.add_theme_constant_override("outline_size", ow)
	rim.add_theme_color_override("font_outline_color", outline)
	fill.add_theme_color_override("font_color", Color.WHITE)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("top_col", top)
	m.set_shader_parameter("bot_col", bottom)
	fill.material = m
	c.fill_mat = m
	var sz: Vector2 = fill.get_minimum_size() + Vector2(float(ow) * 2.0, float(ow))
	sz.x = maxf(sz.x, 40.0)
	c.size_px = sz
	m.set_shader_parameter("box", Vector2(sz.x, sz.y))
	for l in layers:
		(l as Label).size = sz
		(l as Label).position = -sz * 0.5
		c.add_child(l)
	shadow.position += Vector2(0, float(ow) * 0.55 + 3.0)
	c.pivot_offset = Vector2.ZERO
	return c


## pop in (overshoot + sheen), hold, rise and fade; frees itself. Real-time tweens (the slow-motion replays must not slow the HUD)
func play(hold := 1.0, from_scale := 1.55, rise := 26.0, sparkle := false) -> void:
	scale = Vector2(from_scale, from_scale)
	modulate.a = 0.0
	var y0 := position.y
	position.y = y0 + 18.0
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.1)
	tw.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", y0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): fill_mat.set_shader_parameter("sheen", v), -0.25, 1.25, 0.55).set_delay(0.08)
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(self, "modulate:a", 0.0, 0.28)
	tw.parallel().tween_property(self, "position:y", y0 - rise, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
	if sparkle:
		_sparkles()


## persistent elastic pop (combo counters): scales from `from_scale` with an elastic overshoot, one sheen sweep, optional sparkles
func pop(from_scale := 1.6, sparkle := false) -> void:
	scale = Vector2(from_scale, from_scale)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): fill_mat.set_shader_parameter("sheen", v), -0.25, 1.25, 0.5)
	if sparkle:
		_sparkles()


## replaced by a newer callout: quick fade
func dismiss() -> void:
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.1)
	tw.tween_callback(queue_free)


func _sparkles() -> void:
	if _star == null and ResourceLoader.exists("res://assets/env/star.png"):
		_star = load("res://assets/env/star.png")
	var p := CPUParticles2D.new()
	p.texture = _star
	p.amount = 9
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 190.0
	p.damping_min = 90.0
	p.damping_max = 140.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(size_px.x * 0.45, size_px.y * 0.3)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.96, 0.7, 1.0))
	ramp.set_color(1, Color(1.0, 0.9, 0.5, 0.0))
	p.color_ramp = ramp
	add_child(p)
