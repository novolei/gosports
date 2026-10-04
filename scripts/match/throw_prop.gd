class_name ThrowProp
extends RefCounted
## The little things the umpire throws at a server who takes too long (pencil stub, eraser, paper ball, rubber duck, paper plane,
## score book). Each is a handful of vertex-coloured boxes / spheres in one mesh, built when it is thrown.

const SMALL := ["pencil", "eraser", "paper", "plane", "sock", "banana"]
const BIG := ["duck", "book", "fish", "slipper", "hammer", "fish", "slipper"]


static func random_id(tier: int) -> String:
	if Game.main != null and Game.main.dev.has("propid"):          # dev: --propid=fish forces the thrown prop
		return String(Game.main.dev["propid"])
	var pool: Array = SMALL if tier <= 1 else BIG
	return String(pool[randi() % pool.size()])


## relative size of each prop (the sardine is a lot smaller than the other tier-2 props)
const SIZE := {"fish": 0.52}


static func make(id: String, scale_k := 1.0) -> MeshInstance3D:
	var m := CourtDeco.Mesher.new()
	match id:
		"pencil":
			m.box(Vector3(0, 0, 0), Vector3(0.034, 0.034, 0.24), Color("ffd23a"))
			m.box(Vector3(0, 0, -0.14), Vector3(0.036, 0.036, 0.04), Color("ff8fb8"))
			m.box(Vector3(0, 0, -0.112), Vector3(0.038, 0.038, 0.022), Color("c9ced6"))
			m.box(Vector3(0, 0, 0.14), Vector3(0.022, 0.022, 0.04), Color("e8c898"))
			m.box(Vector3(0, 0, 0.17), Vector3(0.01, 0.01, 0.026), Color("3a3d46"))
		"eraser":
			m.box(Vector3(0, 0, 0), Vector3(0.1, 0.04, 0.05), Color("ffffff"))
			m.box(Vector3(0, 0, 0), Vector3(0.05, 0.043, 0.053), Color("3f7cff"))
		"paper":
			m.sphere(Vector3.ZERO, 0.055, Color("f4f1e8"), 7, 5, 0.92, Color("ffffff"))
			m.box(Vector3(0.02, 0.03, 0.0), Vector3(0.04, 0.012, 0.03), Color("e1ddd0"))
		"plane":
			m.tri2(Vector3(0, 0, 0.14), Vector3(-0.09, 0.02, -0.08), Vector3(0.09, 0.02, -0.08), Color("ffffff"))
			m.tri2(Vector3(0, 0, 0.14), Vector3(0, -0.03, -0.08), Vector3(0, 0.02, -0.08), Color("8fc8ff"))
		"duck":
			m.sphere(Vector3(0, 0, 0), 0.07, Color("ffd62e"), 8, 5, 0.85, Color("fff08a"))
			m.sphere(Vector3(0, 0.075, 0.04), 0.045, Color("ffd62e"), 8, 5, 1.0, Color("fff08a"))
			m.box(Vector3(0, 0.07, 0.092), Vector3(0.04, 0.016, 0.03), Color("ff8a1e"))
			m.box(Vector3(0.02, 0.09, 0.07), Vector3(0.01, 0.01, 0.01), Color("1a1a22"))
			m.box(Vector3(-0.02, 0.09, 0.07), Vector3(0.01, 0.01, 0.01), Color("1a1a22"))
		"fish":
			# a sardine (about 140 triangles): slim silver body with a blue back, forked tail, small dorsal fin, big round eye
			m.ellipsoid(Vector3(0, 0, 0), Vector3(0.032, 0.04, 0.12), Color("eef5fa"), 8, 4, Color("3d6f9c"))
			m.ellipsoid(Vector3(0, 0.004, 0.0), Vector3(0.034, 0.011, 0.105), Color("b9d3e8"), 8, 2)                  # the silver side stripe
			m.tri2(Vector3(0, 0.0, 0.105), Vector3(0, 0.065, 0.19), Vector3(0, 0.012, 0.165), Color("2c5a7e"))           # forked tail
			m.tri2(Vector3(0, 0.0, 0.105), Vector3(0, -0.065, 0.19), Vector3(0, -0.012, 0.165), Color("2c5a7e"))
			m.tri2(Vector3(0, 0.036, -0.01), Vector3(0, 0.078, 0.035), Vector3(0, 0.036, 0.055), Color("2c5a7e"))        # dorsal fin
			m.box(Vector3(0.029, 0.014, -0.082), Vector3(0.016, 0.02, 0.02), Color.WHITE)                               # eyes
			m.box(Vector3(-0.029, 0.014, -0.082), Vector3(0.016, 0.02, 0.02), Color.WHITE)
			m.box(Vector3(0.037, 0.014, -0.084), Vector3(0.008, 0.012, 0.012), Color("14181f"))
			m.box(Vector3(-0.037, 0.014, -0.084), Vector3(0.008, 0.012, 0.012), Color("14181f"))
		"slipper":
			# a bathroom flip-flop: thick sole + a V strap
			m.box(Vector3(0, 0, 0), Vector3(0.1, 0.022, 0.26), Color("ff8fb8"))
			m.box(Vector3(0, -0.015, 0.0), Vector3(0.092, 0.012, 0.25), Color("f2f2f5"))
			m.sphere(Vector3(0, 0.0, -0.13), 0.05, Color("ff8fb8"), 8, 4, 0.45)
			m.sphere(Vector3(0, 0.0, 0.13), 0.048, Color("ff8fb8"), 8, 4, 0.45)
			m.bar(Vector3(-0.045, 0.014, -0.02), Vector3(0.0, 0.05, -0.085), 0.026, Color("2fd0a8"))
			m.bar(Vector3(0.045, 0.014, -0.02), Vector3(0.0, 0.05, -0.085), 0.026, Color("2fd0a8"))
		"banana":
			var prev := Vector3(0, 0, -0.12)
			for k in range(1, 9):
				var u := float(k) / 8.0
				var q := Vector3(0, 0.05 * sin(u * PI), -0.12 + 0.24 * u)
				m.bar(prev, q, 0.045 * (1.0 - 0.25 * absf(u - 0.5) * 2.0), Color("ffe03a"))
				prev = q
			m.box(Vector3(0, 0.002, -0.125), Vector3(0.03, 0.03, 0.03), Color("6b4a1c"))
			m.box(Vector3(0, 0.002, 0.125), Vector3(0.025, 0.025, 0.025), Color("3a2a12"))
		"sock":
			m.box(Vector3(0, 0.05, 0), Vector3(0.07, 0.12, 0.07), Color("ffffff"))
			m.box(Vector3(0, 0.1, 0), Vector3(0.074, 0.03, 0.074), Color("ff4f6e"))
			m.box(Vector3(0, 0.025, 0.04), Vector3(0.07, 0.05, 0.1), Color("ffffff"))
			m.box(Vector3(0, 0.07, 0), Vector3(0.074, 0.016, 0.074), Color("ff4f6e"))
		"hammer":
			# the squeaky "piko-piko" toy hammer
			m.bar(Vector3(0, 0, -0.1), Vector3(0, 0, 0.1), 0.028, Color("ffd23a"))
			m.cyl(Vector3(-0.07, 0, 0.12), 0.055, 0.055, 0.14, Color("ff4f6e"), 8, Color("ff9db0"))
			m.box(Vector3(0, 0, -0.105), Vector3(0.05, 0.05, 0.02), Color("2f7cff"))
		"book":
			m.box(Vector3(0, 0, 0), Vector3(0.16, 0.045, 0.12), Color("d9304a"))
			m.box(Vector3(0.003, 0, 0.0), Vector3(0.15, 0.036, 0.112), Color("fbf8ef"))
			m.box(Vector3(-0.07, 0, 0), Vector3(0.02, 0.047, 0.122), Color("a82038"))
	var mat := CourtDeco.lit_material()
	mat.vertex_color_is_srgb = true                     # (saturated, cartoon colours: the props are small, so they must pop)
	mat.roughness = 0.5
	var mi := m.commit(mat)
	mi.scale = Vector3.ONE * scale_k * float(SIZE.get(id, 1.0))
	mi.set_meta("id", id)
	return mi


## after the hit the prop is a little physics toy: it bounces off the head, falls, hits the floor and bounces a few more times
## (each bounce lower, slower and quieter), then lies still and is flattened onto its side. `on_bounce(strength)` is called on every
## floor impact (sound / squash). Returns when the prop has come to rest (the caller then shrinks it away).
static func tumble(prop: MeshInstance3D, vel: Vector3, spin: Vector3, rest_y: float, on_bounce: Callable) -> Tween:
	var st := {"v": vel, "w": spin, "t": 0.0, "n": 0, "rest": false}
	var tw := prop.create_tween()
	tw.tween_method(func(t: float):
		var dt: float = t - float(st["t"])
		st["t"] = t
		if bool(st["rest"]) or dt <= 0.0:
			return
		var steps := maxi(int(ceil(dt / 0.016)), 1)
		var h := dt / float(steps)
		for i in steps:
			var v: Vector3 = st["v"]
			v.y -= 12.0 * h
			var p := prop.global_position + v * h
			if p.y <= rest_y and v.y < 0.0:
				p.y = rest_y
				if absf(v.y) > 1.0 and int(st["n"]) < 4:
					on_bounce.call(clampf(absf(v.y) / 5.0, 0.15, 1.0))
					st["n"] = int(st["n"]) + 1
					v.y = -v.y * 0.4                         # restitution
					v.x *= 0.6
					v.z *= 0.6
					st["w"] = (st["w"] as Vector3) * 0.55
				else:
					st["rest"] = true
					v = Vector3.ZERO
					var r := prop.rotation
					prop.rotation = Vector3(wrapf(r.x, -PI, PI), wrapf(r.y, -PI, PI), wrapf(r.z, -PI, PI))
					var flat := prop.create_tween()
					flat.tween_property(prop, "rotation", Vector3(0.0, prop.rotation.y, PI * 0.5), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			prop.global_position = p
			st["v"] = v
			if not bool(st["rest"]):
				prop.rotation += (st["w"] as Vector3) * h
			else:
				break
	, 0.0, 3.2, 3.2)
	return tw


## a prop flies from `from` to the head of athlete `a` (0.66 s, tumbling), hits it (bonk + the "!" mark + sounds + camera nudge) and
## then bounces off and tumbles over the floor. Used by the umpire's warnings and by an angry teammate.
static func launch_at(parent: Node, scene: MatchScene, a: Athlete, id: String, tier: int, from: Vector3) -> void:
	var prop := make(id, 2.6 if tier <= 1 else 3.2)       # (cartoon-sized so it reads from the broadcast camera)
	parent.add_child(prop)
	prop.global_position = from
	var spin := Vector3(randf_range(2.0, 4.0), randf_range(2.0, 5.0), 0.0) * TAU * (1.0 if randf() < 0.5 else -1.0)
	var dur := 0.66
	Sfx.play("whoosh", -6.0, 1.2)
	var tw := prop.create_tween()
	tw.tween_method(func(u: float):
		if not is_instance_valid(a):
			return
		var to := a.rig.head_world() + Vector3(0, 0.04, 0)
		prop.global_position = from.lerp(to, u) + Vector3(0, 0.55 * 4.0 * u * (1.0 - u), 0)
		prop.rotation = spin * u, 0.0, 1.0, dur)
	tw.tween_callback(func(): _hit(scene, a, prop, tier, from))


static func _hit(scene: MatchScene, a: Athlete, prop: MeshInstance3D, tier: int, from_pos: Vector3) -> void:
	if not is_instance_valid(a):
		prop.queue_free()
		return
	a.bonk()
	var head_y: float = a.rig.head_world().y - a.global_position.y + 0.3        # (bone centre -> top of the head)
	AlertMark.spawn_over(a, head_y, 1.4)
	Sfx.play("body_bump", -1.0, 0.9)
	Sfx.play("ui_confirm", -4.0, 1.7)
	var pid := String(prop.get_meta("id")) if prop.has_meta("id") else ""
	if pid == "fish" or pid == "slipper":
		Sfx.play("hit_bump", -3.0, 1.4)                           # the "slap"
	if scene != null:
		scene.cam_rig.shake(0.18 if tier <= 1 else 0.3)
		scene.vfx.hit_burst(prop.global_position, "good", 0.35)
	if Game.main != null and Game.main.dev.has("log"):
		print("[ref] prop hit ", a.display_name, " tier ", tier)
	# it bounces off the head (back towards where it came from, and up), falls and bounces on the floor a few times, then shrinks away
	var base_scale := prop.scale
	var dir := (prop.global_position - from_pos).normalized() if from_pos != Vector3.ZERO else Vector3(1, 0, 0)
	var side := Vector3(-dir.z, 0, dir.x) * randf_range(-0.7, 0.7)
	var launch := Vector3(-dir.x, 0.0, -dir.z) * randf_range(0.9, 1.6) + side + Vector3(0, randf_range(2.6, 3.4), 0)
	var spin := Vector3(randf_range(-9.0, 9.0), randf_range(-7.0, 7.0), randf_range(-9.0, 9.0))
	var bounce := func(k: float):
		if Game.main != null and Game.main.dev.has("log"):
			print("[propbounce] strength=%.2f y=%.2f" % [k, prop.global_position.y])
		Sfx.play("bounce", -13.0 + 7.0 * k, randf_range(1.5, 1.9))
		var sq := prop.create_tween()
		sq.tween_property(prop, "scale", base_scale * Vector3(1.0 + 0.18 * k, 1.0 - 0.22 * k, 1.0 + 0.18 * k), 0.04)
		sq.tween_property(prop, "scale", base_scale, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if scene != null and k > 0.45:
			scene.vfx.hit_burst(Vector3(prop.global_position.x, 0.05, prop.global_position.z), "good", 0.12)
	var tw := tumble(prop, launch, spin, 0.055, bounce)
	tw.tween_interval(1.5)
	tw.tween_property(prop, "scale", Vector3.ZERO, 0.3)
	tw.tween_callback(prop.queue_free)

