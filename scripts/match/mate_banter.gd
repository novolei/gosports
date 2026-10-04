class_name MateBanter
extends Node
## Funny team moments for the player's own side (solo / versus: the CPU partner):
##  * the player's team scores: both team mates CLAP (with a party-popper burst of confetti) instead of the plain cheer;
##  * the player's mistake loses the point (the player's last touch, then out / net / serve fault / serve timeout): the CPU partner
##    sometimes gets ANGRY (stomping, a red anger mark over the head) and every now and then THROWS A SARDINE at the player,
##    who is bonked and gets the "!" mark - the same gag as the umpire's props.
## Rate limits keep it a gag: the partner reacts at most every few points.

const ERRORS := ["出界", "触网", "发球失误", "发球超时"]
const P_ANGRY := 0.45
const P_THROW := 0.4                 # of the angry ones

var scene: MatchScene
var director: MatchDirector
var _since_angry := 9
var _force := ""                  # dev: --banter=clap|angry|throw forces the gag at the next point
var _human: Athlete
var _mate: Athlete


func build(p_scene: MatchScene, p_director: MatchDirector) -> void:
	scene = p_scene
	director = p_director
	for a in director.athletes:
		if a.is_human and _human == null:
			_human = a
	if _human == null:
		return
	_mate = director.mate_of(_human)
	director.point_scored.connect(_on_point)
	if Game.main != null and Game.main.dev.has("banter"):          # dev: --banter=clap|angry|throw plays the gag once after 3 s
		_dev(String(Game.main.dev["banter"]))


func _on_point(team: int, reason: String, _pos: Vector3) -> void:
	if _human == null or director.is_practice():
		return
	await get_tree().create_timer(0.22).timeout                   # (after the director has set every athlete's celebrate / sad state)
	if not is_inside_tree():
		return
	_since_angry += 1
	if team == _human.team:
		_applause()
		return
	if _force == "angry" or _force == "throw":
		_angry(_force == "throw")
		return
	var own_error := director.last_hitter == _human and ERRORS.has(reason)
	if own_error and _mate != null and not _mate.is_human and _since_angry >= 3 and randf() < P_ANGRY:
		_since_angry = 0
		_angry(randf() < P_THROW)


# ------------------------------------------------------------------ applause
func _applause() -> void:
	for a in director.team_athletes(_human.team):
		if a.state != Athlete.S.CELEB:
			continue
		a.rig.play("clap", 0.12, randf_range(0.95, 1.1))
		if scene != null:
			var p := a.global_position + Vector3(0, 1.3, 0)
			scene.vfx.confetti(p, 18)                              # a little party popper each


# ------------------------------------------------------------------ anger and the sardine
func _angry(throw_it: bool) -> void:
	var m := _mate
	if m == null or not is_instance_valid(m):
		return
	m.rig.play("angry", 0.1)
	var head_y: float = m.rig.head_world().y - m.global_position.y + 0.3
	AngerMark.spawn_over(m, head_y, 1.3)
	Sfx.play("crowd_oh", -9.0, 1.2)
	if not throw_it:
		return
	await get_tree().create_timer(0.62).timeout
	if not is_inside_tree() or not is_instance_valid(m) or not is_instance_valid(_human) or m.state != Athlete.S.SAD:
		return
	var to := _human.global_position - m.global_position
	m.facing_override = atan2(-to.x, -to.z)
	m.rig.play("throw_fish", 0.08)
	await get_tree().create_timer(0.42).timeout                    # the release frame of the clip
	if not is_inside_tree() or not is_instance_valid(m) or not is_instance_valid(_human):
		return
	ThrowProp.launch_at(get_parent(), scene, _human, "fish", 2, m.rig.hand_world("r"))
	await get_tree().create_timer(0.75).timeout
	if is_instance_valid(m) and m.state == Athlete.S.SAD:
		m.facing_override = NAN
		m.rig.play("sad", 0.3)


func _dev(kind: String) -> void:
	await get_tree().create_timer(1.2).timeout
	_force = kind
	match kind:
		"clap":
			director._end_point(_human.team, "得分!", Vector3(0.5, 0, -3.0))
		_:
			director.last_hitter = _human
			director._end_point(1 - _human.team, "出界", Vector3(5.6, 0, -3.0))
