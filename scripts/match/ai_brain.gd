class_name AIBrain
extends RefCounted
## Computer player: serve, positioning, intercept timing, set / spike / block decisions.
## skill 0..1 scales reaction time, positioning error, timing error and the odds of perfect hits.

var skill := 0.6
var rng := RandomNumberGenerator.new()
var _serve_wait := -1.0
var _serve_jump := false
var _hit_offset := 0.0
var _seen_hit_seq := -1
var _react_t := 0.0
var _pos_err := Vector2.ZERO
var _block_roll := -1
var _block_t := -1.0
var _spike_jump_done := false
var _hit_pressed_for_seq := -1
var _dive_decided_seq := -1
var _wander_t := 0.0
var _wander := Vector2.ZERO


func _init(p_skill := 0.6) -> void:
	skill = p_skill
	rng.randomize()


func think(a: Athlete, dt: float) -> void:
	var d: MatchDirector = a.director
	a.cmd_move = Vector2.ZERO
	a.aim_point = null
	a.aim_explicit = false
	match d.phase:
		MatchDirector.P.SERVING:
			if d.server == a:
				_serve(a, d, dt)
			else:
				_hold_formation(a, d, dt)
		MatchDirector.P.RALLY:
			_rally(a, d, dt)
	_avoid_mate(a, d)


## keep out of the team mate's way: whoever is not playing the ball gives way early and firmly (even more for a
## human mate), the one running for the ball only bends away when really close
func _avoid_mate(a: Athlete, d: MatchDirector) -> void:
	if a.state != Athlete.S.READY:
		return
	var m: Athlete = d.mate_of(a)
	if m == null:
		return
	var off := Vector2(a.global_position.x - m.global_position.x, a.global_position.z - m.global_position.z)
	var dist := off.length()
	var plan: Dictionary = d.plans[a.team]
	var i_play: bool = plan.get("who") == a and plan.get("mode") == "play"
	var radius := 1.15 if i_play else 2.4
	if dist > radius or dist < 0.01:
		return
	var gain := 0.6 if i_play else 1.5
	if m.is_human and not i_play:
		gain *= 1.3
	# also look at where the mate is heading: giving way matters most when closing in
	var closing := clampf(-(a.vel - m.vel).dot(off / dist) / 6.0 + 0.5, 0.3, 1.5)
	var strength := (1.0 - dist / radius) * gain * closing * (0.6 + skill * 0.6)
	a.cmd_move = (a.cmd_move + off / dist * strength).limit_length(1.0)


# ------------------------------------------------------------------ serve
func _serve(a: Athlete, d: MatchDirector, dt: float) -> void:
	if a.state == Athlete.S.SERVE_HOLD:
		if _serve_wait < 0.0:
			_serve_wait = rng.randf_range(0.9, 2.0)
			_serve_jump = rng.randf() < 0.18 + skill * 0.3 or (Game.main != null and Game.main.dev.has("jumpserve"))
			_hit_offset = rng.randf_range(-0.3, 0.3) * (1.35 - skill)
		_serve_wait -= dt
		if _serve_wait <= 0.0:
			_serve_wait = -1.0
			if _serve_jump:
				a.press_jump()
			else:
				a.press_hit()
	elif a.state in [Athlete.S.SERVE_TOSS, Athlete.S.AIR]:
		var b := a.ball
		var ideal := a.global_position.y + 1.55 + _hit_offset
		if a.state == Athlete.S.AIR:
			# jump serve: strike around the top of the jump while the ball is still in reach
			if a.vy < 2.2 and a.hit_distance("spike") < 0.75 + (1.0 - skill) * 0.45:
				a.press_hit()
		elif b.global_position.y <= ideal + 0.05 and b.vel.y < 1.2 and a.hit_distance("serve") < 1.2:
			a.press_hit()


func _hold_formation(_a: Athlete, _d: MatchDirector, _dt: float) -> void:
	pass    # everybody else waits where the director put them


# ------------------------------------------------------------------ rally
func _rally(a: Athlete, d: MatchDirector, dt: float) -> void:
	# new ball event? (reaction delay)
	var seq := d.rally_len
	if seq != _seen_hit_seq:
		_seen_hit_seq = seq
		_react_t = lerpf(0.22, 0.05, skill) * rng.randf_range(0.8, 1.3)
		_pos_err = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * (1.0 - skill) * 0.9
		_spike_jump_done = false
		_block_roll = -1
		_block_t = -1.0
	if _react_t > 0.0:
		_react_t -= dt
		return
	if a.state in [Athlete.S.CELEB, Athlete.S.SAD, Athlete.S.GETUP]:
		return
	var plan: Dictionary = d.plans[a.team]
	var S := Court.team_sign(a.team)
	var mine: bool = plan.get("who") == a and plan.get("mode") == "play"
	if mine:
		_play_ball(a, d, plan, dt)
	else:
		_support(a, d, dt)
		_try_block(a, d, dt)


func _move_to(a: Athlete, spot: Vector3, speed_scale := 1.0) -> void:
	var to := Vector2(spot.x - a.global_position.x, spot.z - a.global_position.z)
	var dist := to.length()
	if dist < 0.12:
		a.cmd_move = Vector2.ZERO
	else:
		a.cmd_move = to.normalized() * clampf(dist * 1.8, 0.0, 1.0) * speed_scale


func _support(a: Athlete, d: MatchDirector, dt: float) -> void:
	var spot := d.support_spot(a)
	spot.x += _pos_err.x * 0.4
	_move_to(a, spot, 0.9)


func _play_ball(a: Athlete, d: MatchDirector, plan: Dictionary, dt: float) -> void:
	var S := Court.team_sign(a.team)
	var spot: Vector3 = plan["pos"]
	var tn: int = plan["touch"]
	var t: float = plan["t"]
	spot.x += _pos_err.x
	spot.z += _pos_err.y * S
	var kind := a._choose_kind()
	# --- spike approach: jump so that the apex coincides with the contact
	if tn >= 3 and plan["h"] > 2.4:
		_attack(a, d, plan, spot, t, dt)
		return
	_move_to(a, spot)
	# dive when the ball will land out of reach
	if a.state == Athlete.S.READY and _dive_decided_seq != d.rally_len:
		var dist := Vector2(spot.x - a.global_position.x, spot.z - a.global_position.z).length()
		var need := maxf(dist - 0.5, 0.0) / Athlete.RUN_SPEED
		if dist > 1.2 and dist < 3.4 and t - need < 0.12 and t < 0.75 and rng.randf() < 0.45 + skill * 0.5:
			_dive_decided_seq = d.rally_len
			a.cmd_move = Vector2(spot.x - a.global_position.x, spot.z - a.global_position.z).normalized()
			a.press_dive()
			return
	_try_hit(a, d, kind)


func _attack(a: Athlete, d: MatchDirector, plan: Dictionary, spot: Vector3, t: float, dt: float) -> void:
	var S := Court.team_sign(a.team)
	# stand slightly behind the contact point, then jump
	var stand := Vector3(spot.x, 0, spot.z + S * 0.55)
	if a.state == Athlete.S.READY:
		_move_to(a, stand)
		var near := Vector2(stand.x - a.global_position.x, stand.z - a.global_position.z).length() < 1.1
		var jump_lead := Athlete.JUMP_V / Athlete.AGRAV * 0.92
		if near and t <= jump_lead + 0.1 + rng.randf_range(-0.07, 0.07) * (1.2 - skill) and not _spike_jump_done:
			_spike_jump_done = true
			a.press_jump()
	elif a.state == Athlete.S.AIR:
		a.cmd_move = Vector2(spot.x - a.global_position.x, spot.z - a.global_position.z).limit_length(1.0) * 0.6
		_try_hit(a, d, "spike")
		return
	if a.state == Athlete.S.READY and plan["h"] > 2.4:
		_try_hit(a, d, "spike")


func _try_hit(a: Athlete, d: MatchDirector, kind: String) -> void:
	if _hit_pressed_for_seq == d.rally_len and a.state in [Athlete.S.ACTION]:
		return
	if not d.can_hit(a):
		return
	var dist := a.hit_distance(kind)
	var trigger := lerpf(0.75, 0.3, skill) + rng.randf_range(-0.08, 0.08)
	if kind == "spike":
		trigger += 0.1
	elif kind == "dig":
		trigger = Athlete.KINDS["dig"]["zone"] * 0.9
	if Game.main != null and Game.main.dev.has("dbgai") and dist < 1.6:
		print("[aihit] %s kind=%s dist=%.2f trig=%.2f st=%d ball=%s vy=%.1f" % [a.display_name, kind, dist, trigger, a.state, str(a.ball.global_position), a.ball.vel.y])
	if dist <= trigger:
		# aim: usually the "smart" spot; good players sometimes go for the lines
		if kind == "spike" and rng.randf() < 0.18 * skill:
			a.aim_point = Vector3(rng.randf_range(-3.6, 3.6), 0.0, -Court.team_sign(a.team) * rng.randf_range(4.5, 6.2))
		_hit_pressed_for_seq = d.rally_len
		a.press_hit()


func _try_block(a: Athlete, d: MatchDirector, dt: float) -> void:
	# opposing team has just set the ball (their 2nd touch) -> consider blocking at the net
	if a.friendly:
		return                              # the practice ball machine never blocks
	var S := Court.team_sign(a.team)
	if d.last_team != 1 - a.team or d.touches[1 - a.team] != 2:
		return
	if absf(a.global_position.z) > 3.4:
		return
	var b := a.ball
	if _block_roll < 0:
		_block_roll = 1 if rng.randf() < 0.2 + skill * 0.55 else 0
		if _block_roll == 1:
			var at := b.predict_at_height(2.9)
			_block_t = (at["t"] if not at.is_empty() else 0.8) - 0.12 + rng.randf_range(-0.08, 0.08) * (1.2 - skill)
	if _block_roll != 1:
		return
	_block_t -= dt
	# shuffle in front of the attacker
	var ax := clampf(b.global_position.x + b.vel.x * 0.4, -3.8, 3.8)
	_move_to(a, Vector3(ax, 0, S * 1.0), 1.0)
	if _block_t <= 0.0 and a.state == Athlete.S.READY:
		a.press_jump()
		_block_roll = 2
