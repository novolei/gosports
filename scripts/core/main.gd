extends Node
## Root of the game: owns the current screen and the fade transition.
## Dev flags (after "--"):  --screen=match|menu|select|howto   --autoplay (all-AI demo)   --shot=<png>   --frames=<n>

const SCREENS := {
	"menu": "res://scripts/ui/menu_screen.gd",
	"select": "res://scripts/ui/menu_screen.gd",
	"match": "res://scripts/match/match_scene.gd",
	"results": "res://scripts/ui/results_screen.gd",
	"howto": "res://scripts/ui/menu_screen.gd",
}

var current: Node = null
var current_name := ""
var _fade: ColorRect
var _fade_layer: CanvasLayer
var _busy := false
var dev := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.main = self
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(1, 1, 1, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			dev[kv[0]] = kv[1]
		elif a.begins_with("--"):
			dev[a.substr(2)] = true
	if dev.has("touch"):
		Game.settings["touch"] = "on"
		Game._detect_touch()
	if dev.has("quality"):
		Game.settings["quality"] = int(dev["quality"])
		Game.apply_settings()
	var first: String = dev.get("screen", "menu")
	_show(first, {})
	if dev.has("shot"):
		_capture_and_quit()
	if dev.has("burst"):
		_burst_capture()


func goto(screen: String, data := {}) -> void:
	if _busy:
		return
	_busy = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.22)
	await t.finished
	get_tree().paused = false
	Engine.time_scale = Game.base_time_scale
	_show(screen, data)
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, 0.3)
	await t2.finished
	_busy = false


func _show(screen: String, data: Dictionary) -> void:
	if current:
		current.queue_free()
		current = null
	current_name = screen
	var script: GDScript = load(SCREENS[screen])
	var node: Node = script.new()
	node.name = screen.capitalize()
	add_child(node)
	current = node
	if screen in ["select", "howto"]:
		data = data.duplicate()
		data["page"] = screen
	if node.has_method("setup"):
		node.setup(data)


## dev: --burst=<prefix> --burst_n=8 --burst_every=45 --burst_start=300  (frames; saves prefix_<i>.png then quits)
func _burst_capture() -> void:
	var n := int(dev.get("burst_n", 8))
	var every := int(dev.get("burst_every", 45))
	var start := int(dev.get("burst_start", 300))
	for i in start:
		await get_tree().process_frame
	for k in n:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [dev["burst"], k])
		for i in every:
			await get_tree().process_frame
	print("burst done")
	get_tree().quit()


func _capture_and_quit() -> void:
	var frames := int(dev.get("frames", 60))
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(String(dev["shot"]))
	print("shot saved ", dev["shot"], " ", img.get_size())
	get_tree().quit()
