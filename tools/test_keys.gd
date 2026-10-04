extends SceneTree
## Dev test for the key rebinding (run: godot --headless --path . -s tools/test_keys.gd). Does not touch the real settings file.

var fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)


var _ran := false


func _process(_dt: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var g = root.get_node("Game")
	g.key_overrides.clear()
	check(g.key_name("p1_hit") == "J", "default hit key is J (got %s)" % g.key_name("p1_hit"))
	var swapped: String = g.set_key("p1_hit", KEY_F)
	check(swapped == "" and g.key_name("p1_hit") == "F", "hit -> F")
	# binding a key already used by another action swaps the two
	swapped = g.set_key("p1_jump", KEY_F)
	check(swapped == "p1_hit", "swap reported (%s)" % swapped)
	check(g.key_name("p1_jump") == "F" and g.key_name("p1_hit") == "K", "swap result jump=%s hit=%s" % [g.key_name("p1_jump"), g.key_name("p1_hit")])
	# the mouse buttons stay bound
	var has_mouse := false
	for e in InputMap.action_get_events("p1_hit"):
		if e is InputEventMouseButton:
			has_mouse = true
	check(has_mouse, "mouse button survives rebinding")
	g.reset_keys()
	check(g.key_name("p1_hit") == "J" and g.key_name("p1_jump") == "K" and g.key_name("p1_dive") == "L", "reset restores defaults")
	check(g.key_overrides.is_empty(), "no overrides after reset")
	print("KEYS TEST ", "OK" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails > 0 else 0)
