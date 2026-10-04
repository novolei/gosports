class_name PoseSolver
extends RefCounted
## Rig-independent pose description ("spec") <-> skeleton rotations.
##
## A spec is a Dictionary of canonical, proportion-normalised values:
##   hips     Vector3  hips joint offset from rest, canonical (x right, y up, z forward), in leg-lengths
##   body     Vector3  hips rotation (pitch_forward, yaw_right, roll_right) in degrees
##   torso    Vector3  extra bend spread along the spine chain (same convention)
##   head     Vector3  head rotation relative to chest (same convention)
##   hand_l/r Vector3  wrist target relative to shoulder joint, in arm-lengths (canonical)
##   elbow_l/r Vector3 elbow pole direction (canonical)
##   hand_roll_l/r float  forearm twist (degrees) applied to the hand
##   foot_l/r Vector3  ankle target relative to the floor point under the rest hips, in leg-lengths
##   knee_l/r Vector3  knee pole direction (canonical)
##   foot_pitch_l/r float toes-up angle in degrees
##   foot_yaw_l/r float toe-out angle in degrees (+ = toes turn to the character's right)
## Missing keys fall back to neutral(). Positions use z = FORWARD; rotations use degrees.

const SPEC_KEYS := ["hips", "body", "torso", "head", "hand_l", "hand_r", "elbow_l", "elbow_r",
		"hand_roll_l", "hand_roll_r", "foot_l", "foot_r", "knee_l", "knee_r",
		"foot_pitch_l", "foot_pitch_r", "foot_yaw_l", "foot_yaw_r"]


## Canonical->root rotation matrix (x right, y up, z BACK) - a proper rotation.
static func canon_basis(info: RigInfo) -> Basis:
	return Basis(info.right, info.up, -info.fwd)


## Euler (pitch_forward, yaw_right, roll_right) degrees -> rotation about root-space axes.
static func rot_canon(info: RigInfo, e: Vector3) -> Basis:
	var c := canon_basis(info)
	var r := Basis.from_euler(Vector3(deg_to_rad(-e.x), deg_to_rad(-e.y), deg_to_rad(-e.z)), EULER_ORDER_YXZ)
	return c * r * c.inverse()


static func euler_from_rot(info: RigInfo, rot: Basis) -> Vector3:
	var c := canon_basis(info)
	var r := c.inverse() * rot * c
	var e := r.orthonormalized().get_euler(EULER_ORDER_YXZ)
	return Vector3(-rad_to_deg(e.x), -rad_to_deg(e.y), -rad_to_deg(e.z))


static func spec_to_root(info: RigInfo, v: Vector3) -> Vector3:
	return info.right * v.x + info.up * v.y + info.fwd * v.z


static func root_to_spec(info: RigInfo, v: Vector3) -> Vector3:
	return Vector3(v.dot(info.right), v.dot(info.up), v.dot(info.fwd))


static func floor_origin(info: RigInfo) -> Vector3:
	return Vector3(info.hips_rest.x, 0.0, info.hips_rest.z)


static func rest_spec(info: RigInfo) -> Dictionary:
	var s := {}
	s["hips"] = Vector3.ZERO
	s["body"] = Vector3.ZERO
	s["torso"] = Vector3.ZERO
	s["head"] = Vector3.ZERO
	for side in ["l", "r"]:
		var arm := info.pos_of(info.b("arm_" + side))
		var hand := info.pos_of(info.b("hand_" + side))
		var fore := info.pos_of(info.b("fore_" + side))
		s["hand_" + side] = root_to_spec(info, (hand - arm) / info.arm_len)
		s["elbow_" + side] = root_to_spec(info, (fore - (arm + hand) * 0.5).normalized()) if (fore - (arm + hand) * 0.5).length() > 0.001 else Vector3(0, -0.2, -1)
		s["hand_roll_" + side] = 0.0
		var foot := info.pos_of(info.b("foot_" + side))
		s["foot_" + side] = root_to_spec(info, (foot - floor_origin(info)) / info.leg_len)
		s["knee_" + side] = Vector3(0, 0, 1)
		s["foot_pitch_" + side] = 0.0
		s["foot_yaw_" + side] = 0.0
	return s


static func neutral(info: RigInfo) -> Dictionary:
	var s := rest_spec(info)
	# arms hanging relaxed instead of T-pose
	s["hand_l"] = Vector3(-0.16, -0.93, 0.12)
	s["hand_r"] = Vector3(0.16, -0.93, 0.12)
	s["elbow_l"] = Vector3(-0.6, -0.1, -0.8)
	s["elbow_r"] = Vector3(0.6, -0.1, -0.8)
	s["foot_l_off"] = Vector3.ZERO
	s["foot_r_off"] = Vector3.ZERO
	return s


static func with_defaults(info: RigInfo, spec: Dictionary) -> Dictionary:
	var base := neutral(info)
	for k in spec.keys():
		base[k] = spec[k]
	# foot offsets relative to the rest ankle position (rig independent way to stagger the stance)
	for side in ["l", "r"]:
		if spec.has("foot_" + side + "_off"):
			base["foot_" + side] = (neutral(info)["foot_" + side] as Vector3) + (spec["foot_" + side + "_off"] as Vector3)
	return base


static func lerp_spec(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var r := {}
	for k in a.keys():
		if b.has(k):
			r[k] = lerp(a[k], b[k], t)
		else:
			r[k] = a[k]
	for k in b.keys():
		if not r.has(k):
			r[k] = b[k]
	return r


## shortest-arc rotation that takes direction `from` to direction `to`
static func arc(from: Vector3, to: Vector3) -> Basis:
	var f := from.normalized()
	var t := to.normalized()
	var d := f.dot(t)
	if d > 0.99999:
		return Basis.IDENTITY
	if d < -0.99999:
		var axis := f.cross(Vector3.UP)
		if axis.length() < 0.01:
			axis = f.cross(Vector3.RIGHT)
		return Basis(axis.normalized(), PI)
	var ax := f.cross(t).normalized()
	return Basis(ax, acos(clampf(d, -1.0, 1.0)))


## Two-bone chain: returns the middle joint (elbow/knee) position.
static func two_bone_mid(s: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var to_t := t - s
	var dist := to_t.length()
	var dir := to_t / maxf(dist, 0.0001)
	var d := clampf(dist, absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := pole - dir * pole.dot(dir)
	if perp.length() < 0.001:
		perp = dir.cross(Vector3.UP)
		if perp.length() < 0.001:
			perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized()
	return s + dir * a + perp * h


## Solve a spec into local rotations. Returns {"rots": {bone: Quaternion}, "hips_pos": Vector3 (skeleton space)}
static func solve(info: RigInfo, spec_in: Dictionary) -> Dictionary:
	var spec := with_defaults(info, spec_in)
	var g: Dictionary = {}  # bone -> Transform3D (root space)
	var touched: Dictionary = {}
	var sk_basis := info.xf_sk.basis.orthonormalized()
	var hips_i: int = info.b("hips")
	var torso: PackedInt32Array = info.role["torso"]
	var neck_i: int = info.b("neck")
	var head_i: int = info.b("head")
	var body_r := rot_canon(info, spec["body"])
	var torso_frac := 1.0 / maxf(torso.size(), 1)
	var torso_r := rot_canon(info, (spec["torso"] as Vector3) * torso_frac)
	var head_e: Vector3 = spec["head"]
	var neck_r := rot_canon(info, head_e * 0.4)
	var head_r := rot_canon(info, head_e * 0.6)
	var hips_pos_root: Vector3 = info.hips_rest + spec_to_root(info, (spec["hips"] as Vector3) * info.leg_len)

	var side_of := {}
	for side in ["l", "r"]:
		for role_name in ["arm", "fore", "hand", "thigh", "shin", "foot"]:
			side_of[info.b(role_name + "_" + side)] = [role_name, side]

	var floor_o := floor_origin(info)
	var arm_ends := {}   # side -> wrist target
	var leg_ends := {}   # side -> ankle target
	var elbow_pos := {}

	# pass 1: torso/head chain without limb IK (gives shoulder joint positions for "handc_*" targets)
	var g0: Dictionary = {}
	for i in info.order:
		var p0 := info.parents[i]
		var l0 := info.rest_l[i]
		var lx0 := Transform3D(l0.basis.orthonormalized(), l0.origin * info.unit)
		var gd0: Transform3D
		if i == hips_i:
			gd0 = Transform3D(body_r * info.rest_g[i].basis, hips_pos_root)
		elif p0 < 0:
			gd0 = Transform3D(sk_basis, info.xf_sk.origin) * lx0
		else:
			gd0 = g0[p0] * lx0
		if i in torso:
			gd0.basis = torso_r * gd0.basis
		elif i == neck_i:
			gd0.basis = neck_r * gd0.basis
		elif i == head_i:
			gd0.basis = head_r * gd0.basis
		g0[i] = gd0
	var chest_center: Vector3 = ((g0[info.b("arm_l")] as Transform3D).origin + (g0[info.b("arm_r")] as Transform3D).origin) * 0.5

	for i in info.order:
		var p := info.parents[i]
		var l := info.rest_l[i]
		var local_xf := Transform3D(l.basis.orthonormalized(), l.origin * info.unit)
		var gdef: Transform3D
		if i == hips_i:
			gdef = Transform3D(body_r * info.rest_g[i].basis, hips_pos_root)
		elif p < 0:
			gdef = Transform3D(sk_basis, info.xf_sk.origin) * local_xf
		else:
			gdef = g[p] * local_xf
		var cur := gdef
		if i in torso:
			cur.basis = torso_r * gdef.basis
			touched[i] = true
		elif i == neck_i:
			cur.basis = neck_r * gdef.basis
			touched[i] = true
		elif i == head_i:
			cur.basis = head_r * gdef.basis
			touched[i] = true
		elif i == hips_i:
			touched[i] = true
		elif side_of.has(i):
			var rs: Array = side_of[i]
			var rn: String = rs[0]
			var side: String = rs[1]
			touched[i] = true
			match rn:
				"arm":
					var s_pos := gdef.origin
					var t_pos := s_pos + spec_to_root(info, (spec["hand_" + side] as Vector3) * info.arm_len)
					if spec.has("handc_" + side):
						t_pos = chest_center + spec_to_root(info, (spec["handc_" + side] as Vector3) * info.arm_len)
					var pole := spec_to_root(info, spec["elbow_" + side])
					var e_pos := two_bone_mid(s_pos, t_pos, info.upper_arm, info.fore_arm, pole)
					arm_ends[side] = t_pos
					var child_dir_local := info.rest_l[info.b("fore_" + side)].origin.normalized()
					var cur_dir := gdef.basis * child_dir_local
					cur.basis = arc(cur_dir, e_pos - s_pos) * gdef.basis
					elbow_pos[side] = e_pos
				"fore":
					var t_pos2: Vector3 = arm_ends[side]
					var child_dir_local2 := info.rest_l[info.b("hand_" + side)].origin.normalized()
					var cur_dir2 := gdef.basis * child_dir_local2
					cur.basis = arc(cur_dir2, t_pos2 - gdef.origin) * gdef.basis
				"hand":
					var roll: float = spec["hand_roll_" + side]
					if absf(roll) > 0.01:
						var fa: Vector3 = (g[info.b("fore_" + side)].basis * info.rest_l[info.b("hand_" + side)].origin.normalized())
						cur.basis = Basis(fa.normalized(), deg_to_rad(roll)) * gdef.basis
				"thigh":
					var s_pos2 := gdef.origin
					var t_pos3 := floor_o + spec_to_root(info, (spec["foot_" + side] as Vector3) * info.leg_len)
					var pole2 := spec_to_root(info, spec["knee_" + side])
					var k_pos := two_bone_mid(s_pos2, t_pos3, info.thigh, info.shin, pole2)
					leg_ends[side] = t_pos3
					var cd := info.rest_l[info.b("shin_" + side)].origin.normalized()
					cur.basis = arc(gdef.basis * cd, k_pos - s_pos2) * gdef.basis
				"shin":
					var t_pos4: Vector3 = leg_ends[side]
					var cd2 := info.rest_l[info.b("foot_" + side)].origin.normalized()
					cur.basis = arc(gdef.basis * cd2, t_pos4 - gdef.origin) * gdef.basis
				"foot":
					# keep the foot flat on the floor (global rest orientation) + yaw/pitch of the body
					var yaw: float = (spec["body"] as Vector3).y + (spec["torso"] as Vector3).y * 0.0 + (spec["foot_yaw_" + side] as float)
					var fr := rot_canon(info, Vector3(-(spec["foot_pitch_" + side] as float), yaw, 0.0))
					cur.basis = fr * info.rest_g[i].basis
		g[i] = cur

	var rots := {}
	for i in touched.keys():
		var pb: Basis = sk_basis if info.parents[i] < 0 else (g[info.parents[i]] as Transform3D).basis
		rots[i] = (pb.inverse() * (g[i] as Transform3D).basis).orthonormalized().get_rotation_quaternion()
	# hips local position (skeleton space)
	var hp: Vector3
	var hpar := info.parents[hips_i]
	if hpar < 0:
		hp = info.xf_sk.affine_inverse() * hips_pos_root
	else:
		hp = ((g[hpar] as Transform3D).affine_inverse() * hips_pos_root) / info.unit
	return {"rots": rots, "hips_pos": hp}


## Measure a spec from root-space global bone transforms (e.g. a sampled source animation frame).
static func measure(info: RigInfo, g: Array[Transform3D]) -> Dictionary:
	var s := {}
	var hips_i: int = info.b("hips")
	s["hips"] = root_to_spec(info, (g[hips_i].origin - info.hips_rest) / info.leg_len)
	var rel := g[hips_i].basis.orthonormalized() * info.rest_g[hips_i].basis.inverse()
	s["body"] = euler_from_rot(info, rel)
	# torso: chest orientation relative to hips-propagated rest
	var chest_i: int = info.b("chest")
	var chest_def := rel * info.rest_g[chest_i].basis
	var chest_rel := g[chest_i].basis.orthonormalized() * chest_def.inverse()
	s["torso"] = euler_from_rot(info, chest_rel)
	var head_i: int = info.b("head")
	var head_def := g[chest_i].basis.orthonormalized() * (info.rest_g[chest_i].basis.inverse() * info.rest_g[head_i].basis)
	var head_rel := g[head_i].basis.orthonormalized() * head_def.inverse()
	s["head"] = euler_from_rot(info, head_rel)
	var fo := floor_origin(info)
	for side in ["l", "r"]:
		var sh: Vector3 = g[info.b("arm_" + side)].origin
		var el: Vector3 = g[info.b("fore_" + side)].origin
		var wr: Vector3 = g[info.b("hand_" + side)].origin
		s["hand_" + side] = root_to_spec(info, (wr - sh) / info.arm_len)
		var mid := (sh + wr) * 0.5
		var pole := el - mid
		s["elbow_" + side] = root_to_spec(info, pole.normalized()) if pole.length() > info.arm_len * 0.02 else Vector3(0.3 if side == "r" else -0.3, -0.2, -1.0)
		s["hand_roll_" + side] = 0.0
		var hp: Vector3 = g[info.b("thigh_" + side)].origin
		var kn: Vector3 = g[info.b("shin_" + side)].origin
		var an: Vector3 = g[info.b("foot_" + side)].origin
		s["foot_" + side] = root_to_spec(info, (an - fo) / info.leg_len)
		var kmid := (hp + an) * 0.5
		var kp := kn - kmid
		s["knee_" + side] = root_to_spec(info, kp.normalized()) if kp.length() > info.leg_len * 0.02 else Vector3(0, 0, 1)
		# foot pitch / yaw from the foot->toe vector
		var toe: Vector3 = g[info.b("toe_" + side)].origin
		var fv := toe - an
		var fv_c := root_to_spec(info, fv)
		var horiz := Vector2(fv_c.x, fv_c.z).length()
		var rest_fv := root_to_spec(info, info.pos_of(info.b("toe_" + side)) - info.pos_of(info.b("foot_" + side)))
		var rest_h := Vector2(rest_fv.x, rest_fv.z).length()
		var pitch_now := rad_to_deg(atan2(fv_c.y, horiz))
		var pitch_rest := rad_to_deg(atan2(rest_fv.y, rest_h))
		s["foot_pitch_" + side] = pitch_now - pitch_rest
		var yaw_now := rad_to_deg(atan2(fv_c.x, fv_c.z))
		var yaw_rest := rad_to_deg(atan2(rest_fv.x, rest_fv.z))
		# the foot->toe yaw is ill-defined while the toes point (nearly) straight down / up: wrap it, limit it and
		# fade it out with the horizontal length of the vector, otherwise it flips by ~160 degrees from one frame to the next
		var yaw_d := wrapf(yaw_now - yaw_rest - (s["body"] as Vector3).y, -180.0, 180.0)
		var conf := clampf(horiz / maxf(rest_h * 0.6, 0.0001), 0.0, 1.0)
		s["foot_yaw_" + side] = clampf(yaw_d, -50.0, 50.0) * conf
	return s
