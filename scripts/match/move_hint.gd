class_name MoveHint
extends Node3D
## Two cyan chevrons on the floor to the left / right of a human player while they still have to run for the ball
## (like the "move" arrows of the reference game). The one on the side of the landing spot is brighter and pulses outward.

const TEX := "res://assets/ui/chevron.png"

var ath: Athlete
var _l: Sprite3D
var _r: Sprite3D
var _t := 0.0
var _vis := 0.0
var _logged := false


func setup(a: Athlete) -> void:
	ath = a
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var tex: Texture2D = load(TEX)
	for side in 2:
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.axis = Vector3.AXIS_Y            # lies flat on the floor
		sp.pixel_size = 0.0058
		sp.shaded = false
		sp.double_sided = true
		sp.transparent = true
		sp.no_depth_test = false
		sp.render_priority = 1
		sp.flip_h = side == 0               # the texture points right
		sp.modulate.a = 0.0
		add_child(sp)
		if side == 0:
			_l = sp
		else:
			_r = sp


func _process(dt: float) -> void:
	var _p := Prof.t0()
	_process_impl(dt)
	Prof.add("movehint", _p)


func _process_impl(dt: float) -> void:
	if ath == null or not is_instance_valid(ath):
		return
	_t += dt
	var d: MatchDirector = ath.director
	var want := false
	var toward := 0.0
	if d != null and d.phase == MatchDirector.P.RALLY and ath.state == Athlete.S.READY:
		var plan: Dictionary = d.plans[ath.team]
		if plan.get("who") == ath and plan.get("mode") == "play":
			var spot: Vector3 = plan["pos"]
			var dx := spot.x - ath.global_position.x
			var dist := Vector2(dx, spot.z - ath.global_position.z).length()
			want = dist > 0.9
			toward = clampf(dx / 1.2, -1.0, 1.0)
	_vis = move_toward(_vis, 1.0 if want else 0.0, dt * 6.0)
	visible = _vis > 0.01
	if _vis > 0.5 and not _logged and Game.main != null and Game.main.dev.has("log"):
		_logged = true
		print("[movehint] shown for P%d" % ath.player_index)
		if Game.main.dev.has("movehintshot"):
			get_tree().create_timer(0.25, true, false, true).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(str(Game.main.dev["movehintshot"])))
	if not visible:
		return
	var p := ath.global_position
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	var base := 1.3
	_l.global_position = Vector3(p.x - base - 0.1 * pulse * (0.5 + 0.5 * maxf(-toward, 0.0)), 0.04, p.z)
	_r.global_position = Vector3(p.x + base + 0.1 * pulse * (0.5 + 0.5 * maxf(toward, 0.0)), 0.04, p.z)
	var wl := 0.72 + 0.28 * maxf(-toward, 0.0)
	var wr := 0.72 + 0.28 * maxf(toward, 0.0)
	_l.modulate.a = _vis * wl
	_r.modulate.a = _vis * wr
