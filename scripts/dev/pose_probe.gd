class_name PoseProbe
extends Node
## Dev only (--dbgpose): frame-to-frame bone rotation jumps of every athlete, with the state that caused them.

const POP := 0.5            # radians in one frame (~29 deg) counts as a visible pop

var athletes: Array = []
var _prev := {}
var _maxes: Array[float] = []
var _pops := {}             # "state|clip" -> count
var _frames := 0
var _log: Array[String] = []


func attach(scene) -> void:
	athletes = scene.athletes
	scene.add_child(self)


func _process(_dt: float) -> void:
	for a in athletes:
		var sk: Skeleton3D = a.rig.skeleton
		var n := sk.get_bone_count()
		var cur: Array[Quaternion] = []
		cur.resize(n)
		for i in n:
			cur[i] = sk.get_bone_pose_rotation(i)
		if _prev.has(a):
			var pv: Array = _prev[a]
			var worst := 0.0
			var wi := 0
			for i in n:
				var d: float = (pv[i] as Quaternion).angle_to(cur[i])
				if d > worst:
					worst = d
					wi = i
			_maxes.append(worst)
			if worst > POP:
				if _log.size() < 40:
					_log.append("f=%d %s bone=%s d=%.2f spd=%.2f loco=(%.2f,%.2f) state=%d" % [_frames, a.display_name, sk.get_bone_name(wi), worst, a.vel.length(), a.rig._loco_pos.x, a.rig._loco_pos.y, a.state])
				var key := "state=%d rig=%s mix=%s" % [a.state, a.rig.current, a.rig._mix_state]
				_pops[key] = int(_pops.get(key, 0)) + 1
		_prev[a] = cur
	_frames += 1


func _exit_tree() -> void:
	if _maxes.is_empty():
		return
	var s := _maxes.duplicate()
	s.sort()
	var cnt := s.size()
	var over35 := 0
	var over50 := 0
	for v in s:
		if v > 0.35:
			over35 += 1
		if v > POP:
			over50 += 1
	print("[pose] samples=%d  median=%.3f p95=%.3f p99=%.3f max=%.3f  >0.35rad: %d  >0.5rad: %d" % [cnt, s[cnt / 2], s[int(cnt * 0.95)], s[int(cnt * 0.99)], s[cnt - 1], over35, over50])
	for l in _log:
		print("[pose]   ", l)
	for k in _pops.keys():
		print("[pose]   pops  %s  x%d" % [k, _pops[k]])
