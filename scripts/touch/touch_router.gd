class_name TouchRouter
extends RefCounted
## Routes raw touch events to one movement stick and a set of round action buttons (multi-touch). No node, no drawing, no game
## class: the owner feeds it events (`handle`) and a clock tick (`tick`), places the stick zone and the buttons (px), and listens to
## the signals. Rules (learned the hard way in the sibling games):
##  * every finger is bound to what it touched first until it lifts or is cancelled (a thumb that drifts over another button does
##    not press it, a stick finger that leaves the zone keeps steering);
##  * the button whose centre is nearest (relative to its hit radius) wins when hit areas overlap; the hit radius is the drawn radius
##    plus a physical margin, so a thumb that lands a little outside still presses;
##  * a press lasts at least `min_press_msec` (a 40 ms tap would be invisible to a 60 Hz game loop that polls the action state), but a
##    longer press is released at once on lift (the old fixed "+90 ms" tail made every shot-charge and every tap-vs-hold decision late);
##  * a cancelled touch (system gesture, palm, notification shade) is reported as `cancelled = true` so the game can abort instead of
##    firing; the same for focus loss (`release_all`);
##  * `reserved` rectangles (pause button, camera button ...) are left to the GUI: those touches are not routed;
##  * a "pressed" event for a finger that is already bound means an up event was lost: the old binding is cancelled first.
## Sport-agnostic (candidate for the shared core, see docs/CORE_PROPOSAL_TOUCH.md).

signal button_down(name: StringName)
signal button_up(name: StringName, held_msec: int, cancelled: bool)
signal stick_changed
signal stick_released(cancelled: bool)

var stick: StickModel = StickModel.new()
var stick_zone: Rect2 = Rect2()                    ## canvas px: a free finger that lands here takes the stick
var buttons: Dictionary = {}                       ## name -> {"c": Vector2 centre, "r": float drawn radius, "hit": float hit radius} (px)
var reserved: Array[Rect2] = []                    ## areas owned by other controls
var min_press_msec: int = 55
var clock: Callable = Callable()                   ## tests inject a msec clock; empty = Time.get_ticks_msec

var _fingers: Dictionary = {}                      ## finger index -> {"kind": "stick" | "button", "name": StringName}
var _holder: Dictionary = {}                       ## button name -> finger index (physically down)
var _down_at: Dictionary = {}                      ## button name -> msec of the press
var _due: Dictionary = {}                          ## button name -> msec at which the (delayed) release is emitted


func set_button(name: StringName, centre: Vector2, radius: float, hit_extra: float) -> void:
	buttons[name] = {"c": centre, "r": radius, "hit": radius + hit_extra}


## is the button considered down (a delayed release still counts as down)
func is_down(name: StringName) -> bool:
	return _down_at.has(name)


## the button a touch at p would press ("" = none): the nearest centre relative to the hit radius wins
func pick_button(p: Vector2) -> StringName:
	var best: StringName = &""
	var best_n := 1e9
	for name: StringName in buttons:
		var b: Dictionary = buttons[name]
		var d := p.distance_to(b["c"] as Vector2)
		var n := d / maxf(float(b["hit"]), 0.001)
		if n <= 1.0 and n < best_n:
			best_n = n
			best = name
	return best


## feed any input event; true = the event was a touch that this router took (stick / button) or finished
func handle(event: InputEvent) -> bool:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			return _down(touch.index, touch.position)
		return _up(touch.index, touch.canceled)
	var drag := event as InputEventScreenDrag
	if drag != null:
		if _fingers.has(drag.index) and (_fingers[drag.index] as Dictionary)["kind"] == "stick":
			stick.drag(drag.position)
			stick_changed.emit()
			return true
	return false


## call every frame: emits the delayed releases that have become due
func tick() -> void:
	if _due.is_empty():
		return
	var now := _now()
	for name: StringName in _due.keys():
		if now >= int(_due[name]):
			_release(name, false)


## focus loss / pause / the controls were hidden: nothing may stay pressed (no up event will ever arrive)
func release_all() -> void:
	for idx: int in _fingers.keys():
		_up(idx, true)
	for name: StringName in _due.keys():
		_release(name, true)
	if stick.active:
		stick.end()
		stick_released.emit(true)
		stick_changed.emit()


func _down(idx: int, p: Vector2) -> bool:
	if _fingers.has(idx):
		_up(idx, true)                                  # the up event of this finger was lost
	for r in reserved:
		if r.has_point(p):
			return false
	var name := pick_button(p)
	if name != &"":
		if _holder.has(name):
			return true                                 # the button already has a finger: a second one is ignored
		if _due.has(name):
			_release(name, false)                       # a quick re-press: let the previous release go out first
		_fingers[idx] = {"kind": "button", "name": name}
		_holder[name] = idx
		_down_at[name] = _now()
		button_down.emit(name)
		return true
	if not stick.active and stick_zone.has_point(p) and stick.can_capture(p):
		stick.begin(idx, p)
		_fingers[idx] = {"kind": "stick", "name": &""}
		stick_changed.emit()
		return true
	return false


func _up(idx: int, cancelled: bool) -> bool:
	if not _fingers.has(idx):
		return false
	var f: Dictionary = _fingers[idx]
	_fingers.erase(idx)
	if f["kind"] == "stick":
		stick.end()
		stick_released.emit(cancelled)
		stick_changed.emit()
		return true
	var name: StringName = f["name"]
	_holder.erase(name)
	var held := _now() - int(_down_at.get(name, _now()))
	if cancelled or held >= min_press_msec:
		_release(name, cancelled)
	else:
		_due[name] = int(_down_at[name]) + min_press_msec
	return true


func _release(name: StringName, cancelled: bool) -> void:
	var held := _now() - int(_down_at.get(name, _now()))
	_due.erase(name)
	_down_at.erase(name)
	_holder.erase(name)
	button_up.emit(name, held, cancelled)


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()
