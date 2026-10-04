class_name TouchControls
extends Control
## On-screen controls for phones / tablets: floating joystick (left), HIT / JUMP / DIVE buttons (right),
## tap on the opponent's half to place the aim marker. Writes into the InputMap actions of player 1.

signal aim_tapped(screen_pos: Vector2)

const BTN := {
	"hit": {"r": 118.0, "color": Color(1.0, 0.82, 0.2), "label": "击球"},
	"jump": {"r": 82.0, "color": Color(0.35, 0.8, 1.0), "label": "跳"},
	"dive": {"r": 72.0, "color": Color(1.0, 0.5, 0.7), "label": "扑"},
}

var player := 1
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _btn_touch := {}        # touch index -> button name
var _btn_down := {}         # button name -> bool
var _btn_release_at := {}   # button name -> msec when it may be released
var _aim_id := -1
var _layout := {}
var hit_hint := 0.0          # 0..1: the ball is about to be in reach -> the HIT button pulses
var hit_text := "击球"        # what the button will do right now (bump / set / spike / serve)
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	Game.settings_changed.connect(_relayout)


func _relayout() -> void:
	var s := get_viewport_rect().size
	var left_hand: bool = Game.settings.get("left_handed", false)
	var flip := -1.0 if left_hand else 1.0
	var inset: Dictionary = Game.safe_insets()
	var bx := s.x - 250.0 - float(inset["r"]) if not left_hand else 250.0 + float(inset["l"])
	var by := s.y - float(inset["b"])
	_layout = {
		"hit": Vector2(bx, by - 230.0),
		"jump": Vector2(bx - 215.0 * flip, by - 150.0),
		"dive": Vector2(bx - 120.0 * flip, by - 395.0),
	}
	queue_redraw()


func _in_btn(p: Vector2) -> String:
	for k in BTN.keys():
		var c: Vector2 = _layout[k]
		if p.distance_to(c) <= float(BTN[k]["r"]) * 1.12:
			return k
	return ""


func _stick_zone(p: Vector2) -> bool:
	var s := get_viewport_rect().size
	var left_hand: bool = Game.settings.get("left_handed", false)
	var zone_x := p.x < s.x * 0.42 if not left_hand else p.x > s.x * 0.58
	return zone_x and p.y > s.y * 0.38


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_on_down(e.index, e.position)
		else:
			_on_up(e.index, e.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_on_drag(d.index, d.position)


func _on_down(idx: int, p: Vector2) -> void:
	var b := _in_btn(p)
	if b != "":
		_btn_touch[idx] = b
		_press(b)
		return
	if _stick_id < 0 and _stick_zone(p):
		_stick_id = idx
		_stick_origin = p
		_stick_pos = p
		queue_redraw()
		return
	# tap in the field = aim marker
	var s := get_viewport_rect().size
	if p.y < s.y * 0.72 and p.x > s.x * 0.12 and p.x < s.x * 0.88:
		aim_tapped.emit(p)


func _on_up(idx: int, p: Vector2) -> void:
	if idx == _stick_id:
		_stick_id = -1
		_set_stick(Vector2.ZERO)
		queue_redraw()
	if _btn_touch.has(idx):
		var b: String = _btn_touch[idx]
		_btn_touch.erase(idx)
		_btn_release_at[b] = Time.get_ticks_msec() + 90
		queue_redraw()


func _on_drag(idx: int, p: Vector2) -> void:
	if idx == _stick_id:
		var v := p - _stick_origin
		var r := 110.0
		if v.length() > r:
			# the base follows the thumb a little (floating stick)
			_stick_origin += v.normalized() * (v.length() - r)
			v = v.limit_length(r)
		_stick_pos = _stick_origin + v
		_set_stick(v / r)
		queue_redraw()


func _set_stick(v: Vector2) -> void:
	var p := "p%d_" % player
	var dead := 0.12
	var x := v.x if absf(v.x) > dead else 0.0
	var y := v.y if absf(v.y) > dead else 0.0
	_axis(p + "left", p + "right", x)
	_axis(p + "up", p + "down", y)


func _axis(neg: String, pos: String, v: float) -> void:
	if v < 0.0:
		Input.action_press(neg, minf(1.0, -v * 1.15))
		Input.action_release(pos)
	elif v > 0.0:
		Input.action_press(pos, minf(1.0, v * 1.15))
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _press(b: String) -> void:
	_btn_down[b] = true
	_btn_release_at.erase(b)
	Input.action_press("p%d_%s" % [player, b])
	queue_redraw()


func set_hit_hint(v: float, text: String, dt: float) -> void:
	if Game.main != null and Game.main.dev.has("hithint"):
		v = 1.0                                  # dev: pin the pulse for screenshots
		text = "扣球"
	var nv := move_toward(hit_hint, v, dt * (10.0 if v > hit_hint else 5.0))
	if nv != hit_hint or text != hit_text:
		hit_hint = nv
		hit_text = text
		queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	if hit_hint > 0.01:
		queue_redraw()                       # animated pulse
	var now := Time.get_ticks_msec()
	for b in _btn_release_at.keys():
		if now >= _btn_release_at[b]:
			_btn_release_at.erase(b)
			_btn_down[b] = false
			Input.action_release("p%d_%s" % [player, b])
			queue_redraw()


func _exit_tree() -> void:
	for d in ["left", "right", "up", "down", "hit", "jump", "dive"]:
		Input.action_release("p%d_%s" % [player, d])


func _draw() -> void:
	# joystick (only while active, plus a faint resting hint)
	var s := get_viewport_rect().size
	var left_hand: bool = Game.settings.get("left_handed", false)
	if _stick_id >= 0:
		draw_circle(_stick_origin, 118.0, Color(1, 1, 1, 0.16))
		draw_arc(_stick_origin, 118.0, 0, TAU, 48, Color(1, 1, 1, 0.55), 4.0, true)
		draw_circle(_stick_pos, 54.0, Color(1, 1, 1, 0.55))
	else:
		var hint := Vector2(170, s.y - 200.0) if not left_hand else Vector2(s.x - 170.0, s.y - 200.0)
		draw_arc(hint, 100.0, 0, TAU, 48, Color(1, 1, 1, 0.28), 4.0, true)
		draw_circle(hint, 40.0, Color(1, 1, 1, 0.18))
	var font := ThemeDB.fallback_font
	if get_theme_default_font():
		font = get_theme_default_font()
	for k in BTN.keys():
		var c: Vector2 = _layout[k]
		var r: float = BTN[k]["r"]
		var col: Color = BTN[k]["color"]
		var down: bool = _btn_down.get(k, false)
		draw_circle(c + Vector2(0, 6), r, Color(0, 0, 0, 0.25))
		if k == "hit" and hit_hint > 0.01:
			var pulse := 0.5 + 0.5 * sin(_t * (9.0 + 8.0 * hit_hint))
			draw_circle(c, r + 8.0 + 16.0 * pulse * hit_hint, Color(1.0, 0.95, 0.5, 0.22 * hit_hint))
			draw_arc(c, r + 10.0 + 10.0 * pulse * hit_hint, 0, TAU, 56, Color(1.0, 0.97, 0.6, 0.9 * hit_hint), 6.0, true)
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.9 if down else (0.55 + 0.3 * (hit_hint if k == "hit" else 0.0))))
		draw_arc(c, r, 0, TAU, 56, Color(1, 1, 1, 0.9), 5.0, true)
		var fs := 40 if k == "hit" else 32
		var text: String = hit_text if k == "hit" else BTN[k]["label"]
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-sz.x * 0.5, sz.y * 0.28), text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1))
