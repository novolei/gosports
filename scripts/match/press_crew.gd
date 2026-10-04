class_name PressCrew
extends Node3D
## "摄影记者" court decoration: a row of press photographers on a low riser outside the side hoardings (and a few behind the far
## end), cartoon animals in their own outfits with a camera. They idle with the camera at the chest, shoot at random while a
## replay of a scoring play is running (raise the camera, click, a flash of light) and join in briefly when a point is scored.
## Cheap: one rig each (plain AnimationPlayer), one shared camera mesh, one small additive flash quad each.

const X := 9.7                          # outside the hoarding (outer face at 8.6)
const RISER_H := 0.42
const SHOOT_LEN := 0.9

var director: MatchDirector
var scene: MatchScene
var _rng := RandomNumberGenerator.new()
var _crew: Array = []                   # {rig, flash, mat, crouch, next, busy}
var _flash_tex: Texture2D
var _burst_until := 0.0


func build(p_scene: MatchScene, p_director: MatchDirector, look: Dictionary, exclude: Array) -> void:
	scene = p_scene
	director = p_director
	_rng.randomize()
	_flash_tex = load("res://assets/env/soft_circle.png")
	var pool: Array[Dictionary] = []
	for e in Roster.all():
		if e["kind"] == "cube" and not String(e["model"]).ends_with("/Human.fbx") and not exclude.has(e["id"]):
			pool.append(e)
	pool.shuffle()
	var q := int(Game.settings["quality"])
	var side_n := 6 if q >= 2 else (4 if q == 1 else 3)
	var far_n := 3 if q >= 1 else 2
	var spots: Array[Dictionary] = []                         # {pos, crouch}
	for sx in [-1.0, 1.0]:
		for i in side_n:
			var z := lerpf(-8.2, 7.4, float(i) / float(maxi(side_n - 1, 1))) + _rng.randf_range(-0.35, 0.35)
			spots.append({"pos": Vector3(sx * (X + _rng.randf_range(-0.1, 0.5)), RISER_H, z), "crouch": i % 2 == 1})
	for i in far_n:
		var x := lerpf(-3.8, 3.8, float(i) / float(maxi(far_n - 1, 1))) + _rng.randf_range(-0.3, 0.3)
		spots.append({"pos": Vector3(x, RISER_H, -(CourtDeco.hd() + 1.2)), "crouch": i % 2 == 0})
	_build_risers(look)
	var cam_mesh := _camera_mesh()
	var k := 0
	for sp in spots:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.build(pool[k % pool.size()])
		k += 1
		rig.scale *= 1.0
		var p: Vector3 = sp["pos"]
		rig.position = p
		var to := Vector3(0, 0, -1.0) - p
		rig.rotation.y = atan2(-to.x, -to.z)
		var crouch: bool = sp["crouch"]
		rig.play("photo_crouch" if crouch else "photo_idle", 0.0, _rng.randf_range(0.85, 1.15))
		rig.anim.seek(_rng.randf() * 2.0, true)
		# the camera in the right hand
		var cm := MeshInstance3D.new()
		cm.mesh = cam_mesh
		cm.material_override = CourtDeco.lit_material()
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cm)
		# the flash
		var fm := MeshInstance3D.new()
		var qd := QuadMesh.new()
		qd.size = Vector2(0.75, 0.75)
		fm.mesh = qd
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = _flash_tex
		mat.albedo_color = Color(1, 1, 1, 0.0)
		mat.disable_fog = true
		fm.material_override = mat
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fm.visible = false
		add_child(fm)
		_crew.append({"rig": rig, "cam": cm, "flash": fm, "mat": mat, "crouch": crouch, "next": _rng.randf_range(0.5, 2.5), "busy": 0.0})
	director.point_scored.connect(_on_point)


## low riser strips so the photographers stand above the boards
func _build_risers(look: Dictionary) -> void:
	var m := CourtDeco.Mesher.new()
	var body: Color = look["plinth"]
	var cap: Color = look["cap"]
	var d := CourtDeco.hd() + 2.0
	for sx in [-1.0, 1.0]:
		m.box(Vector3(sx * (X + 0.2), RISER_H * 0.5, 0.0), Vector3(2.0, RISER_H, d * 2.0 - 1.0), body.lightened(0.05))
		m.box(Vector3(sx * (X - 0.8), RISER_H - 0.02, 0.0), Vector3(0.06, 0.05, d * 2.0 - 1.0), cap)
	m.box(Vector3(0, RISER_H * 0.5, -(CourtDeco.hd() + 1.5)), Vector3(CourtDeco.hw() * 2.0 + 1.0, RISER_H, 2.0), body.lightened(0.05))
	m.box(Vector3(0, RISER_H - 0.02, -(CourtDeco.hd() + 0.5)), Vector3(CourtDeco.hw() * 2.0 + 1.0, 0.05, 0.06), cap)
	add_child(m.commit(CourtDeco.lit_material()))


func _camera_mesh() -> Mesh:
	var m := CourtDeco.Mesher.new()
	m.box(Vector3(0, 0.0, -0.1), Vector3(0.34, 0.22, 0.2), Color(0.12, 0.13, 0.16))
	m.box(Vector3(0, 0.1, -0.1), Vector3(0.14, 0.05, 0.1), Color(0.8, 0.8, 0.84))
	m.box(Vector3(0, -0.01, -0.24), Vector3(0.15, 0.15, 0.16), Color(0.2, 0.21, 0.25))
	m.box(Vector3(0, -0.01, -0.33), Vector3(0.1, 0.1, 0.03), Color(0.5, 0.65, 0.9))
	m.st.generate_normals()
	return m.st.commit()


func _process(dt: float) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	var replaying: bool = (scene != null and scene.replay != null and scene.replay.playing) or (Game.main != null and Game.main.dev.has("presstest"))
	var active := replaying or now < _burst_until
	for c in _crew:
		var rig: CharacterRig = c["rig"]
		var cm: MeshInstance3D = c["cam"]            # the camera follows the right hand (the bone attachment space is not metric)
		cm.global_position = rig.hand_world("r")
		cm.global_transform.basis = rig.global_transform.basis.orthonormalized()
		c["busy"] = maxf(float(c["busy"]) - dt, 0.0)
		if float(c["busy"]) <= 0.0 and rig.current.begins_with("photo_") and rig.current.contains("shoot"):
			rig.play("photo_crouch" if c["crouch"] else "photo_idle", 0.2)
		if active and float(c["busy"]) <= 0.0:
			c["next"] = float(c["next"]) - dt
			if float(c["next"]) <= 0.0:
				_shoot(c, 0.45 if replaying else 0.3)
				c["next"] = _rng.randf_range(0.25, 1.1) if replaying else _rng.randf_range(0.5, 1.4)


func _shoot(c: Dictionary, delay: float) -> void:
	var rig: CharacterRig = c["rig"]
	c["busy"] = SHOOT_LEN + 0.05
	rig.play("photo_crouch_shoot" if c["crouch"] else "photo_shoot", 0.1)
	await get_tree().create_timer(delay).timeout       # the camera is up at ~0.2 s, the click at 0.5 s
	if not is_inside_tree() or not is_instance_valid(rig):
		return
	var fm: MeshInstance3D = c["flash"]
	var mat: StandardMaterial3D = c["mat"]
	var fwd := -rig.global_transform.basis.z.normalized()
	fm.global_position = rig.head_world() + fwd * 0.42 + Vector3(0, -0.04, 0)
	fm.visible = true
	fm.scale = Vector3(0.5, 0.5, 0.5)
	var tw := fm.create_tween()
	tw.tween_method(func(a: float): mat.albedo_color = Color(1.0, 0.98, 0.9, a), 1.0, 0.0, 0.2)
	tw.parallel().tween_property(fm, "scale", Vector3(1.5, 1.5, 1.5), 0.2)
	tw.tween_callback(func(): fm.visible = false)
	if _rng.randf() < 0.18:
		Sfx.play("ui_click", -20.0, 2.0, 0.1)


func _on_point(_team: int, _reason: String, _pos: Vector3) -> void:
	_burst_until = float(Time.get_ticks_msec()) / 1000.0 + 1.6
	for c in _crew:
		c["next"] = _rng.randf_range(0.0, 0.9)
