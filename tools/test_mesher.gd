extends SceneTree
## Core test: the optimised Mesher.tri / Mesher.box must produce exactly the same vertices and colours as the original per-face
## implementation (kept below as the reference), and be faster.
##   godot --headless --path . -s core/tools/test_mesher.gd


class RefMesher:
	extends Mesher

	## the original (v0.1.0 / v0.1.1) implementations
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
		var flip := (b - a).cross(c - a).dot(out) > 0.0
		for v in ([a, c, b] if flip else [a, b, c]):
			st.set_color(col)
			st.add_vertex(v)
		tris += 1

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


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	var a := Mesher.new()
	var b := RefMesher.new()
	for i in 3000:
		var c := Vector3(rng.randf_range(-9, 9), rng.randf_range(-3, 5), rng.randf_range(-9, 9))
		var size := Vector3(rng.randf_range(0.01, 4), rng.randf_range(0.01, 4), rng.randf_range(0.01, 4))
		var col := Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		var basis := Basis.IDENTITY if i % 3 == 0 else Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
		match i % 6:
			0, 1, 2:
				a.box(c, size, col, basis)
				b.box(c, size, col, basis)
			3:
				var p := [c, c + Vector3(rng.randf(), 1, rng.randf()), c + Vector3(2, rng.randf(), -1)]
				var o := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
				a.tri(p[0], p[1], p[2], col, o)
				b.tri(p[0], p[1], p[2], col, o)
				a.tri2(p[0], p[1], p[2], col)
				b.tri2(p[0], p[1], p[2], col)
			4:
				var d := c + Vector3(rng.randf_range(-3, 3), rng.randf_range(0.2, 3), rng.randf_range(-3, 3))
				a.bar(c, d, 0.07, col)
				b.bar(c, d, 0.07, col)
			_:
				a.cyl(c, 0.3, 0.1, 1.2, col)
				b.cyl(c, 0.3, 0.1, 1.2, col)
				a.sphere(c, 0.4, col)
				b.sphere(c, 0.4, col)
	var aa := a.st.commit_to_arrays()
	var bb := b.st.commit_to_arrays()
	var ok: bool = a.tris == b.tris and aa[Mesh.ARRAY_VERTEX] == bb[Mesh.ARRAY_VERTEX] and aa[Mesh.ARRAY_COLOR] == bb[Mesh.ARRAY_COLOR]
	print("identical output: ", ok, "  (", a.tris, " triangles, ", (aa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " vertices)")
	# speed: 30000 boxes each
	var t0 := Time.get_ticks_usec()
	var m1 := Mesher.new()
	for i in 30000:
		m1.box(Vector3(i % 50, 0, i % 7), Vector3(1, 2, 3), Color.WHITE, Basis.from_euler(Vector3(0.3, float(i) * 0.01, 0.1)))
	var t1 := Time.get_ticks_usec()
	var m2 := RefMesher.new()
	for i in 30000:
		m2.box(Vector3(i % 50, 0, i % 7), Vector3(1, 2, 3), Color.WHITE, Basis.from_euler(Vector3(0.3, float(i) * 0.01, 0.1)))
	var t2 := Time.get_ticks_usec()
	print("30000 boxes: new %.0f ms, reference %.0f ms (x%.2f)" % [float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0, float(t2 - t1) / maxf(float(t1 - t0), 1.0)])
	quit(0 if ok else 1)
