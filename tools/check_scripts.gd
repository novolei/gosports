extends SceneTree
## Dev tool: load (= parse/compile) every GDScript of the game and report errors.
## godot --headless --path . -s tools/check_scripts.gd

func _initialize() -> void:
	var bad := 0
	var total := 0
	for dir in ["res://scripts", "res://tools"]:
		for p in _gd_files(dir):
			total += 1
			var s = load(p)
			# a script with a parse error can still come back as a resource: it then can not be instantiated
			if s == null or (s is GDScript and not (s as GDScript).can_instantiate()):
				print("FAILED: ", p)
				bad += 1
	print("checked ", total, " scripts, failed: ", bad)
	quit(1 if bad > 0 else 0)


func _gd_files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			if not n.begins_with("."):
				out.append_array(_gd_files(dir + "/" + n))
		elif n.ends_with(".gd"):
			out.append(dir + "/" + n)
		n = d.get_next()
	return out
