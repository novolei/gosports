class_name ReplayOverlay
extends Control
## HUD layer of the instant replay: a diagonal teal wipe that covers the cut, the "Replay" label with a thin progress
## line (top left) and the skip prompt (bottom right).

var _wipe: Control
var _label: Label
var _line: Control
var _skip: Control
var _progress := 0.0
var _w := 1920.0
var _h := 1080.0
const SKEW := 260.0


class _Progress:
	extends Control
	var u := 0.0

	func _draw() -> void:
		draw_line(Vector2(0, 4), Vector2(size.x, 4), Color(1, 1, 1, 0.35), 4.0, true)
		draw_line(Vector2(0, 4), Vector2(size.x * u, 4), Color.WHITE, 4.0, true)
		draw_circle(Vector2(size.x * u, 4), 7.0, Color.WHITE)


func build(vp := Vector2(1920, 1080)) -> ReplayOverlay:
	_w = vp.x
	_h = vp.y
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset: Dictionary = Game.safe_insets()
	_label = UIKit.label("回放", 42, Color.WHITE, 10, Color(0.05, 0.12, 0.3, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_label.position = Vector2(46.0 + float(inset["l"]), 28.0 + float(inset["t"]))
	_label.size = Vector2(300, 56)
	_label.visible = false
	add_child(_label)
	_line = _Progress.new()
	_line.position = Vector2(50.0 + float(inset["l"]), 88.0 + float(inset["t"]))
	_line.size = Vector2(380, 10)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.visible = false
	add_child(_line)
	_skip = Panel.new()
	_skip.size = Vector2(330, 56)
	_skip.position = Vector2(_w - 330.0 - 40.0 - float(inset["r"]), _h - 56.0 - 34.0 - float(inset["b"]))
	_skip.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.05, 0.12, 0.3, 0.55), 28, 2, Color(1, 1, 1, 0.8), 6))
	_skip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint := "轻触跳过" if Game.is_touch else "按任意键跳过"
	var sl := UIKit.label(hint, 28, Color.WHITE, 6, Color(0.05, 0.1, 0.25, 0.9))
	sl.size = _skip.size
	_skip.add_child(sl)
	_skip.visible = false
	add_child(_skip)
	# wipe: two parallelograms (white leading edge, teal body)
	_wipe = Control.new()
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.visible = false
	add_child(_wipe)
	var x := _w + 2.0 * SKEW
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(SKEW, 0), Vector2(x + SKEW, 0), Vector2(x, _h), Vector2(0, _h)])
	body.color = Color("2fc7b0")
	_wipe.add_child(body)
	var edge := Polygon2D.new()
	edge.polygon = PackedVector2Array([Vector2(x + SKEW, 0), Vector2(x + SKEW + 90.0, 0), Vector2(x + 90.0, _h), Vector2(x, _h)])
	edge.color = Color(1, 1, 1, 0.95)
	_wipe.add_child(edge)
	return self


func _tween() -> Tween:
	var t := create_tween()
	t.set_ignore_time_scale(true)
	return t


## wipe in: returns when the whole screen is covered
func cover() -> void:
	Sfx.play("ui_swoosh", -3.0)
	_wipe.visible = true
	_wipe.position = Vector2(-(_w + 3.0 * SKEW + 200.0), 0)
	var t := _tween()
	t.tween_property(_wipe, "position:x", -SKEW, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished


## wipe out (does not block)
func reveal() -> void:
	var t := _tween()
	t.tween_property(_wipe, "position:x", _w + 80.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): _wipe.visible = false)


func begin() -> void:
	_label.visible = true
	_line.visible = true
	_skip.visible = true
	set_progress(0.0)


func end() -> void:
	_label.visible = false
	_line.visible = false
	_skip.visible = false


func set_progress(u: float) -> void:
	(_line as _Progress).u = u
	_line.queue_redraw()
