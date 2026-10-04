extends SceneTree
## Dev tool: build the Arena, put four athletes on court and shoot from the match camera.
## godot --path . -s tools/preview_arena.gd -- out.png [cam_variant]

var out_path := ""
var frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = a[0]
	var variant := int(a[1]) if a.size() > 1 else 0
	root.size = Vector2i(1600, 900)
	var arena := Arena.new()
	root.add_child(arena)
	arena.build(2)
	var all := Roster.all()
	var spots := [Vector3(-1.5, 0, 4.5), Vector3(2.2, 0, 2.2), Vector3(-2.0, 0, -3.0), Vector3(1.8, 0, -4.8)]
	for i in 4:
		var rig := CharacterRig.new()
		root.add_child(rig)
		rig.build(all[[0, 5, 3, 20][i]])
		rig.position = spots[i]
		rig.rotation.y = 0.0 if i < 2 else PI
	var cam := Camera3D.new()
	cam.fov = 52
	root.add_child(cam)
	match variant:
		0: cam.look_at_from_position(Vector3(0, 4.6, 14.2), Vector3(0, 1.1, -2.0))
		1: cam.look_at_from_position(Vector3(0, 7.5, 16.0), Vector3(0, 0.8, -1.0))
		2: cam.look_at_from_position(Vector3(-9, 6.0, 12.0), Vector3(0, 1.0, -1.0))
		_: cam.look_at_from_position(Vector3(0, 30, 2), Vector3(0, 0, 0))
	cam.current = true


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 20:
		root.get_viewport().get_texture().get_image().save_png(out_path)
		print("saved ", out_path)
		quit()
	return false
