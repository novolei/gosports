class_name GestureExclusion
extends RefCounted
## Android 10+ system gesture exclusion (View.setSystemGestureExclusionRects). With gesture navigation (Mi 11 / HyperOS: navigation_mode 2)
## a swipe that starts at the left or right screen edge is the system "back" gesture: a thumb that lands near the edge on the stick and
## drags inwards is taken over by the system and the game gets ACTION_CANCEL (the player stops, a charged shot is aborted). This tells the
## system "do not use these edge columns for back": one rectangle per edge, as tall as the controls (the system honours at most 200 dp
## of height per edge; the bottom home gesture cannot be excluded, so keep controls 6 mm above the bottom edge).
## Everything is dynamic (Engine.get_singleton + JavaClassWrapper): on desktop / iOS / web it returns false without touching anything. A
## failure only sets `last_error`; it never affects the game. Sport-agnostic (candidate for the shared core).

static var last_error: String = ""
static var applied: bool = false
static var last_rects: Array[Rect2] = []           ## what was sent last (window px), for tests / the tuner report


static func supported() -> bool:
	return OS.has_feature("android") and Engine.has_singleton(&"AndroidRuntime")


## `rects`: window pixels. Returns true when the request was handed to the system.
static func apply_rects(rects: Array[Rect2]) -> bool:
	last_rects = rects.duplicate()
	if not supported():
		return false
	var runtime: Object = Engine.get_singleton(&"AndroidRuntime")
	var wrapper: Object = Engine.get_singleton(&"JavaClassWrapper")
	var activity: Object = runtime.call(&"getActivity") as Object
	if activity == null or wrapper == null:
		last_error = "no activity / JavaClassWrapper"
		return false
	var rect_class: Object = wrapper.call(&"wrap", "android.graphics.Rect") as Object
	var list_class: Object = wrapper.call(&"wrap", "java.util.ArrayList") as Object
	if rect_class == null or list_class == null:
		last_error = "class wrap failed"
		return false
	var list: Object = list_class.call(&"ArrayList") as Object
	for rect: Rect2 in rects:
		list.call(&"add", rect_class.call(&"Rect", int(rect.position.x), int(rect.position.y), int(rect.end.x), int(rect.end.y)))
	var apply_on_ui := func() -> void:
		var decor: Object = (activity.call(&"getWindow") as Object).call(&"getDecorView") as Object
		decor.call(&"setSystemGestureExclusionRects", list)
	activity.call(&"runOnUiThread", runtime.call(&"createRunnableFromGodotCallable", apply_on_ui))
	var error: Object = wrapper.call(&"get_exception") as Object if wrapper.has_method(&"get_exception") else null
	last_error = "" if error == null else str(error)
	applied = not rects.is_empty() and error == null
	return error == null


## two edge columns (left / right) around the given rest heights. `window_px`: window size; y centres in window px; width in dp
static func apply_edges(window_px: Vector2i, left_y_px: float, right_y_px: float, edge_dp: float) -> bool:
	var density := float(DisplayServer.screen_get_dpi()) / 160.0       # logical density: 1 dp = density px (matches DisplayMetrics.density)
	var half := 100.0 * density                                          # the system honours 200 dp of height per edge
	var width := edge_dp * density
	var rects: Array[Rect2] = []
	for side: Array in [[0.0, left_y_px], [float(window_px.x) - width, right_y_px]]:
		var top := clampf(float(side[1]) - half, 0.0, float(window_px.y))
		var bottom := clampf(float(side[1]) + half, 0.0, float(window_px.y))
		rects.append(Rect2(float(side[0]), top, width, bottom - top))
	return apply_rects(rects)


static func clear() -> void:
	last_rects = []
	if applied:
		var none: Array[Rect2] = []
		apply_rects(none)
		applied = false
