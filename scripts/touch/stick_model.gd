class_name StickModel
extends RefCounted
## The logic of one on-screen movement stick (no node, no drawing: unit-testable). Floating by default: the zero point is where the
## finger lands (a touch at the edge is still 0 output) and the base follows the thumb when it is dragged past the radius; the fixed
## style keeps the base at `home` and only takes touches near it.
## Output: `value` = the push re-mapped for a radial dead zone and a full-speed plateau (0 at the dead-zone rim, length 1 at
## `full_at` * radius, no jump anywhere), `strength` = the raw push 0..1, `sprint` = the "full push" flag with hysteresis.
## Sport-agnostic (candidate for the shared core, see docs/CORE_PROPOSAL_TOUCH.md).

var radius: float = 110.0           ## px: finger travel for a full push
var dead: float = 14.0              ## px: radial dead zone
var full_at: float = 0.92           ## fraction of the radius that already is value length 1
var response: float = 1.0           ## exponent applied to the length (> 1: finer control around the centre)
var follow: bool = true             ## the base follows the thumb past the radius (floating style only)
var fixed: bool = false
var reach: float = 1.6              ## fixed style: radii around `home` that grab the stick
var home: Vector2 = Vector2.ZERO    ## where the base rests (and the zero point of the fixed style)
var sprint_on: float = 0.93
var sprint_off: float = 0.78

var active: bool = false
var index: int = -1                 ## the finger that owns the stick
var origin: Vector2 = Vector2.ZERO  ## the current zero point (moves when the base follows)
var pos: Vector2 = Vector2.ZERO     ## the finger
var value: Vector2 = Vector2.ZERO
var strength: float = 0.0
var sprint: bool = false


## may a finger that lands at `p` take the stick?
func can_capture(p: Vector2) -> bool:
	return not fixed or p.distance_to(home) <= radius * reach


func begin(finger: int, p: Vector2) -> void:
	active = true
	index = finger
	origin = home if fixed else p
	pos = p
	_update()


func drag(p: Vector2) -> void:
	if not active:
		return
	pos = p
	var offset := pos - origin
	var len := offset.length()
	if follow and not fixed and len > radius:
		origin += offset / len * (len - radius)       # the base chases the thumb: pulling back responds at once
	_update()


func end() -> void:
	active = false
	index = -1
	value = Vector2.ZERO
	strength = 0.0
	sprint = false


## where the knob is drawn relative to the base (clamped to the base circle)
func knob_offset() -> Vector2:
	return (pos - origin).limit_length(radius) if active else Vector2.ZERO


func _update() -> void:
	var offset := pos - origin
	var len := offset.length()
	strength = clampf(len / maxf(radius, 0.001), 0.0, 1.0)
	if len <= dead:
		value = Vector2.ZERO
	else:
		var span := maxf(radius * full_at - dead, 0.001)
		var m := clampf((len - dead) / span, 0.0, 1.0)
		if response != 1.0:
			m = pow(m, response)
		value = offset / len * m
	sprint = strength > sprint_off if sprint else strength >= sprint_on
