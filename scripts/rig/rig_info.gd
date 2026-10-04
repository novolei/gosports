class_name RigInfo
extends RefCounted
## Rest-pose knowledge about one humanoid skeleton (cartoon animals/humans, ninjas, Mixamo, ...).
## All "root space" values are expressed in the frame of the instantiated model root, so rigs
## of different bone conventions can be compared through a canonical frame:
##   x = character right, y = up, z = forward.

const ROLE_BONES := {
	"cube": {
		"hips": "hips", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head",
		"torso": ["spine", "chest"],
		"shoulder_l": "shoulder.L", "arm_l": "upper_arm.L", "fore_l": "forearm.L", "hand_l": "hand.L", "hand_end_l": "palm.01.L",
		"shoulder_r": "shoulder.R", "arm_r": "upper_arm.R", "fore_r": "forearm.R", "hand_r": "hand.R", "hand_end_r": "palm.01.R",
		"thigh_l": "thigh.L", "shin_l": "shin.L", "foot_l": "foot.L", "toe_l": "toe.L",
		"thigh_r": "thigh.R", "shin_r": "shin.R", "foot_r": "foot.R", "toe_r": "toe.R",
	},
	"cube_anim": {  # the 504-bone Rigify rig inside the Cubebrush animation FBX
		"hips": "ORG-hips", "spine": "ORG-spine", "chest": "ORG-chest", "neck": "ORG-neck", "head": "ORG-head",
		"torso": ["ORG-spine", "ORG-chest"],
		"shoulder_l": "ORG-shoulder.L", "arm_l": "ORG-upper_arm.L", "fore_l": "ORG-forearm.L", "hand_l": "ORG-hand.L", "hand_end_l": "ORG-palm.01.L",
		"shoulder_r": "ORG-shoulder.R", "arm_r": "ORG-upper_arm.R", "fore_r": "ORG-forearm.R", "hand_r": "ORG-hand.R", "hand_end_r": "ORG-palm.01.R",
		"thigh_l": "ORG-thigh.L", "shin_l": "ORG-shin.L", "foot_l": "ORG-foot.L", "toe_l": "ORG-toe.L",
		"thigh_r": "ORG-thigh.R", "shin_r": "ORG-shin.R", "foot_r": "ORG-foot.R", "toe_r": "ORG-toe.R",
	},
	"ninja": {
		"hips": "RigPelvis", "spine": "RigSpine1", "chest": "RigRibcage", "neck": "RigNeck", "head": "RigHead",
		"torso": ["RigSpine1", "RigSpine2", "RigSpine3", "RigRibcage"],
		"shoulder_l": "RigLCollarbone", "arm_l": "RigLUpperarm", "fore_l": "RigLForearm", "hand_l": "RigLPalm", "hand_end_l": "RigLFinger21",
		"shoulder_r": "RigRCollarbone", "arm_r": "RigRUpperarm", "fore_r": "RigRForearm", "hand_r": "RigRPalm", "hand_end_r": "RigRFinger21",
		"thigh_l": "RigLThigh", "shin_l": "RigLCalf", "foot_l": "RigLFoot", "toe_l": "RigLToe11",
		"thigh_r": "RigRThigh", "shin_r": "RigRCalf", "foot_r": "RigRFoot", "toe_r": "RigRToe11",
	},
	"mixamo": {
		"hips": "mixamorig_Hips", "spine": "mixamorig_Spine", "chest": "mixamorig_Spine2", "neck": "mixamorig_Neck", "head": "mixamorig_Head",
		"torso": ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"],
		"shoulder_l": "mixamorig_LeftShoulder", "arm_l": "mixamorig_LeftArm", "fore_l": "mixamorig_LeftForeArm", "hand_l": "mixamorig_LeftHand", "hand_end_l": "mixamorig_LeftHandMiddle1",
		"shoulder_r": "mixamorig_RightShoulder", "arm_r": "mixamorig_RightArm", "fore_r": "mixamorig_RightForeArm", "hand_r": "mixamorig_RightHand", "hand_end_r": "mixamorig_RightHandMiddle1",
		"thigh_l": "mixamorig_LeftUpLeg", "shin_l": "mixamorig_LeftLeg", "foot_l": "mixamorig_LeftFoot", "toe_l": "mixamorig_LeftToeBase",
		"thigh_r": "mixamorig_RightUpLeg", "shin_r": "mixamorig_RightLeg", "foot_r": "mixamorig_RightFoot", "toe_r": "mixamorig_RightToeBase",
	},
}

## cartoon limbs are stubby; arms are scaled up (isotropically on the upper-arm bone, children inherit)
const ARM_SCALE := {"cube": 1.45, "ninja": 1.0, "cube_anim": 1.0, "mixamo": 1.0}

var kind := ""
var skeleton: Skeleton3D
var root: Node3D
var role: Dictionary = {}            # role -> bone index (torso -> PackedInt32Array)
var xf_sk := Transform3D.IDENTITY    # skeleton node -> model root
var unit := 1.0                      # skeleton length unit -> root length unit
var count := 0
var parents := PackedInt32Array()
var order := PackedInt32Array()      # parents always before children
var rest_l: Array[Transform3D] = []  # skeleton-space local rest
var rest_g: Array[Transform3D] = []  # root-space global rest (orthonormal basis)
var right := Vector3.RIGHT
var up := Vector3.UP
var fwd := Vector3.FORWARD
var arm_len := 1.0                   # shoulder joint -> wrist joint
var upper_arm := 1.0
var fore_arm := 1.0
var leg_len := 1.0                   # hip joint -> ankle joint
var thigh := 1.0
var shin := 1.0
var hips_rest := Vector3.ZERO        # root-space rest position of the hips joint
var shoulder_span := 1.0


static func norm_name(s: String) -> String:
	return s.replace(":", "_")


func setup(p_root: Node3D, p_skeleton: Skeleton3D, p_kind: String) -> bool:
	root = p_root
	skeleton = p_skeleton
	kind = p_kind
	count = skeleton.get_bone_count()
	# skeleton node transform relative to the model root
	var xf := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	xf_sk = xf
	unit = xf.basis.get_scale().x
	var map: Dictionary = ROLE_BONES[kind]
	for k in map.keys():
		var v = map[k]
		if v is Array:
			var arr := PackedInt32Array()
			for nm in v:
				var i := skeleton.find_bone(nm)
				if i < 0:
					i = skeleton.find_bone(norm_name(nm))
				if i >= 0:
					arr.append(i)
			role[k] = arr
		else:
			var i := skeleton.find_bone(v)
			if i < 0:
				i = skeleton.find_bone(norm_name(v))
			if i < 0:
				push_warning("RigInfo[%s]: bone for role '%s' (%s) not found" % [kind, k, v])
				return false
			role[k] = i
	parents.resize(count)
	rest_l.resize(count)
	rest_g.resize(count)
	for i in count:
		parents[i] = skeleton.get_bone_parent(i)
		rest_l[i] = skeleton.get_bone_rest(i)
	# topological order
	var done := {}
	var ord: Array[int] = []
	var guard := 0
	while ord.size() < count and guard < count + 4:
		guard += 1
		for i in count:
			if done.has(i):
				continue
			if parents[i] < 0 or done.has(parents[i]):
				done[i] = true
				ord.append(i)
	order = PackedInt32Array(ord)
	var sk_basis := xf_sk.basis.orthonormalized()
	for i in order:
		var p := parents[i]
		var l := rest_l[i]
		var local_xf := Transform3D(l.basis.orthonormalized(), l.origin * unit)
		if p < 0:
			rest_g[i] = Transform3D(sk_basis, xf_sk.origin) * local_xf
		else:
			rest_g[i] = rest_g[p] * local_xf
	_measure_axes()
	return true


func b(r: String) -> int:
	return role[r]


## Apply the per-kind arm enlargement to a live skeleton (call once after instancing the model).
func apply_runtime_scales(sk: Skeleton3D) -> void:
	var asc: float = ARM_SCALE.get(kind, 1.0)
	if is_equal_approx(asc, 1.0):
		return
	for side in ["l", "r"]:
		var i: int = role["arm_" + side]
		sk.set_bone_pose_scale(i, Vector3.ONE * asc)


func pos_of(i: int) -> Vector3:
	return rest_g[i].origin


func _measure_axes() -> void:
	up = Vector3.UP
	var r := rest_g[b("arm_r")].origin - rest_g[b("arm_l")].origin
	r.y = 0.0
	right = r.normalized()
	fwd = up.cross(right).normalized()
	var toe := rest_g[b("toe_l")].origin - rest_g[b("foot_l")].origin
	if toe.dot(fwd) < 0.0:
		# toe points the other way: the right vector was mirrored
		right = -right
		fwd = up.cross(right).normalized()
	var asc: float = ARM_SCALE.get(kind, 1.0)
	upper_arm = (pos_of(b("fore_l")) - pos_of(b("arm_l"))).length() * asc
	fore_arm = (pos_of(b("hand_l")) - pos_of(b("fore_l"))).length() * asc
	arm_len = upper_arm + fore_arm
	thigh = (pos_of(b("shin_l")) - pos_of(b("thigh_l"))).length()
	shin = (pos_of(b("foot_l")) - pos_of(b("shin_l"))).length()
	leg_len = thigh + shin
	hips_rest = pos_of(b("hips"))
	shoulder_span = (pos_of(b("arm_r")) - pos_of(b("arm_l"))).length()


## canonical (x right, y up, z forward) -> root space
func to_root(v: Vector3) -> Vector3:
	return right * v.x + up * v.y + fwd * v.z


## root space -> canonical
func to_canon(v: Vector3) -> Vector3:
	return Vector3(v.dot(right), v.dot(up), v.dot(fwd))


## Forward kinematics. rots: bone index -> Quaternion (local, skeleton space); missing = rest.
## hips_pos: skeleton-space local position of the hips bone (or null for rest).
func fk(rots: Dictionary, hips_pos = null) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(count)
	var sk_basis := xf_sk.basis.orthonormalized()
	var hips_i: int = role["hips"]
	for i in order:
		var l := rest_l[i]
		var q: Quaternion = rots[i] if rots.has(i) else l.basis.get_rotation_quaternion()
		var o := l.origin * unit
		if i == hips_i and hips_pos != null:
			o = (hips_pos as Vector3) * unit
		var local_xf := Transform3D(Basis(q), o)
		var p := parents[i]
		if p < 0:
			g[i] = Transform3D(sk_basis, xf_sk.origin) * local_xf
		else:
			g[i] = g[p] * local_xf
	return g
