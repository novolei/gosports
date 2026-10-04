class_name CharacterRig
extends Node3D
## Visual character: skinned model + materials + baked animation library.
## The rig node faces -Z (the Godot forward) and is scaled to ~1.7 m tall.

signal clip_finished(clip: String)

static var _lib_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

## blend-space smoothing: half-life of the blend position / lean (seconds)
const LOCO_HALFLIFE := 0.055
const LEAN_HALFLIFE := 0.09
const MAX_LEAN := 0.2                # radians (~11 degrees)

var entry: Dictionary = {}
var kind := "cube"
var hero := false                    # athletes / stage / replay ghosts: shader material with ground occlusion + outline
var info: RigInfo
var skeleton: Skeleton3D
var model: Node3D
var lean_pivot: Node3D
var anim: AnimationPlayer
var hand_l: BoneAttachment3D
var hand_r: BoneAttachment3D
var head_att: BoneAttachment3D
var current := ""
var clip_speed := 1.0

# AnimationTree locomotion layer (athletes only; menus / crowd keep the plain AnimationPlayer)
var tree: AnimationTree
var tree_on := false
var _mix: AnimationNodeTransition
var _act_nodes: Array[AnimationNodeAnimation] = []
var _act_slot := 0
var _mix_state := "loco"
var _loco_pos := Vector2.ZERO        # smoothed blend position: x = right, y = forward (fractions of LOCO_SPEED)
var _lean := Vector2.ZERO            # current lean (radians), x = toward right, y = toward forward
var _lean_target := Vector2.ZERO


func build(p_entry: Dictionary, use_tree := false) -> CharacterRig:
	entry = p_entry
	kind = entry["kind"]
	var scn: PackedScene = load(entry["model"])
	model = scn.instantiate()
	model.rotation.y = PI    # models face +Z; the rig faces -Z
	lean_pivot = Node3D.new()
	lean_pivot.name = "Lean"
	add_child(lean_pivot)
	lean_pivot.add_child(model)
	scale = Vector3.ONE * float(entry["scale"])
	skeleton = _find_skeleton(model)
	info = RigInfo.new()
	info.setup(model, skeleton, kind)
	info.apply_runtime_scales(skeleton)
	_apply_materials()
	if kind == "ninja":
		_build_ninja_parts()
	# animation
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	anim.root_node = anim.get_path_to(model)
	anim.add_animation_library("", _get_lib(kind))
	anim.playback_default_blend_time = 0.12
	anim.animation_finished.connect(func(n: StringName): clip_finished.emit(String(n)))
	# attachments
	hand_l = _attach("hand_l")
	hand_r = _attach("hand_r")
	head_att = _attach("head")
	if use_tree:
		_build_tree()
	play("ready", 0.0)
	return self


static func _get_lib(k: String) -> AnimationLibrary:
	if not _lib_cache.has(k):
		_lib_cache[k] = load("res://assets/anim/%s_lib.res" % k)
	return _lib_cache[k]


func _attach(role: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.bone_name = skeleton.get_bone_name(info.b(role))
	skeleton.add_child(att)
	return att


# ---------------------------------------------------------------- AnimationTree locomotion
## Blend-space points: [clip, x (right), y (forward)] in fractions of ClipDefs.LOCO_SPEED.
static func _loco_points() -> Array:
	var pts: Array = [["ready", 0.0, 0.0]]
	for lv in ClipDefs.LOCO_LEVELS:
		var tag := str(int(round(lv * 100.0)))
		pts.append(["loco_f_" + tag, 0.0, lv])
		pts.append(["loco_b_" + tag, 0.0, -lv])
		pts.append(["loco_l_" + tag, -lv, 0.0])
		pts.append(["loco_r_" + tag, lv, 0.0])
	# forward diagonals (the clips travel ~27 degrees off the forward axis)
	pts.append(["loco_fl_70", -0.35, 0.7])
	pts.append(["loco_fr_70", 0.35, 0.7])
	pts.append(["loco_fl_100", -0.5, 1.0])
	pts.append(["loco_fr_100", 0.5, 1.0])
	return pts


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-1.5, -1.5)
	bs.max_space = Vector2(1.5, 1.5)
	bs.auto_triangles = true
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	bs.sync = true
	for p in _loco_points():
		var a := AnimationNodeAnimation.new()
		a.animation = StringName(p[0])
		bs.add_blend_point(a, Vector2(p[1], p[2]), -1, StringName(p[0]))
	bt.add_node("Loco", bs, Vector2(0, 0))
	bt.add_node("LocoTS", AnimationNodeTimeScale.new(), Vector2(200, 0))
	_act_nodes.clear()
	for n in ["ActA", "ActB"]:
		var an := AnimationNodeAnimation.new()
		an.animation = &"ready"
		bt.add_node(n, an, Vector2(0, 200))
		_act_nodes.append(an)
	_mix = AnimationNodeTransition.new()
	_mix.input_count = 3
	_mix.set_input_name(0, "loco")
	_mix.set_input_name(1, "a")
	_mix.set_input_name(2, "b")
	_mix.set_input_reset(0, false)       # the gait phase continues across action interruptions
	_mix.xfade_time = 0.12
	bt.add_node("Mix", _mix, Vector2(400, 0))
	bt.connect_node("LocoTS", 0, "Loco")
	bt.connect_node("Mix", 0, "LocoTS")
	bt.connect_node("Mix", 1, "ActA")
	bt.connect_node("Mix", 2, "ActB")
	bt.connect_node("output", 0, "Mix")
	tree = AnimationTree.new()
	tree.name = "Tree"
	add_child(tree)
	tree.tree_root = bt
	tree.anim_player = tree.get_path_to(anim)
	tree.root_node = tree.get_path_to(model)
	anim.stop()
	anim.active = false
	tree.active = true
	tree_on = true
	_mix_state = "loco"
	tree.set("parameters/Mix/transition_request", "loco")
	tree.advance(0.0)


## Locomotion input: velocity in the character's own frame (x = right, y = forward), m/s.
func set_locomotion(local_vel: Vector2, dt: float) -> void:
	if not tree_on:
		return
	var target := local_vel / ClipDefs.LOCO_SPEED
	var k := 1.0 - exp(-dt * 0.693147 / LOCO_HALFLIFE)
	_loco_pos = _loco_pos.lerp(target, k)
	tree.set("parameters/Loco/blend_position", _loco_pos)
	tree.set("parameters/LocoTS/scale", gait_rate(_loco_pos.length()))


## Cycle rate for a speed fraction r (1.0 = LOCO_SPEED). The characters are chibi (0.43 m legs) yet cover the court
## at 5+ m/s, so the cadence rises with speed (up to ~3.8 steps/s) to keep the feet from skating; idle plays at 1.0.
static func gait_rate(r: float) -> float:
	var up := smoothstep(0.08, 0.6, r)
	return 1.0 + 0.5 * up + 0.35 * clampf((r - 1.0) / 0.3, 0.0, 1.0)


## Lean the whole body (about the feet) toward `dir_local` (x right, y forward) by `amount` (0..1).
func set_lean_target(dir_local: Vector2) -> void:
	_lean_target = dir_local.limit_length(2.2) * MAX_LEAN


func update_lean(dt: float) -> void:
	var k := 1.0 - exp(-dt * 0.693147 / LEAN_HALFLIFE)
	_lean = _lean.lerp(_lean_target, k)
	if _lean.length_squared() < 1e-7:
		lean_pivot.basis = Basis.IDENTITY
		return
	# rig faces -Z: "forward" is -Z, "right" is +X
	var d := Vector3(_lean.x, 0.0, -_lean.y)
	var ang := d.length()
	lean_pivot.basis = Basis(Vector3.UP.cross(d).normalized(), ang)


func is_loco() -> bool:
	return not tree_on or _mix_state == "loco"


func play_loco(blend := 0.12) -> void:
	if not tree_on:
		play("ready", blend)
		return
	if _mix_state == "loco":
		return
	_mix_state = "loco"
	current = "loco"
	_mix.xfade_time = blend
	tree.set("parameters/Mix/transition_request", "loco")


func play_action(clip: String, blend := 0.12) -> void:
	if not anim.has_animation(clip):
		return
	_act_slot = 1 - _act_slot
	var node: AnimationNodeAnimation = _act_nodes[_act_slot]
	node.animation = StringName(clip)
	current = clip
	_mix_state = "a" if _act_slot == 0 else "b"
	_mix.xfade_time = blend
	tree.set("parameters/Mix/transition_request", _mix_state)


func play(clip: String, blend := 0.12, speed := 1.0, from := 0.0) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if tree_on:
		if clip == "ready":
			play_loco(blend)
		elif from > 0.0 and anim.has_animation(clip + "_h"):
			play_action(clip + "_h", blend)    # same clip, baked to start at the lead-in frame
		else:
			play_action(clip, blend)
		return
	current = clip
	clip_speed = speed
	anim.speed_scale = 1.0
	anim.play(clip, blend, speed)
	if from > 0.0:
		anim.seek(from, true)


## play `clip` unless it is already the current one (and still running)
func play_if(clip: String, blend := 0.12) -> void:
	if tree_on:
		if clip == "ready":
			play_loco(blend)
		elif current != clip:
			play(clip, blend)
		return
	if current != clip or not anim.is_playing():
		play(clip, blend)


func is_clip_playing(clip: String) -> bool:
	if tree_on:
		return current == clip
	return anim.is_playing() and anim.current_animation == clip


func clip_pos() -> float:
	return anim.current_animation_position


func set_visible_rig(v: bool) -> void:
	visible = v


# ---------------------------------------------------------------- queries
func hand_world(side: String) -> Vector3:
	var att: BoneAttachment3D = hand_l if side == "l" else hand_r
	return att.global_position


func head_world() -> Vector3:
	return head_att.global_position


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


# ---------------------------------------------------------------- materials
static var _hero_shader: Shader
static var _outline_mat: ShaderMaterial


## hero characters need quality >= 1 (the outline is a second pass over every mesh)
static func hero_enabled() -> bool:
	var style := _dev_style() if _dev_style() >= 0 else int(Game.settings.get("char_style", 0))
	return style == 1 and int(Game.settings.get("quality", 1)) >= 1 and not Game.dbg("nohero") and not (Game.main != null and Game.main.dev.has("nohero"))


## dev: --charstyle=1 forces the outlined look for a run without touching the saved setting
static func _dev_style() -> int:
	return int(Game.main.dev["charstyle"]) if (Game.main != null and Game.main.dev.has("charstyle")) else -1


static func _hero_material(tex: Texture2D, pixel: bool, tint: Color, alpha_cut: bool) -> ShaderMaterial:
	if _hero_shader == null:
		_hero_shader = load("res://shaders/character.gdshader")
		var om := ShaderMaterial.new()
		om.shader = load("res://shaders/character_outline.gdshader")
		_outline_mat = om
	var key := "H|%s|%s|%s|%s" % [tex.resource_path if tex else "", pixel, tint.to_html(), alpha_cut]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _hero_shader
	m.set_shader_parameter("tex_n", tex)
	m.set_shader_parameter("tex_l", tex)
	m.set_shader_parameter("pixel", pixel)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("alpha_cut", alpha_cut)
	if not alpha_cut:                                  # (the ninja face decal is a cut-out: it gets no second pass)
		m.next_pass = _outline_mat
	_mat_cache[key] = m
	return m


static func make_material(tex: Texture2D, pixel := false, tint := Color.WHITE, alpha_cut := false, hero_look := false) -> Material:
	if hero_look and hero_enabled():
		return _hero_material(tex, pixel, tint, alpha_cut)
	var key := "%s|%s|%s|%s" % [tex.resource_path if tex else "", pixel, tint.to_html(), alpha_cut]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if pixel else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.62
	m.metallic = 0.0
	m.metallic_specular = 0.35
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	# soft rim light instead of cel shading (Switch Sports style); no emission (it washes the colours out)
	m.rim_enabled = true
	m.rim = 0.28
	m.rim_tint = 0.6
	if alpha_cut:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
	_mat_cache[key] = m
	return m


func _apply_materials() -> void:
	var meshes: Array = []
	_meshes(model, meshes)
	var tex: Texture2D = load(entry["tex"])
	var pixel: bool = kind == "cube"
	var main_mat := make_material(tex, pixel, Color.WHITE, false, hero)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			m.set_surface_override_material(s, main_mat)
		# human hair is the second surface of the human models
		if kind == "cube" and entry.get("hair", "") != "" and m.mesh.get_surface_count() > 1:
			m.set_surface_override_material(1, make_material(load(entry["hair"]), true, Color.WHITE, false, hero))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_ninja_parts() -> void:
	var head_bone := info.b("head")
	var rest := info.rest_g[head_bone]
	var mats := {
		"skin": make_material(load(entry["skin"]), false, Color.WHITE, false, hero),
		"face": make_material(load(entry["face"]), false, Color.WHITE, true, hero),
		"gear": make_material(load(entry["gear_tex"]), false, Color.WHITE, false, hero) if entry.get("gear_tex", "") != "" else null,
		"hair": make_material(load(entry["hair_tex"]), false, entry["hair_tint"], false, hero) if entry.get("hair", "") != "" else null,
	}
	var parts := [
		[entry["head"], mats["skin"]],
		["res://assets/characters/ninja/fbx/Face.fbx", mats["face"]],
	]
	if entry.get("hair", "") != "":
		parts.append([entry["hair"], mats["hair"]])
	if entry.get("gear", "") != "":
		parts.append([entry["gear"], mats["gear"]])
	var att := BoneAttachment3D.new()
	att.bone_name = skeleton.get_bone_name(head_bone)
	skeleton.add_child(att)
	for p in parts:
		var scn: PackedScene = load(p[0])
		var node: Node3D = scn.instantiate()
		att.add_child(node)
		node.transform = rest.affine_inverse()
		var ms: Array = []
		_meshes(node, ms)
		for mi in ms:
			var m := mi as MeshInstance3D
			# the part FBXs carry a stray -90deg pre-rotation; their vertices are already in model space
			m.transform = Transform3D.IDENTITY
			for s in m.mesh.get_surface_count():
				m.set_surface_override_material(s, p[1])
