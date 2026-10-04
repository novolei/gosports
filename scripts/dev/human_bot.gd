class_name HumanBot
extends Node
## Dev tool: plays player 1 through the real InputMap actions (so HumanBrain, assist, aim and the HUD are exercised).
## Enabled with --humanbot. Not part of normal play.

var ms: MatchScene
var athlete: Athlete
var _release := {}
var _serve_wait := -1.0
var _spike_jump := false
var _t := 0.0


func _ready() -> void:
	process_physics_priority = -20      # act before the athletes read the input


func attach(p_ms: MatchScene) -> void:
	ms = p_ms
	for a in ms.athletes:
		if a.is_human and a.player_index == 1:
			athlete = a


func _press(action: String) -> void:
	Input.action_press(action)
	_release[action] = 2


func _physics_process(dt: float) -> void:
	_t += dt
	for k in _release.keys():
		_release[k] -= 1
		if _release[k] <= 0:
			Input.action_release(k)
			_release.erase(k)
	if athlete == null:
		return
	var d := ms.director
	var a := athlete
	var ball := ms.ball
	if d.phase == MatchDirector.P.SERVING and d.server == a:
		if a.state == Athlete.S.SERVE_HOLD:
			if _serve_wait < 0.0:
				_serve_wait = 1.2
			_serve_wait -= dt
			if _serve_wait <= 0.0:
				_serve_wait = -1.0
				_press("p1_hit")
		elif a.state == Athlete.S.SERVE_TOSS:
			if ball.global_position.y <= a.global_position.y + 1.65 and ball.vel.y < 1.0:
				_press("p1_hit")
		return
	if d.phase != MatchDirector.P.RALLY:
		return
	var plan: Dictionary = d.plans[a.team]
	if plan.get("who") != a or plan.get("mode") != "play":
		return
	var tn: int = plan["touch"]
	var kind := a._choose_kind()
	if tn >= 3 and plan["h"] > 2.5:
		var t: float = plan["t"]
		if a.state == Athlete.S.READY and t < Athlete.JUMP_V / Athlete.AGRAV * 0.95 + 0.12 and not _spike_jump:
			_spike_jump = true
			_press("p1_jump")
		elif a.state == Athlete.S.AIR and a.hit_distance("spike") < 0.6:
			_press("p1_hit")
		return
	_spike_jump = false
	if Game.main != null and Game.main.dev.has("dbgbot") and a.hit_distance(kind) < 1.6:
		print("[bot] tn=%d kind=%s dist=%.2f can=%s st=%d ball=%s" % [tn, kind, a.hit_distance(kind), d.can_hit(a), a.state, str(ball.global_position)])
	if d.can_hit(a) and a.hit_distance(kind) < 0.5:
		_press("p1_hit")
