class_name BenchCrew
extends Node3D
## The "教练与队友" court decoration: a bench for each team outside the left hoarding (our side blue, the opponents pink),
## a few cartoon substitutes sitting on it and a standing coach. They watch the court and react to the match: cheer when their
## team scores, sigh / shake their heads when the other one does, and play small gags in between. Same baked clips as the umpire
## ("ref_*" for the seated ones, the stock "cheer" / "sad" / "idle_*" for the coaches).

const X := -9.75                    # outside the hoarding (x = -8.45), clear of everything that moves
const IDLE_COACH := ["idle_a", "idle_b", "idle_c"]
const GAGS := ["ref_wave", "ref_nod", "ref_yawn", "ref_wipe", "ref_shrug", "ref_wow"]

var director: MatchDirector
var _rng := RandomNumberGenerator.new()
var _seated: Array = [[], []]        # per team: CharacterRig
var _coach: Array = [null, null]
var _gag_in := [6.0, 9.0]


func build(p_director: MatchDirector, look: Dictionary, exclude: Array) -> void:
	director = p_director
	_rng.randomize()
	var pool: Array[Dictionary] = []
	for e in Roster.all():
		if e["kind"] == "cube" and not String(e["model"]).ends_with("/Human.fbx") and not exclude.has(e["id"]):
			pool.append(e)
	pool.shuffle()
	var per := 3 if int(Game.settings["quality"]) >= 1 else 2
	var taken := 0
	var leg := 0.5
	for team in 2:
		var sgn := 1.0 if team == 0 else -1.0
		var zc := sgn * 5.9
		var yaw := -PI * 0.5 + sgn * 0.35                       # facing the court, turned a little towards the net
		for i in per:
			var rig := _make_rig(pool[taken])
			taken += 1
			leg = rig.info.hips_rest.y * rig.scale.y
			rig.position = Vector3(X, 0.03, zc + (float(i) - float(per - 1) * 0.5) * 1.15)       # (hips end up level with the seat)
			rig.rotation.y = yaw
			rig.play("ref_idle", 0.0, _rng.randf_range(0.85, 1.15))
			rig.anim.seek(_rng.randf() * 4.0, true)
			_seated[team].append(rig)
		var coach := _make_rig(pool[taken])
		taken += 1
		coach.position = Vector3(X + 0.15, 0.0, zc - sgn * 2.9)
		coach.rotation.y = yaw
		coach.play(IDLE_COACH[_rng.randi() % IDLE_COACH.size()], 0.0, _rng.randf_range(0.9, 1.1))
		coach.anim.seek(_rng.randf() * 2.0, true)
		_coach[team] = coach
	_build_benches(look, 0.5 * leg + 0.03)
	director.point_scored.connect(_on_point)
	director.match_over.connect(_on_over)


func _make_rig(entry: Dictionary) -> CharacterRig:
	var rig := CharacterRig.new()
	add_child(rig)
	rig.build(entry)
	rig.scale *= 1.05
	return rig


func _build_benches(look: Dictionary, seat_h: float) -> void:
	var m := CourtDeco.Mesher.new()
	var frame := Color(0.82, 0.84, 0.88)
	var wood := Color(0.72, 0.55, 0.38)
	for team in 2:
		var sgn := 1.0 if team == 0 else -1.0
		var col := UIKit.team_color(team)
		var zc := sgn * 5.9
		var len := 4.1
		m.box(Vector3(X, seat_h - 0.03, zc), Vector3(0.5, 0.06, len), wood)
		m.box(Vector3(X, seat_h + 0.01, zc), Vector3(0.44, 0.04, len - 0.14), col)
		m.box(Vector3(X - 0.3, seat_h + 0.3, zc), Vector3(0.05, 0.5, len), col.darkened(0.12))
		for dz in [-len * 0.5 + 0.2, 0.0, len * 0.5 - 0.2]:
			m.box(Vector3(X, seat_h * 0.5 - 0.02, zc + dz), Vector3(0.42, seat_h - 0.04, 0.07), frame)
		# a team flag at the end of the bench
		var zf := zc + sgn * (len * 0.5 + 0.35)
		m.bar(Vector3(X - 0.1, 0.0, zf), Vector3(X - 0.1, 2.3, zf), 0.06, frame)
		var a := Vector3(X - 0.1, 2.25, zf)
		m.tri2(a, a + Vector3(0, -0.6, 0), a + Vector3(0.0, -0.3, -sgn * 0.8), col)
	var mat := CourtDeco.lit_material()
	add_child(m.commit(mat))


func _process(dt: float) -> void:
	for team in 2:
		_gag_in[team] -= dt
		if _gag_in[team] <= 0.0:
			_gag_in[team] = _rng.randf_range(7.0, 14.0)
			if director != null and director.phase != MatchDirector.P.RALLY:
				var rig: CharacterRig = _seated[team][_rng.randi() % _seated[team].size()]
				_play_then_idle(rig, GAGS[_rng.randi() % GAGS.size()], "ref_idle")


func _on_point(team: int, _reason: String, _pos: Vector3) -> void:
	for t in 2:
		var won := t == team
		for i in _seated[t].size():
			var rig: CharacterRig = _seated[t][i]
			var delay := 0.08 * float(i) + _rng.randf() * 0.12
			var clip: String = "ref_cheer" if won else ["ref_sigh", "ref_shake", "ref_shrug"][_rng.randi() % 3]
			_after(delay, func(): _play_then_idle(rig, clip, "ref_idle"))
		var coach: CharacterRig = _coach[t]
		_after(0.1, func(): _play_for(coach, "cheer" if won else "sad", 2.2 if won else 1.8))


func _on_over(winner: int) -> void:
	for t in 2:
		var won := t == winner
		for rig in _seated[t]:
			_play_then_idle(rig, "ref_cheer" if won else "ref_sigh", "ref_idle")
		_play_for(_coach[t], "cheer" if won else "sad", 5.0)


func _after(delay: float, cb: Callable) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree():
		cb.call()


func _play_then_idle(rig: CharacterRig, clip: String, idle: String) -> void:
	if not is_instance_valid(rig) or not rig.anim.has_animation(clip):
		return
	rig.play(clip, 0.15)
	var len := rig.anim.get_animation(clip).length
	await get_tree().create_timer(len).timeout
	if is_instance_valid(rig) and rig.current == clip:
		rig.play(idle, 0.3)


func _play_for(rig: CharacterRig, clip: String, secs: float) -> void:
	if not is_instance_valid(rig) or not rig.anim.has_animation(clip):
		return
	rig.play(clip, 0.15)
	await get_tree().create_timer(secs).timeout
	if is_instance_valid(rig) and rig.current == clip:
		rig.play(IDLE_COACH[_rng.randi() % IDLE_COACH.size()], 0.3)
