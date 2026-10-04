class_name BodyCollisions
extends Node
## Athlete <-> athlete collisions. Opponents are kept apart by the net, so this is about team mates sharing a half
## (running for the same ball, a dive into a standing player, a head-on sprint).
## Every tick overlapping bodies are pushed apart (lighter one moves more, a downed player barely moves). The
## closing speed along the contact normal, shared out by mass, becomes a "jolt" for each side:
##   brushed  -> nothing but a push          stumble -> thrown off balance for a moment
##   knock-down -> falls, is dazed (stars), gets up again - with sound, dust / star burst and camera shake.

var athletes: Array = []
var director = null
var _log := false
var _test_t := 0.0
var _test_mode := ""
var _test_step := 0
var _shots := 0


func setup(list: Array, d) -> void:
	athletes = list
	director = d
	process_physics_priority = 5            # after every athlete moved
	_log = Game.main != null and Game.main.dev.has("log")
	if Game.main != null and Game.main.dev.has("dbgcollide"):
		_test_mode = str(Game.main.dev["dbgcollide"])


func _physics_process(dt: float) -> void:
	var _p := Prof.t0()
	_physics_process_impl(dt)
	Prof.add("collide", _p)


func _physics_process_impl(dt: float) -> void:
	if _test_mode != "":
		_drive_test(dt)
	var n := athletes.size()
	for i in n:
		var a: Athlete = athletes[i]
		if not a.collidable():
			continue
		for j in range(i + 1, n):
			var b: Athlete = athletes[j]
			if b.team != a.team or not b.collidable():
				continue
			_pair(a, b)


func _pair(a: Athlete, b: Athlete) -> void:
	var off := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
	var dist := off.length()
	var rr := 2.0 * Athlete.BODY_R + (0.12 if (a.is_down() or b.is_down()) else 0.0)
	if dist >= rr:
		return
	var nrm := off / dist if dist > 0.001 else Vector2.RIGHT.rotated(randf() * TAU)
	var ma := a.mass()
	var mb := b.mass()
	var share_a := mb / (ma + mb)            # the lighter one takes more of everything
	var share_b := 1.0 - share_a
	var pen := rr - dist
	var wa := share_a
	var wb := share_b
	if a.is_down():
		wa = 0.1
		wb = 0.9
	elif b.is_down():
		wa = 0.9
		wb = 0.1
	a.nudge_position(-nrm * pen * wa)
	b.nudge_position(nrm * pen * wb)
	var vc := (a.vel - b.vel).dot(nrm)       # > 0: closing in
	if vc < 0.6:
		return
	var la := a.take_collision(-nrm, vc * share_a * 2.0)
	var lb := b.take_collision(nrm, vc * share_b * 2.0)
	var lvl := maxi(la, lb)
	var e := 0.15 if lvl == 0 else (0.25 if lvl == 1 else (0.45 if lvl == 2 else 0.7))
	a.vel = (a.vel - nrm * vc * share_a * (1.0 + e)).limit_length(6.5)
	b.vel = (b.vel + nrm * vc * share_b * (1.0 + e)).limit_length(6.5)
	for pair in [[a, la], [b, lb]]:
		if int(pair[1]) == 3:
			var victim: Athlete = pair[0]
			director.stats["knockdowns"][victim.team] += 1
			if victim.team == 0:
				Game.live("knockdowns")
	if lvl >= 1:
		_effects(a, b, lvl, vc)


func _effects(a: Athlete, b: Athlete, lvl: int, vc: float) -> void:
	var mid := (a.global_position + b.global_position) * 0.5 + Vector3(0.0, 0.55, 0.0)
	var human := a.is_human or b.is_human
	if _log:
		var pl: Dictionary = director.plans[a.team]
		var who: Athlete = pl.get("who")
		print("[collide] %s x %s  closing=%.1f  level=%d  va=%.1f vb=%.1f  who=%s mode=%s phase=%d" % [a.display_name, b.display_name, vc, lvl, a.vel.length(), b.vel.length(), who.display_name if who != null else "-", pl.get("mode", "-"), director.phase])
	if director.vfx != null:
		director.vfx.body_hit(mid, lvl)
	if _test_mode != "" and lvl == 3 and _shots == 0 and Game.main.dev.has("collshots"):
		_shots = 1
		for k in 4:
			var delay: float = [0.12, 0.45, 0.95, 1.9][k]
			get_tree().create_timer(delay, true, false, true).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png("%s_%d.png" % [Game.main.dev["collshots"], k]))
	match lvl:
		1:
			if vc > 1.6:
				Sfx.play("body_bump", -10.0, 1.1, 0.1)
		2:
			Sfx.play("body_bump", -2.0, 0.9, 0.08)
			if human:
				Game.haptic(90, 0.6)
			if director.cam != null:
				director.cam.shake(0.18 if human else 0.08)
		3:
			Sfx.play("crash", 0.0, 1.0, 0.05)
			if human:
				Game.haptic(240, 1.0)
			if director.cam != null:
				director.cam.shake(0.45 if human else 0.25)
				director.cam.punch(5.0, 0.3, 0.2)


# ------------------------------------------------------------------ dev: --dbgcollide=head|chase|brush
## Every few seconds sends the two near-team athletes at each other (autoplay only).
func _drive_test(dt: float) -> void:
	if director.phase != MatchDirector.P.RALLY or athletes.size() < 2:
		return
	_test_t -= dt
	if _test_t > 0.0:
		return
	_test_t = 5.0
	var a: Athlete = athletes[0]
	var b: Athlete = athletes[1]
	if a.is_busy() or b.is_busy():
		return
	var s := Court.team_sign(a.team)
	var pa := Vector3(-1.6, 0.0, 4.5 * s)
	var pb := Vector3(1.6, 0.0, 4.5 * s)
	_test_step += 1
	match _test_mode:
		"head":
			a.teleport(pa)
			b.teleport(pb)
			a.auto_walk_to(pb)
			b.auto_walk_to(pa)
		"chase":
			a.teleport(Vector3(-2.4, 0.0, 6.0 * s))
			b.teleport(Vector3(-2.4, 0.0, 3.2 * s))
			a.auto_walk_to(Vector3(-2.4, 0.0, 2.8 * s))
			b.auto_walk_to(Vector3(-2.4, 0.0, 3.2 * s))
		_:
			a.teleport(Vector3(-0.5, 0.0, 4.5 * s))
			b.teleport(Vector3(0.5, 0.0, 4.5 * s))
			a.auto_walk_to(Vector3(0.5, 0.0, 4.5 * s))
			b.auto_walk_to(Vector3(-0.5, 0.0, 4.5 * s))
