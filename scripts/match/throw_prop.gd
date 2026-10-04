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

