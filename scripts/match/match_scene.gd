class_name MatchScene
extends Node3D
## One complete match: builds the arena, the ball, four athletes with brains, the referee, camera, VFX and HUD.

var arena: Arena
var ball: Ball
var vfx: Vfx
var crowd: Crowd = null
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


func setup(data: Dictionary) -> void:
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
	for i in 4:
		var a := athletes[i]
		if human_slots.has(i):
			var hb := HumanBrain.new()
			hb.index = human_slots[i]
			a.brain = hb
			a.set_human(hb.index)
			a.skill = 0.7
			humans.append(hb)
		else:
			var s: float = opp_skill if a.team == 1 else mate_skill
			if autoplay:
				s = [0.7, 0.7, 0.6, 0.6][i]
			a.brain = AIBrain.new(s)
			a.skill = s

	# --- camera
	cam_rig = CameraRig.new()
	add_child(cam_rig)
	cam_rig.ball = ball
	cam_rig.director = director
	cam_rig.set_style(1)
	director.cam = cam_rig
	for h in humans:
		h.camera = cam_rig.cam

	# --- HUD
	var hud_script: GDScript = load("res://scripts/ui/hud.gd")
	hud = hud_script.new()
	add_child(hud)
	hud.bind(self)
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
	if Game.mode == "training":
		coach = TrainingCoach.new()
		add_child(coach)
		coach.setup(director)
		coach.finished.connect(_on_training_done)
	if Game.profile_enabled:                  # (dev autoplay / --nosave runs switch it off at the top of _build)
		Game.profile.begin_match()
	director.start_match()


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
	director.popup.connect(func(t, k, p): if _log_events: print("[popup] ", t, " ", k))
	ball.floor_contact.connect(_on_floor)
	ball.net_contact.connect(func(p): vfx.hit_burst(p, "good", 0.2); cam_rig.shake(0.2))
	director.score_changed.connect(func(s, st): if _log_events: print("[score] ", s, " serving=", st))


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
	elif big:
		cam_rig.hit_stop(0.03)
	if big and q != "ok":
		hud.flash_speed_lines(0.3, 1.0 if q == "perfect" else 0.6)
	if a.is_human:
		Game.haptic(int(30 + power * 50) + (30 if q == "perfect" else 0), 0.35 + power * 0.5)


var _fever_demo := false
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
		"close_call":
			var cp: Vector3 = data["pos"]
			Sfx.play("crowd_oh", -5.0)
			vfx.ring_pulse(Vector3(cp.x, 0.0, cp.z), Color(1.0, 0.95, 0.5, 1.0))
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


func _on_match_over(winner: int) -> void:
	_over = true
	Sfx.crowd(false)
	await get_tree().create_timer(3.4, true, false, true).timeout
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
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		print("QUIT_AFTER score=", director.score, " stats=", director.stats, " phase=", director.phase)
		get_tree().quit()
	# aim marker for the first human
	if humans.size() > 0:
		vfx.show_aim(humans[0].aim_marker)
	else:
		vfx.show_aim(null)


func _unhandled_input(event: InputEvent) -> void:
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


func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	if hud:
		hud.show_pause(paused)
