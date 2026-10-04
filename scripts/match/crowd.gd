class_name Crowd
extends Node3D
## Spectators standing / sitting on the Stadium-Kit stands: cartoon characters with idle / cheer animations.
## Seat heights are found by ray-casting against the stand meshes (triangle meshes, no physics bodies needed).

var arena: Arena
var _stand_meshes: Array = []
var _rigs: Array[CharacterRig] = []
var _t := 0.0
var _excited := 0.0


func build(p_arena: Arena, count: int, quality: int) -> void:
	arena = p_arena
	for c in arena.get_children():
		if c.has_meta("kit") and String(c.get_meta("kit")).begins_with("Seating"):
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).mesh != null:
					_stand_meshes.append(mi)
	var roster := Roster.all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 40:
		tries += 1
		var seat = _random_seat(rng)
		if seat == null:
			continue
		var p: Vector3 = seat
		var entry := roster[rng.randi() % 20]     # cartoon characters only
		var rig := CharacterRig.new()
		add_child(rig)
		rig.build(entry)
		rig.global_position = p
		rig.scale *= rng.randf_range(0.8, 0.95)
		# face the court centre (the rig looks down -Z)
		var to: Vector3 = Vector3(0, 0, 0) - p
		rig.rotation.y = atan2(-to.x, -to.z)
		var clip: String = ["idle_a", "idle_b", "cheer", "idle_c"][rng.randi() % 4]
		rig.play(clip, 0.0, rng.randf_range(0.8, 1.2))
		rig.anim.seek(rng.randf() * 1.5, true)
		_rigs.append(rig)
		placed += 1


func _random_seat(rng: RandomNumberGenerator):
	# pick a random spot in front of one of the stands and drop a ray onto the stand geometry
	var hw := Court.HALF_W + Court.FREE_ZONE
	var hd := Court.HALF_D + Court.FREE_ZONE
	var side := rng.randi() % 3
	var x := 0.0
	var z := 0.0
	match side:
		0:
			x = rng.randf_range(-20.0, 20.0)
			z = -hd - rng.randf_range(4.0, 11.0)
		1:
			x = -hw - rng.randf_range(6.0, 12.0)
			z = rng.randf_range(-12.0, 12.0)
		_:
			x = hw + rng.randf_range(6.0, 12.0)
			z = rng.randf_range(-12.0, 12.0)
	var best = null
	for m in _stand_meshes:
		var mi := m as MeshInstance3D
		var tm := (mi.mesh as ArrayMesh) if mi.mesh is ArrayMesh else null
		var tri := mi.mesh.generate_triangle_mesh()
		if tri == null:
			continue
		var inv := mi.global_transform.affine_inverse()
		var o := inv * Vector3(x, 20.0, z)
		var d := (inv.basis * Vector3.DOWN).normalized()
		var hit := tri.intersect_ray(o, d)
		if hit.is_empty():
			continue
		var wp: Vector3 = mi.global_transform * (hit["position"] as Vector3)
		var nrm: Vector3 = (mi.global_transform.basis * (hit["normal"] as Vector3)).normalized()
		# only walkable (flat-ish) surfaces that are not the roof (roofs are above 4 m)
		if nrm.y < 0.8 or wp.y > 6.2 or wp.y < 0.2:
			continue
		if best == null or wp.y > (best as Vector3).y:
			best = wp
	return best


func cheer(on: bool) -> void:
	for r in _rigs:
		r.play("cheer" if on else "idle_a", 0.2, randf_range(0.9, 1.3))
