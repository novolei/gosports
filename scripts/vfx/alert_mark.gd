class_name AlertMark
extends Node3D
## The classic stealth-game alert: a small yellow "!" with a clean dark outline that pops up ABOVE somebody's head (here: the server
## who just got hit by the umpire's projectile). It floats clear of the head (the stem of the mark never touches the hair), springs
## in with an elastic overshoot, then keeps a gentle squash-and-stretch bounce with a tiny wiggle until it shrinks away.
## One Label3D + one tween: practically free.

const GAP := 0.56                                  # (old: straight above the head) kept for reference / other users
const SIDE := 0.62                                 # the mark floats BESIDE the head (to the screen-right, flipped near the right edge) ...
const SIDE_LIFT := -0.1                            # ... with its foot a little below the top of the head, so it never covers the serve bubble /
                                                   # the player tag that sit straight above the head
const H := 0.46                                    # height of the glyph in metres


## a mark over somebody on the FAR side of the court is drawn larger (up to 2.4x) so it is as readable as one on the near side
static func dist_scale(a: Node3D) -> float:
	var cam := a.get_viewport().get_camera_3d() if a.is_inside_tree() else null
	if cam == null:
		return 1.0
	return clampf(cam.global_position.distance_to(a.global_position) / 9.0, 1.0, 2.4)


## the offset (in a's local space) that puts the mark to the viewer's right of the head - or to the left when the head is already
## in the right quarter of the screen
static func _side_offset(a: Node3D, k: float) -> Vector3:
	var cam := a.get_viewport().get_camera_3d() if a.is_inside_tree() else null
	if cam == null:
		return Vector3(SIDE * k, 0.0, 0.0)
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var sgn := 1.0
	var vp := a.get_viewport().get_visible_rect().size
	if not cam.is_position_behind(a.global_position + Vector3(0, 1.6, 0)) and cam.unproject_position(a.global_position + Vector3(0, 1.6, 0)).x > vp.x * 0.78:
		sgn = -1.0
	return a.global_transform.basis.inverse() * (right * SIDE * k * sgn)


static func spawn_over(a: Node3D, head_y: float, hold := 1.4) -> AlertMark:
	var m := AlertMark.new()
	a.add_child(m)
	var k := dist_scale(a)
	var side := _side_offset(a, k)
	m.position = Vector3(side.x, head_y + SIDE_LIFT * k, side.z)     # the origin is the BOTTOM of the mark: it squashes and stretches from there
	var l := Label3D.new()
	l.text = "!"
	l.font = Fonts.display_italic()
	l.font_size = 64
	l.pixel_size = 0.0088
	l.outline_size = 14
	l.modulate = Color("ffd91e")
	l.outline_modulate = Color(0.06, 0.05, 0.1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.render_priority = 12
	l.double_sided = true
	l.position = Vector3(0, H * 0.62, 0)
	m.add_child(l)
	m.scale = Vector3.ZERO
	var tw := m.create_tween()
	# spring in: from nothing, overshoot, settle (elastic)
	tw.tween_property(m, "scale", Vector3.ONE * k, 0.62).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# idle: bounce with squash and stretch, little wiggle
	var rounds := maxi(int(hold / 0.5), 1)
	for i in rounds:
		tw.tween_property(m, "scale", Vector3(0.88, 1.18, 0.88) * k, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(m, "position:y", head_y + (SIDE_LIFT + 0.1) * k, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "rotation:z", 0.12 if i % 2 == 0 else -0.12, 0.14)
		tw.tween_property(m, "scale", Vector3(1.1, 0.9, 1.1) * k, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(m, "position:y", head_y + SIDE_LIFT * k, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(m, "scale", Vector3.ONE * k, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "rotation:z", 0.0, 0.2)
	# away: a quick wind-up then pop out
	tw.tween_property(m, "scale", Vector3(1.15, 1.15, 1.15) * k, 0.08)
	tw.tween_property(m, "scale", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(m.queue_free)
	return m
