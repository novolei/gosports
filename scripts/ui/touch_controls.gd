class_name TouchControls
extends Control
## On-screen controls for phones / tablets: floating joystick (left), HIT / JUMP / DIVE buttons (right),
## tap on the opponent's half to place the aim marker. Writes into the InputMap actions of player 1.

signal aim_tapped(screen_pos: Vector2)

## the action buttons carry pictograms instead of words (assets/ui/act_<icon>.png); the HIT button's icon follows the
## context (bump / set / spike / serve / block), see Hud._update_timing_ring()
const BTN := {
	"hit": {"r": 118.0, "color": Color(1.0, 0.76, 0.16), "icon": "bump"},
	"jump": {"r": 82.0, "color": Color(0.28, 0.72, 1.0), "icon": "jump"},
	"dive": {"r": 72.0, "color": Color(1.0, 0.42, 0.66), "icon": "dive"},
}
const KIND_ICON := {"bump": "bump", "dig": "bump", "set": "set", "spike": "spike", "serve": "serve", "block": "block"}
static var _icons := {}

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
var hit_kind := "bump"       # what the button will do right now (bump / set / spike / serve / block)
var _pop := 0.0              # icon "pop" when the context changes
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


func set_hit_hint(v: float, kind: String, dt: float) -> void:
	if Game.main != null and Game.main.dev.has("hithint"):
		v = 1.0                                  # dev: pin the pulse for screenshots
		kind = String(Game.main.dev["hithint"]) if Game.main.dev["hithint"] is String else "spike"
	kind = String(KIND_ICON.get(kind, "bump"))
	var nv := move_toward(hit_hint, v, dt * (10.0 if v > hit_hint else 5.0))
	if kind != hit_kind:
		hit_kind = kind
		_pop = 1.0
	if nv != hit_hint or _pop > 0.0:
		hit_hint = nv
		queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	if _pop > 0.0:
		_pop = maxf(_pop - dt * 4.5, 0.0)
	if hit_hint > 0.01 or _pop > 0.0:
		queue_redraw()                       # animated pulse / icon pop
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


static func _icon(n: String) -> Texture2D:
	if not _icons.has(n):
		var path := "res://assets/ui/act_%s.png" % n
		_icons[n] = load(path) if ResourceLoader.exists(path) else null
	return _icons[n]


func _draw() -> void:
	# joystick (only while active, plus a faint resting hint)
	var s := get_viewport_rect().size
	var left_hand: bool = Game.settings.get("left_handed", false)
	if _stick_id >= 0:
		draw_circle(_stick_origin + Vector2(0, 5), 118.0, Color(0, 0, 0, 0.14))
		draw_circle(_stick_origin, 118.0, Color(1, 1, 1, 0.16))
		draw_arc(_stick_origin, 118.0, 0, TAU, 48, Color(1, 1, 1, 0.6), 5.0, true)
		draw_circle(_stick_pos + Vector2(0, 5), 54.0, Color(0, 0, 0, 0.2))
		draw_circle(_stick_pos, 54.0, Color(1, 1, 1, 0.62))
		draw_circle(_stick_pos + Vector2(-14, -16), 26.0, Color(1, 1, 1, 0.35))
	else:
		var hint := Vector2(170, s.y - 200.0) if not left_hand else Vector2(s.x - 170.0, s.y - 200.0)
		draw_arc(hint, 100.0, 0, TAU, 48, Color(1, 1, 1, 0.3), 5.0, true)
		draw_circle(hint, 40.0, Color(1, 1, 1, 0.2))
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var tip: Vector2 = hint + d * 80.0
			var perp := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([tip + d * 12.0, tip + perp * 9.0, tip - perp * 9.0]), Color(1, 1, 1, 0.3))
	for k in BTN.keys():
		var c: Vector2 = _layout[k]
		var r: float = BTN[k]["r"]
		var col: Color = BTN[k]["color"]
		var down: bool = _btn_down.get(k, false)
		var hot: float = hit_hint if k == "hit" else 0.0
		# soft ground shadow
		draw_circle(c + Vector2(0, 16), r * 0.98, Color(0, 0, 0, 0.2))
		if hot > 0.01:
			var pulse := 0.5 + 0.5 * sin(_t * (9.0 + 8.0 * hot))
			draw_circle(c, r + 10.0 + 18.0 * pulse * hot, Color(1.0, 0.95, 0.5, 0.2 * hot))
			draw_arc(c, r + 12.0 + 10.0 * pulse * hot, 0, TAU, 56, Color(1.0, 0.97, 0.6, 0.9 * hot), 6.0, true)
		# a fat "arcade" button: dark base (the visible edge) + a face that sinks when pressed
		draw_circle(c + Vector2(0, 9), r, Color(col.r * 0.55, col.g * 0.5, col.b * 0.6, 0.95))
		var f := c + Vector2(0, 7 if down else 0)
		var fa := 0.97 if down else clampf(0.84 + 0.12 * hot, 0.0, 1.0)
		draw_circle(f, r, Color(col.r, col.g, col.b, fa))
		draw_arc(f, r, 0, TAU, 56, Color(1, 1, 1, 0.95), 5.0, true)                                # flat face + white rim (lightly flat look)
		var tex := _icon(hit_kind if k == "hit" else String(BTN[k]["icon"]))
		if tex != null:
			var sz := r * (1.32 if k == "hit" else 1.3)
			if k == "hit":
				sz *= 1.0 + 0.22 * _pop
			var rect := Rect2(f - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
			draw_texture_rect(tex, Rect2(rect.position + Vector2(3, 5), rect.size), false, Color(0, 0, 0, 0.32))
			draw_texture_rect(tex, rect, false, Color.WHITE)
