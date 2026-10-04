class_name HawkEye
extends Node3D
## "鹰眼" line-call review. When a ball comes down within ~16 cm of a line (too close to read by eye) the game cuts to a close-up of
## the spot: the ball drops in slow motion, squashes on the floor and leaves an ink print; the print and the line are highlighted
## and the umpire's verdict (IN / OUT, by how many cm) stamps on screen. It is the "referee's reference" the user asked for:
## the same numbers drive the actual point (MatchDirector._on_floor_contact), so the review always agrees with the score.
##
## The camera is the replay camera (CameraRig.start_replay / set_replay_view), the transition is the replay wipe, the HUD is hidden
## like in a replay. Skippable with any key (like the instant replay).

const DROP_T := 0.55                      # seconds (game time) of the final fall that are shown
const SLOW := 0.42                        # the fall plays at this fraction of real speed
const PRINT_R := 0.2                      # radius of the ink print (the ball's squashed footprint)

var ms: MatchScene
var playing := false
var _skip := false
var _started_ms := 0
var _ghost: MeshInstance3D
var _print: MeshInstance3D
var _line_flash: MeshInstance3D
var _ui: Control
var _ring: MeshInstance3D


## the review is wanted for this point? (close call, a real match, replays on)
static func wanted(info: Dictionary) -> bool:
	if not info.has("floor"):
		return false
	if Game.main != null and Game.main.dev.has("hawk"):
		return true
	var f: Dictionary = info["floor"]
	return absf(float(f["dist"])) < 0.16


## `info["floor"]` = {"pos": Vector3, "vel": Vector3, "inside": bool, "dist": float}  (dist: metres inside the line, negative = outside)
func play(p_ms: MatchScene, info: Dictionary) -> void:
	ms = p_ms
	if playing:
		return
	playing = true
	_skip = false
	_started_ms = Time.get_ticks_msec()
	var f: Dictionary = info["floor"]
	var pos: Vector3 = f["pos"]
	var vel: Vector3 = f["vel"]
	var inside: bool = f["inside"]
	var dist: float = f["dist"]
	var hud := ms.hud
	var ov: ReplayOverlay = hud.replay_overlay
	await ms.get_tree().create_timer(1.55, true, false, true).timeout
	if not is_instance_valid(ms) or not ms.is_inside_tree() or ms._over:
		playing = false
		return
	await ov.cover()
	# --- enter: hide the match, build the close-up set
	ms.director.clock_hold += 1
	for a in ms.athletes:
		a.visible = false
	ms.ball.visible = false
	hud.replay_mode = true
	ms.cam_rig.start_replay()
	_build_set(pos, vel, inside)
	ov.begin_titled(tr("鹰眼回放"), "eye")
	ov.reveal()
	# --- the sequence (all real time; the fall is slowed down by hand)
	var line_pt := _line_point(pos)
	var cam_pos := _cam_pos(pos, line_pt)
	var focus := Vector3(line_pt.x * 0.4 + pos.x * 0.6, 0.08, line_pt.z * 0.4 + pos.z * 0.6)
	var t := 0.0
	var phase_hold := 0.0
	var verdict_shown := false
	var landed := false
	while playing and not _skip and t < 5.2:
		var dt := ms.get_process_delta_time() / maxf(Engine.time_scale, 0.05)
		t += dt
		var fall_u := clampf(t / (DROP_T / SLOW), 0.0, 1.0)         # 0..1 over the slowed fall
		var zoom := smoothstep(0.0, 2.0, t)
		ms.cam_rig.set_replay_view(cam_pos.lerp(focus + (cam_pos - focus).normalized() * 1.55, zoom * 0.45), focus, lerpf(34.0, 21.0, zoom))
		_drop(pos, vel, fall_u)
		if fall_u >= 1.0 and not landed:
			landed = true
			_land(inside)
			Sfx.play("bounce", -4.0)
		if landed:
			phase_hold += dt
			_pulse(phase_hold, inside)
			if phase_hold > 0.65 and not verdict_shown:
				verdict_shown = true
				_verdict(inside, dist)
				Sfx.play("ui_confirm" if inside else "ui_back", -2.0)
		ov.set_progress(clampf(t / 4.2, 0.0, 1.0))
		if verdict_shown and phase_hold > 2.4:
			break
		await ms.get_tree().process_frame
	# --- leave
	await ov.cover()
	ov.end()
	_clear_set()
	for a in ms.athletes:
		a.visible = true
	ms.ball.visible = true
	hud.replay_mode = false
	ms.cam_rig.end_replay()
	ov.reveal()
	ms.director.clock_hold = maxi(ms.director.clock_hold - 1, 0)
	playing = false


func skip() -> void:
	if playing and Time.get_ticks_msec() - _started_ms > 500:
		_skip = true


func _input(event: InputEvent) -> void:
	if not playing:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed) or (event is InputEventJoypadButton and event.pressed):
		skip()


# ------------------------------------------------------------------ geometry
## the nearest point on the court boundary (on the floor)
func _line_point(p: Vector3) -> Vector3:
	var ex := Court.HALF_W - absf(p.x)
	var ez := Court.HALF_D - absf(p.z)
	if ex < ez:
		return Vector3(signf(p.x) * Court.HALF_W, 0.0, p.z)
	return Vector3(p.x, 0.0, signf(p.z) * Court.HALF_D)


func _cam_pos(p: Vector3, lp: Vector3) -> Vector3:
	# from the playing-court side, above and a little along the line, looking down at the spot
	var inward := Vector3(p.x - lp.x, 0.0, p.z - lp.z)
	inward.y = 0.0
	var n := inward.normalized() if inward.length() > 0.001 else Vector3(-signf(lp.x), 0, -signf(lp.z))
	var along := Vector3(-n.z, 0, n.x)
	return lp + n * 1.9 + along * 1.0 + Vector3(0, 1.75, 0)


# ------------------------------------------------------------------ the set
func _build_set(pos: Vector3, vel: Vector3, inside: bool) -> void:
	_ghost = MeshInstance3D.new()
	_ghost.mesh = ms.ball.mesh.mesh
	_ghost.material_override = ms.ball.mesh.material_override
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ms.add_child(_ghost)
	var col := Color(0.15, 0.85, 0.65) if inside else Color(1.0, 0.32, 0.4)
	# ink print: an ellipse lying on the floor (a unit disc scaled, tinted)
	_print = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_print.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ring.gdshader")
	m.set_shader_parameter("ring_color", Color(col.r, col.g, col.b, 1.0))
	m.set_shader_parameter("grad", load("res://assets/env/ring_gradient.png"))
	m.set_shader_parameter("inner", 0.0)
	m.set_shader_parameter("rainbow", 0.0)
	m.set_shader_parameter("fill_alpha", 0.72)
	m.set_shader_parameter("width", 0.12)
	_print.material_override = m
	_print.rotation_degrees.x = -90
	_print.position = Vector3(pos.x, 0.03, pos.z)
	_print.scale = Vector3(PRINT_R * 2.0 * 1.15, PRINT_R * 2.0, 1)
	_print.visible = false
	_print.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ms.add_child(_print)
	# the line, highlighted for ~2.4 m around the spot
	var lp := _line_point(pos)
	var along_x := absf(lp.z) > absf(lp.x) * 0.0 + 0.0 and absf(absf(lp.z) - Court.HALF_D) < 0.001
	_line_flash = MeshInstance3D.new()
	var lq := QuadMesh.new()
	lq.size = Vector2(2.6, 0.13) if along_x else Vector2(0.13, 2.6)
	_line_flash.mesh = lq
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.albedo_color = Color(1.0, 0.95, 0.4, 0.0)
	_line_flash.material_override = lm
	_line_flash.rotation_degrees.x = -90
	_line_flash.position = Vector3(lp.x, 0.025, lp.z)
	_line_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ms.add_child(_line_flash)
	# ring ripple under the print
	_ring = MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(1, 1)
	_ring.mesh = rq
	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/ring.gdshader")
	rm.set_shader_parameter("ring_color", Color(col.r, col.g, col.b, 1.0))
	rm.set_shader_parameter("grad", load("res://assets/env/ring_gradient.png"))
	rm.set_shader_parameter("inner", 0.0)
	rm.set_shader_parameter("rainbow", 0.0)
	rm.set_shader_parameter("fill_alpha", 0.0)
	rm.set_shader_parameter("intensity", 0.0)
	_ring.material_override = rm
	_ring.rotation_degrees.x = -90
	_ring.position = Vector3(pos.x, 0.032, pos.z)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ms.add_child(_ring)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ms.hud.replay_overlay.add_child(_ui)
	_ui.move_to_front()
	_drop(pos, vel, 0.0)


func _clear_set() -> void:
	for n in [_ghost, _print, _line_flash, _ring, _ui]:
		if n != null and is_instance_valid(n):
			n.queue_free()


## the ball's last DROP_T seconds before touching down, reconstructed from the contact position and velocity
func _drop(pos: Vector3, vel: Vector3, u: float) -> void:
	var tt := -DROP_T * (1.0 - u)                       # game time relative to the touch-down
	var vy := -absf(vel.y)
	var p := Vector3(pos.x + vel.x * tt, 0.0, pos.z + vel.z * tt)
	p.y = Court.BALL_R + vy * tt + 0.5 * Court.GRAVITY * tt * tt          # y(t) with gravity pulling down
	_ghost.position = p
	# squash when it arrives
	var sq := 1.0
	var s := ms.ball._base_s
	_ghost.scale = Vector3.ONE * s
	if u >= 1.0:
		_ghost.scale = Vector3(s * 1.2, s * 0.62, s * 1.2)
		_ghost.position.y = Court.BALL_R * 0.62
	_ghost.rotation.y += 0.05


func _land(inside: bool) -> void:
	_print.visible = true
	ms.vfx.hit_burst(_print.position + Vector3(0, 0.05, 0), "good", 0.3)
	var tw := _print.create_tween()
	_print.scale *= 0.2
	tw.tween_property(_print, "scale", Vector3(PRINT_R * 2.0 * 1.15, PRINT_R * 2.0, 1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# the ball pops away and the print remains
	var gt := _ghost.create_tween()
	gt.tween_interval(0.25)
	gt.tween_property(_ghost, "position:y", 1.3, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gt.parallel().tween_property(_ghost, "scale", Vector3.ZERO, 0.35)
	gt.tween_callback(func(): _ghost.visible = false)


func _pulse(t: float, inside: bool) -> void:
	var lm: StandardMaterial3D = _line_flash.material_override
	var a := clampf(t * 3.0, 0.0, 1.0) * (0.55 + 0.45 * sin(t * 12.0))
	lm.albedo_color = Color(1.0, 0.95, 0.4, a)
	var rm: ShaderMaterial = _ring.material_override
	var u := fposmod(t * 1.4, 1.0)
	_ring.scale = Vector3.ONE * lerpf(0.4, 1.8, u)
	rm.set_shader_parameter("intensity", (1.0 - u) * 0.9)


func _verdict(inside: bool, dist: float) -> void:
	var col := Color("14b08a") if inside else Color("f2475f")
	var vp := ms.get_viewport().get_visible_rect().size
	var word := tr("界内") if inside else tr("出界")
	var top := Color("e8fff6") if inside else Color("ffeaec")
	var bot := Color("6fe8c0") if inside else Color("ff8f9a")
	var c := Callout.make(word.to_upper() if Loc.is_en() else word, 150, top, bot, col.darkened(0.5))
	c.position = Vector2(vp.x * 0.5, vp.y * 0.2)
	_ui.add_child(c)
	c.scale = Vector2(1.7, 1.7)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_ignore_time_scale(true).set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.1)
	tw.tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): c.fill_mat.set_shader_parameter("sheen", v), -0.25, 1.25, 0.6)
	var cm := int(round(absf(dist) * 100.0))
	var note := ""
	if inside and dist < 0.1:
		note = tr("压线球！") + ("  %d cm" % cm)
	elif inside:
		note = tr("仅余 %d cm") % cm
	else:
		note = tr("差 %d cm") % cm
	var sub := Callout.make(note, 56, Color.WHITE, Color("dff3ff"), col.darkened(0.55))
	sub.position = Vector2(vp.x * 0.5, vp.y * 0.2 + 138.0)
	_ui.add_child(sub)
	sub.modulate.a = 0.0
	var st := sub.create_tween().set_ignore_time_scale(true)
	st.tween_interval(0.25)
	st.tween_property(sub, "modulate:a", 1.0, 0.15)
