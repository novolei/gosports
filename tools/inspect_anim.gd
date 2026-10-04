extends SceneTree
## Dev tool: summarise animations inside imported FBX files (track targets, lengths).
## Usage: godot --headless --path . -s tools/inspect_anim.gd -- res://a.fbx [res://b.fbx ...]

func _initialize() -> void:
	for p in OS.get_cmdline_user_args():
		_inspect(p)
	quit()


func _inspect(path: String) -> void:
	print("=================== ", path)
	var res = load(path)
	if res == null:
		print("  !! cannot load")
		return
	var root: Node = res.instantiate()
	var ap := _find(root, "AnimationPlayer") as AnimationPlayer
	var sk := _find(root, "Skeleton3D") as Skeleton3D
	if sk:
		print("skeleton bones=", sk.get_bone_count(), " path=", root.get_path_to(sk))
	if ap:
		for n in ap.get_animation_list():
			var a := ap.get_animation(n)
			var kinds := {}
			for t in a.get_track_count():
				var k := str(a.track_get_type(t))
				kinds[k] = int(kinds.get(k, 0)) + 1
			print("  anim '%s' len=%.2f tracks=%d kinds=%s loop=%d" % [n, a.length, a.get_track_count(), str(kinds), a.loop_mode])
			if a.get_track_count() > 0:
				var shown := 0
				for t in a.get_track_count():
					var tp := str(a.track_get_path(t))
					if tp.to_lower().contains("hips") or tp.to_lower().contains("upper_arm.l") or shown < 2:
						print("      track ", t, ": ", tp, " keys=", a.track_get_key_count(t))
						shown += 1
					if shown > 5:
						break
	root.free()


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
