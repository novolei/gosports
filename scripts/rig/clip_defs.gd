class_name ClipDefs
extends RefCounted
## Definitions of animation clips baked into per-rig AnimationLibraries by tools/bake_anims.gd.
## Specs are rig independent (see PoseSolver): x = character right, y = up, z = forward;
## hand targets "handc_*" are relative to the chest centre in arm-lengths, feet "foot_*_off" are
## offsets from the rest ankle in leg-lengths.

const LOOPING := ["idle_a", "idle_b", "idle_c", "idle_d", "run_forward", "run_backwards", "run_left", "run_right",
		"run_strafe_left", "run_strafe_right", "walk_forward", "walk_backwards", "walk_left", "walk_right",
		"walk_strafe_left", "walk_strafe_right", "fight_idle", "falling", "ref_idle", "ref_sleep", "photo_idle", "photo_crouch"]

# retargeted Mixamo clips: name -> {file, loop, keep_xz, trim}
## Locomotion blend-space clips: direction -> Cubebrush source clip (all 0.79 s cycles, phase aligned).
## Speed levels are made by scaling the gait amplitude (see bake_anims.gd _scale_gait): level 1.0 = full run.
const LOCO_SOURCES := {"f": "run_forward", "b": "run_backwards", "l": "run_strafe_left", "r": "run_strafe_right",
		"fl": "run_left", "fr": "run_right"}
## The source strafe-left / back-run cycles are out of phase with the forward ones (left foot lifts at a different time),
## which cancels the leg swing when the blend space mixes them on the diagonals. Fraction of a cycle to roll each by.
const LOCO_PHASE := {"l": 0.54, "b": 0.66}
const LOCO_LEVELS := [0.35, 0.7, 1.0]
const LOCO_SPEED := 5.05             # m/s travelled by the full-run clips (one 0.79 s cycle = 4 m)
## Action clips are also baked as "<name>_h": the same clip starting just before its contact frame (no latency on hit).
const LEAD_START := {"bump": 0.155, "set": 0.155, "spike": 0.215, "serve_hit": 0.255}

## (empty by default: the volleyball clips are authored; the baker can retarget any Mixamo FBX through
##  this table, e.g. "dive_mx": {"file": "res://assets/mixamo/gk_dive.fbx", "loop": false, "keep_xz": false})
const MIXAMO := {}


static func is_loop(clip: String) -> bool:
	return LOOPING.has(clip)


static func _m(base: Dictionary, over: Dictionary) -> Dictionary:
	var r := base.duplicate()
	for k in over.keys():
		r[k] = over[k]
	return r


## shorthand for a pair of joined / mirrored hand targets
static func hands(x: float, y: float, z: float, spread := 0.0) -> Dictionary:
	return {"handc_l": Vector3(-x - spread, y, z), "handc_r": Vector3(x + spread, y, z)}


static func authored() -> Dictionary:
	var stand := {
		"hips": Vector3(0, 0, 0), "body": Vector3.ZERO, "torso": Vector3.ZERO, "head": Vector3.ZERO,
		"handc_l": Vector3(-0.28, -0.9, 0.1), "handc_r": Vector3(0.28, -0.9, 0.1),
		"elbow_l": Vector3(-0.7, -0.2, -0.7), "elbow_r": Vector3(0.7, -0.2, -0.7),
		"foot_l_off": Vector3.ZERO, "foot_r_off": Vector3.ZERO,
		"knee_l": Vector3(0, 0, 1), "knee_r": Vector3(0, 0, 1),
	}
	# athletic "ready" stance: knees bent, hands forward
	var ready := _m(stand, {
		"hips": Vector3(0, -0.11, 0.04), "body": Vector3(14, 0, 0), "torso": Vector3(8, 0, 0), "head": Vector3(-16, 0, 0),
		"handc_l": Vector3(-0.3, -0.5, 0.55), "handc_r": Vector3(0.3, -0.5, 0.55),
		"elbow_l": Vector3(-0.8, -0.6, -0.3), "elbow_r": Vector3(0.8, -0.6, -0.3),
		"foot_l_off": Vector3(-0.09, 0, 0.06), "foot_r_off": Vector3(0.09, 0, -0.05),
		"knee_l": Vector3(-0.25, 0, 1), "knee_r": Vector3(0.25, 0, 1),
	})
	var ready_b := _m(ready, {"hips": Vector3(0, -0.125, 0.045), "torso": Vector3(10, 0, 0),
			"handc_l": Vector3(-0.3, -0.55, 0.52), "handc_r": Vector3(0.3, -0.55, 0.52)})

	var bump_load := _m(ready, _m(hands(0.03, -0.62, 0.66), {
		"hips": Vector3(0, -0.2, 0.06), "body": Vector3(26, 0, 0), "torso": Vector3(10, 0, 0), "head": Vector3(-30, 0, 0),
		"elbow_l": Vector3(-0.4, -0.9, -0.1), "elbow_r": Vector3(0.4, -0.9, -0.1),
		"foot_l_off": Vector3(-0.12, 0, 0.08), "foot_r_off": Vector3(0.12, 0, -0.06)}))
	var bump_hit := _m(bump_load, _m(hands(0.03, -0.38, 0.86), {
		"hips": Vector3(0, -0.16, 0.07), "body": Vector3(18, 0, 0), "torso": Vector3(4, 0, 0)}))
	var bump_follow := _m(ready, _m(hands(0.03, 0.12, 0.9), {
		"hips": Vector3(0, -0.05, 0.05), "body": Vector3(6, 0, 0), "torso": Vector3(-6, 0, 0), "head": Vector3(-28, 0, 0),
		"elbow_l": Vector3(-0.4, -0.8, 0.0), "elbow_r": Vector3(0.4, -0.8, 0.0)}))

	var set_load := _m(ready, {
		"hips": Vector3(0, -0.13, 0.03), "body": Vector3(6, 0, 0), "torso": Vector3(-2, 0, 0), "head": Vector3(-34, 0, 0),
		"handc_l": Vector3(-0.2, 0.78, 0.36), "handc_r": Vector3(0.2, 0.78, 0.36),
		"elbow_l": Vector3(-1.0, 0.1, -0.2), "elbow_r": Vector3(1.0, 0.1, -0.2)})
	var set_hit := _m(set_load, {
		"hips": Vector3(0, -0.02, 0.02), "body": Vector3(2, 0, 0), "torso": Vector3(-4, 0, 0), "head": Vector3(-34, 0, 0),
		"handc_l": Vector3(-0.16, 0.9, 0.52), "handc_r": Vector3(0.16, 0.9, 0.52),
		"foot_l_off": Vector3(-0.09, 0.0, 0.06), "foot_r_off": Vector3(0.09, 0.02, -0.02)})
	var set_follow := _m(set_hit, {
		"hips": Vector3(0, 0.02, 0.02), "head": Vector3(-24, 0, 0),
		"handc_l": Vector3(-0.2, 0.84, 0.72), "handc_r": Vector3(0.2, 0.84, 0.72),
		"foot_l_off": Vector3(-0.09, 0.05, 0.06), "foot_r_off": Vector3(0.09, 0.08, -0.02)})

	# in the air, tucked, arms up for the swing
	var air := _m(stand, {
		"hips": Vector3(0, -0.04, 0.0), "body": Vector3(-6, 0, 0), "torso": Vector3(-4, 0, 0), "head": Vector3(-20, 0, 0),
		"handc_l": Vector3(-0.45, 0.6, 0.25), "handc_r": Vector3(0.45, 0.6, 0.25),
		"elbow_l": Vector3(-0.9, 0.2, -0.3), "elbow_r": Vector3(0.9, 0.2, -0.3),
		"foot_l_off": Vector3(-0.07, 0.3, -0.14), "foot_r_off": Vector3(0.07, 0.24, -0.2),
		"knee_l": Vector3(-0.2, 0, 1), "knee_r": Vector3(0.2, 0, 1)})
	var spike_cock := _m(air, {
		"body": Vector3(-14, -8, 0), "torso": Vector3(-14, -26, 0), "head": Vector3(-22, 10, 0),
		"handc_r": Vector3(0.55, 0.62, -0.35), "elbow_r": Vector3(0.9, 0.35, -0.5),
		"handc_l": Vector3(-0.3, 0.92, 0.5), "elbow_l": Vector3(-0.8, 0.2, -0.1),
		"foot_l_off": Vector3(-0.07, 0.38, -0.2), "foot_r_off": Vector3(0.07, 0.32, -0.28)})
	var spike_hit := _m(spike_cock, {
		"body": Vector3(10, 6, 0), "torso": Vector3(18, 24, 0), "head": Vector3(-10, -6, 0),
		"handc_r": Vector3(0.14, 0.98, 0.78), "elbow_r": Vector3(0.9, 0.5, -0.3),
		"handc_l": Vector3(-0.25, 0.1, 0.5), "elbow_l": Vector3(-0.8, -0.4, -0.1),
		"foot_l_off": Vector3(-0.07, 0.3, 0.1), "foot_r_off": Vector3(0.07, 0.22, -0.18)})
	var spike_follow := _m(spike_hit, {
		"body": Vector3(18, 10, 0), "torso": Vector3(26, 34, 0),
		"handc_r": Vector3(-0.15, 0.1, 0.78), "elbow_r": Vector3(0.4, -0.6, -0.4),
		"handc_l": Vector3(-0.45, -0.3, 0.2),
		"foot_l_off": Vector3(-0.07, 0.15, 0.1), "foot_r_off": Vector3(0.07, 0.12, 0.0)})

	var serve_stand := _m(stand, {
		"hips": Vector3(0, -0.05, 0.0), "body": Vector3(6, 14, 0), "head": Vector3(-10, -6, 0),
		"handc_l": Vector3(-0.3, -0.15, 0.7), "handc_r": Vector3(0.5, 0.4, -0.12),
		"elbow_l": Vector3(-0.7, -0.6, -0.2), "elbow_r": Vector3(1.0, 0.2, -0.6),
		"foot_l_off": Vector3(-0.07, 0, 0.12), "foot_r_off": Vector3(0.1, 0, -0.1)})
	var serve_toss_up := _m(serve_stand, {
		"hips": Vector3(0, 0.0, 0.0), "body": Vector3(-4, 14, 0), "torso": Vector3(-8, 8, 0), "head": Vector3(-30, -6, 0),
		"handc_l": Vector3(-0.2, 0.95, 0.4), "elbow_l": Vector3(-0.7, 0.2, -0.1),
		"foot_l_off": Vector3(-0.07, 0, 0.12), "foot_r_off": Vector3(0.1, 0.02, -0.1)})
	var serve_cock := _m(serve_toss_up, {
		"body": Vector3(-8, 12, 0), "torso": Vector3(-14, -10, 0), "head": Vector3(-30, 0, 0),
		"handc_r": Vector3(0.55, 0.64, -0.35), "elbow_r": Vector3(0.9, 0.35, -0.5),
		"handc_l": Vector3(-0.25, 0.7, 0.5), "elbow_l": Vector3(-0.8, 0.0, -0.2)})
	var serve_hit := _m(serve_cock, {
		"hips": Vector3(0, -0.02, 0.02), "body": Vector3(8, -6, 0), "torso": Vector3(16, 22, 0), "head": Vector3(-16, 0, 0),
		"handc_r": Vector3(0.12, 0.98, 0.72), "elbow_r": Vector3(0.9, 0.5, -0.3),
		"handc_l": Vector3(-0.3, 0.0, 0.4)})

	var block := _m(air, {
		"hips": Vector3(0, -0.02, 0.02), "body": Vector3(10, 0, 0), "torso": Vector3(6, 0, 0), "head": Vector3(-26, 0, 0),
		"handc_l": Vector3(-0.17, 1.0, 0.42), "handc_r": Vector3(0.17, 1.0, 0.42),
		"elbow_l": Vector3(-0.5, 0.2, -0.2), "elbow_r": Vector3(0.5, 0.2, -0.2),
		"foot_l_off": Vector3(-0.05, 0.22, -0.1), "foot_r_off": Vector3(0.05, 0.22, -0.1)})

	var dive_start := _m(ready, {"hips": Vector3(0, -0.2, 0.1), "body": Vector3(34, 0, 0), "torso": Vector3(10, 0, 0),
			"handc_l": Vector3(-0.12, -0.2, 0.95), "handc_r": Vector3(0.12, -0.2, 0.95)})
	var dive_fly := _m(stand, {
		"hips": Vector3(0, -0.36, 0.55), "body": Vector3(78, 0, 0), "torso": Vector3(6, 0, 0), "head": Vector3(-30, 0, 0),
		"handc_l": Vector3(-0.14, 0.0, 1.0), "handc_r": Vector3(0.14, 0.0, 1.0),
		"elbow_l": Vector3(-0.3, 0.3, 0.0), "elbow_r": Vector3(0.3, 0.3, 0.0),
		"foot_l_off": Vector3(-0.05, 0.15, -0.9), "foot_r_off": Vector3(0.05, 0.2, -0.95),
		"knee_l": Vector3(0, 1, 0), "knee_r": Vector3(0, 1, 0)})
	var dive_slide := _m(dive_fly, {"hips": Vector3(0, -0.5, 0.62), "body": Vector3(86, 0, 0),
			"foot_l_off": Vector3(-0.05, -0.02, -0.95), "foot_r_off": Vector3(0.05, 0.05, -1.0)})

	var cheer_a := _m(stand, {
		"hips": Vector3(0, -0.1, 0.0), "body": Vector3(8, 0, 0), "head": Vector3(-8, 0, 0),
		"handc_l": Vector3(-0.5, 0.2, 0.4), "handc_r": Vector3(0.5, 0.2, 0.4),
		"elbow_l": Vector3(-0.8, -0.3, -0.4), "elbow_r": Vector3(0.8, -0.3, -0.4),
		"foot_l_off": Vector3(-0.06, 0, 0.0), "foot_r_off": Vector3(0.06, 0, 0)})
	var cheer_b := _m(stand, {
		"hips": Vector3(0, 0.12, 0.0), "body": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0),
		"handc_l": Vector3(-0.55, 0.92, 0.2), "handc_r": Vector3(0.55, 0.92, 0.2),
		"elbow_l": Vector3(-0.9, 0.1, -0.3), "elbow_r": Vector3(0.9, 0.1, -0.3),
		"foot_l_off": Vector3(-0.06, 0.34, -0.1), "foot_r_off": Vector3(0.06, 0.3, -0.12)})
	var sad_a := _m(stand, {
		"hips": Vector3(0, -0.06, 0.02), "body": Vector3(22, 0, 3), "torso": Vector3(16, 0, 0), "head": Vector3(-34, 6, 0),
		"handc_l": Vector3(-0.26, -0.95, 0.12), "handc_r": Vector3(0.26, -0.95, 0.12),
		"foot_l_off": Vector3(-0.03, 0, 0.0), "foot_r_off": Vector3(0.03, 0, 0)})
	var sad_b := _m(sad_a, {"body": Vector3(25, 0, -3), "head": Vector3(-30, -6, 0), "hips": Vector3(0, -0.075, 0.02)})

	var whiff_a := _m(ready, _m(hands(0.05, -0.55, 0.7), {"hips": Vector3(0, -0.15, 0.05), "body": Vector3(20, 0, 0)}))
	var whiff_b := _m(ready, _m(hands(0.05, 0.0, 0.85), {"hips": Vector3(0, -0.08, 0.04), "body": Vector3(10, 0, 0)}))

	var land := _m(ready, {"hips": Vector3(0, -0.22, 0.04), "body": Vector3(20, 0, 0), "torso": Vector3(10, 0, 0),
			"foot_l_off": Vector3(-0.1, 0, 0.0), "foot_r_off": Vector3(0.1, 0, 0.0)})

	# --- body collisions: a short stumble, and a full knock-down -> dazed sitting -> get-up
	var stumble_a := _m(ready, {
		"hips": Vector3(0, -0.15, -0.05), "body": Vector3(-12, 0, 0), "torso": Vector3(-8, 0, 0), "head": Vector3(-6, 0, 0),
		"handc_l": Vector3(-0.66, 0.15, 0.3), "handc_r": Vector3(0.66, 0.15, 0.3),
		"elbow_l": Vector3(-0.9, 0.0, -0.3), "elbow_r": Vector3(0.9, 0.0, -0.3),
		"foot_l_off": Vector3(-0.1, 0.12, -0.2), "foot_r_off": Vector3(0.1, 0.0, 0.08)})
	var stumble_b := _m(stumble_a, {
		"hips": Vector3(0, -0.2, -0.03), "body": Vector3(-5, 0, 4), "torso": Vector3(-2, 0, 0),
		"handc_l": Vector3(-0.8, 0.3, 0.1), "handc_r": Vector3(0.8, 0.0, 0.4),
		"foot_l_off": Vector3(-0.1, 0.0, -0.22), "foot_r_off": Vector3(0.1, 0.16, -0.04)})
	var ko_a := _m(stand, {
		"hips": Vector3(0, -0.12, -0.1), "body": Vector3(-24, 0, 0), "torso": Vector3(-12, 0, 0), "head": Vector3(-8, 0, 0),
		"handc_l": Vector3(-0.75, 0.35, 0.25), "handc_r": Vector3(0.75, 0.35, 0.25),
		"elbow_l": Vector3(-0.95, 0.1, -0.2), "elbow_r": Vector3(0.95, 0.1, -0.2),
		"foot_l_off": Vector3(-0.08, 0.18, 0.12), "foot_r_off": Vector3(0.08, 0.1, 0.22),
		"knee_l": Vector3(-0.2, 0, 1), "knee_r": Vector3(0.2, 0, 1)})
	var ko_b := _m(ko_a, {
		"hips": Vector3(0, -0.45, -0.45), "body": Vector3(-62, 0, 0), "torso": Vector3(-8, 0, 0), "head": Vector3(-14, 0, 0),
		"handc_l": Vector3(-0.7, 0.4, 0.15), "handc_r": Vector3(0.7, 0.4, 0.15),
		"foot_l_off": Vector3(-0.1, 0.5, 0.35), "foot_r_off": Vector3(0.1, 0.42, 0.45),
		"knee_l": Vector3(-0.1, 0.6, 1), "knee_r": Vector3(0.1, 0.6, 1)})
	var ko_lie := _m(ko_b, {
		"hips": Vector3(0, -0.9, -0.62), "body": Vector3(-86, 0, 0), "torso": Vector3(-2, 0, 0), "head": Vector3(-22, 0, 0),
		"handc_l": Vector3(-0.8, 0.0, 0.0), "handc_r": Vector3(0.8, 0.0, 0.0),
		"elbow_l": Vector3(-1, -0.2, 0), "elbow_r": Vector3(1, -0.2, 0),
		"foot_l_off": Vector3(-0.12, 0.0, 0.9), "foot_r_off": Vector3(0.14, 0.02, 0.8),
		"knee_l": Vector3(-0.3, 1, 0), "knee_r": Vector3(0.3, 1, 0)})
	var sit_a := _m(stand, {
		"hips": Vector3(0, -0.9, -0.2), "body": Vector3(-14, 0, 3), "torso": Vector3(-4, 0, 0), "head": Vector3(8, 0, 10),
		"handc_l": Vector3(-0.5, -0.5, 0.1), "handc_r": Vector3(0.18, 0.5, 0.25),
		"elbow_l": Vector3(-0.8, -0.5, -0.3), "elbow_r": Vector3(0.9, 0.3, -0.3),
		"foot_l_off": Vector3(-0.22, 0.0, 0.85), "foot_r_off": Vector3(0.22, 0.0, 0.8),
		"knee_l": Vector3(-0.3, 1, 0.1), "knee_r": Vector3(0.3, 1, 0.1)})
	var sit_b := _m(sit_a, {"body": Vector3(-8, 0, -4), "torso": Vector3(-2, 0, 0), "head": Vector3(16, 0, -12),
			"handc_r": Vector3(0.22, 0.55, 0.2)})

	# --- the umpire on the high chair (scripts/match/referee.gd): sitting, hands on the knees, and a bag of reactions
	var rsit := _m(stand, {
		"hips": Vector3(0, -0.5, -0.16), "body": Vector3(-2, 0, 0), "torso": Vector3(2, 0, 0), "head": Vector3.ZERO,
		"handc_l": Vector3(-0.3, -0.62, 0.38), "handc_r": Vector3(0.3, -0.62, 0.38),
		"elbow_l": Vector3(-0.8, -0.4, -0.5), "elbow_r": Vector3(0.8, -0.4, -0.5),
		"foot_l_off": Vector3(-0.08, 0.04, 0.5), "foot_r_off": Vector3(0.08, 0.04, 0.5),
		"knee_l": Vector3(-0.15, 1, 0.4), "knee_r": Vector3(0.15, 1, 0.4)})
	var rsit_b := _m(rsit, {"hips": Vector3(0, -0.508, -0.16), "torso": Vector3(4, 0, 0)})
	var rl := _m(rsit_b, {"head": Vector3(-2, -16, 0), "body": Vector3(-2, -5, 0)})
	var rr := _m(rsit_b, {"head": Vector3(-2, 16, 0), "body": Vector3(-2, 5, 0)})
	var r_whistle := _m(rsit, {"handc_r": Vector3(0.1, 0.55, 0.42), "elbow_r": Vector3(0.6, 0.3, -0.5), "head": Vector3(-8, 0, 0), "torso": Vector3(-2, 0, 0)})
	var r_point_l := _m(rsit, {"handc_l": Vector3(-1.0, 0.18, 0.3), "elbow_l": Vector3(-1, 0.0, -0.1), "head": Vector3(-4, -26, 0),
			"body": Vector3(-2, -10, 0), "torso": Vector3(0, -14, 0)})
	var r_point_r := _m(rsit, {"handc_r": Vector3(1.0, 0.18, 0.3), "elbow_r": Vector3(1, 0.0, -0.1), "head": Vector3(-4, 26, 0),
			"body": Vector3(-2, 10, 0), "torso": Vector3(0, 14, 0)})
	var r_out := _m(rsit, {"handc_l": Vector3(-0.42, 0.52, 0.18), "handc_r": Vector3(0.42, 0.52, 0.18),
			"elbow_l": Vector3(-1, -0.2, -0.1), "elbow_r": Vector3(1, -0.2, -0.1), "head": Vector3(-8, 0, 0)})
	var r_no_a := _m(rsit, {"head": Vector3(4, -30, -6), "torso": Vector3(6, -6, 0), "body": Vector3(2, -4, 0)})
	var r_no_b := _m(rsit, {"head": Vector3(4, 30, 6), "torso": Vector3(6, 6, 0), "body": Vector3(2, 4, 0)})
	var r_inhale := _m(rsit, {"torso": Vector3(-8, 0, 0), "body": Vector3(-5, 0, 0), "head": Vector3(-12, 0, 0), "hips": Vector3(0, -0.49, -0.17),
			"handc_l": Vector3(-0.3, -0.5, 0.36), "handc_r": Vector3(0.3, -0.5, 0.36)})
	var r_slump := _m(rsit, {"torso": Vector3(16, 0, 0), "body": Vector3(12, 0, 0), "head": Vector3(26, 0, 0), "hips": Vector3(0, -0.54, -0.12),
			"handc_l": Vector3(-0.3, -0.72, 0.3), "handc_r": Vector3(0.3, -0.72, 0.3)})
	var r_cheer_a := _m(rsit, {"handc_l": Vector3(-0.55, 0.92, 0.15), "handc_r": Vector3(0.55, 0.92, 0.15),
			"elbow_l": Vector3(-0.9, 0.1, -0.3), "elbow_r": Vector3(0.9, 0.1, -0.3), "head": Vector3(-14, 0, 0), "body": Vector3(-6, 0, 0)})
	var r_cheer_b := _m(r_cheer_a, {"hips": Vector3(0, -0.44, -0.16), "handc_l": Vector3(-0.45, 0.8, 0.2), "handc_r": Vector3(0.45, 0.8, 0.2)})
	var r_wow := _m(rsit, {"body": Vector3(-12, 0, 0), "torso": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0), "hips": Vector3(0, -0.47, -0.2),
			"handc_l": Vector3(-0.3, 0.3, 0.36), "handc_r": Vector3(0.3, 0.3, 0.36), "elbow_l": Vector3(-1, -0.2, -0.2), "elbow_r": Vector3(1, -0.2, -0.2)})
	var r_yawn := _m(rsit, {"head": Vector3(-26, 0, 0), "body": Vector3(-8, 0, 0), "torso": Vector3(-4, 0, 0), "handc_r": Vector3(0.12, 0.6, 0.5),
			"elbow_r": Vector3(0.7, 0.2, -0.5)})
	var r_yawn_b := _m(r_yawn, {"head": Vector3(-30, 0, 0), "body": Vector3(-10, 0, 0)})
	var r_wipe_a := _m(rsit, {"handc_r": Vector3(0.22, 0.92, 0.34), "elbow_r": Vector3(0.9, 0.4, -0.3), "head": Vector3(4, 4, 0), "torso": Vector3(6, 0, 0)})
	var r_wipe_b := _m(r_wipe_a, {"handc_r": Vector3(-0.06, 0.92, 0.38), "head": Vector3(4, -4, 0)})
	var r_nod_a := _m(rsit, {"head": Vector3(16, 0, 0)})
	var r_think := _m(rsit, {"handc_r": Vector3(0.1, 0.5, 0.42), "elbow_r": Vector3(0.6, 0.3, -0.5), "head": Vector3(-6, 8, 8), "torso": Vector3(4, 0, 0)})
	var r_wave_a := _m(rsit, {"handc_r": Vector3(0.6, 0.9, 0.22), "elbow_r": Vector3(0.9, 0.2, -0.3), "head": Vector3(-6, 8, 4), "body": Vector3(-3, 5, 0)})
	var r_wave_b := _m(r_wave_a, {"handc_r": Vector3(0.9, 0.95, 0.2)})
	var r_sleep_a := _m(rsit, {"head": Vector3(26, 0, 6), "body": Vector3(8, 0, 0), "torso": Vector3(10, 0, 0), "hips": Vector3(0, -0.53, -0.14),
			"handc_l": Vector3(-0.3, -0.7, 0.32), "handc_r": Vector3(0.3, -0.7, 0.32)})
	var r_sleep_b := _m(r_sleep_a, {"head": Vector3(38, 0, 8), "body": Vector3(12, 0, 0), "torso": Vector3(14, 0, 0)})
	var r_shrug := _m(rsit, {"handc_l": Vector3(-0.6, -0.1, 0.3), "handc_r": Vector3(0.6, -0.1, 0.3), "elbow_l": Vector3(-1, -0.3, -0.1),
			"elbow_r": Vector3(1, -0.3, -0.1), "head": Vector3(0, 0, 10), "torso": Vector3(-2, 0, 0)})

	# --- the press photographers (scripts/match/press_crew.gd): a camera held at the chest, raised to the eye for a shot
	var pho_hold := _m(stand, {
		"hips": Vector3(0, -0.06, 0.0), "body": Vector3(8, 0, 0), "head": Vector3(-6, 0, 0),
		"handc_l": Vector3(-0.1, -0.22, 0.52), "handc_r": Vector3(0.1, -0.22, 0.52),
		"elbow_l": Vector3(-0.8, -0.7, -0.3), "elbow_r": Vector3(0.8, -0.7, -0.3),
		"foot_l_off": Vector3(-0.07, 0, 0.04), "foot_r_off": Vector3(0.07, 0, -0.04),
		"knee_l": Vector3(-0.15, 0, 1), "knee_r": Vector3(0.15, 0, 1)})
	var pho_hold_b := _m(pho_hold, {"hips": Vector3(0, -0.066, 0.0), "head": Vector3(-8, 4, 0), "body": Vector3(9, 2, 0)})
	var pho_up := _m(pho_hold, {
		"handc_l": Vector3(-0.08, 0.5, 0.5), "handc_r": Vector3(0.08, 0.5, 0.5),
		"elbow_l": Vector3(-0.95, 0.1, -0.2), "elbow_r": Vector3(0.95, 0.1, -0.2), "head": Vector3(-12, 0, 0), "body": Vector3(6, 0, 0)})
	var pho_click := _m(pho_up, {"handc_r": Vector3(0.1, 0.46, 0.46), "head": Vector3(-14, 0, 0)})
	var pho_crouch := _m(pho_hold, {"hips": Vector3(0, -0.22, 0.04), "body": Vector3(16, 0, 0),
		"foot_l_off": Vector3(-0.1, 0, 0.08), "foot_r_off": Vector3(0.1, 0, -0.06), "knee_l": Vector3(-0.3, 0, 1), "knee_r": Vector3(0.3, 0, 1)})
	var pho_crouch_up := _m(pho_crouch, {"handc_l": Vector3(-0.08, 0.52, 0.5), "handc_r": Vector3(0.08, 0.52, 0.5),
		"elbow_l": Vector3(-0.95, 0.1, -0.2), "elbow_r": Vector3(0.95, 0.1, -0.2), "head": Vector3(-16, 0, 0)})

	# --- the umpire throws something at a server who is dawdling (scripts/match/referee.gd): wind-up, release, follow-through
	var r_wind_r := _m(rsit, {"handc_r": Vector3(0.62, 0.85, -0.5), "elbow_r": Vector3(1.0, 0.6, -0.9), "handc_l": Vector3(-0.3, -0.3, 0.45),
			"torso": Vector3(-4, -26, 0), "body": Vector3(-3, -14, 0), "head": Vector3(-4, 20, 0)})
	var r_rel_r := _m(rsit, {"handc_r": Vector3(0.3, 0.45, 1.0), "elbow_r": Vector3(0.9, 0.2, -0.1), "handc_l": Vector3(-0.3, -0.3, 0.45),
			"torso": Vector3(8, 24, 0), "body": Vector3(6, 12, 0), "head": Vector3(-4, 14, 0)})
	var r_fol_r := _m(rsit, {"handc_r": Vector3(-0.1, 0.0, 0.8), "elbow_r": Vector3(0.7, -0.3, 0.0), "torso": Vector3(10, 18, 0), "body": Vector3(6, 8, 0), "head": Vector3(-6, 8, 0)})
	var r_wind_l := _m(rsit, {"handc_l": Vector3(-0.62, 0.85, -0.5), "elbow_l": Vector3(-1.0, 0.6, -0.9), "handc_r": Vector3(0.3, -0.3, 0.45),
			"torso": Vector3(-4, 26, 0), "body": Vector3(-3, 14, 0), "head": Vector3(-4, -20, 0)})
	var r_rel_l := _m(rsit, {"handc_l": Vector3(-0.3, 0.45, 1.0), "elbow_l": Vector3(-0.9, 0.2, -0.1), "handc_r": Vector3(0.3, -0.3, 0.45),
			"torso": Vector3(8, -24, 0), "body": Vector3(6, -12, 0), "head": Vector3(-4, -14, 0)})
	var r_fol_l := _m(rsit, {"handc_l": Vector3(0.1, 0.0, 0.8), "elbow_l": Vector3(-0.7, -0.3, 0.0), "torso": Vector3(10, -18, 0), "body": Vector3(6, -8, 0), "head": Vector3(-6, -8, 0)})
	var r_stern := _m(rsit, {"handc_r": Vector3(0.45, 0.4, 0.5), "elbow_r": Vector3(0.9, 0.0, -0.4), "head": Vector3(8, 0, 0), "torso": Vector3(6, 0, 0)})

	# --- a player who gets hit on the head by a thrown prop: head snaps back, hands fly to the head, a dizzy wobble, then recovers
	var bonk_a := _m(serve_stand, {"hips": Vector3(0, -0.07, -0.02), "body": Vector3(-6, 0, 0), "torso": Vector3(-8, 0, 0), "head": Vector3(-44, 0, 0),
			"handc_l": Vector3(-0.26, 0.82, 0.2), "handc_r": Vector3(0.26, 0.82, 0.2), "elbow_l": Vector3(-0.9, 0.1, -0.3), "elbow_r": Vector3(0.9, 0.1, -0.3)})
	var bonk_b := _m(bonk_a, {"hips": Vector3(0, -0.1, 0.0), "body": Vector3(8, 0, 4), "torso": Vector3(6, 0, 0), "head": Vector3(10, 6, 14)})
	var bonk_c := _m(bonk_a, {"hips": Vector3(0, -0.09, 0.0), "body": Vector3(6, 0, -4), "torso": Vector3(4, 0, 0), "head": Vector3(6, -6, -12)})

	return {
		"ready": {"loop": true, "keys": [[0.0, ready], [0.55, ready_b, "smooth"], [1.1, ready, "smooth"]]},
		"ref_throw_r": {"keys": [[0.0, rsit], [0.3, r_wind_r, "smooth"], [0.44, r_rel_r, "out"], [0.62, r_fol_r, "smooth"], [1.3, r_fol_r], [1.7, rsit, "smooth"]]},
		"ref_throw_l": {"keys": [[0.0, rsit], [0.3, r_wind_l, "smooth"], [0.44, r_rel_l, "out"], [0.62, r_fol_l, "smooth"], [1.3, r_fol_l], [1.7, rsit, "smooth"]]},
		"ref_stern": {"keys": [[0.0, rsit], [0.25, r_stern, "smooth"], [1.6, r_stern], [2.0, rsit, "smooth"]]},
		"bonk": {"keys": [[0.0, serve_stand], [0.07, bonk_a, "out"], [0.3, bonk_b, "smooth"], [0.58, bonk_c, "smooth"], [0.85, bonk_b, "smooth"], [1.15, serve_stand, "smooth"]]},
		"photo_idle": {"loop": true, "keys": [[0.0, pho_hold], [0.9, pho_hold_b, "smooth"], [1.8, pho_hold, "smooth"]]},
		"photo_shoot": {"keys": [[0.0, pho_hold], [0.16, pho_up, "out"], [0.46, pho_up], [0.52, pho_click], [0.6, pho_up], [0.9, pho_hold, "smooth"]]},
		"photo_crouch": {"loop": true, "keys": [[0.0, pho_crouch], [1.0, _m(pho_crouch, {"head": Vector3(-8, 5, 0)}), "smooth"], [2.0, pho_crouch, "smooth"]]},
		"photo_crouch_shoot": {"keys": [[0.0, pho_crouch], [0.16, pho_crouch_up, "out"], [0.46, pho_crouch_up], [0.52, _m(pho_crouch_up, {"handc_r": Vector3(0.1, 0.48, 0.46)})], [0.6, pho_crouch_up], [0.9, pho_crouch, "smooth"]]},
		"ref_idle": {"loop": true, "keys": [[0.0, rsit], [0.7, rl, "smooth"], [1.5, rsit_b, "smooth"], [2.2, rr, "smooth"], [3.0, rsit, "smooth"], [3.6, rsit_b, "smooth"], [4.2, rsit, "smooth"]]},
		"ref_whistle": {"keys": [[0.0, rsit], [0.16, r_whistle, "smooth"], [0.8, r_whistle], [1.05, rsit, "smooth"]]},
		"ref_point_l": {"keys": [[0.0, rsit], [0.18, r_point_l, "out"], [1.2, r_point_l], [1.55, rsit, "smooth"]]},
		"ref_point_r": {"keys": [[0.0, rsit], [0.18, r_point_r, "out"], [1.2, r_point_r], [1.55, rsit, "smooth"]]},
		"ref_out": {"keys": [[0.0, rsit], [0.16, r_out, "out"], [0.3, _m(r_out, {"handc_l": Vector3(-0.4, 0.6, 0.18), "handc_r": Vector3(0.4, 0.6, 0.18)}), "smooth"],
				[0.45, r_out, "smooth"], [1.1, r_out], [1.4, rsit, "smooth"]]},
		"ref_shake": {"keys": [[0.0, rsit], [0.14, r_no_a, "out"], [0.34, r_no_b, "smooth"], [0.54, r_no_a, "smooth"], [0.74, r_no_b, "smooth"], [0.95, _m(r_no_a, {"head": Vector3(4, -18, -4)}), "smooth"],
				[1.25, rsit, "smooth"]]},
		"ref_sigh": {"keys": [[0.0, rsit], [0.55, r_inhale, "smooth"], [0.95, r_inhale], [1.5, r_slump, "smooth"], [2.4, r_slump], [3.0, rsit, "smooth"]]},
		"ref_cheer": {"keys": [[0.0, rsit], [0.2, r_cheer_a, "out"], [0.4, r_cheer_b, "smooth"], [0.6, r_cheer_a, "smooth"], [0.8, r_cheer_b, "smooth"], [1.0, r_cheer_a, "smooth"],
				[1.2, r_cheer_b, "smooth"], [1.6, rsit, "smooth"]]},
		"ref_wow": {"keys": [[0.0, rsit], [0.12, r_wow, "out"], [1.1, r_wow], [1.5, rsit, "smooth"]]},
		"ref_yawn": {"keys": [[0.0, rsit], [0.5, r_yawn, "smooth"], [1.7, r_yawn_b, "smooth"], [2.2, _m(rsit, {"head": Vector3(8, 0, 0)}), "smooth"], [2.8, rsit, "smooth"]]},
		"ref_wipe": {"keys": [[0.0, rsit], [0.3, r_wipe_a, "smooth"], [0.6, r_wipe_b, "smooth"], [0.9, r_wipe_a, "smooth"], [1.2, r_wipe_b, "smooth"], [1.5, r_slump, "smooth"], [2.4, r_slump], [3.0, rsit, "smooth"]]},
		"ref_nod": {"keys": [[0.0, rsit], [0.15, r_nod_a, "smooth"], [0.35, rsit, "smooth"], [0.55, r_nod_a, "smooth"], [0.75, rsit, "smooth"]]},
		"ref_think": {"keys": [[0.0, rsit], [0.3, r_think, "smooth"], [1.4, _m(r_think, {"head": Vector3(-6, -6, -8)}), "smooth"], [1.8, rsit, "smooth"]]},
		"ref_wave": {"keys": [[0.0, rsit], [0.25, r_wave_a, "out"], [0.5, r_wave_b, "smooth"], [0.75, r_wave_a, "smooth"], [1.0, r_wave_b, "smooth"], [1.25, r_wave_a, "smooth"], [1.7, rsit, "smooth"]]},
		"ref_sleep": {"loop": true, "keys": [[0.0, r_sleep_a], [1.4, r_sleep_b, "smooth"], [2.8, r_sleep_a, "smooth"]]},
		"ref_shrug": {"keys": [[0.0, rsit], [0.2, r_shrug, "out"], [1.1, r_shrug], [1.5, rsit, "smooth"]]},
		"bump": {"keys": [[0.0, ready], [0.12, bump_load], [0.2, bump_hit, "out"], [0.38, bump_follow, "smooth"], [0.7, ready, "smooth"]]},
		"set": {"keys": [[0.0, ready], [0.1, set_load], [0.2, set_hit, "out"], [0.36, set_follow, "smooth"], [0.65, ready, "smooth"]]},
		"air": {"loop": true, "keys": [[0.0, air], [0.4, _m(air, {"hips": Vector3(0, -0.05, 0.0)}), "smooth"], [0.8, air, "smooth"]]},
		"spike": {"keys": [[0.0, air], [0.14, spike_cock], [0.26, spike_hit, "out"], [0.44, spike_follow, "smooth"], [0.8, _m(ready, {"hips": Vector3(0, -0.15, 0.04)}), "smooth"]]},
		"serve_ready": {"loop": true, "keys": [[0.0, serve_stand], [0.6, _m(serve_stand, {"hips": Vector3(0, -0.058, 0.0)}), "smooth"], [1.2, serve_stand, "smooth"]]},
		"serve_toss": {"keys": [[0.0, serve_stand], [0.4, serve_toss_up, "smooth"]]},
		"serve_hit": {"keys": [[0.0, serve_toss_up], [0.18, serve_cock], [0.3, serve_hit, "out"], [0.55, _m(serve_hit, {"torso": Vector3(24, 30, 0)}), "smooth"], [0.9, ready, "smooth"]]},
		"block": {"keys": [[0.0, air], [0.12, block, "out"], [0.6, block]]},
		"dive": {"keys": [[0.0, ready], [0.1, dive_start], [0.26, dive_fly, "out"], [0.5, dive_slide, "smooth"], [1.0, dive_slide]]},
		"getup": {"keys": [[0.0, dive_slide], [0.35, dive_start, "smooth"], [0.7, ready, "smooth"]]},
		"cheer": {"loop": true, "keys": [[0.0, cheer_a], [0.26, cheer_b, "out"], [0.52, cheer_a, "in"], [0.78, cheer_b, "out"], [1.04, cheer_a, "in"]]},
		"sad": {"loop": true, "keys": [[0.0, sad_a], [1.0, sad_b, "smooth"], [2.0, sad_a, "smooth"]]},
		"whiff": {"keys": [[0.0, ready], [0.1, whiff_a], [0.2, whiff_b, "out"], [0.5, ready, "smooth"]]},
		"land": {"keys": [[0.0, land], [0.22, ready, "smooth"]]},
		"stumble": {"keys": [[0.0, ready], [0.07, stumble_a, "out"], [0.2, stumble_b, "smooth"], [0.34, stumble_a, "smooth"], [0.55, ready, "smooth"]]},
		"knockdown": {"keys": [[0.0, ready], [0.08, ko_a, "out"], [0.26, ko_b, "smooth"], [0.42, ko_lie, "in"],
				[0.5, _m(ko_lie, {"hips": Vector3(0, -0.84, -0.6), "body": Vector3(-82, 0, 0)}), "out"], [0.62, ko_lie, "smooth"], [0.95, sit_a, "smooth"]]},
		"dizzy": {"loop": true, "keys": [[0.0, sit_a], [0.6, sit_b, "smooth"], [1.2, sit_a, "smooth"]]},
		"getup_sit": {"keys": [[0.0, sit_a], [0.32, dive_start, "smooth"], [0.65, ready, "smooth"]]},
	}
