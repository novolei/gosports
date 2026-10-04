class_name AngerMark
extends Node3D
## The manga "anger vein" (the red cross of four curved wedges) that pops up over a cross teammate's head, with a dark outline copy
## behind it so it reads on any background. A billboard unlit mesh (about 40 triangles) + one tween: pops in with an elastic overshoot,
## pulses twice like a throbbing vein, then pops away.

const GAP := 0.5


static func spawn_over(a: Node3D, head_y: float, hold := 1.2) -> AngerMark:
	var m := AngerMark.new()
	a.add_child(m)
	m.position = Vector3(0, head_y + GAP, 0)
	var st := CourtDeco.Mesher.new()
	for k in 4:
		var ang := PI * 0.25 + PI * 0.5 * float(k)
		for pass_i in 2:                                           # pass 0: dark outline (a bit bigger, behind); pass 1: the red wedge
			var grow := 1.0 if pass_i == 1 else 1.35
			var col := Color("ff3b30") if pass_i == 1 else Color(0.2, 0.03, 0.03)
			var z := 0.0 if pass_i == 1 else -0.004
			var d := Vector2(cos(ang), sin(ang))
			var n := Vector2(-d.y, d.x)
			var inner := d * 0.03
			var tip := d * 0.2 * grow
			var s1 := d * 0.1 + n * 0.062 * grow
			var s2 := d * 0.1 - n * 0.02 * grow
			st.tri2(Vector3(inner.x, inner.y + 0.0, z), Vector3(s1.x, s1.y, z), Vector3(tip.x, tip.y, z), col)
			st.tri2(Vector3(inner.x, inner.y, z), Vector3(tip.x, tip.y, z), Vector3(s2.x, s2.y, z), col)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 11
	var mi := st.commit(mat)
	mi.position = Vector3(0, 0.2, 0)
	m.add_child(mi)
	m.scale = Vector3.ZERO
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	for i in 2:                                                     # the throbbing
		tw.tween_property(m, "scale", Vector3(1.28, 1.28, 1.28), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(hold - 0.9, 0.1))
	tw.tween_property(m, "scale", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(m.queue_free)
	return m
