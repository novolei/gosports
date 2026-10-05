class_name TouchTuner
extends Control
## An on-device tuning panel for the touch feel: pick a number (`<` `>`), change it (`-` `+`, hold to repeat), watch a live read-out, and
## `Copy` the changed numbers (clipboard + log + user://touch_tune_last.txt) - a player reports numbers instead of "it feels floaty".
## Changes apply at once and are saved to user://touch_tune.json (re-applied at the next start; `Reset` removes them).
## Open it with three fingers held still for 2 s (hidden gesture, any build; `TouchFeel.tuner_gesture`), with the small "T" chip
## (debug builds on a touch device, or `--touch-tune`). Only reads input (never eats an event); idle = one node, no _process.
## The owner supplies `relayout` (re-place the controls after a size change) and `readout` (a String about the live state), and keeps
## `rect()` in the router's `reserved` list while the panel is open so the panel's own touches do not steer the player.
## Sport-agnostic (candidate for the shared core, see docs/CORE_PROPOSAL_TOUCH.md).

signal toggled(open: bool)

const ARG := "--touch-tune"
const HOLD_SECONDS := 2.0
const STILL_MM := 4.0                    ## "held still": each finger stays within this of where it landed
const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.09

var feel: TouchFeel = TouchFeel.shared()
var relayout: Callable = Callable()      ## () -> void
var readout: Callable = Callable()       ## () -> String
var show_chip: bool = false
var mm_per_px: float = 0.0644            ## the owner updates it (button sizes are physical)
var _vp: Vector2 = Vector2(1920, 1080)   ## canvas size (the owner calls layout())

var _index: int = 0
var _panel: PanelContainer
var _name_label: Label
var _value_label: Label
var _info: Label
var _chip: Button
var _touches: Dictionary = {}            ## finger -> landing point
var _moved: bool = false
var _hold: float = 0.0
var _hold_dir: int = 0
var _hold_time: float = 0.0
var _info_time: float = 0.0
var _minus: Button
var _plus: Button


static func wanted() -> bool:
	return ARG in OS.get_cmdline_user_args()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS               # the pause menu pauses the tree: the panel keeps working
	if show_chip or wanted():
		_build_chip()
	set_process(false)


## place the chip and the panel at the top centre of a canvas of this size (explicit positions: no anchor surprises)
func layout(canvas: Vector2) -> void:
	_vp = canvas
	if _chip != null:
		_chip.position = Vector2(canvas.x * 0.5 - 40.0, 70.0)
	if _panel != null:
		_panel.position = Vector2(canvas.x * 0.5 - 430.0, 140.0)


func rect() -> Rect2:
	return _panel.get_global_rect() if _panel != null and _panel.visible else Rect2()


func chip_rect() -> Rect2:
	return _chip.get_global_rect() if _chip != null else Rect2()


func is_open() -> bool:
	return _panel != null and _panel.visible


func toggle() -> void:
	if _panel == null:
		_build_panel()
		_panel.visible = true
	else:
		_panel.visible = not _panel.visible
	_refresh()
	_sync_process()
	toggled.emit(_panel.visible)


func _btn(text: String, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.24, 0.42, 0.78, 0.95) if state != "pressed" else Color(0.4, 0.62, 1.0, 1.0)
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.6)
		b.add_theme_stylebox_override(state, sb)
	return b


func _lbl(text: String, size := 24) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _build_chip() -> void:
	_chip = _btn("T", Vector2(80, 60))
	_chip.size = Vector2(80, 60)
	_chip.pressed.connect(toggle)
	add_child(_chip)
	layout(_vp)


func _build_panel() -> void:
	var unit := 1.0 / maxf(mm_per_px, 0.01)                                    # px per mm
	var bs := Vector2(9.0 * unit, 8.0 * unit)                                  # >= 9 x 8 mm: easy to hit
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.07, 0.16, 0.9)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(860, 0)
	add_child(_panel)
	layout(_vp)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_panel.add_child(rows)
	var head := HBoxContainer.new()
	rows.add_child(head)
	var title := _lbl("TOUCH TUNE   (Copy, then paste the numbers back)")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _btn("x", bs * Vector2(0.7, 0.8))
	close.pressed.connect(toggle)
	head.add_child(close)
	var pick := HBoxContainer.new()
	rows.add_child(pick)
	var prev := _btn("<", bs)
	prev.pressed.connect(_step_index.bind(-1))
	pick.add_child(prev)
	_name_label = _lbl("")
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick.add_child(_name_label)
	var next := _btn(">", bs)
	next.pressed.connect(_step_index.bind(1))
	pick.add_child(next)
	var val := HBoxContainer.new()
	rows.add_child(val)
	_minus = _btn("-", bs)
	_minus.button_down.connect(_press_step.bind(-1))
	val.add_child(_minus)
	_value_label = _lbl("", 30)
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_child(_value_label)
	_plus = _btn("+", bs)
	_plus.button_down.connect(_press_step.bind(1))
	val.add_child(_plus)
	_info = _lbl("", 20)
	rows.add_child(_info)
	var foot := HBoxContainer.new()
	rows.add_child(foot)
	for item: Array in [["Copy", _copy], ["Reset", _reset]]:
		var b := _btn(str(item[0]), Vector2(bs.x * 1.6, bs.y * 0.9))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(item[1])
		foot.add_child(b)


## three fingers held still for HOLD_SECONDS toggle the panel (only observes)
func _input(event: InputEvent) -> void:
	if not feel.tuner_gesture and not wanted():
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		if _touches.size() < 3:
			_hold = 0.0
			_moved = false
		_sync_process()
	elif event is InputEventScreenDrag and _touches.has((event as InputEventScreenDrag).index):
		var drag := event as InputEventScreenDrag
		if (drag.position - (_touches[drag.index] as Vector2)).length() * mm_per_px > STILL_MM:
			_moved = true


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)
	if _touches.size() >= 3 and not _moved:
		_hold += real
		if _hold >= HOLD_SECONDS:
			_hold = -1000.0                                 # not again before the fingers lift
			toggle()
	if _hold_dir != 0:
		if not (_minus.button_pressed or _plus.button_pressed):
			_hold_dir = 0
		else:
			_hold_time += real
			if _hold_time >= REPEAT_DELAY + REPEAT_EVERY:
				_hold_time -= REPEAT_EVERY
				_bump(_hold_dir)
	_info_time += real
	if is_open() and _info_time >= 0.1:
		_info_time = 0.0
		_info.text = _info_text()
	if not is_open() and _touches.size() < 3:
		set_process(false)


func _sync_process() -> void:
	set_process(is_open() or _touches.size() >= 3)


func _step_index(d: int) -> void:
	_index = posmod(_index + d, TouchFeel.rows().size())
	_refresh()


func _press_step(d: int) -> void:
	_hold_dir = d
	_hold_time = 0.0
	_bump(d)
	_sync_process()


func _bump(d: int) -> void:
	var row: Array = TouchFeel.rows()[_index]
	var step: float = row[2]
	var v := clampf(snappedf(float(feel.get(row[0])) + float(d) * step, step * 0.5), float(row[3]), float(row[4]))
	feel.apply({row[0]: v})
	feel.save()
	if bool(row[6]) and relayout.is_valid():
		relayout.call()
	_refresh()


func _refresh() -> void:
	if _chip != null:
		_chip.text = "T*" if not feel.changed(TouchFeel.pristine()).is_empty() else "T"
	if _name_label == null:
		return
	var row: Array = TouchFeel.rows()[_index]
	var cur := float(feel.get(row[0]))
	var base := float(TouchFeel.pristine().get(row[0], cur))
	_name_label.text = "%d/%d   %s" % [_index + 1, TouchFeel.rows().size(), row[1]]
	_value_label.text = "%s %s%s" % [str(snappedf(cur, 0.001)), row[5], "" if absf(cur - base) < 0.00001 else "     (default %s)" % str(base)]
	_info.text = _info_text()


func _info_text() -> String:
	var extra := String(readout.call()) if readout.is_valid() else ""
	return "dpi %.1f (%s)   %.4f mm/px\n%s" % [TouchMetrics.dpi(), TouchMetrics.last_source, mm_per_px, extra]


func _copy() -> void:
	var text := "TOUCH_TUNE %s\n%s" % [OS.get_model_name(), feel.report(_info_text())]
	DisplayServer.clipboard_set(text)
	print(text)
	var f := FileAccess.open("user://touch_tune_last.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
	_info.text = "copied (clipboard + log + user://touch_tune_last.txt)"


func _reset() -> void:
	feel.reset_all()
	if relayout.is_valid():
		relayout.call()
	_refresh()
