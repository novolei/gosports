extends SceneTree
## Dev test for the match camera views (run: godot --headless --path . -s tools/test_camera_views.gd). Needs no rendering:
##  - the C / V keys are bound and the two settings exist,
##  - for every view and distance the screen directions of CameraRig.input_basis() are the real screen directions of the camera pose,
##  - HumanBrain turns a screen-relative stick / key vector into the right world direction (including the aim keys of both teams),
##  - the whole court (corners + net posts) stays inside the picture at 16:9 and 20:9 in the side view at the far / normal distance, also with the
##    camera slid as far along the court as CameraRig.SIDE_PAN allows (the servers behind the end lines are reported, not asserted).

var fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)


var _ran := false


func _process(_dt: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


## the camera transform of a pose: looks from pos at focus, vertical field of view (Godot's default keep-height)
func _xf(pos: Vector3, focus: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(focus - pos, Vector3.UP), pos)


## NDC of a world point (x, y in -1..1 inside the picture); Vector3.INF when the point is behind the camera
func _ndc(xf: Transform3D, fov_deg: float, aspect: float, w: Vector3) -> Vector3:
	var c := xf.affine_inverse() * w
	if c.z >= -0.01:
		return Vector3.INF
	var t := tan(deg_to_rad(fov_deg) * 0.5)
	return Vector3(c.x / (-c.z) / (t * aspect), c.y / (-c.z) / t, -c.z)


func _extent(xf: Transform3D, fov: float, asp: float, pts: Array) -> float:
	var worst := 0.0
	for c in pts:
		var n := _ndc(xf, fov, asp, c)
		worst = INF if n == Vector3.INF else maxf(worst, maxf(absf(n.x), absf(n.y)))
	return worst


func _run() -> void:
	var g = root.get_node("Game")
	for pair in [["camera_toggle", KEY_C], ["camera_zoom", KEY_V]]:
		var act: String = pair[0]
		check(InputMap.has_action(act), "%s is registered" % act)
		var has_key := false
		if InputMap.has_action(act):
			for e in InputMap.action_get_events(act):
				if e is InputEventKey and (e as InputEventKey).physical_keycode == pair[1]:
					has_key = true
		check(has_key, "%s is bound to its key" % act)
	check(int(g.settings.get("cam_view", -1)) == 0 and int(g.settings.get("cam_zoom", -1)) == 1, "cam_view / cam_zoom settings exist with their defaults")

	# (loaded at run time: the scripts name the Game autoload, which does not exist yet while this file compiles)
	var CR: GDScript = load("res://scripts/match/camera_rig.gd")
	var CT: GDScript = load("res://scripts/match/court.gd")
	var HB: GDScript = load("res://scripts/match/human_brain.gd")
	var rig = CR.new()
	var corners: Array = []
	var servers: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			corners.append(Vector3(sx * CT.HALF_W, 0.0, sz * CT.HALF_D))
			servers.append(Vector3(sx * CT.HALF_W, 0.0, sz * (CT.HALF_D + 1.5)))
		corners.append(Vector3(sx * CT.NET_X, 2.4, 0.0))
	check(CR.VIEW_NAMES.size() == 2 and CR.ZOOM_NAMES.size() == 3, "2 views and 3 distances are named")
	for v in CR.VIEW_NAMES.size():
		for zoom in 3:
			rig.view = v
			rig.style = zoom
			var pose: Dictionary = rig.game_pose()
			var xf := _xf(pose["pos"], pose["focus"])
			# the controls follow the picture: input right / down = the camera's right / towards-the-camera on the ground
			var right := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
			var fwd := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()           # basis.z points BACK towards the camera
			var b: Array = CR.input_basis(v)
			check((b[0] as Vector2).dot(right) > 0.99, "view %d zoom %d: input right = screen right (%s vs %s)" % [v, zoom, str(b[0]), str(right)])
			check((b[1] as Vector2).dot(fwd) > 0.99, "view %d zoom %d: input down = towards the camera (%s vs %s)" % [v, zoom, str(b[1]), str(fwd)])
			for asp in [16.0 / 9.0, 20.0 / 9.0]:
				var worst := _extent(xf, float(pose["fov"]), asp, corners)
				var worst_pan := worst
				if v == 1:
					var pan: float = float(CR.SIDE_PAN[zoom])
					for sgn in [-1.0, 1.0]:                     # the camera slid to either end of the court (position by pan, focus by 1.4 pan)
						var pos: Vector3 = pose["pos"] + Vector3(0, 0, sgn * pan)
						var foc: Vector3 = pose["focus"] + Vector3(0, 0, sgn * pan * 1.4)
						worst_pan = maxf(worst_pan, _extent(_xf(pos, foc), float(pose["fov"]), asp, corners))
				var srv := _extent(xf, float(pose["fov"]), asp, servers)
				print("view %d zoom %d aspect %.2f: court extent %.2f (slid %.2f, servers %.2f) of the half picture %s" % [v, zoom, asp, worst, worst_pan, srv, "whole court in" if worst_pan <= 1.0 else "(cropped at rest: the behind view is framed by the net, the distance close is meant to crop)"])
				if v == 1 and zoom < 2:
					check(worst_pan <= 1.0, "side view zoom %d at aspect %.2f keeps the whole court in the picture, also slid (extent %.2f)" % [zoom, asp, worst_pan])
					if zoom == 1:
						check(srv <= 1.0, "side view normal distance at aspect %.2f keeps the servers behind the end lines in the picture (extent %.2f)" % [asp, srv])
	rig.free()

	# HumanBrain: a screen vector -> the world direction of the active view
	var hb = HB.new()
	hb.rig = CR.new()
	hb.rig.view = 0
	check(hb._to_world(Vector2(1, 0)) == Vector2(1, 0) and hb._to_world(Vector2(0, 1)) == Vector2(0, 1), "behind view: screen = world")
	hb.rig.view = 1
	check(hb._to_world(Vector2(1, 0)).is_equal_approx(Vector2(0, -1)), "side view: stick right = world -z (the right of the picture, towards the far end for team 0)")
	check(hb._to_world(Vector2(0, 1)).is_equal_approx(Vector2(1, 0)), "side view: stick down = world +x (towards the camera)")
	check(hb._to_world(Vector2(1, -1)).is_equal_approx(Vector2(-1, -1)), "side view: right + up = world (-1, -1)")
	hb.rig.free()
	hb.rig = null
	check(hb._to_world(Vector2(0.3, -0.7)) == Vector2(0.3, -0.7), "no camera: unchanged")
	print("test_camera_views: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
