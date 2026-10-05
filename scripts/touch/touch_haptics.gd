class_name TouchHaptics
extends RefCounted
## Short vibration ticks for touch events (button down, the shot charge entering its sweet zone, the stick starting to sprint ...).
## Event driven (never per frame) and throttled: Android's one-shot vibration rings 20-50 ms after the pulse, so two pulses closer than
## `GLOBAL_GAP_MSEC` blur into one buzz, and the same kind of tick is not repeated faster than its own gap. Android: `vibrate_handheld`
## = createOneShot(ms, amplitude); keep ticks short (10-20 ms; the Mi 11's X-axis linear motor shows them crisply, a rotor motor smears
## them). The owner decides whether haptics are allowed (`allowed` callable, e.g. the player's setting) and tests take the pulse
## through `sink`.
## Sport-agnostic (candidate for the shared core, see docs/CORE_PROPOSAL_TOUCH.md).

const GLOBAL_GAP_MSEC := 40

static var allowed: Callable = Callable()          ## () -> bool; empty = always allowed
static var sink: Callable = Callable()             ## (ms: int, amplitude: float) -> void; empty = Input.vibrate_handheld
static var count: int = 0                          ## pulses sent (debug / tests)

static var _last_any: int = -100000
static var _last_kind: Dictionary = {}


## one tick; returns true when it was sent. ms <= 0 = this tick is switched off.
static func pulse(kind: StringName, ms: int, amplitude: float, min_gap_msec: int = 120) -> bool:
	if ms <= 0:
		return false
	if allowed.is_valid() and not bool(allowed.call()):
		return false
	var now := Time.get_ticks_msec()
	if now - _last_any < GLOBAL_GAP_MSEC or now - int(_last_kind.get(kind, -100000)) < min_gap_msec:
		return false
	_last_any = now
	_last_kind[kind] = now
	count += 1
	if sink.is_valid():
		sink.call(ms, amplitude)
	elif OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, clampf(amplitude, 0.05, 1.0))
	return true


static func reset() -> void:
	_last_any = -100000
	_last_kind.clear()
	count = 0
