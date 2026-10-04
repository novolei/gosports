class_name CourtDeco
extends RefCounted
## Court decoration styles (the "场地装饰" collection, Profile.DECOS): what stands around the court. Every style is built
## procedurally as a few merged, vertex-coloured meshes (1-3 draw calls, no textures) and never touches the playing area:
## plain / garden / bunting / festival / neon / beach / sakura / party (+ the benches of "team", see BenchCrew).
## The LED ad hoardings ("ads") live in Arena._build_boards because they need the ad atlas shader.

const DEPTH := 0.3


# ------------------------------------------------------------------ mesh builder
class Mesher:
	var st := SurfaceTool.new()
	var tris := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## triangle that faces `out` (Godot front faces are clockwise)
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
		var flip := (b - a).cross(c - a).dot(out) > 0.0
		for v in ([a, c, b] if flip else [a, b, c]):
			st.set_color(col)
			st.add_vertex(v)
		tris += 1

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
		tri(a, b, c, col, out)
		tri(a, c, d, col, out)

	## flat triangle visible from both sides (pennants, petals, leaves)
	func tri2(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (b - a).cross(c - a)
		tri(a, b, c, col, n)
		tri(a, b, c, col, -n)

	func quad2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri2(a, b, c, col)
		tri2(a, c, d, col)

	func box(c: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
		var h := size * 0.5
		var faces := [
			[Vector3(1, 0, 0), [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
			[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
			[Vector3(0, 1, 0), [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
			[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
			[Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
			[Vector3(0, 0, -1), [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
		]
		for f in faces:
			var q: Array = f[1]
			quad(c + basis * (q[0] as Vector3), c + basis * (q[1] as Vector3), c + basis * (q[2] as Vector3), c + basis * (q[3] as Vector3), col, basis * (f[0] as Vector3))

	## thin square bar between two points
	func bar(a: Vector3, b: Vector3, th: float, col: Color) -> void:
		var dir := b - a
		var len := dir.length()
		if len < 0.0001:
			return
		var y := dir / len
		var x := y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
		var z := x.cross(y).normalized()
		box((a + b) * 0.5, Vector3(th, len, th), col, Basis(x, y, z))

	## tapered cylinder standing on `base` (r1 = 0 makes a cone)
	func cyl(base: Vector3, r0: float, r1: float, h: float, col: Color, segs := 8, col_top := Color(0, 0, 0, 0)) -> void:
		var top_col := col if col_top.a == 0.0 else col_top
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var b0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var b1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var t0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
			var t1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
			var o := Vector3(cos((a0 + a1) * 0.5), 0.2, sin((a0 + a1) * 0.5))
			if r1 > 0.0001:
				tri(b0, b1, t1, col, o)
				tri(b0, t1, t0, col, o)
			else:
				tri(b0, b1, t0, col, o)
			if r1 > 0.0001:
				tri(t0, t1, base + Vector3(0, h, 0), top_col, Vector3.UP)

	func sphere(c: Vector3, r: float, col: Color, segs := 8, rings := 5, squash := 1.0, col_top := Color(0, 0, 0, 0)) -> void:
		var tc := col if col_top.a == 0.0 else col_top
		for j in rings:
			var p0 := PI * float(j) / float(rings)
			var p1 := PI * float(j + 1) / float(rings)
			for i in segs:
				var a0 := TAU * float(i) / float(segs)
				var a1 := TAU * float(i + 1) / float(segs)
				var v00 := c + Vector3(sin(p0) * cos(a0) * r, cos(p0) * r * squash, sin(p0) * sin(a0) * r)
				var v01 := c + Vector3(sin(p0) * cos(a1) * r, cos(p0) * r * squash, sin(p0) * sin(a1) * r)
				var v10 := c + Vector3(sin(p1) * cos(a0) * r, cos(p1) * r * squash, sin(p1) * sin(a0) * r)
				var v11 := c + Vector3(sin(p1) * cos(a1) * r, cos(p1) * r * squash, sin(p1) * sin(a1) * r)
				var mid := (v00 + v11) * 0.5 - c
				var k := col.lerp(tc, clampf(0.5 + mid.y / maxf(r, 0.001) * 0.5, 0.0, 1.0))
				if j > 0:
					tri(v00, v01, v11, k, mid)
				if j < rings - 1:
					tri(v00, v11, v10, k, mid)

	func commit(mat: Material) -> MeshInstance3D:
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi


static func lit_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.62
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return m


static func neon_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/neon.gdshader")
	return sm


static func unlit_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# ------------------------------------------------------------------ the hoarding runs (same layout as the ad boards)
static func hw() -> float:
	return Court.HALF_W + Court.FREE_ZONE + 0.45


static func hd() -> float:
	return Court.HALF_D + Court.FREE_ZONE + 0.55


static func runs() -> Array:
	var w := hw()
	var d := hd()
	return [
		{"c": Vector3(-w, 0, 0), "dir": Vector3(0, 0, 1), "len": d * 2.0 + DEPTH, "n": Vector3(1, 0, 0)},
		{"c": Vector3(w, 0, 0), "dir": Vector3(0, 0, 1), "len": d * 2.0 + DEPTH, "n": Vector3(-1, 0, 0)},
		{"c": Vector3(0, 0, -d), "dir": Vector3(1, 0, 0), "len": w * 2.0 - DEPTH, "n": Vector3(0, 0, 1)},
	]


## the closed path left side -> far end -> right side, for strings of flags / lanterns
static func path_points() -> Array[Vector3]:
	var w := hw()
	var d := hd()
	return [Vector3(-w, 0, d), Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(w, 0, d)]


## points every ~`step` metres along the closed path (corners always included)
static func resample(step: float) -> Array[Vector3]:
	var pts := path_points()
	var out: Array[Vector3] = []
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(int(round(a.distance_to(b) / step)), 1)
		for k in n:
			out.append(a.lerp(b, float(k) / float(n)))
	out.append(pts[pts.size() - 1])
	return out


## solid hoarding: plinth + cap + two-tone panels (both faces). `team_split` colours our half blue and the opponents' half pink.
static func hoarding(m: Mesher, look: Dictionary, col_a: Color, col_b: Color, cap_col: Color, body_col: Color, team_split := false) -> void:
	for r in runs():
		var c: Vector3 = r["c"]
		var dir: Vector3 = r["dir"]
		var length: float = r["len"]
		var n: Vector3 = r["n"]
		var along_z := absf(dir.z) > 0.5
		var size := Vector3(DEPTH, 0.96, length) if along_z else Vector3(length, 0.96, DEPTH)
		m.box(c + Vector3(0, 0.48, 0), size, body_col)
		var capsz := size + (Vector3(0.1, 0, 0) if along_z else Vector3(0, 0, 0.1))
		capsz.y = 0.07
		m.box(c + Vector3(0, 0.99, 0), capsz, cap_col)
		var count := int(floor(length / 2.05))
		var used := float(count) * 2.05
		for side in [1.0, -1.0]:
			var nn: Vector3 = n * float(side)
			for i in count:
				var along := -used * 0.5 + (float(i) + 0.5) * 2.05
				var pc := c + dir * along + nn * (DEPTH * 0.5 + 0.008) + Vector3(0, 0.52, 0)
				var col := col_a if (i % 2 == 0) else col_b
				if team_split:
					var zz := pc.z if along_z else -1.0
					col = UIKit.BLUE if zz >= 0.0 else UIKit.PINK
					if i % 2 == 1:
						col = col.lightened(0.18)
				var psz := Vector3(0.02, 0.8, 1.96) if along_z else Vector3(1.96, 0.8, 0.02)
				m.box(pc, psz, col)
				var ssz := Vector3(0.025, 0.07, 1.96) if along_z else Vector3(1.96, 0.07, 0.025)
				m.box(pc + Vector3(0, 0.05, 0), ssz, Color(1, 1, 1, 1))


# ------------------------------------------------------------------ net styles (the "球网风格" collection)
## material overrides for Arena._build_net: post / band colours + net shader parameters
static func net_look(id: String) -> Dictionary:
	match id:
		"candy":
			return {"post": Color(1.0, 0.55, 0.75), "band": Color(1, 1, 1), "shader": {"tape_col": Color(1.0, 0.55, 0.75), "tape_col2": Color(1, 1, 1), "tape_stripe": 0.25, "mesh_col": Color(0.3, 0.1, 0.22)}}
		"cloud":
			return {"post": Color(0.95, 0.97, 1.0), "band": Color(0.45, 0.72, 1.0), "shader": {"tape_col": Color(0.78, 0.9, 1.0), "tape_col2": Color(1, 1, 1), "tape_stripe": 0.6, "mesh_col": Color(0.2, 0.32, 0.5)}}
		"cat":
			return {"post": Color(0.3, 0.5, 1.0), "post2": Color(1.0, 0.45, 0.7), "band": Color(1, 1, 1), "shader": {"tape_col": Color(1, 1, 1), "mesh_col": Color(0.12, 0.14, 0.24)}}
		"heart":
			return {"post": Color(1.0, 0.5, 0.7), "band": Color(1, 1, 1), "shader": {"tape_col": Color(1.0, 0.5, 0.7), "hearts": 1.0, "mesh_col": Color(0.26, 0.12, 0.22)}}
		"star":
			return {"post": Color(0.16, 0.18, 0.38), "band": Color(1.0, 0.82, 0.25), "shader": {"tape_col": Color(1.0, 0.82, 0.25), "mesh_col": Color(0.08, 0.09, 0.2)}}
		"rainbow":
			return {"post": Color(0.97, 0.97, 1.0), "band": Color(0.7, 0.5, 1.0), "shader": {"rainbow": 1.0, "mesh_col": Color(0.2, 0.24, 0.36)}}
	return {}


## the small accents on the posts (and a charm or two on the tape ends): one merged lit mesh, a few hundred triangles
static func net_toppers(arena: Arena, id: String) -> void:
	if id == "classic":
		return
	var m := Mesher.new()
	var ptop := 2.7
	for s in [-1.0, 1.0]:
		var x: float = s * Court.NET_X
		var p := Vector3(x, ptop, 0.0)
		match id:
			"candy":
				m.bar(p, p + Vector3(0, 0.28, 0), 0.05, Color(0.97, 0.97, 0.98))
				m.sphere(p + Vector3(0, 0.46, 0), 0.19, Color(1.0, 0.5, 0.74), 10, 6, 1.0, Color(1.0, 0.75, 0.88))
				for k in 4:                                                          # white swirl bands on the lollipop
					var a := TAU * float(k) / 4.0
					m.box(p + Vector3(cos(a) * 0.15, 0.46, sin(a) * 0.15), Vector3(0.05, 0.3, 0.05), Color(1, 1, 1), Basis(Vector3.UP, -a))
			"cloud":
				for off in [Vector3(-0.15, 0.1, 0), Vector3(0.0, 0.2, 0.02), Vector3(0.16, 0.1, 0), Vector3(0.0, 0.08, -0.12)]:
					m.sphere(p + off + Vector3(0, 0.12, 0), 0.16, Color(0.93, 0.96, 1.0), 8, 5, 0.85, Color(1, 1, 1))
			"cat":
				var col := Color(0.3, 0.5, 1.0) if s < 0 else Color(1.0, 0.45, 0.7)
				for sx in [-1.0, 1.0]:
					m.cyl(p + Vector3(sx * 0.1, 0.0, 0), 0.1, 0.0, 0.3, col, 4)
					m.cyl(p + Vector3(sx * 0.1, 0.03, 0.045), 0.055, 0.0, 0.2, Color(1.0, 0.82, 0.88), 4)
				m.sphere(Vector3(x - s * 0.34, Court.NET_TOP - 0.2, 0.0), 0.06, Color(1.0, 0.82, 0.25), 6, 4)       # a little bell on the tape
				m.bar(Vector3(x - s * 0.34, Court.NET_TOP - 0.02, 0.0), Vector3(x - s * 0.34, Court.NET_TOP - 0.15, 0.0), 0.012, Color(0.9, 0.2, 0.3))
			"heart":
				var pk := Color(1.0, 0.42, 0.64)
				m.sphere(p + Vector3(-0.09, 0.26, 0), 0.12, pk, 8, 5)
				m.sphere(p + Vector3(0.09, 0.26, 0), 0.12, pk, 8, 5)
				m.cyl(p + Vector3(0, 0.38, 0), 0.0, 0.0, 0.0, pk)
				# the lower point of the heart: a cone pointing down
				for k in 8:
					var a0 := TAU * float(k) / 8.0
					var a1 := TAU * float(k + 1) / 8.0
					var tip := p + Vector3(0, 0.07, 0)
					m.tri(p + Vector3(cos(a0) * 0.19, 0.3, sin(a0) * 0.08), p + Vector3(cos(a1) * 0.19, 0.3, sin(a1) * 0.08), tip, pk, Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5)))
			"star":
				_star(m, p + Vector3(0, 0.3, 0), 0.22, Color(1.0, 0.84, 0.28))
				_star(m, Vector3(x - s * 0.4, Court.NET_TOP - 0.22, 0.0), 0.1, Color(1.0, 0.9, 0.5))
				m.bar(Vector3(x - s * 0.4, Court.NET_TOP - 0.02, 0.0), Vector3(x - s * 0.4, Court.NET_TOP - 0.14, 0.0), 0.012, Color(1.0, 0.9, 0.5))
			"rainbow":
				var bands: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.85, 0.3), Color(0.35, 0.7, 1.0)]
				for r in 3:
					var rad := 0.2 - 0.06 * float(r)
					var prev := p + Vector3(rad, 0.02, 0)
					for k in range(1, 9):
						var a := PI * float(k) / 8.0
						var q := p + Vector3(cos(a) * rad, 0.02 + sin(a) * rad, 0)
						m.bar(prev, q, 0.05, bands[r])
						prev = q
				m.sphere(p + Vector3(-0.23, 0.04, 0), 0.07, Color(1, 1, 1), 6, 4)
				m.sphere(p + Vector3(0.23, 0.04, 0), 0.07, Color(1, 1, 1), 6, 4)
	arena.add_child(m.commit(lit_material()))


## flat five-point star in the XY plane (faces the broadcast camera), double-sided
static func _star(m: Mesher, c: Vector3, r: float, col: Color) -> void:
	for i in 5:
		var a0 := -PI * 0.5 + TAU * float(i) / 5.0
		var a1 := -PI * 0.5 + TAU * float(i + 1) / 5.0
		var am := (a0 + a1) * 0.5
		var tip := c + Vector3(cos(a0), sin(a0), 0) * r
		var nxt := c + Vector3(cos(a1), sin(a1), 0) * r
		var inner := c + Vector3(cos(am), sin(am), 0) * r * 0.42
		m.tri2(c, tip, inner, col)
		m.tri2(c, inner, nxt, col)
	m.box(c + Vector3(0, 0, -0.015), Vector3(0.001, 0.001, 0.001), col)


# ------------------------------------------------------------------ entry
static func build(arena: Arena, id: String, look: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lit := Mesher.new()
	var unlit := Mesher.new()
	var cap: Color = look["cap"]
	var body: Color = look["plinth"]
	match id:
		"plain":
			hoarding(lit, look, cap, (cap.lerp(Color.WHITE, 0.82)), cap.darkened(0.2), body)
		"team":
			hoarding(lit, look, cap, cap, Color(0.95, 0.96, 0.98), Color(0.16, 0.2, 0.3), true)
		"garden":
			_garden(lit, rng, look)
		"bunting":
			hoarding(lit, look, Color(0.97, 0.97, 0.98), cap.lerp(Color.WHITE, 0.75), cap, body)
			_flags(lit, rng, false)
		"festival":
			hoarding(lit, look, Color(0.82, 0.12, 0.14), Color(0.95, 0.72, 0.2), Color(0.95, 0.72, 0.2), Color(0.35, 0.06, 0.08))
			_flags(lit, rng, true, unlit)
		"neon":
			hoarding(lit, look, Color(0.06, 0.07, 0.14), Color(0.09, 0.1, 0.2), Color(0.05, 0.05, 0.1), Color(0.04, 0.05, 0.1))
			_neon(unlit)
		"beach":
			_beach(lit, rng)
		"sakura":
			hoarding(lit, look, Color(0.99, 0.95, 0.96), Color(1.0, 0.85, 0.9), Color(1.0, 0.7, 0.82), Color(0.86, 0.6, 0.7))
			_sakura(lit, rng)
			if int(arena.quality) >= 1:
				_petals(arena)
		"party":
			_party_boards(lit, rng)
			_balloons(lit, rng)
		_:
			return
	if lit.tris > 0:
		arena.add_child(lit.commit(lit_material()))
	if unlit.tris > 0:
		var mi := unlit.commit(neon_material() if id == "neon" else unlit_material())
		arena.add_child(mi)


# ------------------------------------------------------------------ garden: hedges + topiary balls
static func _garden(m: Mesher, rng: RandomNumberGenerator, look: Dictionary) -> void:
	var pot := Color(0.55, 0.36, 0.24)
	var stone := Color(0.78, 0.76, 0.72)
	for r in runs():
		var c: Vector3 = r["c"]
		var dir: Vector3 = r["dir"]
		var length: float = r["len"]
		var along_z := absf(dir.z) > 0.5
		var sz := Vector3(0.9, 0.34, length) if along_z else Vector3(length, 0.34, 0.9)
		m.box(c + Vector3(0, 0.17, 0), sz, stone)
		var seg := 0.95
		var cnt := int(floor(length / seg))
		for i in cnt:
			var along := -float(cnt) * seg * 0.5 + (float(i) + 0.5) * seg
			var h := 0.5 + rng.randf() * 0.22
			var g := Color.from_hsv(rng.randf_range(0.27, 0.36), rng.randf_range(0.5, 0.62), rng.randf_range(0.55, 0.7))
			var pc := c + dir * along + Vector3(0, 0.34 + h * 0.5, 0)
			var bsz := Vector3(0.72, h, seg * 0.94) if along_z else Vector3(seg * 0.94, h, 0.72)
			m.box(pc, bsz, g)
			# a few tiny blossoms on top
			if rng.randf() < 0.45:
				var fc := Color(1, 0.96, 0.9) if rng.randf() < 0.5 else Color(1.0, 0.78, 0.86)
				m.box(pc + Vector3(rng.randf_range(-0.2, 0.2), h * 0.5 + 0.03, rng.randf_range(-0.2, 0.2)) * (Vector3(1, 1, 1)), Vector3(0.1, 0.07, 0.1), fc)
		# round topiary in a pot every ~3.8 m
		var tc := int(floor(length / 3.8))
		for i in tc:
			var along2 := -float(tc) * 3.8 * 0.5 + (float(i) + 0.5) * 3.8
			var base := c + dir * along2 + Vector3(0, 0.34, 0)
			m.cyl(base, 0.34, 0.28, 0.36, pot)
			var leaf := Color.from_hsv(rng.randf_range(0.28, 0.34), 0.62, rng.randf_range(0.6, 0.72))
			m.sphere(base + Vector3(0, 0.95, 0), 0.62, leaf.darkened(0.12), 10, 6, 1.0, leaf.lightened(0.12))
	# conical trees at the corners
	var w := hw() + 0.9
	var d := hd() + 0.9
	for corner in [Vector3(-w, 0, -d), Vector3(w, 0, -d)]:
		for k in 3:
			m.cyl(corner + Vector3(0, 0.5 + float(k) * 0.85, 0), 1.0 - float(k) * 0.24, 0.0, 1.35, Color.from_hsv(0.31, 0.55, 0.52 + 0.06 * k))
		m.box(corner + Vector3(0, 0.25, 0), Vector3(0.22, 0.5, 0.22), pot)


# ------------------------------------------------------------------ bunting (pennants) / festival (lanterns)
static func _flags(m: Mesher, rng: RandomNumberGenerator, lanterns: bool, unlit: Mesher = null) -> void:
	var pole_col := Color(0.95, 0.95, 0.97) if not lanterns else Color(0.7, 0.1, 0.12)
	var pts := resample(5.4)
	var top := 3.3
	var palette: Array[Color] = [Color("ff4fa0"), Color("ffce30"), Color("2f7cff"), Color("2fd0a8"), Color("ff8a3a"), Color("a56bff")]
	for p in pts:
		m.bar(p, p + Vector3(0, top, 0), 0.09, pole_col)
		m.sphere(p + Vector3(0, top + 0.1, 0), 0.14, Color(1.0, 0.82, 0.25), 6, 4)
	var k := 0
	for i in pts.size() - 1:
		var a := pts[i] + Vector3(0, top - 0.1, 0)
		var b := pts[i + 1] + Vector3(0, top - 0.1, 0)
		var seg_len := a.distance_to(b)
		var steps := maxi(int(seg_len / (1.25 if lanterns else 0.55)), 2)
		var prev := a
		for s in range(1, steps + 1):
			var t := float(s) / float(steps)
			var q := a.lerp(b, t) - Vector3(0, 0.55 * 4.0 * t * (1.0 - t), 0)
			m.bar(prev, q, 0.03, pole_col.darkened(0.15))
			var tm := (float(s) - 0.5) / float(steps)
			var mid := a.lerp(b, tm) - Vector3(0, 0.55 * 4.0 * tm * (1.0 - tm), 0)
			var along := (b - a).normalized()
			if lanterns:
				var lm: Mesher = unlit if unlit != null else m
				var lc := Color(0.95, 0.16, 0.14).lerp(Color(1.0, 0.45, 0.1), rng.randf() * 0.5)
				lm.sphere(mid - Vector3(0, 0.3, 0), 0.24, lc.darkened(0.15), 8, 5, 0.85, lc.lightened(0.25))
				m.box(mid - Vector3(0, 0.07, 0), Vector3(0.16, 0.05, 0.16), Color(1.0, 0.8, 0.25))
				m.box(mid - Vector3(0, 0.55, 0), Vector3(0.14, 0.04, 0.14), Color(1.0, 0.8, 0.25))
				m.bar(mid - Vector3(0, 0.57, 0), mid - Vector3(0, 0.78, 0), 0.025, Color(1.0, 0.8, 0.25))
			else:
				var col := palette[k % palette.size()]
				k += 1
				m.tri2(mid - along * 0.17, mid + along * 0.17, mid - Vector3(0, 0.4, 0), col)
			prev = q


# ------------------------------------------------------------------ neon tubes
static func _neon(m: Mesher) -> void:
	var cols: Array[Color] = [Color(1.0, 0.2, 0.65), Color(0.1, 0.9, 1.0), Color(0.6, 0.35, 1.0)]
	var idx := 0
	for r in runs():
		var c: Vector3 = r["c"]
		var dir: Vector3 = r["dir"]
		var length: float = r["len"]
		var n: Vector3 = r["n"]
		var seg := length / 6.0
		for i in 6:
			var a := c + dir * (-length * 0.5 + seg * float(i) + 0.05)
			var b := c + dir * (-length * 0.5 + seg * float(i + 1) - 0.05)
			var col := cols[(idx + i) % cols.size()]
			for side in [1.0, -1.0]:
				var off: Vector3 = n * float(side) * (DEPTH * 0.5 + 0.03)
				m.bar(a + off + Vector3(0, 1.03, 0), b + off + Vector3(0, 1.03, 0), 0.07, col)
				m.bar(a + off + Vector3(0, 0.12, 0), b + off + Vector3(0, 0.12, 0), 0.05, cols[(idx + i + 1) % cols.size()])
		idx += 1
	# tall light pillars at the four corners of the hoarding
	var w := hw()
	var d := hd()
	for corner in [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d)]:
		m.bar(corner + Vector3(0, 0.1, 0), corner + Vector3(0, 3.0, 0), 0.13, cols[1] if corner.x < 0 else cols[0])


# ------------------------------------------------------------------ beach: wooden fence, parasols, palms, sand
static func _beach(m: Mesher, rng: RandomNumberGenerator) -> void:
	var wood := Color(0.78, 0.58, 0.38)
	var wood2 := Color(0.9, 0.74, 0.54)
	var sand := Color(0.96, 0.86, 0.64)
	for r in runs():
		var c: Vector3 = r["c"]
		var dir: Vector3 = r["dir"]
		var length: float = r["len"]
		var n: Vector3 = r["n"]
		var cnt := int(floor(length / 1.0))
		for i in cnt + 1:
			var p := c + dir * (-float(cnt) * 0.5 + float(i))
			m.box(p + Vector3(0, 0.5, 0), Vector3(0.13, 1.0, 0.13), wood)
		var sz := Vector3(0.06, 0.1, length) if absf(dir.z) > 0.5 else Vector3(length, 0.1, 0.06)
		m.box(c + Vector3(0, 0.82, 0), sz, wood2)
		m.box(c + Vector3(0, 0.5, 0), sz, wood2)
		m.box(c + Vector3(0, 0.18, 0), sz, wood2)
		# a strip of sand outside the fence
		var out := -n
		var ssz := Vector3(3.2, 0.03, length + 2.0) if absf(dir.z) > 0.5 else Vector3(length + 2.0, 0.03, 3.2)
		m.box(c + out * 1.9 + Vector3(0, 0.0, 0), ssz, sand)
	# parasols
	var cols: Array[Color] = [Color(0.95, 0.25, 0.3), Color(0.2, 0.55, 0.95), Color(1.0, 0.75, 0.15), Color(0.2, 0.75, 0.6)]
	var k := 0
	var w := hw()
	for sz2 in [-8.0, -2.5, 3.0, 8.5]:
		for sx in [-1.0, 1.0]:
			var base := Vector3(sx * (w + 1.9), 0.0, sz2 + rng.randf_range(-0.6, 0.6))
			m.cyl(base, 0.05, 0.04, 2.3, Color(0.92, 0.92, 0.94), 6)
			var cc := cols[k % cols.size()]
			k += 1
			for s in 8:
				var a0 := TAU * float(s) / 8.0
				var a1 := TAU * float(s + 1) / 8.0
				var col := cc if s % 2 == 0 else Color(1, 1, 1)
				var tp := base + Vector3(0, 2.75, 0)
				m.tri2(tp, base + Vector3(cos(a0) * 1.35, 2.25, sin(a0) * 1.35), base + Vector3(cos(a1) * 1.35, 2.25, sin(a1) * 1.35), col)
			m.sphere(base + Vector3(0, 2.78, 0), 0.07, Color(0.95, 0.95, 0.95), 5, 3)
	# palm trees at the far corners and mid far end
	for pp in [Vector3(-w - 1.6, 0, -hd() - 1.0), Vector3(w + 1.6, 0, -hd() - 1.0), Vector3(-w - 2.0, 0, 6.0), Vector3(w + 2.0, 0, 6.0)]:
		_palm(m, pp, rng)


static func _palm(m: Mesher, base: Vector3, rng: RandomNumberGenerator) -> void:
	var lean := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
	var p := base
	var trunk := Color(0.62, 0.45, 0.3)
	for i in 6:
		var np := p + Vector3(0, 0.62, 0) + lean * 0.35
		m.bar(p, np, 0.3 - float(i) * 0.03, trunk if i % 2 == 0 else trunk.darkened(0.08))
		p = np
	var leaf := Color(0.25, 0.65, 0.35)
	for l in 7:
		var a := TAU * float(l) / 7.0 + rng.randf() * 0.4
		var dirv := Vector3(cos(a), 0, sin(a))
		var tip := p + dirv * 1.9 + Vector3(0, -0.7, 0)
		var mid := p + dirv * 1.0 + Vector3(0, 0.25, 0)
		var side := Vector3(-dirv.z, 0, dirv.x) * 0.32
		var col := leaf.lightened(0.05 * float(l % 3))
		m.tri2(p, mid + side, mid - side, col)
		m.tri2(mid + side, tip, mid - side, col.darkened(0.08))
	m.sphere(p + Vector3(0, 0.05, 0), 0.2, Color(0.5, 0.35, 0.2), 6, 4)


# ------------------------------------------------------------------ sakura: blossom trees + petals on the floor
static func _sakura(m: Mesher, rng: RandomNumberGenerator) -> void:
	var trunk := Color(0.45, 0.32, 0.28)
	var pinks: Array[Color] = [Color(1.0, 0.76, 0.86), Color(1.0, 0.84, 0.9), Color(0.98, 0.68, 0.8), Color(1.0, 0.9, 0.94)]
	var w := hw()
	var spots: Array[Vector3] = []
	for z in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		spots.append(Vector3(-w - 1.5, 0, z))
		spots.append(Vector3(w + 1.5, 0, z + 1.4))
	spots.append(Vector3(-4.5, 0, -hd() - 1.6))
	spots.append(Vector3(4.5, 0, -hd() - 1.6))
	for sp in spots:
		var h := rng.randf_range(2.2, 2.8)
		m.cyl(sp, 0.26, 0.16, h, trunk, 6)
		m.bar(sp + Vector3(0, h * 0.7, 0), sp + Vector3(0.7, h * 0.95, 0.2), 0.1, trunk)
		m.bar(sp + Vector3(0, h * 0.6, 0), sp + Vector3(-0.6, h * 0.9, -0.25), 0.1, trunk)
		for k in 5:
			var off := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.0, 0.7), rng.randf_range(-0.9, 0.9))
			var col := pinks[rng.randi() % pinks.size()]
			m.sphere(sp + Vector3(0, h + 0.2, 0) + off, rng.randf_range(0.7, 1.05), col.darkened(0.06), 8, 5, 0.82, col.lightened(0.04))
	# fallen petals on the deck
	for i in 140:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p := Vector3(side * rng.randf_range(w + 0.2, w + 4.5), 0.012, rng.randf_range(-hd(), hd()))
		if rng.randf() < 0.18:
			p = Vector3(rng.randf_range(-w, w), 0.012, -hd() - rng.randf_range(0.2, 4.0))
		var a := rng.randf() * TAU
		var u := Vector3(cos(a), 0, sin(a)) * 0.08
		var v := Vector3(-sin(a), 0, cos(a)) * 0.05
		var col2 := pinks[rng.randi() % pinks.size()]
		m.tri(p - u - v, p + u - v, p + v, col2, Vector3.UP)


## a few slowly falling petals (GPU particles, quality >= 1 only)
static func _petals(arena: Arena) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 36
	ps.lifetime = 7.0
	ps.preprocess = 7.0
	ps.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 12, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.0, 0.2, 11.0)
	pm.direction = Vector3(0.2, -1, 0.1)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.1, -0.12, 0)
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	ps.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.11, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.76, 0.86)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = mat
	ps.draw_pass_1 = qm
	ps.position = Vector3(0, 5.0, 0)
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(ps)


# ------------------------------------------------------------------ party: pastel hoarding + balloon clusters
static func _party_boards(m: Mesher, rng: RandomNumberGenerator) -> void:
	var cols: Array[Color] = [Color("ff8fb8"), Color("ffd35a"), Color("7fe0c8"), Color("8fb8ff")]
	for r in runs():
		var c: Vector3 = r["c"]
		var dir: Vector3 = r["dir"]
		var length: float = r["len"]
		var n: Vector3 = r["n"]
		var along_z := absf(dir.z) > 0.5
		var size := Vector3(DEPTH, 0.96, length) if along_z else Vector3(length, 0.96, DEPTH)
		m.box(c + Vector3(0, 0.48, 0), size, Color(1.0, 0.97, 0.92))
		var count := int(floor(length / 2.05))
		var used := float(count) * 2.05
		for side in [1.0, -1.0]:
			var nn: Vector3 = n * float(side)
			for i in count:
				var along := -used * 0.5 + (float(i) + 0.5) * 2.05
				var pc := c + dir * along + nn * (DEPTH * 0.5 + 0.008) + Vector3(0, 0.5, 0)
				var col := cols[(i + (0 if side > 0.0 else 2)) % cols.size()]
				var psz := Vector3(0.02, 0.74, 1.9) if along_z else Vector3(1.9, 0.74, 0.02)
				m.box(pc, psz, col)
				# polka dots
				for d in 3:
					var dp := pc + dir * (-0.6 + 0.6 * float(d)) + nn * 0.012 + Vector3(0, rng.randf_range(-0.15, 0.15), 0)
					m.box(dp, Vector3(0.03, 0.16, 0.16) if along_z else Vector3(0.16, 0.16, 0.03), Color(1, 1, 1, 1))


static func _balloons(m: Mesher, rng: RandomNumberGenerator) -> void:
	var cols: Array[Color] = [Color("ff4fa0"), Color("ffce30"), Color("2f7cff"), Color("2fd0a8"), Color("ff8a3a"), Color("a56bff"), Color("ff5a5a")]
	var w := hw()
	var d := hd()
	var spots: Array[Vector3] = []
	for corner in [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d)]:
		spots.append(corner)
	for z in [-5.5, 0.0, 5.5]:
		spots.append(Vector3(-w, 0, z))
		spots.append(Vector3(w, 0, z))
	spots.append(Vector3(0, 0, -d))
	for sp in spots:
		m.bar(sp + Vector3(0, 0.96, 0), sp + Vector3(0, 2.2, 0), 0.04, Color(0.9, 0.9, 0.92))
		for k in 11:
			var a := rng.randf() * TAU
			var rr := rng.randf_range(0.15, 0.6)
			var p := sp + Vector3(cos(a) * rr, 2.3 + rng.randf_range(0.0, 1.3), sin(a) * rr)
			var col := cols[rng.randi() % cols.size()]
			m.sphere(p, 0.32, col.darkened(0.08), 8, 5, 1.2, col.lightened(0.18))
			m.bar(p - Vector3(0, 0.38, 0), sp + Vector3(0, 2.15, 0), 0.012, Color(0.92, 0.92, 0.95))
	# confetti on the deck
	for i in 160:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p2 := Vector3(side * rng.randf_range(w + 0.2, w + 4.0), 0.012, rng.randf_range(-d, d))
		var a2 := rng.randf() * TAU
		var u := Vector3(cos(a2), 0, sin(a2)) * 0.06
		var v := Vector3(-sin(a2), 0, cos(a2)) * 0.035
		var cc := cols[rng.randi() % cols.size()]
		m.quad(p2 - u - v, p2 + u - v, p2 + u + v, p2 - u + v, cc, Vector3.UP)
