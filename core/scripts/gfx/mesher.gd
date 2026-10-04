class_name Mesher
extends RefCounted
## Procedural low-poly mesh builder (SurfaceTool, vertex colours): boxes, bars, cylinders / cones, spheres, ellipsoids, double-sided
## triangles. Every GoSports game builds its props, crowd, decor and throwables with it (a few merged meshes = 1-3 draw calls).
## Moved out of CourtDeco (volleyball); API: tri / quad / tri2 / quad2 / uvquad / box / bar / cyl / sphere / ellipsoid / commit.
## (v0.1.2: faster tri / box and uvquad, taken from the football game's venue builder; output is bit-identical to v0.1.1.)

var st := SurfaceTool.new()
var tris := 0

func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

## triangle that faces `out` (Godot front faces are clockwise)
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
	var s := st
	s.set_color(col)
	s.add_vertex(a)
	if (b - a).cross(c - a).dot(out) > 0.0:
		s.set_color(col)
		s.add_vertex(c)
		s.set_color(col)
		s.add_vertex(b)
	else:
		s.set_color(col)
		s.add_vertex(b)
		s.set_color(col)
		s.add_vertex(c)
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

## textured quad (a=bottom left, b=bottom right, c=top right, d=top left; UV 0..1), double sided via the material: only for meshes
## that ONLY use uvquad (SurfaceTool wants the same vertex attributes everywhere)
func uvquad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [[a, Vector2(0, 1)], [b, Vector2(1, 1)], [c, Vector2(1, 0)], [a, Vector2(0, 1)], [c, Vector2(1, 0)], [d, Vector2(0, 0)]]:
		st.set_color(col)
		st.set_uv(v[1])
		st.add_vertex(v[0])
	tris += 2


## the eight corners are computed once (no per-face arrays: this is the hottest function of every venue build); the faces, winding
## and float results are bit-identical to the original per-face version (tools/test_mesher.gd compares them)
func box(c: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var ppp := c + basis * Vector3(h.x, h.y, h.z)
	var ppn := c + basis * Vector3(h.x, h.y, -h.z)
	var pnp := c + basis * Vector3(h.x, -h.y, h.z)
	var pnn := c + basis * Vector3(h.x, -h.y, -h.z)
	var npp := c + basis * Vector3(-h.x, h.y, h.z)
	var npn := c + basis * Vector3(-h.x, h.y, -h.z)
	var nnp := c + basis * Vector3(-h.x, -h.y, h.z)
	var nnn := c + basis * Vector3(-h.x, -h.y, -h.z)
	quad(pnp, pnn, ppn, ppp, col, basis.x)
	quad(nnn, nnp, npp, npn, col, -basis.x)
	quad(npp, ppp, ppn, npn, col, basis.y)
	quad(nnn, pnn, pnp, nnp, col, -basis.y)
	quad(nnp, pnp, ppp, npp, col, basis.z)
	quad(pnn, nnn, npn, ppn, col, -basis.z)

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

## stretched sphere (radii per axis): cheap rounded bodies (fish, beans). Colour runs from `col` (underside) to `col_top` (top).
func ellipsoid(c: Vector3, r: Vector3, col: Color, segs := 8, rings := 4, col_top := Color(0, 0, 0, 0)) -> void:
	var tc := col if col_top.a == 0.0 else col_top
	for j in rings:
		var p0 := PI * float(j) / float(rings)
		var p1 := PI * float(j + 1) / float(rings)
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var v00 := c + Vector3(sin(p0) * cos(a0) * r.x, cos(p0) * r.y, sin(p0) * sin(a0) * r.z)
			var v01 := c + Vector3(sin(p0) * cos(a1) * r.x, cos(p0) * r.y, sin(p0) * sin(a1) * r.z)
			var v10 := c + Vector3(sin(p1) * cos(a0) * r.x, cos(p1) * r.y, sin(p1) * sin(a0) * r.z)
			var v11 := c + Vector3(sin(p1) * cos(a1) * r.x, cos(p1) * r.y, sin(p1) * sin(a1) * r.z)
			var mid := (v00 + v11) * 0.5 - c
			var k := col.lerp(tc, clampf(0.5 + mid.y / maxf(r.y, 0.001) * 0.5, 0.0, 1.0))
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
