class_name TouchMetrics
extends RefCounted
## Physical size of the canvas on the screen: canvas pixels <-> millimetres.
## A thumb does not scale with the resolution, so every touch size (stick radius, button radius, dead zone, hit margin) is designed in
## millimetres and converted here. Rules:
##  * real phone / tablet: (window pixels / canvas pixels) * 25.4 / DPI. Godot reports the Android *density bucket* (Mi 11: 560, Redmi
##    Note 9 Pro: 440), not the physical DPI (515.1 / 394.7): 9-11 % too big. The physical value is read from DisplayMetrics (xdpi / ydpi,
##    through AndroidRuntime + reflection) and falls back to the per-model table, then to the engine value.
##  * desktop (also `--touch` with the mouse and every automated test): a reference phone (landscape short side 69.5 mm = the project's
##    viewport height), so the result never depends on the monitor DPI or on the window shape.
##  * `forced_dpi` / `forced_mm_per_px` / `--touch-dpi=395` win over everything (tests, calibration).
## Sport-agnostic: no game class is named here (candidate for the shared core, see docs/CORE_PROPOSAL_TOUCH.md).

const REFERENCE_HEIGHT_MM := 69.5        ## landscape short side of the reference phone (6.7", 2400x1080, ~395 ppi)
const DPI_MIN := 120.0
const DPI_MAX := 640.0
const MM_PER_INCH := 25.4
const DPI_ARG := "--touch-dpi="

static var forced_dpi: float = 0.0
static var forced_mm_per_px: float = 0.0
## OS.get_model_name() -> measured physical ppi (only needed when the DisplayMetrics lookup is unavailable)
static var dpi_overrides: Dictionary = {"M2007J17C": 394.7, "M2011K2C": 515.1}
static var last_source: String = "reference"      ## which rule produced the last dpi(): forced | arg | android | table | engine | reference
static var _platform_dpi: float = -1.0           ## cache of the platform lookup (it does a few JNI calls)
static var _platform_source: String = ""
static var _arg_dpi: float = -1.0


## a real touch device (phone / tablet): only those are trusted for DPI
static func is_real_device() -> bool:
	return OS.has_feature("mobile")


## the on-screen controls are shown (real device, web, or the desktop `--touch` test mode)
static func touch_ui() -> bool:
	return is_real_device() or OS.has_feature("web") or "--touch" in OS.get_cmdline_user_args()


## millimetres per canvas pixel
static func mm_per_px(viewport: Viewport) -> float:
	if forced_mm_per_px > 0.0:
		return forced_mm_per_px
	var d := dpi()
	if d <= 0.0:
		var canvas_h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
		return REFERENCE_HEIGHT_MM / maxf(canvas_h, 1.0)
	return canvas_scale(viewport) * MM_PER_INCH / d


static func px_per_mm(viewport: Viewport) -> float:
	return 1.0 / maxf(mm_per_px(viewport), 0.0001)


## window pixels per canvas pixel (the project stretches the canvas to the window height: "canvas_items" + "expand")
static func canvas_scale(viewport: Viewport) -> float:
	var canvas_h := maxf(viewport.get_visible_rect().size.y, 1.0)
	var window := viewport.get_window()
	return float(window.size.y) / canvas_h if window != null else 1.0


## the physical DPI in use; <= 0 = none trusted (desktop: the reference phone applies)
static func dpi() -> float:
	if forced_dpi > 0.0:
		last_source = "forced"
		return clampf(forced_dpi, DPI_MIN, DPI_MAX)
	if _arg_dpi < 0.0:
		_arg_dpi = 0.0
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with(DPI_ARG):
				_arg_dpi = arg.trim_prefix(DPI_ARG).to_float()
	if _arg_dpi > 0.0:
		last_source = "arg"
		return clampf(_arg_dpi, DPI_MIN, DPI_MAX)
	if not is_real_device():
		last_source = "reference"
		return 0.0
	if _platform_dpi < 0.0:
		_platform_dpi = _lookup_platform_dpi()
	last_source = _platform_source
	return _platform_dpi


## DisplayMetrics (xdpi + ydpi) / model table / engine value, in that order
static func _lookup_platform_dpi() -> float:
	var android := _android_display_dpi()
	if android > 0.0:
		_platform_source = "android"
		return android
	var model := OS.get_model_name()
	if dpi_overrides.has(model):
		_platform_source = "table"
		return clampf(float(dpi_overrides[model]), DPI_MIN, DPI_MAX)
	_platform_source = "engine"
	return clampf(float(DisplayServer.screen_get_dpi()), DPI_MIN, DPI_MAX)


## Android: Resources.getDisplayMetrics() -> the public float fields xdpi / ydpi, read with java.lang.reflect.Field (the wrapper only
## exposes methods). Every step is checked: any failure returns 0 and the caller falls back.
static func _android_display_dpi() -> float:
	if not OS.has_feature("android") or not Engine.has_singleton(&"AndroidRuntime"):
		return 0.0
	var runtime: Object = Engine.get_singleton(&"AndroidRuntime")
	var activity: Object = runtime.call(&"getActivity") as Object
	if activity == null:
		return 0.0
	var resources: Object = activity.call(&"getResources") as Object
	var metrics: Object = resources.call(&"getDisplayMetrics") as Object if resources != null else null
	if metrics == null:
		return 0.0
	var klass: Object = metrics.call(&"getClass") as Object
	if klass == null:
		return 0.0
	var sum := 0.0
	var n := 0
	for field_name: String in ["xdpi", "ydpi"]:
		var field: Object = klass.call(&"getField", field_name) as Object
		if field == null:
			continue
		var v := float(field.call(&"getFloat", metrics))
		if v >= DPI_MIN and v <= DPI_MAX:
			sum += v
			n += 1
	if n == 0:
		return 0.0
	var found := sum / float(n)
	# sanity: a bogus report (160 / 0) is more than 40 % away from the density bucket the engine knows
	var engine := float(DisplayServer.screen_get_dpi())
	if engine > 0.0 and absf(found - engine) / engine > 0.4:
		return 0.0
	return found
