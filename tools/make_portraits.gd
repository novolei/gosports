extends SceneTree
## Renders a round-friendly head-and-shoulders portrait of every roster character into res://assets/portraits/<id>.png
## godot --path . -s tools/make_portraits.gd   (needs a real renderer, i.e. not --headless)

var vp: SubViewport
var rig: CharacterRig
var cam: Camera3D
var idx := 0
var list: Array[Dictionary] = []
var wait := 0


func _initialize() -> void:
	list = Roster.all()
	DirAccess.make_dir_recursive_absolute("res://assets/portraits")
	vp = SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 1.0)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.9)
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	cam.current = true
	_next()


func _next() -> void:
	if rig:
		rig.queue_free()
	if idx >= list.size():
		print("portraits done")
		quit()
		return
	rig = CharacterRig.new()
	vp.add_child(rig)
	rig.build(list[idx])
	rig.rotation.y = PI + deg_to_rad(-16)
	rig.anim.stop()
	rig.skeleton.reset_bone_poses()
	wait = 0


func _process(_dt: float) -> bool:
	if rig == null:
		return false
	wait += 1
	if wait == 4:
		# frame on the head
		var hp := rig.head_world()
		var center := hp + Vector3(0, 0.24, 0)
		cam.look_at_from_position(center + Vector3(0.0, 0.04, 1.55), center)
	if wait == 9:
		var img := vp.get_texture().get_image()
		img.save_png("res://assets/portraits/%s.png" % list[idx]["id"])
		idx += 1
		_next()
	return false
