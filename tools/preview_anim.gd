extends SceneTree
## Dev tool: contact sheet of one clip (several phases side by side), windowed run.
## godot --path . -s tools/preview_anim.gd -- out.png kind lib clip [n=8] [view=front|side|three]
## kind: cube|ninja   lib: e.g. cube_spec  (res://assets/anim/<lib>_lib.res)

const MODEL := {
	"cube": "res://assets/characters/cube/models/Human.fbx",
	"ninja": "res://assets/characters/ninja/fbx/Male_Ninja_02.fbx",
}
const TEX := {
	"cube": "res://assets/characters/cube/textures/Tex_Human_A_Casual_A.png",
	"ninja": "res://assets/characters/ninja/tex/fair_red.png",
}

var out_path := ""
var frames := 0
var players: Array = []
var times: Array = []
var clip := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = a[0]
	var kind: String = a[1]
	var lib_name: String = a[2]
	clip = a[3]
	var n := int(a[4]) if a.size() > 4 else 8
	var view: String = a[5] if a.size() > 5 else "front"
	root.size = Vector2i(1800, 700)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.88, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	root.add_child(sun)
	var lib: AnimationLibrary = load("res://assets/anim/%s_lib.res" % lib_name)
	var clip_len: float = lib.get_animation(clip).length
	var scn: PackedScene = load(MODEL[kind])
	var tex: Texture2D = load(TEX[kind])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var sc := 0.6 if kind == "cube" else 1.0
	var sp := 1.7
	for i in n:
		var holder := Node3D.new()
		holder.position = Vector3((i - (n - 1) * 0.5) * sp, 0, 0)
		holder.scale = Vector3.ONE * sc
		if view == "side":
			holder.rotation_degrees.y = 90
		elif view == "three":
			holder.rotation_degrees.y = 35
		root.add_child(holder)
		var inst: Node3D = scn.instantiate()
		holder.add_child(inst)
		for mi in _meshes(inst):
			mi.material_override = mat
		var info := RigInfoC.new()
		var sk := _find_sk(inst)
		if info.setup(inst, sk, kind):
			info.apply_runtime_scales(sk)
		var ap := AnimationPlayer.new()
		holder.add_child(ap)
		ap.root_node = ap.get_path_to(inst)
		ap.add_animation_library("", lib)
		ap.play(clip)
		ap.seek(clip_len * float(i) / float(n if lib.get_animation(clip).loop_mode != Animation.LOOP_NONE else maxi(n - 1, 1)), true)
		ap.pause()
		players.append(ap)
	var cam := Camera3D.new()
	cam.fov = 32
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.3, 10.5), Vector3(0, 0.9, 0))
	cam.current = true


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 8:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out_path)
		print("saved ", out_path)
		quit()
	return false


const RigInfoC := preload("res://scripts/rig/rig_info.gd")


func _find_sk(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_sk(c)
		if r:
			return r
	return null


func _meshes(n: Node) -> Array:
	var r := []
	if n is MeshInstance3D:
		r.append(n)
	for c in n.get_children():
		r.append_array(_meshes(c))
	return r
