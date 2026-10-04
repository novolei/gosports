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
	if dev.has("timingwin"):                                    # dev: --timingwin=0|1|2 (relaxed / standard / precise) for this run
		Game.settings["timing_window"] = clampi(int(dev["timingwin"]), 0, 2)
	if dev.has("music") or dev.has("sfx"):                      # dev (promo recording): --music=0 --sfx=0.9 override the saved volumes for this run
		if dev.has("music"):
			Game.settings["music"] = float(dev["music"])
		if dev.has("sfx"):
			Game.settings["sfx"] = float(dev["sfx"])
		Game.apply_settings()
	if dev.has("lang"):
		Loc.apply(String(dev["lang"]))
	var first: String = dev.get("screen", "menu")
	if not (dev.has("shot") or dev.has("burst") or dev.has("autoplay") or dev.has("humanbot") or dev.has("noloading")):
		# continue from the boot splash: start covered by its solid colour (== boot_splash/bg_color) and let the first screen emerge from it
		_fade.color = Color(0.1137, 0.7294, 0.8039, 1.0)
		var t0 := create_tween()
		t0.tween_interval(0.15)
		t0.tween_property(_fade, "color:a", 0.0, 0.55)
	if dev.has("audit"):
		_audit_after(int(dev["audit"]))
	if dev.has("fontscan"):
		_fontscan_after(int(dev["fontscan"]))
	_show(first, {})
	if dev.has("shot"):
		_capture_and_quit()
	if dev.has("burst"):
		_burst_capture()


## dev: --lang=en --audit=<frames>  prints every Control text that still contains Chinese after translation, then quits
func _audit_after(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	var cjk := RegEx.new()
	cjk.compile("[\u4e00-\u9fff]")
	var seen := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var t := ""
		if n is Label or n is Button or n is RichTextLabel:
			t = String(n.get("text"))
		if t != "" and cjk.search(TranslationServer.translate(t)) != null and not seen.has(t):
			seen[t] = true
			print("[audit] ", TranslationServer.translate(t).replace("
", " | "))
	print("[audit] done, leftovers=", seen.size())
	get_tree().quit()


## dev: --fontscan=<frames>  lists every text control whose resolved font is NOT one of the game's own (Fonts.body / display /
## display_italic) or that holds Chinese text without a font that can draw it, then quits
func _fontscan_after(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	var ours: Array = [Fonts.body(), Fonts.display(), Fonts.display_italic()]
	var cjk := RegEx.new()
	cjk.compile("[一-鿿]")
	var bad := 0
	var total := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var f: Font = null
		var t := ""
		var kind := ""
		if n is Label or n is Button:
			f = (n as Control).get_theme_font("font")
			t = String(n.get("text"))
			kind = n.get_class()
		elif n is RichTextLabel:
			f = (n as Control).get_theme_font("normal_font")
			t = String(n.get("text"))
			kind = "RichTextLabel"
		elif n is Label3D:
			f = (n as Label3D).font
			t = String(n.get("text"))
			kind = "Label3D"
		else:
			continue
		if t == "":
			continue
		total += 1
		var tt := TranslationServer.translate(t)
		var is_ours := ours.has(f)
		var draws_cjk := f != null and cjk.search(tt) != null and f.has_char(0x4e2d) or (f != null and ours.has(f))
		if not is_ours or (cjk.search(tt) != null and not draws_cjk):
			bad += 1
			print("[fontscan] ", kind, " font=", (f.get_font_name() if f != null else "null"), " (", f, ") text='", tt.substr(0, 30).replace("
", " "), "' path=", n.get_path())
	print("[fontscan] done: ", total, " text nodes, ", bad, " not using the game fonts")
	get_tree().quit()


func goto(screen: String, data := {}) -> void:
	if _busy:
		return
	_busy = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.22)
	await t.finished
	get_tree().paused = false
	Engine.time_scale = Game.base_time_scale
	var card: LoadingCard = null
	var t_card := Time.get_ticks_msec()
	if screen == "match" and not dev.has("noloading") and not dev.has("autoplay") and not dev.has("shot") and not dev.has("burst"):
		card = LoadingCard.new().build()
		_fade_layer.add_child(card)
		card.modulate.a = 0.0
		var tw_card := create_tween()
		tw_card.tween_property(card, "modulate:a", 1.0, 0.18)
		await tw_card.finished
		_fade.color.a = 0.0                  # the card covers the screen now
		if dev.has("loadshot"):
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png(str(dev["loadshot"]))
			get_tree().quit()
	_show(screen, data)
	if card != null:
		var left := 1.5 - float(Time.get_ticks_msec() - t_card) / 1000.0      # keep the tip readable for a moment
		if left > 0.0:
			await get_tree().create_timer(left).timeout
		var tc := create_tween()
		tc.tween_property(card, "modulate:a", 0.0, 0.3)
		await tc.finished
		card.queue_free()
	else:
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
