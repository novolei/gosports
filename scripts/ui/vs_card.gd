class_name VsCard
extends Control
## Match intro card like the reference game: letterbox bars, a diagonal split between the two teams, a big "VS" and a
## name plate (title + name) under every player. Built over the side-on "VS" camera shot of the real court.

var _bars: Array[ColorRect] = []
var _plates: Array[Control] = []
var _vs: Label
var _tag: Label
var _gone := false
var _vp := Vector2(1920, 1080)
var _cam: Camera3D
var _plate_of: Array = []


func build(athletes: Array, cam: Camera3D, round_name := "", vp := Vector2(1920, 1080)) -> VsCard:
	_vp = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# "LIVE" bug (broadcast feel)
	var live := Panel.new()
	live.size = Vector2(122, 46)
	live.position = Vector2(54.0, 96.0 + 26.0)
	live.add_theme_stylebox_override("panel", UIKit.style_box(Color("e5384f"), 12, 3, Color.WHITE, 4))
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(live)
	var ldot := Panel.new()
	ldot.position = Vector2(14, 15)
	ldot.size = Vector2(16, 16)
	ldot.add_theme_stylebox_override("panel", UIKit.style_box(Color.WHITE, 8))
	ldot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.add_child(ldot)
	var blink := ldot.create_tween().set_loops()
	blink.tween_property(ldot, "modulate:a", 0.25, 0.55)
	blink.tween_property(ldot, "modulate:a", 1.0, 0.55)
	var ll := UIKit.label("LIVE", 28, Color.WHITE)
	ll.position = Vector2(34, 0)
	ll.size = Vector2(82, 46)
	live.add_child(ll)
	# letterbox bars
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.size = Vector2(vp.x, 96)
		b.position = Vector2(0, -96.0 if top else vp.y)
		add_child(b)
		_bars.append(b)
		create_tween().tween_property(b, "position:y", 0.0 if top else vp.y - 96.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# name plates (UI-style capsules) under every player; they follow their player while the camera orbits
	_cam = cam
	for a in athletes:
		var team: int = a.team
		var col := UIKit.team_color(team)
		var plate := Control.new()
		var perk := Roster.perk_info(String(a.perk))
		var title := UIKit.label(String(perk["name"]) if perk["name"] != "" else "新秀", 28, col.lightened(0.35), 8, col.darkened(0.55))
		title.position = Vector2(-120, -4)
		title.size = Vector2(240, 38)
		plate.add_child(title)
		var bar := Panel.new()
		bar.position = Vector2(-110, 34)
		bar.size = Vector2(220, 50)
		bar.add_theme_stylebox_override("panel", UIKit.style_box(col, 25, 4, Color.WHITE, 8))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(bar)
		var nm := UIKit.label(String(a.display_name), 38, Color.WHITE, 8, col.darkened(0.5))
		nm.size = bar.size
		bar.add_child(nm)
		plate.modulate.a = 0.0
		add_child(plate)
		_plates.append(plate)
		_plate_of.append({"plate": plate, "who": a})
		# the opponents are introduced first, our pair fades in as the camera arrives
		var delay := (0.35 + 0.12 * float(a.slot)) if team == 1 else (2.2 + 0.12 * float(a.slot))
		var tw := plate.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(plate, "modulate:a", 1.0, 0.25)
		plate.pivot_offset = Vector2(0, 50)
		plate.scale = Vector2(0.7, 0.7)
		tw.parallel().tween_property(plate, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# VS
	_vs = UIKit.label("VS", 210, Color("2fe0c4"), 34, Color.WHITE)
	_vs.position = Vector2(vp.x * 0.5 - 250.0, vp.y * 0.5 - 330.0)
	_vs.size = Vector2(500, 300)
	_vs.pivot_offset = _vs.size * 0.5
	_vs.rotation = deg_to_rad(-5.0)
	_vs.scale = Vector2(2.4, 2.4)
	_vs.modulate.a = 0.0
	add_child(_vs)
	var vt := _vs.create_tween().set_parallel(true)
	vt.tween_interval(1.5)
	vt.chain().tween_property(_vs, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	vt.parallel().tween_property(_vs, "modulate:a", 1.0, 0.12)
	if round_name != "":
		_tag = UIKit.label(round_name, 44, Color.WHITE, 10, Color(0.5, 0.25, 0.0, 0.9))
		_tag.position = Vector2(vp.x * 0.5 - 300.0, vp.y * 0.5 + 100.0)
		_tag.size = Vector2(600, 60)
		add_child(_tag)
	# "press any key to skip" chip above the bottom bar
	var chip := Panel.new()
	chip.size = Vector2(330, 56)
	chip.position = Vector2(vp.x - 330.0 - 40.0, vp.y - 96.0 - 76.0)
	chip.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.05, 0.12, 0.3, 0.55), 28, 2, Color(1, 1, 1, 0.8), 6))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := UIKit.label("轻触跳过" if Game.is_touch else "按任意键跳过", 28, Color.WHITE, 6, Color(0.05, 0.1, 0.25, 0.9))
	cl.size = chip.size
	chip.add_child(cl)
	add_child(chip)
	Sfx.play("ui_swoosh", -3.0)
	return self


func _process(_dt: float) -> void:
	if _cam == null or _gone:
		return
	for e in _plate_of:
		var who: Node3D = e["who"]
		var pl: Control = e["plate"]
		var wp := who.global_position
		if _cam.is_position_behind(wp):
			pl.visible = false
			continue
		var sp := _cam.unproject_position(wp)
		# a plate lives only while its player is comfortably in frame (no piles of capsules on the screen edge)
		var edge := minf(sp.x - 130.0, _vp.x - 130.0 - sp.x)
		pl.visible = edge > -60.0
		pl.position = Vector2(sp.x, clampf(sp.y + 14.0, 240.0, _vp.y - 200.0))


## slides the card away (bars retreat, plates fade)
func dismiss() -> void:
	if _gone:
		return
	_gone = true
	var vp := _vp
	for i in _bars.size():
		create_tween().tween_property(_bars[i], "position:y", -96.0 if i == 0 else vp.y, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(queue_free)
