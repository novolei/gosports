class_name MateBanter
extends Node
## The little show after every point, for BOTH teams (solo / versus / coop / tournament; not practice):
##
##  Winners celebrate with a randomly chosen routine:
##    cheer     the plain arms-up cheer (the director's default)
##    clap      both clap, a small party popper each
##    highfive  the two walk to each other and slap hands in the middle (hit spark + confetti)
##    dance     both dance for the camera (three dances)
##  Losers: when somebody made the mistake (the last toucher hit it out / into the net / faulted the serve, or was the closest to a
##  ball that dropped), the OTHER partner (if a CPU) may blow up: stomping with an anger mark, and then
##    sardine    throws a sardine at the culprit (bonk + "!" mark, the same gag as the umpire's props), or
##    punch      storms over and throws a wild punch: the culprit is knocked down, sees stars, "POW!"
##    angry      just stomps.
##
##  After the match-winning point the losers' tantrum is likelier (70 %) and always aimed at the player (or at the culprit on a CPU
##  pair): sardine or punch, and the match scene waits for the show (wait_idle) before the final replay / Win! banner.
##
## Celebrations and gags make the point phase a bit longer (director.celebration_hold, at most ~3.9 s) and can be SKIPPED like the
## instant replay: press any key / tap (a "skip" chip appears at the bottom). A replay / hawk-eye review takes priority: then only a
## quick clap / cheer is used.

const ERRORS := ["出界", "触网", "发球失误", "发球超时"]
const P_ERR := 0.45                  # the culprit's partner erupts after the culprit's own error ...
const P_BLAME := 0.16                # ... or after a ball that dropped near the culprit
const MIN_GAP := 3                   # points between two eruptions of the same team
const P_FINAL := 0.7                 # after the LAST point of the match the losing pair falls out much more often (sardine or punch only)
const DANCES := ["dance_a", "dance_b", "dance_c"]

var scene: MatchScene
var director: MatchDirector
var _gen := 0                        # bumped to abort every running routine (new point / skip)
var _since_gag := [9, 9]
var _celebrating := false
var _celeb_t := 0.0
var _gag_busy := false
var _chip_layer: CanvasLayer
var _chip: Panel
var _force_celeb := ""               # dev: --banter=clap|highfive|dance|cheer
var _force_gag := ""                 # dev: --banter=sardine|punch|angry
var _rng := RandomNumberGenerator.new()


func build(p_scene: MatchScene, p_director: MatchDirector) -> void:
	scene = p_scene
	director = p_director
	_rng.randomize()
	director.point_scored.connect(_on_point)
	director.phase_changed.connect(func(p): if p != MatchDirector.P.POINT and p != MatchDirector.P.OVER: _stop_show())
	if Game.main != null and Game.main.dev.has("skiptest"):                       # dev: --skiptest presses a key 1 s into every celebration and times the gap
		director.phase_changed.connect(func(p): print("[skiptest] phase=%d at %.2f s" % [p, float(Time.get_ticks_msec()) / 1000.0]))
	_build_chip()
	if Game.main != null and Game.main.dev.has("banter"):
		var k := String(Game.main.dev["banter"])
		if k in ["sardine", "punch", "angry"]:
			_force_gag = k
		else:
			_force_celeb = k
		_dev_point()


func _build_chip() -> void:
	_chip_layer = CanvasLayer.new()
	_chip_layer.layer = 11
	add_child(_chip_layer)
	var vp := get_viewport().get_visible_rect().size
	_chip = Panel.new()
	_chip.size = Vector2(340, 56)
	_chip.position = Vector2((vp.x - 340.0) * 0.5, vp.y - 56.0 - 128.0)
	_chip.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.05, 0.12, 0.3, 0.55), 28, 2, Color(1, 1, 1, 0.8), 6))
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(tr("轻触跳过") if Game.is_touch else tr("按任意键跳过"), 28, Color.WHITE, 6, Color(0.05, 0.1, 0.25, 0.9))
	l.size = _chip.size
	_chip.add_child(l)
	_chip.visible = false
	_chip_layer.add_child(_chip)


func _alive(gen: int) -> bool:
	return gen == _gen and is_inside_tree()


func _wait(secs: float, gen: int) -> bool:
	await get_tree().create_timer(secs).timeout
	return _alive(gen)


# ------------------------------------------------------------------ the show
func _on_point(team: int, reason: String, pos: Vector3) -> void:
	if director.is_practice():
		return
	_stop_show()
	_gen += 1
	var gen := _gen
	await get_tree().create_timer(0.22).timeout                   # (after the director has set every athlete's celebrate / sad state)
	if not _alive(gen):
		return
	_since_gag[0] += 1
	_since_gag[1] += 1
	var final := director.phase == MatchDirector.P.OVER           # the match-winning point
	var replay_due := director.hold_next                         # a replay / hawk-eye review is about to take over the screen
	if final:
		replay_due = scene.hawk != null and HawkEye.wanted(director._point_info)     # (the scene's own final replay waits for this show)
	# ---- the losers: somebody blows up?
	var culprit := _culprit(1 - team, reason, pos)
	if final:
		culprit = _final_target(1 - team, culprit)
	var gag := ""
	if not replay_due and culprit != null:
		var actor := director.mate_of(culprit)
		if actor != null and not actor.is_human and not actor.choreo:
			if _force_gag != "":
				gag = _force_gag
			elif _force_celeb != "":
				pass                                                                # (a forced celebration test shows only the celebration)
			elif final:
				if _rng.randf() < P_FINAL:
					gag = "sardine" if _rng.randf() < 0.5 else "punch"
			elif int(_since_gag[1 - team]) >= MIN_GAP and _rng.randf() < (P_ERR if ERRORS.has(reason) else P_BLAME):
				var r := _rng.randf()
				gag = "sardine" if r < 0.45 else ("punch" if r < 0.75 else "angry")
	# ---- the winners: a routine
	# the player's side just lost the MATCH: the opponents do not dance on it - they stand calmly while the losers sulk / fall out
	var sulk_final := final
	for w in director.team_athletes(team):
		if w.is_human:
			sulk_final = false
	var kind := _force_celeb if _force_celeb != "" else ("cheer" if sulk_final else _pick_celebration(reason, replay_due))
	if sulk_final and _force_celeb == "":
		for w in director.team_athletes(team):
			w.rig.play("ready", 0.35)
	_celebrating = kind != "cheer" or gag != ""
	_celeb_t = 0.0
	if gag != "":
		_since_gag[1 - team] = 0
		_gag(gen, culprit, gag)
	if kind != "cheer":
		director.celebration_hold = director.phase_time + 3.9
		_chip.visible = true
		if Game.main != null and Game.main.dev.has("skiptest"):
			_press_key_later(1.0, gen)
	match kind:
		"clap": await _clap(gen, team)
		"highfive": await _highfive(gen, team)
		"dance": await _dance(gen, team)
	while _gag_busy and _alive(gen):
		await get_tree().process_frame
	if not _alive(gen):
		return
	_celebrating = false
	_chip.visible = false
	director.celebration_hold = 0.0


## the victim of the final tantrum: the human player of the losing pair if there is one, else the culprit, else anybody - but always
## somebody whose partner is a CPU (a human partner cannot be made to throw things)
func _final_target(loser: int, culprit: Athlete) -> Athlete:
	var ts: Array[Athlete] = director.team_athletes(loser)
	var cands: Array[Athlete] = []
	for a in ts:
		if a.is_human:
			cands.append(a)
	if culprit != null and not cands.has(culprit):
		cands.append(culprit)
	var start := _rng.randi() % maxi(ts.size(), 1)
	for i in ts.size():
		var a: Athlete = ts[(start + i) % ts.size()]
		if not cands.has(a):
			cands.append(a)
	for a in cands:
		var m := director.mate_of(a)
		if m != null and not m.is_human:
			return a
	return null


func _pick_celebration(reason: String, replay_due: bool) -> String:
	if replay_due:
		return "clap" if _rng.randf() < 0.5 else "cheer"
	var big := reason == "ACE!" or director.rally_len >= 8
	var w := {"cheer": 14.0, "clap": 20.0, "highfive": 36.0, "dance": 30.0 if big else 22.0}
	var total := 0.0
	for k in w.keys():
		total += float(w[k])
	var r := _rng.randf() * total
	for k in w.keys():
		r -= float(w[k])
		if r <= 0.0:
			return String(k)
	return "cheer"


## who made the mistake on the losing team (null = nobody in particular)
func _culprit(loser: int, reason: String, pos: Vector3) -> Athlete:
	if ERRORS.has(reason):
		var h: Athlete = director.last_hitter
		if reason == "发球失误" or reason == "发球超时" or h == null:
			h = director.server
		return h if (h != null and h.team == loser) else null
	if reason == "得分!" or reason == "ACE!":
		var best: Athlete = null
		var bd := 99.0
		for a in director.team_athletes(loser):
			var d := Vector2(a.global_position.x - pos.x, a.global_position.z - pos.z).length()
			if d < bd:
				bd = d
				best = a
		return best if bd < 3.2 else null
	return null


## the match scene waits for the final celebration / tantrum before it starts the closing replay (a key press ends it at once)
func wait_idle(max_s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (_celebrating or _gag_busy) and is_inside_tree() and float(Time.get_ticks_msec() - t0) < max_s * 1000.0:
		await get_tree().process_frame
	if _celebrating or _gag_busy:
		_stop_show()


func _process(dt: float) -> void:
	if _celebrating:
		_celeb_t += dt


func _input(event: InputEvent) -> void:
	if not _celebrating or _celeb_t < 0.5:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed) or (event is InputEventJoypadButton and event.pressed):
		_skip()


func _skip() -> void:
	_stop_show()
	director.skip_point_wait()


## aborts the routines and puts everybody back in the plain winner / loser pose
func _stop_show() -> void:
	_gen += 1
	_celebrating = false
	_gag_busy = false
	if _chip != null:
		_chip.visible = false
	if director == null:
		return
	director.celebration_hold = 0.0
	var winner := int(director._point_info.get("winner", -1))
	for a in director.athletes:
		if a.choreo:
			a.choreo_end(a.team == winner)
			if a.team != winner and a.state != Athlete.S.KNOCKED and a.state != Athlete.S.GETUP:
				a.sad()


# ------------------------------------------------------------------ celebrations
func _clap(gen: int, team: int) -> void:
	for a in director.team_athletes(team):
		if a.state != Athlete.S.CELEB:
			continue
		a.rig.play("clap", 0.12, _rng.randf_range(0.95, 1.1))
		scene.vfx.confetti(a.global_position + Vector3(0, 1.3, 0), 18)              # a little party popper each
	director.celebration_hold = director.phase_time + 2.6
	await _wait(2.4, gen)


func _highfive(gen: int, team: int) -> void:
	var ws: Array[Athlete] = director.team_athletes(team)
	var a: Athlete = ws[0]
	var b: Athlete = ws[1]
	if a.global_position.x > b.global_position.x:
		var t := a
		a = b
		b = t
	var s := Court.team_sign(team)
	var arm := float(a.rig.info.arm_len) * a.rig.scale.y
	var gap := clampf(2.0 * 0.82 * arm, 0.8, 1.7)                                  # their hands meet in the middle
	var mx := clampf((a.global_position.x + b.global_position.x) * 0.5, -2.6, 2.6)
	var mz := s * clampf(absf(a.global_position.z + b.global_position.z) * 0.5, 2.6, 6.2)
	a.choreo_walk(Vector3(mx - gap * 0.5, 0.0, mz))
	b.choreo_walk(Vector3(mx + gap * 0.5, 0.0, mz))
	var t_walk := 0.0
	while t_walk < 2.3 and not (a.choreo_arrived() and b.choreo_arrived()):
		await get_tree().process_frame
		if not _alive(gen):
			return
		t_walk += get_process_delta_time()
	director.celebration_hold = director.phase_time + 1.9
	a.choreo_pose(-PI * 0.5, "highfive_r", 0.12)                                  # a (on the left) faces +x and uses the right hand ...
	b.choreo_pose(PI * 0.5, "highfive_l", 0.12)                                   # ... b faces -x and uses the left hand
	if not await _wait(0.42, gen):
		return
	var mid := (a.rig.hand_world("r") + b.rig.hand_world("l")) * 0.5
	Sfx.play("hit_perfect", -3.0, 1.35)
	scene.vfx.hit_burst(mid, "perfect", 0.5)
	scene.vfx.confetti(mid + Vector3(0, 0.2, 0), 26)
	scene.cam_rig.shake(0.12)
	if not await _wait(1.05, gen):
		return
	a.choreo_end()
	b.choreo_end()
	await _wait(0.3, gen)


func _dance(gen: int, team: int) -> void:
	var dance: String = DANCES[_rng.randi() % DANCES.size()]
	if Game.main != null and Game.main.dev.has("dance"):                         # dev: --dance=dance_a|dance_b|dance_c
		dance = String(Game.main.dev["dance"])
	var ws: Array[Athlete] = director.team_athletes(team)
	ws[0].choreo_pose(PI, dance, 0.15)                                             # facing +z: towards the camera and the crowd
	if not await _wait(0.1, gen):
		return
	ws[1].choreo_pose(PI, dance, 0.15)
	director.celebration_hold = director.phase_time + 3.2
	if not await _wait(3.1, gen):
		return
	for a in ws:
		a.choreo_end()


# ------------------------------------------------------------------ the gags
func _gag(gen: int, culprit: Athlete, kind: String) -> void:
	var actor := director.mate_of(culprit)
	_gag_busy = true
	match kind:
		"sardine": await _do_sardine(gen, actor, culprit)
		"punch": await _do_punch(gen, actor, culprit)
		_: await _do_angry(gen, actor)
	_gag_busy = false
	if _alive(gen) and is_instance_valid(actor) and actor.state == Athlete.S.SAD:
		actor.facing_override = NAN


func _angry_start(actor: Athlete) -> void:
	actor.rig.play("angry", 0.1)
	var head_y: float = actor.rig.head_world().y - actor.global_position.y + 0.3
	AngerMark.spawn_over(actor, head_y, 1.3)
	Sfx.play("crowd_oh", -9.0, 1.2)


func _do_angry(gen: int, actor: Athlete) -> void:
	_angry_start(actor)
	if await _wait(1.25, gen) and actor.state == Athlete.S.SAD:
		actor.rig.play("sad", 0.3)


func _do_sardine(gen: int, actor: Athlete, culprit: Athlete) -> void:
	_angry_start(actor)
	if not await _wait(0.62, gen) or actor.state != Athlete.S.SAD:
		return
	var to := culprit.global_position - actor.global_position
	actor.facing_override = atan2(-to.x, -to.z)
	actor.rig.play("throw_fish", 0.08)
	if not await _wait(0.42, gen):                                                  # the release frame of the clip
		return
	ThrowProp.launch_at(get_parent(), scene, culprit, "fish", 2, actor.rig.hand_world("r"))
	if await _wait(0.8, gen) and actor.state == Athlete.S.SAD:
		actor.rig.play("sad", 0.3)


func _do_punch(gen: int, actor: Athlete, culprit: Athlete) -> void:
	_angry_start(actor)
	var d := Vector2(culprit.global_position.x - actor.global_position.x, culprit.global_position.z - actor.global_position.z)
	if d.length() > 1.4:                                                           # storm over to the culprit
		var near := culprit.global_position - Vector3(d.x, 0.0, d.y).normalized() * 0.95
		actor.choreo_walk(near, 2.0)
		var t := 0.0
		while t < 2.1 and not actor.choreo_arrived():
			await get_tree().process_frame
			if not _alive(gen):
				return
			t += get_process_delta_time()
	director.celebration_hold = maxf(director.celebration_hold, director.phase_time + 1.9)
	_celebrating = true
	var dir := Vector2(culprit.global_position.x - actor.global_position.x, culprit.global_position.z - actor.global_position.z)
	if dir.length() < 0.01:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	actor.choreo_pose(atan2(-dir.x, -dir.y), "punch", 0.08)
	if not await _wait(0.34, gen):                                                  # the fist lands at ~0.34 s
		return
	culprit.punched_by(dir)
	Sfx.play("hit_spike", -2.0, 1.1)
	AlertMark.spawn_over(culprit, culprit.rig.head_world().y - culprit.global_position.y + 0.3, 1.6)    # (the same "!" as after a thrown sardine)
	scene.cam_rig.shake(0.35)
	scene.vfx.hit_burst(culprit.rig.head_world(), "perfect", 0.6)
	var cam := scene.cam_rig.cam
	var head := culprit.rig.head_world() + Vector3(0, 0.35, 0)
	if not cam.is_position_behind(head):
		var pow := Callout.make("POW!", 78, Color("fff6b0"), Color("ffb62e"), Color("a8470c"))
		pow.position = cam.unproject_position(head)
		pow.rotation = deg_to_rad(-10.0)
		scene.hud.popup_layer.add_child(pow)
		pow.play(0.55, 1.7, 36.0, true)
	if not await _wait(0.75, gen):
		return
	actor.choreo_end(false)
	actor.sad()


# ------------------------------------------------------------------ dev
func _press_key_later(secs: float, gen: int) -> void:
	await get_tree().create_timer(secs).timeout
	if _alive(gen):
		var ev := InputEventKey.new()
		ev.keycode = KEY_F5
		ev.pressed = true
		Input.parse_input_event(ev)


## --banter=<kind> [--banter_team=0|1]: that team wins a point after 1.2 s, the other team's last toucher having hit it out
func _dev_point() -> void:
	await get_tree().create_timer(1.2).timeout
	var win := int(Game.main.dev.get("banter_team", 0))
	if Game.main.dev.has("banter_final"):                                         # dev: --banter_final makes it the match-winning point
		director.score[win] = director.target_points - 1
		director.score[1 - win] = 0
	var losers := director.team_athletes(1 - win)
	director.last_hitter = losers[0]
	director._end_point(win, "出界", Vector3(5.6, 0.0, 3.0 * Court.team_sign(1 - win)))
