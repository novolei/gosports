class_name MatchScene
extends Node3D
## One complete match: builds the arena, the ball, four athletes with brains, the referee, camera, VFX and HUD.

var arena: Arena
var ball: Ball
var vfx: Vfx
var crowd: Crowd = null
var referee: Referee = null
var cam_rig: CameraRig
var director: MatchDirector
var athletes: Array[Athlete] = []
var hud: Node = null
var humans: Array[HumanBrain] = []
var autoplay := false
var paused := false
var _over := false
var _data := {}
var _log_events := false
var _auto_time_scale := 1.0
var _quit_after := -1.0
var _elapsed := 0.0
var _stats_log := []
var replay: ReplaySystem = null
var hawk: HawkEye = null
var _points_since_replay := 2
var _pause_test_done := false
var _last_replay_ours := true          # the previous replay was for the player's team (so one against them may follow)


func setup(data: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE          # Main is PROCESS_MODE_ALWAYS (fades, loading card): the match itself must really freeze on pause
	_data = data
	autoplay = Game.main != null and Game.main.dev.has("autoplay")
	_log_events = Game.main != null and Game.main.dev.has("log")
	if Game.main != null and Game.main.dev.has("timescale"):
		_auto_time_scale = float(Game.main.dev["timescale"])
	if Game.main != null and Game.main.dev.has("quit_after"):
		_quit_after = float(Game.main.dev["quit_after"])
	if not Game.launched_via_start:          # dev: launched straight into the match, not through start_match()
		Game.match_difficulty = int(Game.settings["difficulty"])
		Game.match_points = int(Game.settings["points"])
	if Game.main != null and Game.main.dev.has("points"):
		Game.match_points = int(Game.main.dev["points"])
	if Game.main != null and Game.main.dev.has("diff"):
		Game.match_difficulty = int(Game.main.dev["diff"])
	if Game.main != null and Game.main.dev.has("mode"):
		Game.mode = String(Game.main.dev["mode"])
	if Game.main != null and Game.main.dev.has("team_a"):
		Game.team_a = String(Game.main.dev["team_a"]).split(",")
	if Game.main != null and Game.main.dev.has("team_b"):
		Game.team_b = String(Game.main.dev["team_b"]).split(",")
	_build()


func _build() -> void:
	Game.profile_enabled = not (Game.main != null and (Game.main.dev.has("autoplay") or Game.main.dev.has("nosave")))
	arena = Arena.new()
	add_child(arena)
	arena.build(Game.settings["quality"])
	if int(Game.settings["quality"]) >= 1 and not Game.dbg("nocrowd"):
		crowd = Crowd.new()
		add_child(crowd)
		crowd.build(arena, 30 if int(Game.settings["quality"]) >= 2 else 14, int(Game.settings["quality"]))
	ball = Ball.new()
	if Game.profile != null and Game.profile_enabled:
		ball.skin_tint = Game.profile.equipped_item("ball").get("tint", Color.WHITE)
		ball.trail_style = String(Game.profile.equipped_item("trail")["id"])
	if Game.main != null and Game.main.dev.has("trail"):
		ball.trail_style = String(Game.main.dev["trail"])
	if Game.main != null and Game.main.dev.has("ballskin"):
		ball.skin_tint = Profile.item("ball", String(Game.main.dev["ballskin"]))["tint"]
	add_child(ball)
	vfx = Vfx.new()
	add_child(vfx)
	vfx.ball = ball
	director = MatchDirector.new()
	add_child(director)
	director.vfx = vfx

	# --- athletes
	var ids_a: Array = Game.team_a
	var ids_b: Array = Game.team_b
	var diff: int = Game.match_difficulty
	var opp_skill: float = [0.3, 0.5, 0.72, 0.93][diff]
	if Game.is_practice():
		opp_skill = 0.95                # the ball machine does not miss
	var mate_skill: float = clampf(opp_skill + 0.15, 0.4, 0.9)
	var roster := [ids_a[0], ids_a[1], ids_b[0], ids_b[1]]
	for i in 4:
		var a := Athlete.new()
		add_child(a)
		a.setup(i / 2, i % 2, Roster.by_id(roster[i]), ball, director)
		athletes.append(a)
	director.setup(athletes, ball, Game.match_points, diff)
	if not Game.dbg("noref"):
		referee = Referee.new()
		add_child(referee)
		referee.build(director, ball, Arena.LOOKS.get(arena.theme_id, Arena.LOOKS["day"]), self)
	if arena.deco_id == "press" and not Game.dbg("nodeco"):
		var press := PressCrew.new()
		add_child(press)
		var used_p: Array = Game.team_a + Game.team_b
		if referee != null:
			used_p.append(referee.entry["id"])
		press.build(self, director, Arena.LOOKS.get(arena.theme_id, Arena.LOOKS["day"]), used_p)
	if arena.deco_id == "team" and not Game.dbg("nodeco"):
		var bench := BenchCrew.new()
		add_child(bench)
		var used: Array = Game.team_a + Game.team_b
		if referee != null:
			used.append(referee.entry["id"])
		bench.build(director, Arena.LOOKS.get(arena.theme_id, Arena.LOOKS["day"]), used)
	if Game.is_practice():
		director.mode_rules = Game.mode
		director.serving_team = 1
		director.target_points = 9999
		athletes[2].friendly = true
		athletes[3].friendly = true
	# --- control assignment
	var human_slots := {}   # athlete index -> player number
	if not autoplay:
		match Game.mode:
			"solo", "rally", "training", "tournament": human_slots = {0: 1}
			"coop": human_slots = {0: 1, 1: 2}
			"versus": human_slots = {0: 1, 2: 2}
	vfx.director = director
	for i in 4:
		var a := athletes[i]
		if human_slots.has(i):
			var hb := HumanBrain.new()
			hb.index = human_slots[i]
			a.brain = hb
			a.set_human(hb.index)
			a.skill = 0.7
			humans.append(hb)
			vfx.humans.append(a)
		else:
			var s: float = opp_skill if a.team == 1 else mate_skill
			if autoplay:
				s = [0.7, 0.7, 0.6, 0.6][i]
			a.brain = AIBrain.new(s)
			a.skill = s

	if not humans.is_empty() and not Game.is_practice() and not Game.dbg("nobanter"):
		var banter := MateBanter.new()
		add_child(banter)
		banter.build(self, director)

	# --- camera
	cam_rig = CameraRig.new()
	add_child(cam_rig)
	cam_rig.ball = ball
	cam_rig.director = director
	cam_rig.set_style(1)
	for a in athletes:
		if a.is_human:
			cam_rig.follow_players.append(a)
	director.cam = cam_rig
	for h in humans:
		h.camera = cam_rig.cam

	if Game.mode == "training":                   # (before the HUD, which builds the tutorial card from it)
		coach = TrainingCoach.new()
		add_child(coach)
		coach.setup(director)
		coach.finished.connect(_on_training_done)

	# --- HUD
	var hud_script: GDScript = load("res://scripts/ui/hud.gd")
	hud = hud_script.new()
	add_child(hud)
	hud.bind(self)
	if not Game.is_practice() and Game.settings.get("replays", true) and (not autoplay or Game.main.dev.has("replay")):
		replay = ReplaySystem.new()
		add_child(replay)
		replay.setup(self)
		hawk = HawkEye.new()
		add_child(hawk)
	if Game.dbg("nohud"):
		hud.visible = false

	if Game.main != null and Game.main.dev.has("humanbot") and not humans.is_empty():
		var bot := HumanBot.new()
		add_child(bot)
		bot.attach(self)
	var bodies := BodyCollisions.new()
	add_child(bodies)
	bodies.setup(athletes, director)
	if Game.main != null and Game.main.dev.has("dbgpose"):
		PoseProbe.new().attach(self)
	_connect_signals()
	Sfx.music("bgm_match")
	Sfx.crowd(true)
	cam_rig.intro()
	if _auto_time_scale != 1.0:
		Game.base_time_scale = _auto_time_scale
		Engine.time_scale = _auto_time_scale
	if Game.profile_enabled:                  # (dev autoplay / --nosave runs switch it off at the top of _build)
		Game.profile.begin_match()
	director.start_match()
	if Game.main != null and Game.main.dev.has("refcam"):
		var rc := String(Game.main.dev["refcam"]).split(",")
		cam_rig.set_free(Vector3(float(rc[0]), float(rc[1]), float(rc[2])), Vector3(float(rc[3]), float(rc[4]), float(rc[5])), float(rc[6]))
	if Game.main != null and Game.main.dev.has("propshow"):          # dev: --propshow lines every umpire prop up in front of the camera
		var ids := ["pencil", "eraser", "paper", "plane", "sock", "banana", "duck", "book", "fish", "slipper", "hammer"]
		for i in ids.size():
			var pr := ThrowProp.make(ids[i], 3.0)
			add_child(pr)
			pr.global_position = Vector3(-4.4 + 0.88 * float(i), 1.1, 5.0)
			pr.rotation = Vector3(0.5, 0.6 if i % 2 == 0 else -0.6, 0.0)
	if Game.main != null and Game.main.dev.has("hawkdemo"):          # dev: --hawkdemo=in|out plays the hawk-eye review on a synthetic call
		_dev_hawk(String(Game.main.dev["hawkdemo"]))
	if Game.main != null and Game.main.dev.has("callshot"):          # dev: --callshot=in|out|inclose|outclose fires a fake line call after 4 s
		_dev_call(String(Game.main.dev["callshot"]))
	if director.vs_time > 0.0:
		cam_rig.start_vs()
		ball.visible = false                    # no stray ball on the floor in the broadcast shot


func _connect_signals() -> void:
	for a in athletes:
		a.hit_done.connect(_on_hit_done)
		a.whiffed.connect(func(_a): pass)
		a.jumped.connect(func(_a): pass)
	director.rally_event.connect(_on_rally_event)
	director.point_scored.connect(_on_point)
	director.match_over.connect(_on_match_over)
	director.fever_started.connect(_on_fever_started)
	director.fever_ended.connect(_on_fever_ended)
	director.popup.connect(_on_popup_fx)
	ball.floor_contact.connect(_on_floor)
	ball.net_contact.connect(func(p): vfx.hit_burst(p, "good", 0.2); cam_rig.shake(0.2))
	director.score_changed.connect(func(s, st): if _log_events: print("[score] ", s, " serving=", st))


func _dev_hawk(kind: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var inside := not kind.ends_with("out")
	var pos := Vector3(4.54 if inside else 4.64, 0.14, 3.2)
	if kind.begins_with("end"):
		pos = Vector3(1.0, 0.14, 6.98 if inside else 7.1)
	hawk = hawk if hawk != null else HawkEye.new()
	if hawk.get_parent() == null:
		add_child(hawk)
	await hawk.play(self, {"floor": {"pos": pos, "vel": Vector3(-1.5, -7.0, 2.0), "inside": inside, "dist": minf(4.5 - absf(pos.x), 7.0 - absf(pos.z)) + 0.04}})
	get_tree().quit()


func _dev_call(kind: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var p := Vector3(4.2, 0.3, 3.0)
	match kind:
		"out": p = Vector3(5.05, 0.3, 3.2)
		"inclose": p = Vector3(4.46, 0.3, 3.2)
		"outclose": p = Vector3(4.62, 0.3, 3.2)
	director.popup.emit("In" if kind.begins_with("in") else "Out", "inout", p)


func _on_popup_fx(text: String, kind: String, pos: Vector3) -> void:
	if _log_events:
		print("[popup] ", text, " ", kind)
	if kind == "inout":
		vfx.line_call(pos, text == "In")
		Sfx.play("ui_confirm" if text == "In" else "ui_back", -7.0)


func _on_hit_done(a: Athlete, info: Dictionary) -> void:
	var kind: String = info["kind"]
	var q: String = info["quality"]
	var contact: Vector3 = info["contact"]
	var snd: String = {"bump": "hit_bump", "set": "hit_set", "spike": "hit_spike", "serve": "hit_serve", "dig": "hit_bump"}[kind]
	if q == "perfect":
		Sfx.play("hit_perfect", 0.0, 1.0, 0.03)
		Sfx.play("perfect", -8.0)
	else:
		Sfx.play(snd, 0.0, 1.0, 0.06)
	vfx.hit_burst(contact, q, info["power"])
	ball.flash(0.5 if q != "perfect" else 1.0)
	_hit_feel(a, kind, q, float(info["power"]))
	if kind == "spike" or (kind == "serve" and info["power"] > 0.8):
		var amt := 0.35 if q == "perfect" else 0.15
		cam_rig.shake(amt)
		if q == "perfect" and kind == "spike":
			cam_rig.punch(7.0, 0.4, 0.22)
	if _log_events:
		print("[hit] t=%.1f team=%d %s %s %s touch=%d" % [_elapsed, a.team, a.display_name, kind, q, director.touches[a.team]])
	if Game.main != null and Game.main.dev.has("hitshots"):
		_hit_shot(kind, a.team)
	# human controlled athletes drop their touch-aim marker after hitting
	for h in humans:
		if h.index == a.player_index:
			h.clear_touch_aim()


## hit-stop, squash & stretch, speed lines, vibration - scaled by how good and how hard the hit was
func _hit_feel(a: Athlete, kind: String, q: String, power: float) -> void:
	var big := kind == "spike" or (kind == "serve" and power > 0.8)
	ball.punch_shape((0.5 + power * 0.7) * (1.15 if q == "perfect" else 0.85))
	if q == "perfect":
		cam_rig.hit_stop(0.055 if big else 0.032)
		cam_rig.punch(2.2 if not big else 3.5, 0.0, 0.05)
		if big:
			cam_rig.roll_kick(randf_range(1.4, 2.2) * (1.0 if a.global_position.x < 0.0 else -1.0))
			hud.flash_screen(0.2 if power > 0.8 else 0.12, 0.14)
	elif big:
		cam_rig.hit_stop(0.03)
	if big and q != "ok":
		hud.flash_speed_lines(0.3, 1.0 if q == "perfect" else 0.6)
	if a.is_human:
		Game.haptic(int(30 + power * 50) + (30 if q == "perfect" else 0), 0.35 + power * 0.5)


var _fever_demo := false
var _demo_done := false


## dev: --demo=matchpoint|pill|win|title shows one HUD cue and saves --demoshot=<png> a moment later
func _run_demo(kind: String) -> void:
	match kind:
		"matchpoint": hud.show_match_banner("赛点", 0)
		"pill": hud.show_pill("比赛结束!", 2.0)
		"win": hud.show_win_banner(0)
		"title": hud.show_title_tag(3.0)
	await get_tree().create_timer(1.0, true, false, true).timeout
	if Game.main.dev.has("demoshot"):
		get_viewport().get_texture().get_image().save_png(str(Game.main.dev["demoshot"]))
		get_tree().quit()
var coach: TrainingCoach = null
var _hit_shot_counts := {}


func _hit_shot(kind: String, team: int) -> void:
	var key := "%s_%d" % [kind, team]
	var n: int = _hit_shot_counts.get(key, 0)
	if n >= 2:
		return
	_hit_shot_counts[key] = n + 1
	for i in 2:
		await get_tree().create_timer(0.07 + i * 0.08).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%s_%d_%d.png" % [Game.main.dev["hitshots"], key, n, i])


func _on_rally_event(ev: String, data: Dictionary) -> void:
	match ev:
		"toss":
			Sfx.play("toss", -4.0)
		"block":
			cam_rig.shake(0.3)
			vfx.hit_burst(ball.global_position, "perfect" if data.get("kill", false) else "good", 0.6)
		"match_point":
			Sfx.play("match_point", -4.0)
			Sfx.music_tension(true)
		"vs_end":
			cam_rig.intro()
			ball.visible = true
		"close_call":
			var cp: Vector3 = data["pos"]
			Sfx.play("crowd_oh", -5.0)
		"point":
			pass


func _on_training_done() -> void:
	await get_tree().create_timer(1.2).timeout
	if is_inside_tree() and not _over:
		director.finish_practice()


func _on_fever_started(team: int) -> void:
	Sfx.play("fever", -3.0)
	cam_rig.punch(5.0, 0.25, 0.3)
	vfx.confetti(Vector3(0, 0, Court.team_sign(team) * 3.5), 40)
	for a in athletes:
		if a.team == team:
			vfx.ring_pulse(Vector3(a.global_position.x, 0.0, a.global_position.z), Color(1.0, 0.6, 0.15, 1.0))
	if crowd:
		crowd.cheer(true)
	if team == 0:
		Game.haptic(200, 0.85)


func _on_fever_ended(team: int) -> void:
	if crowd and not director.is_fever(1 - team):
		crowd.cheer(false)


func _on_floor(pos: Vector3) -> void:
	Sfx.play("bounce", -3.0, 1.0, 0.08)
	vfx.floor_impact(pos)


func _on_point(team: int, reason: String, pos: Vector3) -> void:
	if crowd:
		crowd.cheer(true)
		get_tree().create_timer(2.5).timeout.connect(func(): if crowd: crowd.cheer(false))
	cam_rig.point_focus(pos, team)
	cam_rig.slowmo(0.35, 0.55)
	if hawk != null and HawkEye.wanted(director._point_info):
		director.hold_next = true
		_run_hawkeye()
	elif _replay_wanted(reason):
		director.hold_next = true
		_run_point_replay()
	var winners_center := Vector3.ZERO
	var n := 0
	for a in athletes:
		if a.team == team:
			winners_center += a.global_position
			n += 1
	vfx.confetti(winners_center / maxf(n, 1.0), 60)
	var human_team_won := false
	for a in athletes:
		if a.is_human and a.team == team:
			human_team_won = true
	Sfx.play("cheer" if true else "", -4.0)
	if human_team_won or team == 0:
		Sfx.play("point_win", -6.0)
	else:
		Sfx.play("point_lose", -6.0)


## which points deserve an instant replay. The replay is a reward, so it is weighted towards the human side:
##  * a point the player's team wins: any highlight (ace, spike winner, kill block, power spike, 6+ touch rally) -> replay when at
##    least 2 points have passed since the last one; and a guarantee: after 5 points without one, any decent rally (3+) gets it
##  * a point against the player: only the exceptional ones (ace, power spike, 10+ touch rally), never twice in a row and at least
##    4 points apart
func _replay_wanted(reason: String) -> bool:
	if replay == null:
		return false
	_points_since_replay += 1
	var info: Dictionary = director._point_info
	var winner := int(info.get("winner", 0))
	var kind := String(info.get("kind", ""))
	var rally := director.rally_len
	var humans := {}
	for a in athletes:
		if a.is_human:
			humans[a.team] = true
	var ours := humans.is_empty() or humans.has(winner) or humans.size() > 1
	var mistake := reason == "出界" or reason == "触网" or reason == "发球失误" or reason == "发球超时"     # points that came from an error are not highlights ...
	var highlight := (reason == "ACE!" or kind == "spike" or kind == "block" or ball.combo or rally >= 6) if not mistake else rally >= 12   # ... unless it was a marathon
	var want := false
	if ours:
		want = (highlight and _points_since_replay >= 2) or (_points_since_replay >= 5 and rally >= 3 and not mistake)
	else:
		var wow := reason == "ACE!" or ball.combo or rally >= 10
		want = wow and _points_since_replay >= 4 and _last_replay_ours
	if Game.main != null and Game.main.dev.has("replay") and highlight:
		want = true
	if _log_events:
		print("[replaycheck] winner=%d ours=%s kind=%s rally=%d reason=%s since=%d -> %s" % [winner, ours, kind, rally, reason, _points_since_replay, want])
	if want:
		_points_since_replay = 0
		_last_replay_ours = ours
	return want


func _run_hawkeye() -> void:
	await hawk.play(self, director._point_info)
	director.hold_next = false


func _run_point_replay() -> void:
	await get_tree().create_timer(1.9, true, false, true).timeout
	if is_inside_tree() and not _over and replay.can_play():
		replay.start(0.6)
		await replay.finished
	director.hold_next = false


func _on_match_over(winner: int) -> void:
	_over = true
	Sfx.crowd(false)
	if Game.is_practice():
		hud.show_banner("练习结束!", UIKit.YELLOW, 130, 2.5, UIKit.INK)
		await get_tree().create_timer(3.4, true, false, true).timeout
	else:
		await get_tree().create_timer(1.9, true, false, true).timeout
		if is_inside_tree() and replay != null and replay.can_play():
			replay.start(0.8)
			await replay.finished
		if is_inside_tree():
			hud.show_win_banner(winner)
			await get_tree().create_timer(3.0, true, false, true).timeout
	if is_inside_tree():
		Game.last_result = {
			"winner": winner, "score": director.score.duplicate(), "stats": director.stats.duplicate(true),
			"team_a": Game.team_a.duplicate(), "team_b": Game.team_b.duplicate(), "mode": Game.mode,
		}
		if winner == 0:
			Game.player_stats["won"] += 1
		if Game.is_practice():
			Game.last_result["practice"] = {"mode": Game.mode, "best": director.rally_best, "total": director.rally_total, "rallies": director.rally_count,
					"completed": coach != null and coach.progress() >= TrainingCoach.ITEMS.size()}
			if Game.profile != null and Game.profile_enabled:
				Game.last_result["reward"] = Game.profile.finish_practice(Game.last_result["practice"])
		elif Game.profile != null and Game.profile_enabled:
			var st: Dictionary = director.stats
			Game.last_result["reward"] = Game.profile.finish_match({
				"won": winner == 0, "score": director.score.duplicate(), "target": director.target_points,
				"difficulty": Game.match_difficulty, "mode": Game.mode, "time": _elapsed, "deuce": director.deuce,
				"comeback": winner == 0 and int(director.max_deficit[0]) >= 5, "stats": st, "spike_points": int(st["spike_points"][0]),
			})
		Game.save_settings()
		if autoplay and Game.main.dev.has("quit_on_over"):
			var lens := []
			var reasons := {}
			for r in director.rally_history:
				lens.append(r["len"])
				reasons[r["reason"]] = reasons.get(r["reason"], 0) + 1
			print("MATCH OVER score=", director.score, " rallies=", lens, " reasons=", reasons, " time=%.0f" % _elapsed)
			get_tree().quit()
			return
		Game.goto("results", Game.last_result)


func _physics_process(dt: float) -> void:
	var _p := Prof.t0()
	_physics_process_impl(dt)
	Prof.add("scene", _p)


func _physics_process_impl(dt: float) -> void:
	_elapsed += dt
	if Game.main != null and Game.main.dev.has("fever") and _elapsed > 7.0 and not _fever_demo:
		_fever_demo = true
		director.add_hype(0, 1.0)            # dev: jump straight into fever time
	if Game.main != null and Game.main.dev.has("demo") and _elapsed > 7.0 and not _demo_done:
		_demo_done = true
		_run_demo(String(Game.main.dev["demo"]))
	if Game.main != null and Game.main.dev.has("pauseshot") and _elapsed > 9.0 and not paused:
		toggle_pause()
	if Game.main != null and Game.main.dev.has("pausetest") and _elapsed > 6.0 and not paused and not _pause_test_done:
		_pause_test_done = true
		_run_pause_test()
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		print("QUIT_AFTER score=", director.score, " stats=", director.stats, " phase=", director.phase)
		get_tree().quit()
	# aim zone for the first human: only while a hit is imminent (or for an explicit aim), never while just running about
	if humans.size() > 0 and not paused:
		var hb: HumanBrain = humans[0]
		var ha: Athlete = null
		for a in athletes:
			if a.brain == hb:
				ha = a
		if _log_events and Engine.get_physics_frames() % 60 == 0:
			print("[aimdbg] marker=%s src=%s imminent=%s phase=%d ha=%s" % [str(hb.aim_marker), hb.aim_source, str(ha != null and hb.hit_imminent(ha)), director.phase, str(ha != null)])
		var show := hb.aim_marker != null and ha != null and (hb.aim_source == "key" or hb.aim_source == "touch" or hb.hit_imminent(ha))
		if show and director.phase != MatchDirector.P.POINT and director.phase != MatchDirector.P.OVER:
			var info := director.aim_preview(ha)
			if _log_events and Engine.get_physics_frames() % 60 == 0:
				print("[aimdbg] info=", info)
			if info.is_empty() and (hb.aim_source == "key" or hb.aim_source == "touch"):
				vfx.show_aim(hb.aim_marker)                      # plain marker for the explicit aim on a first / second touch
			elif info.is_empty():
				vfx.show_aim(null)
			else:
				vfx.show_aim(hb.aim_marker, info)
		else:
			vfx.show_aim(null)
	elif humans.is_empty():
		vfx.show_aim(null)


func _unhandled_input(event: InputEvent) -> void:
	if director != null and director.phase == MatchDirector.P.INTRO and director.vs_time > 0.0:
		var press: bool = event.is_action_pressed("p1_hit") or event.is_action_pressed("p1_jump")
		press = press or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if press:
			director.skip_vs()
	if event.is_action_pressed("pause") and not _over:
		toggle_pause()
	if event.is_action_pressed("camera_toggle"):
		cam_rig.set_style((cam_rig.style + 1) % 3)


func _notification(what: int) -> void:
	# auto-pause when the window loses focus / the phone app goes to the background / Android back button
	if _over or paused or director == null:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if Game.main != null and (Game.main.dev.has("autoplay") or Game.main.dev.has("shot") or Game.main.dev.has("burst")):
			return
		toggle_pause()


## dev: --pausetest pauses for 2 real seconds and prints what moved (it must be nothing)
func _run_pause_test() -> void:
	var snap := func() -> Dictionary:
		var d := {"ball": ball.global_position, "t": director.match_time, "anim": athletes[0].rig.anim.current_animation_position, "elapsed": _elapsed}
		if crowd != null and not crowd._rigs.is_empty():
			d["crowd"] = crowd._rigs[0].anim.current_animation_position
		d["pos"] = athletes[2].global_position
		return d
	var before: Dictionary = snap.call()
	toggle_pause()
	await get_tree().create_timer(2.0, true, false, true).timeout
	var after: Dictionary = snap.call()
	var moved := []
	for k in before.keys():
		if before[k] != after[k]:
			moved.append("%s: %s -> %s" % [k, str(before[k]), str(after[k])])
	print("[pausetest] changed during 2 s of pause: ", moved if not moved.is_empty() else "nothing")
	get_tree().quit()


func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	if hud:
		hud.show_pause(paused)
