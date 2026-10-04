extends SceneTree
## Offline animation baker.
##   godot --headless --path . -s tools/bake_anims.gd -- <target: cube|ninja> [flags]
## Builds res://assets/anim/<target>_lib.res (an AnimationLibrary) out of
##   - Cubebrush locomotion clips (direct bone rename for cube, spec-retarget for ninja)
##   - Mixamo clips (spec-retarget)
##   - hand-authored volleyball clips (see scripts/rig/clip_defs.gd)

const RigInfoC := preload("res://scripts/rig/rig_info.gd")
const Solver := preload("res://scripts/rig/pose_solver.gd")
const Defs := preload("res://scripts/rig/clip_defs.gd")

const MODEL := {
	"cube": "res://assets/characters/cube/models/Human.fbx",
	"ninja": "res://assets/characters/ninja/fbx/Male_Ninja_02.fbx",
}
const FPS := 30.0

var dst: RigInfo
var target := "cube"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	target = args[0] if args.size() > 0 else "cube"
	var force_spec := args.has("--spec")
	dst = _load_rig(MODEL[target], target)
	if dst == null:
		quit(1)
		return
	var lib := AnimationLibrary.new()

	# 1) Cubebrush locomotion / base clips
	for f in ["Idle", "Run", "Jump", "Walk", "Fight", "Turn"]:
		var src_scene: PackedScene = load("res://assets/characters/cube/anim/%s.fbx" % f)
		var inst: Node3D = src_scene.instantiate()
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		var sk := _find(inst, "Skeleton3D") as Skeleton3D
		var src := RigInfoC.new()
		if not src.setup(inst, sk, "cube_anim"):
			push_error("cube_anim rig failed for " + f)
			continue
		for an in ap.get_animation_list():
			var clip_name := (an as String).get_slice("|", 1).to_lower()
			var a: Animation
			if target == "cube" and not force_spec:
				a = _remap_direct(ap.get_animation(an), src)
			else:
				a = _retarget(src, ap.get_animation(an), false)
			a.loop_mode = Animation.LOOP_LINEAR if Defs.is_loop(clip_name) else Animation.LOOP_NONE
			lib.add_animation(clip_name, a)
			# locomotion blend-space clips (spec retarget for every rig, gait amplitude scaled per speed level)
			for dir_key in Defs.LOCO_SOURCES.keys():
				if Defs.LOCO_SOURCES[dir_key] != clip_name:
					continue
				var specs := _roll_cycle(_smooth_feet(_loco_specs(src, ap.get_animation(an))), float(Defs.LOCO_PHASE.get(dir_key, 0.0)))
				for level in Defs.LOCO_LEVELS:
					if dir_key in ["fl", "fr"] and level < 0.7:
						continue
					var la := _bake_specs(_scale_gait(specs, level), FPS, true)
					la.loop_mode = Animation.LOOP_LINEAR
					lib.add_animation("loco_%s_%d" % [dir_key, int(round(level * 100.0))], la)
		inst.free()

	# 2) hand-authored clips (+ "_h" variants that start right before the contact frame)
	var authored: Dictionary = Defs.authored()
	for clip_name in authored.keys():
		var def: Dictionary = authored[clip_name]
		lib.add_animation(clip_name, _bake_keys(def["keys"], def.get("loop", false), def.get("fps", FPS)))
		if Defs.LEAD_START.has(clip_name):
			lib.add_animation(clip_name + "_h", _bake_keys(def["keys"], false, def.get("fps", FPS), float(Defs.LEAD_START[clip_name])))

	# 3) mixamo clips
	for clip_name in Defs.MIXAMO.keys():
		var def2: Dictionary = Defs.MIXAMO[clip_name]
		var scn: PackedScene = load(def2["file"])
		if scn == null:
			push_warning("missing mixamo file " + def2["file"])
			continue
		var inst2: Node3D = scn.instantiate()
		var ap2 := _find(inst2, "AnimationPlayer") as AnimationPlayer
		var sk2 := _find(inst2, "Skeleton3D") as Skeleton3D
		var src2 := RigInfoC.new()
		if not src2.setup(inst2, sk2, "mixamo"):
			push_error("mixamo rig failed for " + clip_name)
			inst2.free()
			continue
		var names := ap2.get_animation_list()
		var pick := ""
		for n in names:
			if n != "RESET" and n != "Take 001" or pick == "":
				pick = n
		var anim_src := ap2.get_animation(pick)
		var a2 := _retarget(src2, anim_src, def2.get("keep_xz", false), def2.get("trim", Vector2(0, -1)))
		a2.loop_mode = Animation.LOOP_LINEAR if def2.get("loop", false) else Animation.LOOP_NONE
		lib.add_animation(clip_name, a2)
		inst2.free()

	var tag := ""
	for a_ in args:
		if (a_ as String).begins_with("--tag="):
			tag = "_" + (a_ as String).substr(6)
	var out := "res://assets/anim/%s%s_lib.res" % [target, tag]
	DirAccess.make_dir_recursive_absolute("res://assets/anim")
	var err := ResourceSaver.save(lib, out)
	print("saved ", out, " err=", err, " clips=", lib.get_animation_list().size())
	for n in lib.get_animation_list():
		print("   ", n, "  ", "%.2fs" % lib.get_animation(n).length)
	quit()


func _load_rig(path: String, kind: String) -> RigInfo:
	var scn: PackedScene = load(path)
	if scn == null:
		push_error("cannot load " + path)
		return null
	var inst: Node3D = scn.instantiate()
	var sk := _find(inst, "Skeleton3D") as Skeleton3D
	var info := RigInfoC.new()
	if not info.setup(inst, sk, kind):
		return null
	print("rig ", kind, " bones=", info.count, " unit=", info.unit, " right=", info.right, " fwd=", info.fwd,
			" arm=", info.arm_len, " leg=", info.leg_len, " hips_rest=", info.hips_rest)
	return info


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


## track bookkeeping for a source animation
func _tracks(src: RigInfo, a: Animation) -> Dictionary:
	var rot := {}
	var pos := {}
	for t in a.get_track_count():
		var tt := a.track_get_type(t)
		if tt != Animation.TYPE_ROTATION_3D and tt != Animation.TYPE_POSITION_3D:
			continue
		var bone_name := String(a.track_get_path(t).get_concatenated_subnames())
		var bi := src.skeleton.find_bone(bone_name)
		if bi < 0:
			bi = src.skeleton.find_bone(RigInfoC.norm_name(bone_name))
		if bi < 0:
			continue
		if tt == Animation.TYPE_ROTATION_3D:
			rot[bi] = t
		else:
			pos[bi] = t
	return {"rot": rot, "pos": pos}


func _sample_globals(src: RigInfo, a: Animation, tr: Dictionary, t: float) -> Array[Transform3D]:
	var rots := {}
	for bi in tr["rot"].keys():
		rots[bi] = a.rotation_track_interpolate(tr["rot"][bi], t)
	var hips_i: int = src.b("hips")
	var hp = null
	if tr["pos"].has(hips_i):
		hp = a.position_track_interpolate(tr["pos"][hips_i], t)
	return src.fk(rots, hp)


## Direct bone-name remap (cube_anim "ORG-x" -> cube "x"), exact for the same skeleton family.
func _remap_direct(a: Animation, src: RigInfo) -> Animation:
	var out := Animation.new()
	out.length = a.length
	var skel_path := str(_path_to(dst))
	for t in a.get_track_count():
		var tt := a.track_get_type(t)
		if tt != Animation.TYPE_ROTATION_3D and tt != Animation.TYPE_POSITION_3D:
			continue
		var bone_name := String(a.track_get_path(t).get_concatenated_subnames())
		if not bone_name.begins_with("ORG-"):
			continue
		var new_name := bone_name.substr(4)
		if dst.skeleton.find_bone(new_name) < 0:
			continue
		if tt == Animation.TYPE_POSITION_3D and new_name != "hips":
			continue
		var ti := out.add_track(tt)
		out.track_set_path(ti, NodePath("%s:%s" % [skel_path, new_name]))
		for k in a.track_get_key_count(t):
			var tm := a.track_get_key_time(t, k)
			var v = a.track_get_key_value(t, k)
			if tt == Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(ti, tm, v)
			else:
				out.position_track_insert_key(ti, tm, v)
		out.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
	return out


func _path_to(info: RigInfo) -> NodePath:
	return info.root.get_path_to(info.skeleton)


## spec-based retarget of any humanoid clip onto dst
func _retarget(src: RigInfo, a: Animation, keep_xz: bool, trim := Vector2(0, -1)) -> Animation:
	var tr := _tracks(src, a)
	var t0: float = trim.x
	var t1: float = a.length if trim.y < 0.0 else minf(trim.y, a.length)
	var n := int(ceil((t1 - t0) * FPS)) + 1
	var specs: Array[Dictionary] = []
	var first_hips := Vector3.ZERO
	for i in n:
		var t := minf(t0 + i / FPS, t1)
		var g := _sample_globals(src, a, tr, t)
		var s := Solver.measure(src, g)
		if i == 0:
			first_hips = s["hips"]
		if not keep_xz:
			var h: Vector3 = s["hips"]
			s["hips"] = Vector3(0.0, h.y, 0.0)
		specs.append(s)
	return _bake_specs(specs, FPS)


## Spec timeline of one locomotion cycle: n evenly spaced frames over [0, length) (loop-ready).
func _loco_specs(src: RigInfo, a: Animation) -> Array[Dictionary]:
	var tr := _tracks(src, a)
	var n := int(round(a.length * FPS))
	var specs: Array[Dictionary] = []
	for i in n:
		var g := _sample_globals(src, a, tr, a.length * float(i) / float(n))
		var s := Solver.measure(src, g)
		var h: Vector3 = s["hips"]
		s["hips"] = Vector3(0.0, h.y, 0.0)     # in place: the athlete moves the root
		specs.append(s)
	return specs


## Circular 3-tap low-pass of the foot angles: the source foot flicks ~50 degrees between two frames at toe-off.
func _smooth_feet(specs: Array[Dictionary]) -> Array[Dictionary]:
	var n := specs.size()
	var out: Array[Dictionary] = []
	for i in n:
		var o: Dictionary = specs[i].duplicate()
		for key in ["foot_pitch_l", "foot_pitch_r", "foot_yaw_l", "foot_yaw_r"]:
			o[key] = 0.25 * float(specs[posmod(i - 1, n)][key]) + 0.5 * float(specs[i][key]) + 0.25 * float(specs[posmod(i + 1, n)][key])
		out.append(o)
	return out


## Rolls a loop-ready cycle later by `frac` of its length (new[i] = old[i - shift]).
func _roll_cycle(specs: Array[Dictionary], frac: float) -> Array[Dictionary]:
	if is_zero_approx(frac):
		return specs
	var n := specs.size()
	var shift := int(round(frac * n))
	var out: Array[Dictionary] = []
	for i in n:
		out.append(specs[posmod(i - shift, n)])
	return out


## Same gait at a lower intensity ("speed level"): amplitudes scale around the cycle mean, lean and arm swing relax.
func _scale_gait(specs: Array[Dictionary], k: float) -> Array[Dictionary]:
	var v3 := ["hips", "body", "torso", "head", "hand_l", "hand_r", "elbow_l", "elbow_r", "foot_l", "foot_r", "knee_l", "knee_r"]
	var fl := ["hand_roll_l", "hand_roll_r", "foot_pitch_l", "foot_pitch_r", "foot_yaw_l", "foot_yaw_r"]
	var mean := {}
	for key in v3:
		var m := Vector3.ZERO
		for s in specs:
			m += s[key]
		mean[key] = m / specs.size()
	for key in fl:
		var m2 := 0.0
		for s in specs:
			m2 += s[key]
		mean[key] = m2 / specs.size()
	var neutral := Solver.neutral(dst)
	var out: Array[Dictionary] = []
	for s in specs:
		var o := {}
		for key in v3:
			var m: Vector3 = mean[key]
			var v: Vector3 = s[key]
			var base := m
			match key:
				"body", "torso":
					base = m * lerpf(0.3, 1.0, k)                 # stand more upright when slower
				"hips":
					base = m + Vector3(0, (1.0 - k) * 0.05, 0)    # taller stance
				"hand_l", "hand_r":
					base = (neutral[key] as Vector3).lerp(m, k)   # arms hang more relaxed
			var d := v - m
			if key == "foot_l" or key == "foot_r":
				d = Vector3(d.x * k, d.y * pow(k, 1.35), d.z * k)   # shorter stride, lower foot lift
			elif key == "hips":
				d *= k
			else:
				d *= k
			o[key] = base + d
		for key in fl:
			o[key] = float(mean[key]) + (float(s[key]) - float(mean[key])) * k
		out.append(o)
	return out


func _bake_keys(keys: Array, loop: bool, fps: float, t_start := 0.0) -> Animation:
	# keys: [[time, spec(Dictionary), ease?], ...] ; interpolated with smoothstep between keys
	var total: float = keys[keys.size() - 1][0]
	var n := int(ceil((total - t_start) * fps)) + 1
	var specs: Array[Dictionary] = []
	for i in n:
		var t := minf(t_start + i / fps, total)
		specs.append(_eval_keys(keys, t))
	var a := _bake_specs(specs, fps)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a


func _eval_keys(keys: Array, t: float) -> Dictionary:
	var base := Solver.neutral(dst)
	if t <= keys[0][0]:
		return _fill(base, keys[0][1])
	for i in range(keys.size() - 1):
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if t <= k1[0]:
			var u := inverse_lerp(k0[0], k1[0], t)
			u = _ease(u, k1[2] if k1.size() > 2 else "smooth")
			return Solver.lerp_spec(_fill(base, k0[1]), _fill(base, k1[1]), u)
	return _fill(base, keys[keys.size() - 1][1])


func _fill(base: Dictionary, spec: Dictionary) -> Dictionary:
	var r := base.duplicate()
	for k in spec.keys():
		r[k] = spec[k]
	return r


func _ease(u: float, mode: String) -> float:
	match mode:
		"linear": return u
		"in": return u * u
		"out": return 1.0 - (1.0 - u) * (1.0 - u)
		"snap": return 1.0 if u > 0.0 else 0.0
		_: return u * u * (3.0 - 2.0 * u)


func _bake_specs(specs: Array[Dictionary], fps: float, loop := false) -> Animation:
	var out := Animation.new()
	out.length = (specs.size() if loop else specs.size() - 1) / fps
	var skel_path := str(_path_to(dst))
	var rot_tracks := {}
	var prev := {}
	var hips_t := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_t, NodePath("%s:%s" % [skel_path, dst.skeleton.get_bone_name(dst.b("hips"))]))
	for i in specs.size():
		var sol := Solver.solve(dst, specs[i])
		var tm := i / fps
		for bi in sol["rots"].keys():
			if not rot_tracks.has(bi):
				var ti := out.add_track(Animation.TYPE_ROTATION_3D)
				out.track_set_path(ti, NodePath("%s:%s" % [skel_path, dst.skeleton.get_bone_name(bi)]))
				rot_tracks[bi] = ti
			var q: Quaternion = sol["rots"][bi]
			if prev.has(bi) and (prev[bi] as Quaternion).dot(q) < 0.0:
				q = -q
			prev[bi] = q
			out.rotation_track_insert_key(rot_tracks[bi], tm, q)
		out.position_track_insert_key(hips_t, tm, sol["hips_pos"])
	return out

