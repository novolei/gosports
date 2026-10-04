extends SceneTree
## Dev tool: locomotion blend-space check.
##   godot --path . -s tools/preview_loco.gd -- sheet out.png [roster_index]   contact sheet: 8 directions x 3 speeds
##   godot --path . -s tools/preview_loco.gd -- slide [roster_index]            foot sliding per direction / speed
##   godot --path . -s tools/preview_loco.gd -- sweep out.png [roster_index]    one turn of the stick, 12 steps at 4.5 m/s

const DIRS := [Vector2(0, 1), Vector2(0.7071, 0.7071), Vector2(1, 0), Vector2(0.7071, -0.7071),
		Vector2(0, -1), Vector2(-0.7071, -0.7071), Vector2(-1, 0), Vector2(-0.7071, 0.7071)]
const DIR_NAMES := ["F", "FR", "R", "BR", "B", "BL", "L", "FL"]
const SPEEDS := [1.8, 3.5, 5.05]

var mode := "sheet"
var out_path := ""
var idx := 0
var frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	mode = a[0]
	if mode == "slide":
		idx = int(a[1]) if a.size() > 1 else 0
	else:
		out_path = a[1]
		idx = int(a[2]) if a.size() > 2 else 0
	root.size = Vector2i(1800, 1000)
	_env()
	if mode == "slide":
		_run_slide.call_deferred()
	elif mode == "sweep":
		_sweep.call_deferred()
	else:
		_sheet.call_deferred()


func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.7, 0.85, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.84, 0.95)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	root.add_child(sun)


func _rig(v: Vector2, phase: float) -> CharacterRig:
	var rig := CharacterRig.new()
	root.add_child(rig)
	rig.build(Roster.all()[idx], true)
	rig.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for i in 6:
		rig.set_locomotion(v, 1.0)
	rig.tree.advance(0.0)
	rig.tree.advance(phase)
	return rig


func _label(text: String, pos: Vector3) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.pixel_size = 0.004
	lb.font_size = 40
	lb.position = pos
	lb.rotation_degrees.x = -40
	root.add_child(lb)


func _sheet() -> void:
	var n := DIRS.size()
	for r in SPEEDS.size():
		for c in n:
			var v: Vector2 = DIRS[c] * SPEEDS[r]
			var rig := _rig(v, 0.2)
			rig.position = Vector3((c - (n - 1) * 0.5) * 1.45, 0, -r * 2.1)
			rig.rotation_degrees.y = 180.0
			_label("%s %.1f" % [DIR_NAMES[c], SPEEDS[r]], rig.position + Vector3(0, 0, 0.9))
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 6.8, 6.4), Vector3(0, 0.3, -1.6))
	cam.fov = 46
	cam.current = true


func _sweep() -> void:
	var steps := 12
	for i in steps:
		var ang := TAU * float(i) / float(steps)
		var v := Vector2(sin(ang), cos(ang)) * 4.5
		var rig := _rig(v, 0.2)
		rig.position = Vector3((i - (steps - 1) * 0.5) * 1.3, 0, 0)
		rig.rotation_degrees.y = 180.0
		_label("%d" % int(rad_to_deg(ang)), rig.position + Vector3(0, 0, 0.7))
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 3.2, 8.2), Vector3(0, 0.8, 0))
	cam.current = true


func _process(_dt: float) -> bool:
	if mode == "slide":
		return false
	frames += 1
	if frames == 14:
		root.get_viewport().get_texture().get_image().save_png(out_path)
		print("saved ", out_path)
		quit()
	return false


func _run_slide() -> void:
	_slide()
	quit()


## stance-foot sliding: the planted foot should move backwards at exactly the body speed
func _slide() -> void:
	var rig := CharacterRig.new()
	root.add_child(rig)
	rig.build(Roster.all()[idx], true)
	rig.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var fl := rig.info.b("foot_l")
	var fr := rig.info.b("foot_r")
	var dt := 1.0 / 60.0
	print("%-4s %5s | %8s %8s | stance-foot slide m/s (mean / max)" % ["dir", "speed", "foot spd", "ideal"])
	for c in DIRS.size():
		for s in SPEEDS:
			var v: Vector2 = DIRS[c] * s
			for i in 8:
				rig.set_locomotion(v, 1.0)
			rig.tree.advance(0.0)
			for i in 30:
				rig.tree.advance(dt)    # skip the start-up
			var prev := _feet(rig, fl, fr)
			var errs := []
			var spd_sum := 0.0
			for i in 48:
				rig.tree.advance(dt)
				var cur := _feet(rig, fl, fr)
				var k := 0 if (cur[0].y + prev[0].y) < (cur[1].y + prev[1].y) else 1
				var fv := Vector3(cur[k].x - prev[k].x, 0.0, cur[k].z - prev[k].z) / dt
				var ideal := Vector3(-v.x, 0.0, v.y)    # body moves (x, -y) in world; feet move the opposite way
				errs.append((fv - ideal).length())
				spd_sum += fv.length()
				prev = cur
			var mean := 0.0
			var mx := 0.0
			for e in errs:
				mean += e
				mx = maxf(mx, e)
			mean /= errs.size()
			print("%-4s %5.2f | %8.2f %8.2f | %5.2f / %5.2f" % [DIR_NAMES[c], s, spd_sum / errs.size(), s, mean, mx])


func _feet(rig: CharacterRig, fl: int, fr: int) -> Array:
	var sk := rig.skeleton
	return [
		sk.global_transform * sk.get_bone_global_pose(fl).origin,
		sk.global_transform * sk.get_bone_global_pose(fr).origin,
	]
