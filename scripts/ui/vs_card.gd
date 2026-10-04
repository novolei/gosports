class_name VsCard
extends Control
## Match intro card like the reference game: letterbox bars, a diagonal split between the two teams, a big "VS" and a
## name plate (title + name) under every player. Built over the side-on "VS" camera shot of the real court.

var _bars: Array[ColorRect] = []
var _plates: Array[Control] = []
var _vs: Label
var _tag: Label
var _gone := false


func build(athletes: Array, cam: Camera3D, round_name := "") -> VsCard:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := Vector2(1920, 1080)
	# diagonal tints: team A on the left, team B on the right
	var skew := 150.0
	var left := Polygon2D.new()
	left.polygon = PackedVector2Array([Vector2(0, 0), Vector2(vp.x * 0.5 + skew, 0), Vector2(vp.x * 0.5 - skew, vp.y), Vector2(0, vp.y)])
	left.color = Color(UIKit.BLUE.r, UIKit.BLUE.g, UIKit.BLUE.b, 0.09)
	add_child(left)
	var right := Polygon2D.new()
	right.polygon = PackedVector2Array([Vector2(vp.x * 0.5 + skew, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(vp.x * 0.5 - skew, vp.y)])
	right.color = Color(UIKit.PINK.r, UIKit.PINK.g, UIKit.PINK.b, 0.09)
	add_child(right)
	var split := Polygon2D.new()
	split.polygon = PackedVector2Array([Vector2(vp.x * 0.5 + skew + 3.0, 0), Vector2(vp.x * 0.5 + skew - 3.0, 0), Vector2(vp.x * 0.5 - skew - 3.0, vp.y), Vector2(vp.x * 0.5 - skew + 3.0, vp.y)])
	split.color = Color(0.05, 0.08, 0.15, 0.9)
	add_child(split)
	# letterbox bars
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.size = Vector2(vp.x, 96)
		b.position = Vector2(0, -96.0 if top else vp.y)
		add_child(b)
		_bars.append(b)
		create_tween().tween_property(b, "position:y", 0.0 if top else vp.y - 96.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# name plates
	for a in athletes:
		var sp := cam.unproject_position((a as Node3D).global_position)
		var team: int = a.team
		var col := UIKit.team_color(team)
		var plate := Control.new()
		plate.position = Vector2(sp.x, clampf(sp.y + 26.0 + (22.0 if a.slot == 0 else 0.0), 600.0, 900.0))
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
		var dx := -420.0 if team == 0 else 420.0
		plate.position.x += dx
		add_child(plate)
		_plates.append(plate)
		var tw := plate.create_tween()
		tw.tween_interval(0.35 + 0.1 * float(_plates.size()))
		tw.tween_property(plate, "position:x", plate.position.x - dx, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(plate, "modulate:a", 1.0, 0.2)
	# VS
	_vs = UIKit.label("VS", 250, Color("2fe0c4"), 34, Color.WHITE)
	_vs.position = Vector2(vp.x * 0.5 - 250.0, vp.y * 0.5 - 190.0)
	_vs.size = Vector2(500, 300)
	_vs.pivot_offset = _vs.size * 0.5
	_vs.rotation = deg_to_rad(-5.0)
	_vs.scale = Vector2(2.4, 2.4)
	_vs.modulate.a = 0.0
	add_child(_vs)
	var vt := _vs.create_tween().set_parallel(true)
	vt.tween_interval(0.2)
	vt.chain().tween_property(_vs, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	vt.parallel().tween_property(_vs, "modulate:a", 1.0, 0.12)
	if round_name != "":
		_tag = UIKit.label(round_name, 44, Color.WHITE, 10, Color(0.5, 0.25, 0.0, 0.9))
		_tag.position = Vector2(vp.x * 0.5 - 300.0, vp.y * 0.5 + 100.0)
		_tag.size = Vector2(600, 60)
		add_child(_tag)
	Sfx.play("ui_swoosh", -3.0)
	return self


## slides the card away (bars retreat, plates fade)
func dismiss() -> void:
	if _gone:
		return
	_gone = true
	var vp := Vector2(1920, 1080)
	for i in _bars.size():
		create_tween().tween_property(_bars[i], "position:y", -96.0 if i == 0 else vp.y, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(queue_free)
