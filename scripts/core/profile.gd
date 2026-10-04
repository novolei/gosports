class_name Profile
extends RefCounted
## Player progression: XP / levels, unlockable cosmetics (ball trails, ball skins, court themes), achievements, daily
## missions with a login streak, lifetime stats. Persisted as JSON in user://profile.json.
## Counters are bumped by the match code ("live" ones show a toast at once), `finish_match()` turns a finished match
## into an XP breakdown (play / points / perfects ... x win / difficulty / deuce / teamwork / streak bonuses).

signal level_up(level: int)
signal achievement_unlocked(ach: Dictionary)
signal mission_done(mission: Dictionary)

const PATH := "user://profile.json"
const MAX_LEVEL := 30

# ---------------------------------------------------------------- catalogues
const TRAILS := [
	{"id": "speed", "name": "速度彩带", "level": 1, "desc": "颜色随球速变化", "swatch": Color(0.42, 0.98, 0.78)},
	{"id": "star", "name": "星光", "level": 2, "desc": "金白色的星尘拖尾", "swatch": Color(1.0, 0.93, 0.55)},
	{"id": "team", "name": "队色", "level": 3, "desc": "跟随你的队伍颜色", "swatch": Color(0.2, 0.62, 1.0)},
	{"id": "sakura", "name": "樱吹雪", "level": 5, "desc": "粉白渐变的花瓣", "swatch": Color(1.0, 0.7, 0.85)},
	{"id": "rainbow", "name": "彩虹", "level": 8, "desc": "七彩渐变", "swatch": Color(0.75, 0.5, 1.0)},
	{"id": "fire", "name": "烈焰", "level": 12, "desc": "红橙色的火焰", "swatch": Color(1.0, 0.45, 0.15)},
	{"id": "ice", "name": "寒霜", "level": 16, "desc": "冰蓝色的冷光", "swatch": Color(0.55, 0.9, 1.0)},
]
const BALLS := [
	{"id": "classic", "name": "经典黄蓝", "level": 1, "desc": "标准比赛用球", "tint": Color(1, 1, 1), "swatch": Color(1.0, 0.85, 0.2)},
	{"id": "beach", "name": "沙滩球", "level": 3, "desc": "暖黄色的沙滩风格", "tint": Color(1.0, 0.86, 0.55), "swatch": Color(1.0, 0.86, 0.55)},
	{"id": "neon", "name": "霓虹", "level": 6, "desc": "青色荧光", "tint": Color(0.55, 1.0, 1.0), "swatch": Color(0.4, 1.0, 1.0)},
	{"id": "candy", "name": "糖果", "level": 9, "desc": "粉嫩甜甜的颜色", "tint": Color(1.0, 0.68, 0.88), "swatch": Color(1.0, 0.6, 0.85)},
	{"id": "gold", "name": "黄金", "level": 14, "desc": "金灿灿的冠军球", "tint": Color(1.25, 1.0, 0.45), "swatch": Color(1.0, 0.8, 0.2)},
	{"id": "midnight", "name": "午夜", "level": 18, "desc": "深蓝色的夜场用球", "tint": Color(0.5, 0.58, 0.95), "swatch": Color(0.35, 0.42, 0.9)},
]
const COURTS := [
	{"id": "day", "name": "晴空日场", "level": 1, "desc": "明亮的白天", "swatch": Color(0.45, 0.72, 1.0)},
	{"id": "sunset", "name": "黄昏", "level": 4, "desc": "金色的夕阳", "swatch": Color(1.0, 0.62, 0.35)},
	{"id": "night", "name": "灯光夜场", "level": 7, "desc": "璀璨的夜间比赛", "swatch": Color(0.15, 0.2, 0.45)},
	{"id": "dawn", "name": "薄雾清晨", "level": 11, "desc": "粉蓝色的清晨", "swatch": Color(0.82, 0.75, 0.95)},
]

const TITLES := ["新手", "新手", "球场新星", "球场新星", "校队候补", "校队候补", "校队主力", "校队主力", "区域好手", "区域好手",
		"地区冠军", "地区冠军", "省队选手", "省队选手", "国家队后备", "国家队后备", "国手", "国手", "传奇", "传奇"]

## key = counter name, kind "sum" = counts up, "max" = highest value ever
const ACHIEVEMENTS := [
	{"id": "first_win", "name": "初战告捷", "desc": "赢得第一场比赛", "key": "wins", "goal": 1, "xp": 40},
	{"id": "wins_10", "name": "常胜将军", "desc": "累计赢得 10 场比赛", "key": "wins", "goal": 10, "xp": 120},
	{"id": "perfect_30", "name": "节奏大师", "desc": "累计 30 次 Nice! 击球", "key": "perfects", "goal": 30, "xp": 60},
	{"id": "perfect_200", "name": "完美主义", "desc": "累计 200 次 Nice! 击球", "key": "perfects", "goal": 200, "xp": 160},
	{"id": "rally_10", "name": "十连不倒", "desc": "单回合 10 次触球", "key": "longest_rally", "goal": 10, "kind": "max", "xp": 50},
	{"id": "rally_25", "name": "拉锯大战", "desc": "单回合 25 次触球", "key": "longest_rally", "goal": 25, "kind": "max", "xp": 120},
	{"id": "power_1", "name": "三连默契", "desc": "完成一次垫传扣全 Nice! 的强力扣球", "key": "power_spikes", "goal": 1, "xp": 60},
	{"id": "power_10", "name": "扣杀之王", "desc": "累计 10 次强力扣球", "key": "power_spikes", "goal": 10, "xp": 140},
	{"id": "ace_5", "name": "发球机器", "desc": "累计 5 个 ACE", "key": "aces", "goal": 5, "xp": 60},
	{"id": "block_5", "name": "铜墙铁壁", "desc": "累计 5 次拦网得分", "key": "blocks", "goal": 5, "xp": 60},
	{"id": "dizzy", "name": "头晕目眩", "desc": "把队友或自己撞得眼冒金星", "key": "knockdowns", "goal": 1, "xp": 30},
	{"id": "fever_1", "name": "热血沸腾", "desc": "触发一次热血时刻", "key": "fever", "goal": 1, "xp": 50},
	{"id": "fever_10", "name": "燃烧吧!", "desc": "累计触发 10 次热血时刻", "key": "fever", "goal": 10, "xp": 140},
	{"id": "comeback", "name": "绝地反击", "desc": "落后 5 分以上后逆转获胜", "key": "comebacks", "goal": 1, "xp": 120},
	{"id": "shutout", "name": "完美零封", "desc": "不让对手得分赢下比赛", "key": "shutouts", "goal": 1, "xp": 100},
	{"id": "tutorial", "name": "合格新人", "desc": "完成新手教学", "key": "tutorial", "goal": 1, "xp": 80},
	{"id": "rally_mode", "name": "回合达人", "desc": "回合挑战中拿到金牌", "key": "rally_gold", "goal": 1, "xp": 100},
	{"id": "champion", "name": "锦标赛冠军", "desc": "夺得一次锦标赛冠军", "key": "tournaments", "goal": 1, "xp": 200},
	{"id": "streak_3", "name": "三天打卡", "desc": "连续 3 天登录", "key": "streak", "goal": 3, "kind": "max", "xp": 60},
	{"id": "level_10", "name": "十级球员", "desc": "达到 10 级", "key": "level", "goal": 10, "kind": "max", "xp": 150},
]

## daily mission templates: text uses %d for the goal
const MISSION_POOL := [
	{"id": "win", "text": "赢得 %d 场比赛", "key": "wins", "goals": [1, 2], "xp": 80},
	{"id": "perfect", "text": "完成 %d 次 Nice! 击球", "key": "perfects", "goals": [15, 25, 40], "xp": 70},
	{"id": "spike", "text": "扣杀得分 %d 次", "key": "spike_points", "goals": [3, 5, 8], "xp": 70},
	{"id": "rally", "text": "单回合达到 %d 次触球", "key": "longest_rally", "goals": [8, 12, 16], "kind": "max", "xp": 80},
	{"id": "ace", "text": "发出 %d 个 ACE", "key": "aces", "goals": [1, 2, 3], "xp": 70},
	{"id": "block", "text": "拦网得分 %d 次", "key": "blocks", "goals": [1, 2, 3], "xp": 80},
	{"id": "fever", "text": "触发 %d 次热血时刻", "key": "fever", "goals": [1, 2], "xp": 90},
	{"id": "power", "text": "完成 %d 次强力扣球", "key": "power_spikes", "goals": [1, 2], "xp": 100},
	{"id": "play", "text": "完成 %d 场比赛", "key": "matches", "goals": [2, 3], "xp": 60},
]

const MEDALS := [
	{"id": "bronze", "name": "铜牌", "goal": 10, "xp": 30, "color": Color(0.85, 0.52, 0.28)},
	{"id": "silver", "name": "银牌", "goal": 25, "xp": 60, "color": Color(0.82, 0.87, 0.93)},
	{"id": "gold", "name": "金牌", "goal": 50, "xp": 120, "color": Color(1.0, 0.82, 0.2)},
]

# ---------------------------------------------------------------- state
var xp := 0
var stats := {}                # lifetime numbers shown on the career page
var counters := {}             # achievement / mission counters
var achievements := {}         # id -> unix time unlocked
var equipped := {"trail": "speed", "ball": "classic", "court": "day"}
var daily := {"day": "", "list": [], "streak": 0, "last_day": ""}
var flags := {"tutorial_done": false, "welcomed": false, "tournament_best": 0, "rally_best": 0}
var path := PATH
var new_day := false              # the day rolled over during this launch (the menu greets the player once)
var _fresh_buffer: Array = []      # achievements / missions unlocked since begin_match(), for the results screen
var _mission_buffer: Array = []


func _init(p_path := PATH) -> void:
	path = p_path
	_defaults()


func _defaults() -> void:
	stats = {"matches": 0, "wins": 0, "points": 0, "aces": 0, "blocks": 0, "perfects": 0, "power_spikes": 0,
			"longest_rally": 0, "knockdowns": 0, "fever": 0, "playtime": 0.0}


# ---------------------------------------------------------------- levels
static func need_for(level: int) -> int:
	return 100 + 50 * level


## total xp needed to reach a level
static func xp_for_level(target: int) -> int:
	var t := 0
	for l in range(1, target):
		t += need_for(l)
	return t


## {"level", "into", "need", "ratio", "title"} for a total xp
static func level_info(total_xp: int) -> Dictionary:
	var lv := 1
	var rest := total_xp
	while lv < MAX_LEVEL and rest >= need_for(lv):
		rest -= need_for(lv)
		lv += 1
	var need := need_for(lv) if lv < MAX_LEVEL else 1
	return {"level": lv, "into": rest if lv < MAX_LEVEL else need, "need": need,
			"ratio": clampf(float(rest) / float(need), 0.0, 1.0) if lv < MAX_LEVEL else 1.0, "title": TITLES[mini(lv - 1, TITLES.size() - 1)]}


func level() -> int:
	return int(level_info(xp)["level"])


# ---------------------------------------------------------------- cosmetics
static func catalog(kind: String) -> Array:
	match kind:
		"trail": return TRAILS
		"ball": return BALLS
		"court": return COURTS
	return []


static func item(kind: String, id: String) -> Dictionary:
	for e in catalog(kind):
		if e["id"] == id:
			return e
	return catalog(kind)[0]


func is_unlocked(kind: String, id: String) -> bool:
	return level() >= int(item(kind, id)["level"]) or flags.get("unlock_all", false)


func equip(kind: String, id: String) -> bool:
	if not is_unlocked(kind, id):
		return false
	equipped[kind] = id
	save()
	return true


func equipped_item(kind: String) -> Dictionary:
	var id: String = equipped.get(kind, catalog(kind)[0]["id"])
	if not is_unlocked(kind, id):
		id = catalog(kind)[0]["id"]
	return item(kind, id)


## everything that becomes available between two levels: [{"kind", "id", "name"}]
static func unlocks_between(from_level: int, to_level: int) -> Array:
	var out := []
	for kind in ["trail", "ball", "court"]:
		for e in catalog(kind):
			if int(e["level"]) > from_level and int(e["level"]) <= to_level:
				out.append({"kind": kind, "id": e["id"], "name": e["name"], "level": e["level"]})
	return out


# ---------------------------------------------------------------- counters / achievements
func counter(key: String) -> int:
	return int(counters.get(key, 0))


## add n to a counter and check achievements + missions; returns the newly unlocked achievements
func bump(key: String, n := 1) -> Array:
	counters[key] = counter(key) + n
	if key in stats:
		stats[key] = int(stats[key]) + n
	return _after_change(key)


## keep the highest value seen (longest rally, streak, level)
func record_max(key: String, v: int) -> Array:
	if v > counter(key):
		counters[key] = v
		if key in stats:
			stats[key] = v
		return _after_change(key)
	return []


## unlock every achievement the counters already satisfy (legacy records / healed saves); no rewards pop up for them
func recheck_all() -> void:
	stats["wins"] = mini(int(stats.get("wins", 0)), int(stats.get("matches", 0)))
	for a in ACHIEVEMENTS:
		if not achievements.has(a["id"]) and counter(String(a["key"])) >= int(a["goal"]):
			achievements[a["id"]] = int(Time.get_unix_time_from_system())
			xp += int(a.get("xp", 0))
	_fresh_buffer.clear()


func _after_change(key: String) -> Array:
	var fresh := []
	for a in ACHIEVEMENTS:
		if a["key"] == key and not achievements.has(a["id"]) and counter(key) >= int(a["goal"]):
			achievements[a["id"]] = int(Time.get_unix_time_from_system())
			fresh.append(a)
			_fresh_buffer.append(a)
			xp += int(a.get("xp", 0))
			achievement_unlocked.emit(a)
	return fresh


## mission progress is tracked separately from lifetime counters (it resets every day)
func mission_progress(key: String, n: int, as_max := false) -> void:
	for m in daily["list"]:
		if m["key"] != key or m["done"]:
			continue
		m["progress"] = maxi(int(m["progress"]), n) if as_max else int(m["progress"]) + n
		if int(m["progress"]) >= int(m["goal"]):
			m["done"] = true
			xp += int(m["xp"])
			_mission_buffer.append(m)
			mission_done.emit(m)


# ---------------------------------------------------------------- daily missions + streak
static func _day_string() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func _day_number(day: String) -> int:
	var p := day.split("-")
	if p.size() < 3:
		return 0
	return int(p[0]) * 10000 + int(p[1]) * 100 + int(p[2])


static func _prev_day(day: String) -> String:
	var t := Time.get_unix_time_from_datetime_string(day + "T12:00:00") - 86400
	var d := Time.get_date_dict_from_unix_time(int(t))
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


## call once per launch: rolls the day over (new missions, streak) if needed
func ensure_daily(today := "") -> void:
	if today == "":
		today = _day_string()
	if daily["day"] == today:
		return
	var streak := 1
	if daily["last_day"] == _prev_day(today) and int(daily["streak"]) > 0:
		streak = int(daily["streak"]) + 1
	elif daily["last_day"] == today:
		streak = int(daily["streak"])
	new_day = true
	daily["streak"] = streak
	daily["last_day"] = today
	daily["day"] = today
	daily["list"] = _pick_missions(_day_number(today))
	record_max("streak", streak)
	save()


static func _pick_missions(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var pool := MISSION_POOL.duplicate()
	var out := []
	for i in 3:
		var idx := rng.randi() % pool.size()
		var t: Dictionary = pool[idx]
		pool.remove_at(idx)
		var goals: Array = t["goals"]
		var g := int(goals[mini(rng.randi() % goals.size(), goals.size() - 1)])
		out.append({"id": t["id"], "text": t["text"] % g, "key": t["key"], "goal": g, "progress": 0, "done": false,
				"xp": int(t["xp"]), "kind": t.get("kind", "sum")})
	return out


func streak_bonus() -> float:
	return 1.0 + 0.05 * float(mini(int(daily["streak"]), 5))


func missions_done() -> int:
	var n := 0
	for m in daily["list"]:
		if m["done"]:
			n += 1
	return n


# ---------------------------------------------------------------- matches
func begin_match() -> void:
	_fresh_buffer.clear()
	_mission_buffer.clear()


## summary: {won, score:[a,b], target, difficulty, mode, stats:{...director stats...}, deuce, comeback, power_spikes}
## returns {"lines":[{"name","value"}], "mults":[{"name","mult"}], "xp","level_before","level_after","unlocks","achievements","missions"}
func finish_match(sum: Dictionary) -> Dictionary:
	var xp0 := xp
	var st: Dictionary = sum.get("stats", {})
	var mine := 0                                  # the profile belongs to the player on the near team
	var won: bool = sum.get("won", false)
	var score: Array = sum.get("score", [0, 0])
	var lines := []
	var base := 30
	lines.append({"name": "参赛奖励", "value": 30})
	var pts := mini(int(score[mine]) * 3, 45)
	lines.append({"name": "得分 %d" % int(score[mine]), "value": pts})
	var perfects := int(_pick(st, "perfects", mine))
	var perf_xp := mini(perfects, 40)
	lines.append({"name": "Nice! ×%d" % perfects, "value": perf_xp})
	var aces := int(_pick(st, "aces", mine))
	var blocks := int(_pick(st, "blocks", mine))
	var powers := int(_pick(st, "power_spikes", mine))
	var longest := int(st.get("longest", 0))
	var extra := mini(aces * 4, 20) + mini(blocks * 4, 20) + mini(powers * 6, 30) + mini(maxi(longest - 4, 0), 20)
	if extra > 0:
		lines.append({"name": "精彩表现", "value": extra})
	var subtotal := base + pts + perf_xp + extra
	var mults := []
	var m := 1.0
	if won:
		m *= 1.25
		mults.append({"name": "胜利", "mult": 1.25})
	var dif: int = int(sum.get("difficulty", 1))
	var dm: float = [0.8, 1.0, 1.15, 1.35][clampi(dif, 0, 3)]
	if sum.get("mode", "solo") in ["solo", "coop"] and not is_equal_approx(dm, 1.0):
		m *= dm
		mults.append({"name": "难度", "mult": dm})
	if sum.get("deuce", false):
		m *= 1.1
		mults.append({"name": "加时", "mult": 1.1})
	if powers > 0:
		m *= 1.1
		mults.append({"name": "默契", "mult": 1.1})
	var sb := streak_bonus()
	if sb > 1.001:
		m *= sb
		mults.append({"name": "连续登录", "mult": sb})
	var gained := int(round(float(subtotal) * m))
	var lv0 := level()
	# lifetime counters
	stats["playtime"] = float(stats["playtime"]) + float(sum.get("time", 0.0))
	bump("matches")
	mission_progress("matches", 1)
	stats["points"] = int(stats["points"]) + int(score[mine])
	if won:
		bump("wins")
		mission_progress("wins", 1)
		if int(score[1 - mine]) == 0:
			bump("shutouts")
		if sum.get("comeback", false):
			bump("comebacks")
	if perfects > 0:
		bump("perfects", perfects)
		mission_progress("perfects", perfects)
	if aces > 0:
		bump("aces", aces)
		mission_progress("aces", aces)
	if blocks > 0:
		bump("blocks", blocks)
		mission_progress("blocks", blocks)
	var spk := int(sum.get("spike_points", 0))
	if spk > 0:
		bump("spike_points", spk)
		mission_progress("spike_points", spk)
	record_max("longest_rally", longest)
	mission_progress("longest_rally", longest, true)
	xp += gained
	var fresh := _drain_fresh()
	var lv1 := level()
	record_max("level", lv1)
	if lv1 > lv0:
		level_up.emit(lv1)
	save()
	return {"lines": lines, "mults": mults, "xp": gained, "bonus_xp": xp - xp0 - gained, "level_before": lv0, "level_after": lv1,
			"total_xp": xp, "unlocks": unlocks_between(lv0, lv1), "achievements": fresh, "missions": _done_missions()}


static func _pick(st: Dictionary, key: String, team: int) -> Variant:
	var v: Variant = st.get(key, [0, 0])
	if v is Array and (v as Array).size() > team:
		return v[team]
	return 0


func _drain_fresh() -> Array:
	var out := _fresh_buffer.duplicate()
	_fresh_buffer.clear()
	return out


func _done_missions() -> Array:
	var out := _mission_buffer.duplicate()
	_mission_buffer.clear()
	return out


static func medal_for(best: int) -> Dictionary:
	var out := {}
	for m in MEDALS:
		if best >= int(m["goal"]):
			out = m
	return out


## rally challenge / training: {"mode", "best", "total", "rallies", "completed"} -> same shape as finish_match()
func finish_practice(sum: Dictionary) -> Dictionary:
	var xp0 := xp
	var lines := []
	var gained := 0
	var best := int(sum.get("best", 0))
	var lv0 := level()
	if sum.get("mode", "rally") == "rally":
		var v1 := best * 3
		var v2 := mini(int(sum.get("total", 0)) / 2, 60)
		lines.append({"name": "最长回合 %d" % best, "value": v1})
		lines.append({"name": "累计触球 %d" % int(sum.get("total", 0)), "value": v2})
		gained = v1 + v2
		var medal := medal_for(best)
		if not medal.is_empty():
			lines.append({"name": medal["name"], "value": int(medal["xp"])})
			gained += int(medal["xp"])
		if best > int(flags.get("rally_best", 0)):
			flags["rally_best"] = best
		if medal.get("id", "") == "gold":
			bump("rally_gold")
	else:
		if sum.get("completed", false):
			lines.append({"name": "完成新手教学", "value": 100})
			gained = 100
			if not flags.get("tutorial_done", false):
				flags["tutorial_done"] = true
				bump("tutorial")
		else:
			lines.append({"name": "练习", "value": 20})
			gained = 20
	record_max("longest_rally", best)
	mission_progress("longest_rally", best, true)
	xp += gained
	var lv1 := level()
	record_max("level", lv1)
	if lv1 > lv0:
		level_up.emit(lv1)
	save()
	return {"lines": lines, "mults": [], "xp": gained, "bonus_xp": xp - xp0 - gained, "level_before": lv0, "level_after": lv1,
			"total_xp": xp, "unlocks": unlocks_between(lv0, lv1), "achievements": _drain_fresh(), "missions": _done_missions()}


## xp for things outside a normal match (tutorial, rally challenge, tournament); returns {"xp","level_before","level_after","unlocks"}
func grant_xp(amount: int) -> Dictionary:
	var lv0 := level()
	xp += amount
	var lv1 := level()
	record_max("level", lv1)
	if lv1 > lv0:
		level_up.emit(lv1)
	save()
	return {"xp": amount, "level_before": lv0, "level_after": lv1, "unlocks": unlocks_between(lv0, lv1)}


# ---------------------------------------------------------------- persistence
func to_dict() -> Dictionary:
	return {"xp": xp, "stats": stats, "counters": counters, "achievements": achievements, "equipped": equipped,
			"daily": daily, "flags": flags, "version": 1}


func from_dict(d: Dictionary) -> void:
	xp = int(d.get("xp", 0))
	for k in (d.get("stats", {}) as Dictionary).keys():
		stats[k] = d["stats"][k]
	counters = d.get("counters", {})
	achievements = d.get("achievements", {})
	var eq: Dictionary = d.get("equipped", {})
	for k in eq.keys():
		equipped[k] = eq[k]
	var dl: Dictionary = d.get("daily", {})
	for k in dl.keys():
		daily[k] = dl[k]
	var fl: Dictionary = d.get("flags", {})
	for k in fl.keys():
		flags[k] = fl[k]


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(to_dict()))


func load_from_disk() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		from_dict(parsed)
		return true
	return false
