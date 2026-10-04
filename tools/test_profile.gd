extends SceneTree
## Dev test for Profile: levels, XP breakdown, achievements, daily missions / streak, persistence round trip.
##   godot --headless --path . -s tools/test_profile.gd
var fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	var path := "user://profile_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var p := Profile.new(path)
	p.ensure_daily("2026-10-04")
	check(p.daily["list"].size() == 3, "3 daily missions")
	check(int(p.daily["streak"]) == 1, "streak starts at 1")
	var ids := {}
	for m in p.daily["list"]:
		ids[m["id"]] = true
	check(ids.size() == 3, "missions are distinct")
	# same date -> same missions (seeded)
	var p2 := Profile.new(path)
	p2.ensure_daily("2026-10-04")
	check(p2.daily["list"][0]["text"] == p.daily["list"][0]["text"], "missions are deterministic per day")
	# a win with decent stats
	p.begin_match()
	p.bump("power_spikes")      # live counters (power spike / fever / knock-down) are bumped during the match
	p.mission_progress("power_spikes", 1)
	var res := p.finish_match({"won": true, "score": [11, 0], "difficulty": 2, "mode": "solo", "time": 300.0, "deuce": false,
			"stats": {"perfects": [12, 4], "aces": [2, 0], "blocks": [1, 0], "power_spikes": [1, 0], "longest": 14}, "spike_points": 4})
	print("xp gained ", res["xp"], " bonus ", res["bonus_xp"], " level ", res["level_before"], "->", res["level_after"], " lines ", res["lines"].size(), " mults ", res["mults"])
	check(res["xp"] > 100, "a good win gives > 100 xp")
	check(p.counter("wins") == 1 and p.counter("shutouts") == 1, "win + shutout counted")
	var got := {}
	for a in res["achievements"]:
		got[a["id"]] = true
	check(got.has("first_win") and got.has("shutout") and got.has("power_1") and got.has("rally_10"), "achievements unlocked: %s" % [got.keys()])
	# levels are monotonic and unlocks appear
	var lvl := Profile.level_info(0)
	check(int(lvl["level"]) == 1, "level 1 at 0 xp")
	check(int(Profile.level_info(150)["level"]) == 2, "150 xp = level 2")
	check(int(Profile.level_info(10_000_000)["level"]) == Profile.MAX_LEVEL, "cap")
	var un := Profile.unlocks_between(1, 5)
	check(un.size() >= 5, "unlocks between level 1 and 5: %d" % un.size())
	# equip gating
	check(not p.equip("trail", "fire"), "locked trail can not be equipped")
	check(p.equip("trail", "speed"), "default trail equips")
	# persistence round trip
	p.save()
	var p3 := Profile.new(path)
	check(p3.load_from_disk(), "load works")
	check(p3.xp == p.xp and p3.counter("wins") == 1 and p3.achievements.has("first_win"), "round trip keeps xp / counters / achievements")
	check(int(p3.daily["list"][0]["goal"]) == int(p.daily["list"][0]["goal"]), "missions survive JSON")
	# next day: streak + new missions
	p3.ensure_daily("2026-10-05")
	check(int(p3.daily["streak"]) == 2, "streak continues on the next day (%s)" % p3.daily["streak"])
	p3.ensure_daily("2026-10-08")
	check(int(p3.daily["streak"]) == 1, "streak resets after a gap")
	# helpers added with the career page
	check(Profile.xp_for_level(1) == 0 and Profile.xp_for_level(2) == Profile.need_for(1), "xp_for_level")
	check(int(Profile.level_info(Profile.xp_for_level(7))["level"]) == 7, "xp_for_level round trip")
	var legacy := Profile.new("user://t_legacy.json")
	legacy.stats["matches"] = 2
	legacy.stats["wins"] = 21
	legacy.counters["wins"] = 21
	legacy.recheck_all()
	check(int(legacy.stats["wins"]) == 2, "legacy wins are clamped to matches")
	check(legacy.achievements.has("wins_10") and legacy.achievements.has("first_win"), "recheck_all unlocks satisfied achievements")
	check(Profile.medal_for(30)["id"] == "silver" and Profile.medal_for(3).is_empty(), "medal_for")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PROFILE TEST ", "OK" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails > 0 else 0)
