class_name Prof
extends RefCounted
## Tiny section profiler for phone debug builds: Prof.add("label", t0) accumulates microseconds, Game prints the
## per-frame averages in the [perf] line. Costs two Time calls per section, and nothing in release builds.

static var acc := {}
static var on := false


static func t0() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(label: String, start: int) -> void:
	if not on:
		return
	acc[label] = int(acc.get(label, 0)) + (Time.get_ticks_usec() - start)


## "label=1.2ms ..." averaged over `frames`, then cleared
static func report(frames: int) -> String:
	var parts: Array[String] = []
	var keys := acc.keys()
	keys.sort_custom(func(a, b): return acc[a] > acc[b])
	for k in keys:
		parts.append("%s=%.1f" % [k, float(acc[k]) / 1000.0 / float(maxi(frames, 1))])
	acc.clear()
	return " ".join(parts)
