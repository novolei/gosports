class_name MatchDirector
extends Node
## Referee + coach: rules, scoring, serve rotation, shot planning (how a hit turns into a ball trajectory),
## team intercept planning for AI / assist, blocks.

signal score_changed(score: Array, serving_team: int)
signal popup(text: String, kind: String, pos: Vector3)
signal phase_changed(phase: int)
signal match_over(winner_team: int)
signal serve_started(server: Athlete)
signal rally_event(ev: String, data: Dictionary)
signal point_scored(team: int, reason: String, pos: Vector3)
signal practice_rally_over(length: int, lost_life: bool)
signal fever_started(team: int)
signal fever_ended(team: int)

enum P { INTRO, SERVE_PREP, SERVING, RALLY, POINT, OVER }

var phase: int = P.INTRO
var score := [0, 0]
var target_points := 11
var serving_team := 0
var server: Athlete = null
var server_idx := [0, 0]
var athletes: Array[Athlete] = []
var ball: Ball
var touches := [0, 0]
var last_team := -1
var last_hitter: Athlete = null
var rally_len := 0
var feed_target: Athlete = null            # practice: aim the ball machine at this athlete instead of the human (the coach sets it)
var phase_time := 0.0
var plans := [{}, {}]
var set_target := [Vector3.ZERO, Vector3.ZERO]     # where the last set was aimed (per team)
var vfx = null
var cam = null
var difficulty := 1
var sets_won := [0, 0]
var chain := [0, 0]                 # consecutive "perfect" touches of a team in its current possession
var stats := {"aces": [0, 0], "spikes": [0, 0], "blocks": [0, 0], "perfects": [0, 0], "longest": 0,
		"power_spikes": [0, 0], "knockdowns": [0, 0], "fever": [0, 0], "spike_points": [0, 0]}
const FEVER_TIME := 9.0
var mode_rules := "normal"          # normal | rally (3 lives, count the rally) | training (endless, coach checklist)
var lives := 3
var rally_best := 0
var rally_total := 0
var rally_count := 0
var hype := [0.0, 0.0]              # 0..1 excitement of each team; full = fever time
var fever_left := [0.0, 0.0]        # seconds of fever time remaining
var deuce := false                  # both teams reached match point territory
var max_deficit := [0, 0]           # the biggest deficit each team came back from
var _last_kind := ""
var _serve_timer := 0.0
var _intro_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _point_info := {}
var _last_plan_t := 0.0
var autoplay := false
var rally_history: Array = []


func setup(p_athletes: Array[Athlete], p_ball: Ball, p_target: int, p_difficulty: int) -> void:
	athletes = p_athletes
	ball = p_ball
	target_points = p_target
	difficulty = p_difficulty
	_rng.randomize()
	ball.floor_contact.connect(_on_floor_contact)
	ball.net_contact.connect(_on_net_contact)
	for a in athletes:
		a.director = self


# ------------------------------------------------------------------ helpers
func team_athletes(t: int) -> Array[Athlete]:
	var r: Array[Athlete] = []
	r.append(athletes[t * 2])
	r.append(athletes[t * 2 + 1])
	return r


func mate_of(a: Athlete) -> Athlete:
	return athletes[a.team * 2 + (1 - a.slot)]


func opponents_of(t: int) -> Array[Athlete]:
	return team_athletes(1 - t)


func phase_allows_play() -> bool:
	return phase == P.SERVING or phase == P.RALLY


func is_serving_athlete(a: Athlete) -> bool:
	return a == server and (phase == P.SERVE_PREP or phase == P.SERVING)


func touch_no(t: int) -> int:
	return (touches[t] if last_team == t else 0) + 1


func is_my_team_ball_incoming(a: Athlete) -> bool:
	## is the ball (about) to come to a's side?
	if ball.live:
		return ball.vel.z * Court.team_sign(a.team) > 0.0 and ball.global_position.z * Court.team_sign(a.team) < 0.2
	return false


func can_hit(a: Athlete) -> bool:
	if ball == null:
		return false
	if a.state == Athlete.S.KNOCKED:
		return false
	match phase:
		P.SERVE_PREP:
			return false
		P.SERVING:
			return a == server and not ball.floor_touched
		P.RALLY:
			if ball.floor_touched:
				return false
			if a.team == last_team:
				if touches[a.team] >= 3:
					return false
				if last_hitter == a:
					return false
			return true
	return false


# ------------------------------------------------------------------ match flow
func start_match() -> void:
	score = [0, 0]
	serving_team = 1 if is_practice() else 0          # practice: the ball machine serves, the human only receives
	server_idx = [0, 0]
	_set_phase(P.INTRO)
	_intro_timer = 2.4
	_formation_for_serve(true)
	popup.emit("准备!", "info", Vector3(0, 2.5, 0))


func _set_phase(p: int) -> void:
	phase = p
	phase_time = 0.0
	phase_changed.emit(p)


func _physics_process(dt: float) -> void:
	var _p := Prof.t0()
	_physics_process_impl(dt)
	Prof.add("director", _p)


func _physics_process_impl(dt: float) -> void:
	if athletes.is_empty():
		return
	phase_time += dt
	_update_hype(dt)
	match phase:
		P.INTRO:
			_intro_timer -= dt
			if _intro_timer <= 0.0:
				_begin_serve_prep()
		P.SERVE_PREP:
			# wait until everyone is in place, then the server picks the ball up
			if server != null and not server.is_busy() and server.state == Athlete.S.READY and _all_in_place():
				server.begin_serve_hold()
				serve_started.emit(server)
				_serve_timer = 0.0
				_set_phase(P.SERVING)
				_serve_prompt_given = false
		P.SERVING:
			_serve_timer += dt
		P.RALLY:
			_update_plans(dt)
			_check_blocks()
		P.POINT:
			if phase_time > (1.5 if is_practice() else 2.7):
				if phase == P.POINT:
					_next_point()
	if phase == P.SERVING or phase == P.RALLY:
		if phase == P.SERVING:
			_update_plans(dt)
		# ball far away / stuck safeguard
		if ball.global_position.length() > 60.0:
			_end_point(1 - serving_team if last_team < 0 else 1 - last_team, "out", ball.global_position)


var _serve_prompt_given := false


func _all_in_place() -> bool:
	for a in athletes:
		if a._auto_walk_active():
			return false
	return true


func _begin_serve_prep() -> void:
	server = athletes[serving_team * 2 + server_idx[serving_team]]
	touches = [0, 0]
	last_team = -1
	last_hitter = null
	rally_len = 0
	_set_phase(P.SERVE_PREP)
	_formation_for_serve(false)
	# the server already carries the ball while walking to the serving spot
	ball.hold(server.rig.hand_l, Vector3(0.0, 0.16, 0.0))


func _formation_for_serve(instant: bool) -> void:
	var rx := [-2.3, 2.3]
	for t in 2:
		var s := Court.team_sign(t)
		var is_serving := t == serving_team
		var srv := athletes[t * 2 + server_idx[t]]
		var other := athletes[t * 2 + (1 - server_idx[t])]
		for a in team_athletes(t):
			var p := Vector3.ZERO
			if is_serving and a == srv:
				p = Vector3(_rng.randf_range(-2.0, 2.0) if not a.is_human else 0.0, 0, 8.3 * s)
			elif is_serving:
				p = Vector3(2.4 if srv.global_position.x < 0.0 else -2.4, 0, 3.2 * s)
			else:
				# receivers: W formation
				p = Vector3(-2.4 if a == other else 2.4, 0, (4.6 if a == other else 4.0) * s)
			a.reset_to_ready()
			a.state = Athlete.S.READY
			if instant:
				a.teleport(p)
				a.yaw = 0.0 if t == 0 else PI
				a.rotation.y = a.yaw
			else:
				a.auto_walk_to(p)
	ball.place(Vector3(0, 1.0, 0) + (server.global_position if server else Vector3(0, 0, 8.3)))
	ball.set_trail(false)


func server_toss(a: Athlete) -> void:
	if phase != P.SERVE_PREP and phase != P.SERVING:
		return
	if a != server:
		return
	if a.state != Athlete.S.SERVE_HOLD:
		return
	a.do_toss()
	rally_event.emit("toss", {"athlete": a})


# ------------------------------------------------------------------ practice modes
func is_practice() -> bool:
	return mode_rules != "normal"


## a rally ended in a practice mode: no score, the human side may lose a life (rally challenge only)
func _practice_point(winner: int, reason: String, pos: Vector3) -> void:
	if phase == P.POINT or phase == P.OVER:
		return
	var length := rally_len
	rally_count += 1
	rally_total += length
	rally_best = maxi(rally_best, length)
	var lost := winner == 1 and mode_rules == "rally"
	if lost:
		lives -= 1
	_point_info = {"winner": winner, "reason": reason, "pos": pos}
	_set_phase(P.POINT)
	practice_rally_over.emit(length, lost)
	if Game.main != null and Game.main.dev.has("log"):
		print("[practice] rally over len=%d best=%d lives=%d reason=%s" % [length, rally_best, lives, reason])
	if mode_rules == "rally" and lives <= 0:
		finish_practice()


func finish_practice() -> void:
	if phase == P.OVER:
		return
	_set_phase(P.OVER)
	match_over.emit(0)


## the ball machine: the friendly opponents lob the ball softly to where the human stands
func _shot_friendly(a: Athlete, p0: Vector3, kind: String) -> Dictionary:
	var S := Court.team_sign(a.team)
	var tgt := Vector3(0.0, 0.0, -S * 4.5)
	for h in athletes:
		if h.is_human and h.team != a.team:
			tgt = Vector3(h.global_position.x, 0.0, h.global_position.z)
			break
	if feed_target != null:
		tgt = Vector3(feed_target.global_position.x, 0.0, feed_target.global_position.z)
	tgt += _jitter(1.0)
	tgt.x = clampf(tgt.x, -Court.PLAYER_MAX_X, Court.PLAYER_MAX_X)
	tgt.z = clampf(absf(tgt.z), 2.2, Court.PLAYER_MAX_Z) * -S
	var v := _solve_over_net(p0, Vector3(tgt.x, Court.BALL_R, tgt.z), 1.6 if kind == "serve" else 1.4)
	return {"vel": v, "power": 0.25, "target": tgt, "label": ""}


# ------------------------------------------------------------------ hype / fever time
## excitement grows with perfect hits, chains, blocks, saves and big points; full = FEVER_TIME seconds of fever:
## a wider timing window and extra power for that team, a fiery trail, a roaring crowd
func add_hype(team: int, amount: float) -> void:
	if phase == P.OVER or team < 0 or fever_left[team] > 0.0:
		return
	hype[team] = clampf(float(hype[team]) + amount * (1.0 + 0.5 * float(_perk_hype(team))), 0.0, 1.0)
	if hype[team] >= 1.0:
		_start_fever(team)


func _perk_hype(team: int) -> int:
	for a in athletes:
		if a.team == team and a.perk == "morale":
			return 1
	return 0


func _start_fever(team: int) -> void:
	if Game.main != null and Game.main.dev.has("log"):
		print("[fever] start team %d phase %d" % [team, phase])
	hype[team] = 1.0
	fever_left[team] = FEVER_TIME
	stats["fever"][team] += 1
	if team == 0:
		Game.live("fever")
	fever_started.emit(team)


func _end_fever(team: int) -> void:
	if Game.main != null and Game.main.dev.has("log"):
		print("[fever] end team %d phase %d left %.1f" % [team, phase, float(fever_left[team])])
	fever_left[team] = 0.0
	hype[team] = 0.0
	fever_ended.emit(team)


func is_fever(team: int) -> bool:
	return team >= 0 and float(fever_left[team]) > 0.0


func _update_hype(dt: float) -> void:
	for t in 2:
		if fever_left[t] > 0.0:
			if phase == P.RALLY or phase == P.SERVING or phase == P.SERVE_PREP:
				fever_left[t] = float(fever_left[t]) - dt
			if fever_left[t] <= 0.0:
				_end_fever(t)
		elif phase == P.SERVE_PREP or phase == P.SERVING:
			hype[t] = maxf(float(hype[t]) - 0.01 * dt, 0.0)      # cools down slowly between rallies


# ------------------------------------------------------------------ hits
func on_hit(a: Athlete, info: Dictionary) -> void:
	var kind: String = info["kind"]
	if kind == "serve":
		_set_phase(P.RALLY)
		touches = [0, 0]
	if a.team != last_team:
		touches[a.team] = 0
		touches[1 - a.team] = 0
		chain[a.team] = 0
	touches[a.team] += 1
	chain[1 - a.team] = 0
	last_team = a.team
	last_hitter = a
	rally_len += 1
	stats["longest"] = maxi(stats["longest"], rally_len)
	if info["quality"] == "perfect":
		stats["perfects"][a.team] += 1
	_last_kind = kind
	if kind == "spike":
		stats["spikes"][a.team] += 1
	var contact: Vector3 = info["contact"]
	var label: String = info.get("label", "")
	var q: String = info["quality"]
	if kind == "serve":
		chain[a.team] = 0
	if q == "perfect":
		chain[a.team] += 1
	else:
		chain[a.team] = 0
	match q:
		"perfect":
			var n: int = chain[a.team]
			popup.emit("Nice!" if n < 2 else "Nice! ×%d" % n, "perfect", contact + Vector3(0, 0.6, 0))
		"good":
			if a.is_human:
				popup.emit("Nice", "good", contact + Vector3(0, 0.6, 0))
		_:
			# a little too early / too late (only worth telling the humans)
			if a.is_human and kind != "serve":
				popup.emit("早了!" if info.get("early", true) else "晚了!", "late", contact + Vector3(0, 0.6, 0))
	if label != "":
		popup.emit(label, "label", contact + Vector3(0, 1.1, 0))
	var gain := 0.0
	match q:
		"perfect":
			gain = 0.10 + 0.04 * float(mini(int(chain[a.team]), 4))
		"good":
			gain = 0.04
	if kind == "dig":
		gain += 0.06
	add_hype(a.team, gain)
	if rally_len >= 4:                       # long rallies warm the whole arena up
		add_hype(0, 0.012)
		add_hype(1, 0.012)
	rally_event.emit("hit", {"athlete": a, "info": info, "touch": touches[a.team]})
	# the other team's AI gets a short reaction delay from the brains themselves


func plan_shot(a: Athlete, kind: String, quality: String, face: Vector2) -> Dictionary:
	var p0 := ball.global_position
	var S := Court.team_sign(a.team)
	var mate := mate_of(a)
	var tn := touch_no(a.team)
	if kind == "serve":
		tn = 0
	var skill_err := _error_scale(a, quality)
	var shot := {}
	if a.friendly and (kind == "serve" or kind == "spike" or tn >= 3):
		shot = _shot_friendly(a, p0, kind)
	else:
		shot = _plan_normal(a, kind, quality, p0, mate, tn, skill_err)
	return _finish_shot(a, kind, quality, shot)


func _plan_normal(a: Athlete, kind: String, quality: String, p0: Vector3, mate: Athlete, tn: int, skill_err: float) -> Dictionary:
	var shot := {}
	match kind:
		"serve":
			shot = _shot_serve(a, p0, quality, skill_err)
		"spike":
			shot = _shot_spike(a, p0, quality, skill_err)
		"bump", "dig", "set":
			var must_over := tn >= 3
			var dump := a.aim_explicit and tn < 3 and kind != "set" and _aim_is_forward(a)
			if kind == "set" and tn < 3 and a.aim_explicit and _aim_is_forward(a):
				dump = true
			if must_over or dump:
				shot = _shot_over(a, p0, kind, quality, skill_err)
			elif kind == "set":
				shot = _shot_set(a, mate, p0, quality, skill_err)
			else:
				shot = _shot_pass(a, mate, p0, quality, skill_err, kind == "dig")
	return shot


func _finish_shot(a: Athlete, kind: String, quality: String, shot: Dictionary) -> Dictionary:
	if shot.is_empty():
		return shot
	shot["spin"] = Vector3(_rng.randf_range(-5, 5), _rng.randf_range(-3, 3), _rng.randf_range(-5, 5)) * (0.4 + shot.get("power", 0.4))
	# trail / flash according to power
	var pw: float = shot.get("power", 0.4)
	var prior_chain: int = chain[a.team] if last_team == a.team else 0
	ball.combo = false
	if kind == "spike" and quality == "perfect" and prior_chain >= 2 and a.global_position.y > 0.2:
		# bump -> set -> spike, every touch "Nice": the power spike (pink trail, can not be blocked for a kill)
		ball.combo = true
		add_hype(a.team, 0.2)
		stats["power_spikes"][a.team] += 1
		if a.team == 0:
			Game.live("power_spikes")
		shot["label"] = "快速扣杀!" if a.team != 0 else "POWER SPIKE!"
		pw = 1.0
		if Game.main != null and Game.main.dev.has("log"):
			print("[combo] power spike by %s" % a.display_name)
	if is_fever(a.team) and quality != "ok":
		pw = minf(pw + 0.15, 1.0)
		shot["power"] = pw
	if ball.combo:
		ball.set_trail(true, 2, Color(1.0, 0.36, 0.68), a.team)
	elif is_fever(a.team) and quality != "ok":
		ball.set_trail(true, 1, Color(1.0, 0.5, 0.12), a.team)
	elif quality == "perfect":
		ball.set_trail(true, 1, Color(0, 0, 0, 0), a.team)
	elif pw > 0.62 or quality == "good":
		ball.set_trail(true, 0, Color(0, 0, 0, 0), a.team)
	else:
		ball.set_trail(false)
	if quality == "perfect":
		ball.flash(1.0)
	if Game.main != null and Game.main.dev.has("shotspd"):
		print("[shot] %s %s speed=%.1f" % [kind, quality, (shot["vel"] as Vector3).length()])
	return shot


func _aim_is_forward(a: Athlete) -> bool:
	if a.aim_point == null:
		return false
	var ap: Vector3 = a.aim_point
	return ap.z * Court.team_sign(a.team) < 0.0


func _error_scale(a: Athlete, quality: String) -> float:
	var base := 1.0
	match quality:
		"perfect": base = 0.0
		"good": base = 0.35
		"ok": base = 1.0
	var skill := a.skill
	if a.perk == "steady":
		base *= 0.8
	return base * lerpf(1.5, 0.55, clampf(skill, 0.0, 1.0))


func _jitter(r: float) -> Vector3:
	var ang := _rng.randf() * TAU
	var rad := sqrt(_rng.randf()) * r
	return Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)


## find the flight time >= t_min that makes the shot clear the net
func _solve_over_net(p0: Vector3, target: Vector3, t_min: float, t_max := 2.2) -> Vector3:
	var t := t_min
	var v := Court.solve_velocity(p0, target, t)
	while Court.net_clearance(p0, v) < 0.12 and t < t_max:
		t += 0.04
		v = Court.solve_velocity(p0, target, t)
	return v


func _smart_target(a: Athlete, deep_bias := 0.5, short_ok := true) -> Vector3:
	# pick an open spot on the opponents' side: far from both defenders, inside the lines
	var opp := opponents_of(a.team)
	var S := Court.team_sign(a.team)
	var best := Vector3.ZERO
	var best_score := -1.0
	for xi in 7:
		for di in 4:
			var x := lerpf(-3.9, 3.9, xi / 6.0)
			var d := lerpf(1.6, 6.3, di / 3.0)
			var p := Vector3(x, 0, -S * d)
			var m := 99.0
			for o in opp:
				m = minf(m, Vector2(o.global_position.x - p.x, o.global_position.z - p.z).length())
			var sc := m + _rng.randf() * 1.6 + d * deep_bias * 0.18
			if not short_ok and d < 3.0:
				sc -= 3.0
			if sc > best_score:
				best_score = sc
				best = p
	return best


func _target_for(a: Athlete, deep_bias := 0.5) -> Vector3:
	if a.aim_point != null:
		var ap: Vector3 = a.aim_point
		var S := Court.team_sign(a.team)
		return Vector3(clampf(ap.x, -Court.HALF_W + 0.3, Court.HALF_W - 0.3), 0.0, -S * clampf(absf(ap.z), 0.8, Court.HALF_D - 0.35))
	if not a.is_human and _rng.randf() > 0.2 + 0.6 * a.skill:
		# the computer does not always find the open spot: sometimes it just hits somewhere in the court
		var S2 := Court.team_sign(a.team)
		return Vector3(_rng.randf_range(-3.6, 3.6), 0.0, -S2 * _rng.randf_range(2.0, 6.0))
	return _smart_target(a, deep_bias)


func _shot_serve(a: Athlete, p0: Vector3, q: String, err: float) -> Dictionary:
	var S := Court.team_sign(a.team)
	var tgt := _target_for(a, 0.9)
	tgt += _jitter(0.9 * err)
	var airborne := a.global_position.y > 0.3
	var tmin := 0.95 if q == "perfect" else (1.1 if q == "good" else 1.3)
	if airborne:
		tmin -= 0.22
	var v := _solve_over_net(p0, Vector3(tgt.x, Court.BALL_R, tgt.z), tmin)
	var pw := 0.9 if q == "perfect" else (0.7 if q == "good" else 0.45)
	if airborne:
		pw += 0.1
	return {"vel": v, "power": pw, "target": tgt, "label": "JUMP SERVE" if airborne and q != "ok" else ""}


func _shot_spike(a: Athlete, p0: Vector3, q: String, err: float) -> Dictionary:
	var S := Court.team_sign(a.team)
	var tip := false
	if a.aim_point != null:
		var ap: Vector3 = a.aim_point
		tip = absf(ap.z) < 1.9
	var tgt := _target_for(a, 0.6)
	tgt += _jitter(0.7 * err)
	var d := Vector2(tgt.x - p0.x, tgt.z - p0.z).length()
	var speed := 9.5 if q == "ok" else (12.5 if q == "good" else 16.0)
	speed *= lerpf(0.9, 1.08, clampf(a.skill, 0.0, 1.0)) * a.power_mul
	var t := clampf(d / speed, 0.46, 1.1)
	if tip:
		t = 0.85
	var y_over := p0.y
	var v := _solve_over_net(p0, Vector3(tgt.x, Court.BALL_R, tgt.z), t, 1.6)
	var pw := 1.0 if q == "perfect" else (0.82 if q == "good" else 0.55)
	if tip:
		pw = 0.3
	var label := "扣杀!" if q == "perfect" and not tip else ("吊球" if tip else "")
	if a.team == 0 and q == "perfect":
		label = "SPIKE!"
	return {"vel": v, "power": pw, "target": tgt, "label": label}


func _shot_over(a: Athlete, p0: Vector3, kind: String, q: String, err: float) -> Dictionary:
	var S := Court.team_sign(a.team)
	var tgt := _target_for(a, 0.35)
	tgt += _jitter(1.4 * err)
	var tmin := 1.25 if kind == "set" else 1.15
	var v := _solve_over_net(p0, Vector3(tgt.x, Court.BALL_R, tgt.z), tmin)
	return {"vel": v, "power": 0.35, "target": tgt, "label": ""}


func _shot_pass(a: Athlete, mate: Athlete, p0: Vector3, q: String, err: float, is_dig: bool) -> Dictionary:
	var S := Court.team_sign(a.team)
	# aim at the setter's spot near the net (a little in front of the mate)
	var mx := clampf(mate.global_position.x * 0.5, -1.8, 1.8)
	if absf(mate.global_position.z) < 3.5:
		mx = clampf(mate.global_position.x, -2.2, 2.2)
	var tgt := Vector3(mx, 2.0, S * 1.9)
	var dist := Vector2(tgt.x - p0.x, tgt.z - p0.z).length()
	var t := clampf(0.95 + dist * 0.11, 1.3, 1.95)
	if is_dig:
		t += 0.15
	var e := err * (1.25 if is_dig else 1.0)
	var jit := _jitter(1.3 * e)
	tgt += jit
	tgt.x = clampf(tgt.x, -4.4, 4.4)
	tgt.z = S * clampf(absf(tgt.z), 0.5, 6.5)
	var v := Court.solve_velocity(p0, tgt, t)
	set_target[a.team] = Vector3(tgt.x, 0, tgt.z)
	return {"vel": v, "power": 0.2, "target": tgt, "label": ""}


func _shot_set(a: Athlete, mate: Athlete, p0: Vector3, q: String, err: float) -> Dictionary:
	var S := Court.team_sign(a.team)
	# attacker position: choose left / middle / right by the aim stick, default = where the mate is / is heading
	var ax := clampf(mate.global_position.x, -3.2, 3.2)
	var quick := false
	if a.aim_point != null:
		var ap: Vector3 = a.aim_point
		# aim marker on our own half: pick the attack lane
		ax = clampf(ap.x, -3.4, 3.4)
		quick = absf(ap.z) < 2.2 and ap.z * S > 0.0
	var tgt := Vector3(ax, 2.7, S * 1.35)
	var t := 1.25
	# the spiker already left the ground: "quick" attack - low, fast set right to where they are flying
	if mate.state == Athlete.S.AIR and mate.global_position.y > 0.2 and absf(mate.global_position.z) < 3.4:
		quick = true
		ax = clampf(mate.global_position.x, -3.6, 3.6)
		tgt = Vector3(ax, mate.global_position.y + 1.5, S * clampf(absf(mate.global_position.z), 0.8, 2.2))
	if quick:
		tgt.y = minf(tgt.y, 2.6)
		t = 0.6 if mate.state == Athlete.S.AIR else 0.78
	var jit := _jitter(1.0 * err)
	tgt += Vector3(jit.x, 0.0, jit.z * 0.7)
	tgt.z = S * clampf(absf(tgt.z), 0.6, 3.5)
	var v := Court.solve_velocity(p0, tgt, t)
	set_target[a.team] = Vector3(tgt.x, 0, tgt.z)
	return {"vel": v, "power": 0.25, "target": tgt, "label": "QUICK!" if quick else ""}


# ------------------------------------------------------------------ blocks
func _check_blocks() -> void:
	for a in athletes:
		if not a.is_blocking():
			continue
		var S := Court.team_sign(a.team)
		var bp := ball.global_position
		# only balls travelling towards a's side are blocked
		if ball.vel.z * S <= 0.5 or not ball.live:
			continue
		if last_team == a.team:
			continue
		if absf(bp.z) > 0.55 or bp.z * S < -0.55:
			continue
		var rel_y := bp.y - a.global_position.y
		if rel_y < 0.95 or rel_y > 2.45:      # hands-up reach of a jumping blocker
			continue
		if absf(bp.x - a.global_position.x) > 0.95:
			continue
		_do_block(a)
		return


func _do_block(a: Athlete) -> void:
	var S := Court.team_sign(a.team)
	var power := ball.vel.length()
	var kill_p := clampf(0.12 + a.global_position.y * 0.3 + (0.1 if a.skill > 0.7 else 0.0) + (0.15 if a.perk == "iron" else 0.0), 0.0, 0.85)
	if last_hitter != null and last_hitter.perk == "might":
		kill_p *= 0.5                      # a powerful hitter breaks through the block
	var kill := _rng.randf() < kill_p
	if ball.combo:
		kill = false                       # the power spike goes through (a soft touch at best)
	var bp := ball.global_position
	var v := Vector3.ZERO
	if kill:
		# slammed straight back down into the attackers' court
		v = Vector3(ball.vel.x * -0.1, -6.0, -S * 6.5)
		popup.emit("KILL BLOCK!", "perfect", bp + Vector3(0, 0.8, 0))
		ball.set_trail(true, 1, Color(0.4, 0.9, 1.0))
	else:
		# soft block: popped up on the blockers' side, still playable
		v = Vector3(ball.vel.x * 0.15, 5.4, S * 2.2)
		popup.emit("BLOCK!", "good", bp + Vector3(0, 0.8, 0))
		ball.set_trail(false)
	ball.launch(v, 0.7 if kill else 0.3)
	ball.global_position = Vector3(bp.x, bp.y, S * 0.5)
	ball.flash(1.0)
	last_team = a.team
	last_hitter = a
	touches = [0, 0]
	rally_len += 1
	stats["blocks"][a.team] += 1
	add_hype(a.team, 0.18 if kill else 0.06)
	Sfx.play("block", 0.0, 1.0, 0.05)
	rally_event.emit("block", {"athlete": a, "kill": kill})
	a.blocked_visual()


# ------------------------------------------------------------------ scoring
func _on_net_contact(pos: Vector3) -> void:
	Sfx.play("net_hit", -2.0)
	rally_event.emit("net", {"pos": pos})
	# a serve that touches the net is a fault
	if phase == P.RALLY and rally_len == 1 and last_hitter == server and last_team == serving_team:
		_end_point(1 - serving_team, "触网", pos)


func _on_floor_contact(pos: Vector3) -> void:
	if phase != P.RALLY and phase != P.SERVING:
		return
	var inside := Court.in_court(pos, 0.04)
	var winner := 0
	var reason := ""
	var side := Court.side_of(pos.z)
	if phase == P.SERVING and last_team < 0:
		# toss dropped / serve never hit: serving team loses the point
		winner = 1 - serving_team
		reason = "发球失误"
		if Game.main != null and Game.main.dev.has("log") and server != null:
			print("[servefault] server=%s state=%d skill=%.2f serve_t=%.2f ballpos=%s srvpos=%s hitdist=%.2f" % [server.display_name, server.state, server.skill, _serve_timer, str(pos), str(server.global_position), server.hit_distance("serve")])
	elif inside:
		winner = 1 - side
		reason = "得分!"
		if rally_len == 1 and last_team == serving_team:
			reason = "ACE!"
			stats["aces"][serving_team] += 1
	else:
		winner = 1 - last_team
		reason = "出界"
	if not (phase == P.SERVING and last_team < 0):
		popup.emit("In" if inside else "Out", "inout", Vector3(pos.x, 0.3, pos.z))
		var edge := minf(Court.HALF_W - absf(pos.x), Court.HALF_D - absf(pos.z))
		if absf(edge) < 0.3:
			rally_event.emit("close_call", {"pos": pos, "inside": inside})
	_end_point(winner, reason, pos)


func _end_point(winner: int, reason: String, pos: Vector3) -> void:
	if phase == P.POINT or phase == P.OVER:
		return
	if is_practice():
		_practice_point(winner, reason, pos)
		return
	score[winner] += 1
	for t in 2:
		max_deficit[t] = maxi(int(max_deficit[t]), int(score[1 - t]) - int(score[t]))
	if score[0] >= target_points - 1 and score[1] >= target_points - 1:
		deuce = true
	if _last_kind == "spike" and last_team == winner and (reason == "得分!" or reason == "ACE!"):
		stats["spike_points"][winner] += 1
	rally_history.append({"len": rally_len, "reason": reason, "winner": winner})
	var loser := 1 - winner
	if is_fever(loser):
		_end_fever(loser)
	hype[loser] = float(hype[loser]) * 0.5
	add_hype(winner, 0.12 if (reason == "ACE!" or _last_kind == "spike") else 0.06)
	if Game.main != null and Game.main.dev.has("log"):
		var ds := []
		for a in athletes:
			ds.append("%s:%.1f(%d)" % [a.display_name.substr(0, 1), Vector2(a.global_position.x - pos.x, a.global_position.z - pos.z).length(), a.state])
		print("[pointdbg] len=%d reason=%s landing=(%.1f,%.1f) dists=%s plan_who=%s" % [rally_len, reason, pos.x, pos.z, ds, [plans[0].get("who") != null, plans[1].get("who") != null]])
	var prev_serving := serving_team
	if winner != serving_team:
		serving_team = winner
		server_idx[winner] = 1 - server_idx[winner]
	_point_info = {"winner": winner, "reason": reason, "pos": pos}
	_set_phase(P.POINT)
	score_changed.emit(score, serving_team)
	point_scored.emit(winner, reason, pos)
	Sfx.play("whistle_short", -2.0)
	popup.emit(reason, "point", Vector3(pos.x, 1.6, pos.z))
	for a in athletes:
		if a.team == winner:
			a.celebrate()
		else:
			a.sad()
	rally_event.emit("point", {"winner": winner, "reason": reason, "pos": pos})
	var lead: int = score[winner] - score[1 - winner]
	if score[winner] >= target_points and lead >= 2 or score[winner] >= target_points + 5:
		_set_phase(P.OVER)
		match_over.emit(winner)
	elif score[winner] == target_points - 1 and lead >= 1 or (score[winner] >= target_points - 1 and lead >= 1):
		rally_event.emit("match_point", {"team": winner})


func _next_point() -> void:
	for a in athletes:
		a.reset_to_ready()
	ball.set_trail(false)
	_begin_serve_prep()


# ------------------------------------------------------------------ planning (AI + human assist)
func _update_plans(dt: float) -> void:
	_last_plan_t -= dt
	if _last_plan_t > 0.0:
		return
	_last_plan_t = 0.05
	for t in 2:
		plans[t] = _plan_team(t)


func hit_height_for(touch: int) -> float:
	match touch:
		1: return 1.0
		2: return 1.6
		_: return 2.7


func _plan_team(t: int) -> Dictionary:
	var S := Court.team_sign(t)
	var plan := {"who": null, "pos": Vector3.ZERO, "t": 99.0, "touch": 1, "h": 1.0, "support": {}, "mode": "defend"}
	if ball == null or not ball.live or ball.floor_touched:
		return plan
	var tn := touch_no(t)
	var bp := ball.global_position
	var bv := ball.vel
	var candidates: Array[Athlete] = []
	if last_team == t:
		if touches[t] >= 3:
			plan["mode"] = "cover"
			return plan
		var other := mate_of(last_hitter) if last_hitter != null and last_hitter.team == t else null
		if other != null:
			candidates.append(other)
	else:
		candidates = team_athletes(t)
	if candidates.is_empty():
		return plan
	# is the ball heading to this team's side (or already there)?
	var landing := ball.predict_landing()
	if landing.is_empty():
		return plan
	var lpos: Vector3 = landing["pos"]
	# the ball only matters to this team if it is going to come down on its own half
	if lpos.z * S <= 0.05:
		plan["mode"] = "cover" if last_team == t else "defend"
		return plan
	var h := hit_height_for(tn)
	if last_team != t:
		h = 1.0
	var at := ball.predict_at_height(h)
	var spot := lpos
	var tt: float = landing["t"]
	if not at.is_empty():
		var apos: Vector3 = at["pos"]
		# use the height crossing only if it is on our side; otherwise fall back to the landing point
		if apos.z * S > 0.0 or last_team == t:
			spot = apos
			tt = at["t"]
	spot.y = 0.0
	if last_team != t and spot.z * S < 0.0:
		# ball will land on the other side - nothing to do for this team (maybe a net block follow-up)
		plan["mode"] = "defend"
		return plan
	spot.x = clampf(spot.x, -Court.PLAYER_MAX_X, Court.PLAYER_MAX_X)
	spot.z = S * clampf(absf(spot.z), 0.8, Court.PLAYER_MAX_Z)
	var best: Athlete = null
	var best_margin := -999.0
	for c in candidates:
		var d := Vector2(c.global_position.x - spot.x, c.global_position.z - spot.z).length()
		var need := maxf(d - 0.45, 0.0) / Athlete.RUN_SPEED
		if c.state == Athlete.S.DIVE or c.state == Athlete.S.GETUP:
			need += 0.5
		elif c.state == Athlete.S.STUMBLE:
			need += 0.35
		elif c.state == Athlete.S.KNOCKED:
			need += 3.0       # on the floor, seeing stars
		var margin := tt - need
		if margin > best_margin:
			best_margin = margin
			best = c
	plan["who"] = best
	plan["pos"] = spot
	plan["t"] = tt
	plan["touch"] = tn
	plan["h"] = h
	plan["mode"] = "play"
	plan["margin"] = best_margin
	return plan


## formation spot for the player that is NOT playing the ball
func support_spot(a: Athlete) -> Vector3:
	var t := a.team
	var S := Court.team_sign(t)
	var plan: Dictionary = plans[t]
	var tn := touch_no(t)
	var mate := mate_of(a)
	var ballp := ball.global_position
	if ball.live and last_team == t:
		# our own possession
		if tn == 2:
			# a is the one that just touched: run to the attack position
			var tx: float = clampf((set_target[t] as Vector3).x if (set_target[t] as Vector3) != Vector3.ZERO else -mate.global_position.x, -3.4, 3.4)
			return Vector3(tx, 0, S * 3.6)
		if tn == 3:
			return Vector3(-clampf(ballp.x, -3, 3) * 0.6, 0, S * 5.0)
	if ball.live and last_team != t and plan.get("mode", "") == "play":
		# mate receives: we go to the setting spot next to the net
		var rp: Vector3 = plan["pos"]
		return Vector3(clampf(-rp.x * 0.35, -1.6, 1.6) , 0, S * 1.9)
	# defence formation: stagger according to where the opposing ball came from
	var back := a.slot == 0
	var ox := 0.0
	if last_hitter != null and last_team != t:
		ox = clampf(last_hitter.global_position.x * 0.3, -1.5, 1.5)
	if back:
		return Vector3(-2.2 + ox, 0, S * 5.2)
	return Vector3(2.0 + ox, 0, S * 3.4)


func vfx_dust(pos: Vector3) -> void:
	if vfx:
		vfx.dust(pos)
