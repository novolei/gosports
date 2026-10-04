class_name TrainingCoach
extends Node
## Beginner coach for the training mode, in the style of the reference game's tutorial: one skill at a time
## (bump x3, set x3, spike x3, three "Nice!" timings, a longer rally) with an instruction banner and a card of
## check circles. Finishing the last step ends the session with a reward.

signal changed
signal finished

## text uses [b]..[/b] for the highlighted words of the instruction banner
const ITEMS := [
	{"id": "bump", "title": "垫球", "need": 3, "text": "垫球接发 ×3",
			"tip": "球落到[b]脚下的圈[/b]里时按 [b]击球键[/b]，时机圈缩到最小时最准!"},
	{"id": "set", "title": "传球", "need": 3, "text": "传球 ×3",
			"tip": "让队友先接球，你站在[b]网前[/b]，球飞过来时按 [b]击球键[/b] 传球"},
	{"id": "spike", "title": "扣球", "need": 3, "text": "扣球 ×3",
			"tip": "队友传球后，球在高处时按 [b]击球键[/b]，会自动[b]起跳扣杀[/b]"},
	{"id": "nice", "title": "完美时机", "need": 3, "text": "打出 3 次 Nice!",
			"tip": "击球圈缩到[b]最小[/b]的那一刻按键，就是 [b]Nice![/b]"},
	{"id": "rally", "title": "连续对打", "need": 8, "text": "连续 8 次触球",
			"tip": "多接球、多传球，[b]不要急着扣杀[/b]，把回合打长"},
]

var director: MatchDirector
var done := {}                 # id -> true
var counts := {"bump": 0, "set": 0, "spike": 0, "nice": 0, "rally": 0}
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


func count_of(id: String) -> int:
	return int(counts.get(id, 0))


## the first unfinished step (its instruction is shown to the player)
func current() -> Dictionary:
	for it in ITEMS:
		if not done.has(it["id"]):
			return it
	return {}


func _add(id: String) -> void:
	if done.has(id) or _finished:
		return
	var need := 1
	for it in ITEMS:
		if it["id"] == id:
			need = int(it["need"])
	counts[id] = mini(int(counts[id]) + 1, need)
	if int(counts[id]) >= need:
		_complete(id)
	else:
		Sfx.play("ui_click", -6.0, 1.0 + 0.12 * float(counts[id]))
		changed.emit()


func _complete(id: String) -> void:
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
		_add("bump")
	if kind == "set":
		_add("set")
	if kind == "spike":
		_add("spike")
	if q == "perfect":
		nice_count += 1
		_add("nice")


func _check_rally(length: int) -> void:
	best_rally = maxi(best_rally, length)
	if length > int(counts["rally"]) and not done.has("rally"):
		counts["rally"] = mini(length, 8)
		if length >= 8:
			_complete("rally")
		else:
			changed.emit()
