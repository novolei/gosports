class_name ThrowProp
extends RefCounted
## The little things the umpire throws at a server who takes too long (pencil stub, eraser, paper ball, rubber duck, paper plane,
## score book). Each is a handful of vertex-coloured boxes / spheres in one mesh, built when it is thrown.

const SMALL := ["pencil", "eraser", "paper", "plane"]
const BIG := ["duck", "book", "pencil"]


static func random_id(tier: int) -> String:
	var pool: Array = SMALL if tier <= 1 else BIG
	return String(pool[randi() % pool.size()])


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
		"book":
			m.box(Vector3(0, 0, 0), Vector3(0.16, 0.045, 0.12), Color("d9304a"))
			m.box(Vector3(0.003, 0, 0.0), Vector3(0.15, 0.036, 0.112), Color("fbf8ef"))
			m.box(Vector3(-0.07, 0, 0), Vector3(0.02, 0.047, 0.122), Color("a82038"))
	var mi := m.commit(CourtDeco.lit_material())
	mi.scale = Vector3.ONE * scale_k
	return mi
