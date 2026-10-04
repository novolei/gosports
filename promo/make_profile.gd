extends SceneTree
## Builds a throw-away "veteran" profile for the promo recordings (menus / collection / career pages look lived-in):
##   godot --headless --path . -s promo/make_profile.gd
## writes user://promo_profile.json; record with  -- --profile=user://promo_profile.json --nosave
## It never touches the real save (user://profile.json).


func _init() -> void:
	var p := Profile.new("user://promo_profile.json")
	p.xp = Profile.xp_for_level(19) + 140
	p.stats = {"matches": 64, "wins": 41, "points": 702, "aces": 58, "blocks": 33, "perfects": 412, "power_spikes": 37,
			"longest_rally": 27, "knockdowns": 6, "fever": 29, "playtime": 51240.0}
	p.counters = {"matches": 64, "wins": 41, "perfects": 412, "longest_rally": 27, "blocks": 33, "aces": 58, "power_spikes": 37}
	p.flags["tutorial_done"] = true
	p.flags["welcomed"] = true
	p.flags["tournament_best"] = 3
	p.flags["rally_best"] = 31
	p.flags["unlock_all"] = true
	p.equipped = {"trail": "speed", "ball": "classic", "court": "day", "deco": "ads", "net": "classic"}
	for a in Profile.ACHIEVEMENTS:
		p.achievements[a["id"]] = int(Time.get_unix_time_from_system()) - 86400
	p.ensure_daily("2026-10-05")
	p.save()
	print("promo profile written: level %d" % p.level())
	quit()
