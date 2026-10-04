extends SceneTree
## Dev tool: for every Cubebrush locomotion clip print travel direction (root bone motion, canonical frame)
## and body yaw, so we know which clip is a strafe / diagonal / turning run.

const RigInfoC := preload("res://scripts/rig/rig_info.gd")
const Solver := preload("res://scripts/rig/pose_solver.gd")


func _initialize() -> void:
	for f in ["Run", "Walk"]:
		var scn: PackedScene = load("res://assets/characters/cube/anim/%s.fbx" % f)
		var inst: Node3D = scn.instantiate()
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		var sk := _find(inst, "Skeleton3D") as Skeleton3D
		var info := RigInfoC.new()
		info.setup(inst, sk, "cube_anim")
		for an in ap.get_animation_list():
			var a := ap.get_animation(an)
			var root_i := -1
			for t in a.get_track_count():
				if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t).get_concatenated_subnames()) == "root":
					root_i = t
			var disp := Vector3.ZERO
			if root_i >= 0:
				var p0: Vector3 = a.position_track_interpolate(root_i, 0.0)
				var p1: Vector3 = a.position_track_interpolate(root_i, a.length - 0.001)
				disp = (p1 - p0) * info.unit
			var dc := Solver.root_to_spec(info, info.xf_sk.basis.orthonormalized() * disp)
			# body yaw: average of the measured spec over the cycle
			var yaw := 0.0
			var n := 8
			var tracks := _tracks(info, a)
			for i in n:
				var g := _globals(info, a, tracks, a.length * i / n)
				yaw += (Solver.measure(info, g)["body"] as Vector3).y
			print("%-28s len=%.2f travel(canon x right,y up,z fwd)=(%.2f, %.2f, %.2f) body_yaw=%.0f" % [an, a.length, dc.x, dc.y, dc.z, yaw / n])
		inst.free()
	quit()


func _tracks(src, a: Animation) -> Dictionary:
	var rot := {}
	var pos := {}
	for t in a.get_track_count():
		var tt := a.track_get_type(t)
		if tt != Animation.TYPE_ROTATION_3D and tt != Animation.TYPE_POSITION_3D:
			continue
		var bone_name := String(a.track_get_path(t).get_concatenated_subnames())
		var bi: int = src.skeleton.find_bone(bone_name)
		if bi < 0:
			continue
		if tt == Animation.TYPE_ROTATION_3D:
			rot[bi] = t
		else:
			pos[bi] = t
	return {"rot": rot, "pos": pos}


func _globals(src, a: Animation, tr: Dictionary, t: float) -> Array[Transform3D]:
	var rots := {}
	for bi in tr["rot"].keys():
		rots[bi] = a.rotation_track_interpolate(tr["rot"][bi], t)
	var hp = null
	var hips_i: int = src.b("hips")
	if tr["pos"].has(hips_i):
		hp = a.position_track_interpolate(tr["pos"][hips_i], t)
	return src.fk(rots, hp)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
