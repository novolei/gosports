extends SceneTree
## Dev tool: print properties / methods of engine classes (godot --headless -s tools/inspect_classes.gd -- ClassA ClassB)

func _initialize() -> void:
	for c in OS.get_cmdline_user_args():
		print("=== ", c)
		for p in ClassDB.class_get_property_list(c, true):
			print("  prop ", p["name"], " : ", p["type"], " hint=", p.get("hint_string", ""))
		for m in ClassDB.class_get_method_list(c, true):
			var args := []
			for a in m["args"]:
				args.append(a["name"])
			print("  func ", m["name"], "(", ", ".join(args), ")")
	quit()
