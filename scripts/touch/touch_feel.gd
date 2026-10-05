class_name TouchFeel
extends RefCounted
## The touch "feel" numbers, all in physical units (millimetres / milliseconds / ratios of the stick radius). One shared instance
## (`TouchFeel.shared()`): the router, the stick, the haptics and the tuner panel read it; the tuner edits it live and saves the changed
## values to user://touch_tune.json (re-applied at the next start). A game-level setting (stick style, button size, auto sprint ...) is
## written into the same instance by the game (see TouchControls.apply_settings).
## Sport-agnostic (candidate for the shared core, see docs/CORE_PROPOSAL_TOUCH.md).

const SAVE_PATH := "user://touch_tune.json"

static var _shared: TouchFeel = null
static var _pristine: Dictionary = {}                 ## the defaults before the saved tune was applied (what "Reset" returns to)
static var _saved: Dictionary = {}                    ## what the tuner saved: a game setting must not overwrite a tuned key (see is_tuned)

# --- movement stick ---------------------------------------------------------------------------------------------------------------
var stick_radius_mm: float = 11.0          ## finger travel from the zero point to a full push (Brawl Stars class ~11-14 mm; the old 110 px = 7.2 mm was small)
var stick_dead_mm: float = 1.4             ## radial dead zone (Android's own touch slop is ~1.3 mm); the output is re-mapped so there is no jump
var stick_full_at: float = 0.92            ## a push of this fraction of the radius already is full speed (the thumb does not have to hit the rim)
var stick_response: float = 1.0            ## 1 = linear; > 1 = finer control for small pushes
var stick_follow: bool = true              ## the base follows the thumb when it is dragged past the radius
var stick_fixed: bool = false              ## fixed stick: always at its home, only takes touches near it (player setting)
var stick_fixed_reach: float = 1.6         ## fixed stick: a touch within this many radii of home grabs the stick
var auto_sprint: bool = true               ## a full push of the stick = sprint (frees the right thumb for the buttons; player setting)
var sprint_on: float = 0.93                ## push (fraction of the radius) at which the sprint starts ...
var sprint_off: float = 0.78               ## ... and the lower value at which it ends (hysteresis: no flicker around the threshold)

# --- buttons ----------------------------------------------------------------------------------------------------------------------
var button_scale: float = 1.0              ## player size setting (radius and spread of the button fan)
var hit_extra_mm: float = 3.0              ## a touch up to this far outside the drawn circle still presses the button (the nearest one wins)
var min_press_ms: int = 55                 ## an action stays pressed at least this long: a very quick tap is still seen by the 60 Hz game loop
var edge_margin_mm: float = 7.0            ## controls stay this far from the left / right screen edge (system back gesture zone is ~6 mm)
var bottom_margin_mm: float = 6.0          ## ... and from the bottom edge (home gesture zone ~5 mm)

# --- haptics (a short tick per event; linear motors feel 10-18 ms ticks, rotor motors need longer) ---------------------------------
var haptic_press_ms: int = 10              ## action button down (0 = off)
var haptic_press_amp: float = 0.28
var haptic_sweet_ms: int = 18              ## the shot charge enters the sweet zone (the cue to let go; 0 = off)
var haptic_sweet_amp: float = 0.6
var haptic_sprint_ms: int = 12             ## the stick reaches sprint (0 = off)
var haptic_sprint_amp: float = 0.35

# --- system edge gestures -----------------------------------------------------------------------------------------------------------
var gesture_exclusion: bool = true         ## Android 10+: ask the system not to use the stick / button edge columns for "back"
var gesture_edge_dp: float = 56.0          ## width of those columns

# --- tuner --------------------------------------------------------------------------------------------------------------------------
var tuner_gesture: bool = true             ## three fingers held still for 2 s open the tuner panel (hidden gesture)

## tuner rows: key, label, step, min, max, unit, relayout after a change
const TABLE: Array = [
	["stick_radius_mm", "stick radius", 0.5, 7.0, 18.0, "mm", true],
	["stick_dead_mm", "stick dead zone", 0.2, 0.0, 4.0, "mm", false],
	["stick_full_at", "stick full speed at", 0.02, 0.6, 1.0, "R", false],
	["stick_response", "stick response curve", 0.05, 0.6, 2.0, "pow", false],
	["auto_sprint", "full push = sprint (0/1)", 1.0, 0.0, 1.0, "", false],
	["sprint_on", "sprint starts at", 0.01, 0.6, 1.0, "R", false],
	["sprint_off", "sprint ends at", 0.01, 0.4, 0.98, "R", false],
	["button_scale", "button size", 0.05, 0.7, 1.4, "x", true],
	["hit_extra_mm", "button hit margin", 0.5, 0.0, 8.0, "mm", false],
	["min_press_ms", "minimum press", 5.0, 0.0, 120.0, "ms", false],
	["edge_margin_mm", "side margin", 0.5, 0.0, 14.0, "mm", true],
	["bottom_margin_mm", "bottom margin", 0.5, 0.0, 14.0, "mm", true],
	["haptic_press_ms", "tick on press", 2.0, 0.0, 40.0, "ms", false],
	["haptic_press_amp", "tick strength", 0.05, 0.05, 1.0, "", false],
	["haptic_sweet_ms", "tick in sweet zone", 2.0, 0.0, 40.0, "ms", false],
	["haptic_sweet_amp", "sweet tick strength", 0.05, 0.05, 1.0, "", false],
	["haptic_sprint_ms", "tick on sprint", 2.0, 0.0, 40.0, "ms", false],
	["gesture_exclusion", "edge gesture exclusion (0/1)", 1.0, 0.0, 1.0, "", true],
]


## keys a game does not use (volleyball: no sprint, no shot charge): the tuner panel skips them. Set once by the game (TouchControls).
static var hidden: Array = []


## the tuner rows this game shows
static func rows() -> Array:
	return TABLE.filter(func(row: Array) -> bool: return not hidden.has(row[0]))


## the live instance (the first call applies the saved tune)
static func shared() -> TouchFeel:
	if _shared == null:
		_shared = TouchFeel.new()
		_pristine = _shared.snapshot()
		_saved = load_saved()
		_shared.apply(_saved)
	return _shared


## true when the tuner saved a value for this key: the game's own setting for it (button size, auto sprint) then stays out of the way
static func is_tuned(key: String) -> bool:
	shared()
	return _saved.has(key)


static func pristine() -> Dictionary:
	shared()
	return _pristine


## every tunable value as {key: float}
func snapshot() -> Dictionary:
	var d: Dictionary = {}
	for row: Array in TABLE:
		d[row[0]] = float(get(row[0]))
	return d


## write values back (unknown keys ignored, numbers clamped to the table range, bools / ints coerced)
func apply(values: Dictionary) -> void:
	for row: Array in TABLE:
		var key: String = row[0]
		if not values.has(key):
			continue
		var v := clampf(float(values[key]), float(row[3]), float(row[4]))
		set(key, _coerce(key, v))


func _coerce(key: String, v: float) -> Variant:
	var cur: Variant = get(key)
	if cur is bool:
		return v >= 0.5
	if cur is int:
		return int(roundf(v))
	return v


## only the values that differ from `defaults`
func changed(defaults: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var now := snapshot()
	for key: String in now:
		if absf(float(now[key]) - float(defaults.get(key, now[key]))) > 0.00001:
			out[key] = now[key]
	return out


## the whole tuner state as text (a player pastes this back instead of describing the feel)
func report(extra: String = "") -> String:
	var lines: PackedStringArray = []
	var base := pristine()
	for row: Array in TABLE:
		var key: String = row[0]
		var cur := float(get(key))
		var mark := "" if absf(cur - float(base.get(key, cur))) < 0.00001 else "   (default %s)" % str(base.get(key))
		lines.append("%s = %s%s" % [key, str(snappedf(cur, 0.001)), mark])
	if extra != "":
		lines.append(extra)
	return "\n".join(lines)


static func load_saved() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func save() -> void:
	_saved = changed(pristine())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_saved))


## forget every tuned value
func reset_all() -> void:
	apply(pristine())
	save()
