class_name TrainingCoach
extends Node
## Beginner coach for the training mode: a short checklist that ticks itself off as the player does the things a
## newcomer must learn (receive, set, spike, a "Nice!" hit, a longer rally). Finishing it ends the session with a reward.

signal changed
signal finished

const ITEMS := [
	{"id": "bump", "text": "垫球接发（垫球 Nice! 或 Good）", "tip": "球落在脚下的圈里时按击球键；时机圈缩到最小那一刻最准"},
	{"id": "set", "text": "传一次球", "tip": "让队友先接球，你站在网前等球过来再按击球键"},
	{"id": "spike", "text": "扣一次球", "tip": "队友传球后，球在高处按击球键会自动起跳扣杀"},
	{"id": "nice", "text": "打出 3 次 Nice!", "tip": "在时机圈缩到最小时按键，圆环会变绿"},
	{"id": "rally", "text": "连续 8 次触球", "tip": "多接球、多传球，不要急着扣杀"},
]

var director: MatchDirector
var done := {}                 # id -> true
var nice_count := 0
var best_rally := 0
var _finished := false


func setup(d: MatchDirector) -> void:
	director = d
	director.rally_event.connect(_on_rally_event)
	director.practice_rally_over.connect(func(length: int, _lost: bool): _check_rally(length))
	_update_feed()


func progress() -> int:
	return done.size()


func is_done(id: String) -> bool:
	return done.has(id)


## the first unfinished item (its tip is shown to the player)
func current() -> Dictionary:
	for it in ITEMS:
		if not done.has(it["id"]):
			return it
	return {}


func _tick(id: String) -> void:
	if done.has(id) or _finished:
		return
	done[id] = true
	if Game.main != null and Game.main.dev.has("log"):
		print("[coach] done %s (%d/%d)" % [id, done.size(), ITEMS.size()])
	Sfx.play("ui_confirm", -4.0)
	_update_feed()
	changed.emit()
	if done.size() >= ITEMS.size():
		_finished = true
		finished.emit()


## while the player has to set, the ball machine feeds the team mate first (the mate receives, the player sets)
func _update_feed() -> void:
	var cur := current()
	var target: Athlete = null
	if not cur.is_empty() and cur["id"] == "set":
		for a in director.athletes:
			if a.team == 0 and not a.is_human:
				target = a
	director.feed_target = target


func _on_rally_event(ev: String, data: Dictionary) -> void:
	if ev != "hit":
		return
	var a: Athlete = data["athlete"]
	var info: Dictionary = data["info"]
	_check_rally(director.rally_len)
	if not a.is_human:
		return
	var kind: String = info["kind"]
	var q: String = info["quality"]
	if (kind == "bump" or kind == "dig") and q != "ok":
		_tick("bump")
	if kind == "set":
		_tick("set")
	if kind == "spike":
		_tick("spike")
	if q == "perfect":
		nice_count += 1
		if nice_count >= 3:
			_tick("nice")
		else:
			changed.emit()


func _check_rally(length: int) -> void:
	best_rally = maxi(best_rally, length)
	if length >= 8:
		_tick("rally")
