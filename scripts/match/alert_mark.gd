class_name AlertMark
extends Node3D
## The classic stealth-game alert: a yellow "!" with a heavy black outline that pops up over somebody's head (here: the server who
## just got hit by the umpire's projectile). Billboard Label3D, springs in, wobbles, floats up and fades.


static func spawn_over(a: Node3D, head_y: float, hold := 1.3) -> AlertMark:
	var m := AlertMark.new()
	a.add_child(m)
	m.position = Vector3(0, head_y + 0.55, 0)
	var l := Label3D.new()
	l.text = "!"
	l.font = Fonts.display_italic()
	l.font_size = 110
	l.pixel_size = 0.0075
	l.outline_size = 34
	l.modulate = Color("ffd91e")
	l.outline_modulate = Color(0.04, 0.04, 0.06)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.render_priority = 12
	l.double_sided = true
	l.scale = Vector3.ZERO
	m.add_child(l)
	var tw := m.create_tween()
	tw.tween_property(l, "scale", Vector3(1.5, 1.5, 1.5), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in 3:                                       # a nervous little shake
		tw.tween_property(l, "rotation:z", 0.16, 0.05)
		tw.tween_property(l, "rotation:z", -0.16, 0.05)
	tw.tween_property(l, "rotation:z", 0.0, 0.04)
	tw.tween_interval(hold)
	tw.tween_property(m, "position:y", m.position.y + 0.25, 0.25)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.25)
	tw.tween_callback(m.queue_free)
	return m
