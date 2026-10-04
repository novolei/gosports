class_name Arena
extends Node3D
## The sunny stadium: glossy court, net, Stadium-Kit stands / lights / trees, greenery, skyline, sky + light.

const KIT := "res://assets/stadium/models/"
const KIT_TEX := "res://assets/stadium/tex/"
const ENV := "res://assets/env/"

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var quality := 2
var net_node: Node3D
var _mat_cache := {}
var theme_id := "day"

## sky / light / fog presets for the unlockable court themes
const THEMES := {
	"day": {"sky_top": Color(0.22, 0.52, 0.92), "sky_hor": Color(0.74, 0.9, 1.0), "gnd_hor": Color(0.72, 0.84, 0.88), "gnd_bot": Color(0.55, 0.68, 0.72),
			"amb": 1.05, "amb_col": Color(0.82, 0.88, 0.98), "fog": Color(0.78, 0.9, 1.0), "sat": 1.18, "sun_col": Color(1.0, 0.94, 0.84), "sun_e": 1.25,
			"sun_rot": Vector3(-52, 28, 0), "backdrop": Color(1, 1, 1), "extra_light": false},
	"sunset": {"sky_top": Color(0.3, 0.33, 0.68), "sky_hor": Color(1.0, 0.64, 0.42), "gnd_hor": Color(0.92, 0.62, 0.5), "gnd_bot": Color(0.6, 0.45, 0.5),
			"amb": 0.95, "amb_col": Color(1.0, 0.84, 0.78), "fog": Color(1.0, 0.72, 0.55), "sat": 1.3, "sun_col": Color(1.0, 0.7, 0.42), "sun_e": 1.3,
			"sun_rot": Vector3(-26, 38, 0), "backdrop": Color(1.0, 0.78, 0.66), "extra_light": false},
	"night": {"sky_top": Color(0.02, 0.04, 0.15), "sky_hor": Color(0.1, 0.14, 0.34), "gnd_hor": Color(0.07, 0.1, 0.22), "gnd_bot": Color(0.04, 0.06, 0.14),
			"amb": 0.55, "amb_col": Color(0.3, 0.36, 0.62), "fog": Color(0.1, 0.15, 0.32), "sat": 1.2, "sun_col": Color(0.6, 0.7, 1.0), "sun_e": 0.55,
			"sun_rot": Vector3(-60, 20, 0), "backdrop": Color(0.3, 0.36, 0.62), "extra_light": true},
	"dawn": {"sky_top": Color(0.45, 0.55, 0.88), "sky_hor": Color(1.0, 0.84, 0.92), "gnd_hor": Color(0.86, 0.8, 0.92), "gnd_bot": Color(0.62, 0.62, 0.78),
			"amb": 1.0, "amb_col": Color(0.92, 0.88, 1.0), "fog": Color(0.95, 0.85, 0.95), "sat": 1.12, "sun_col": Color(1.0, 0.88, 0.92), "sun_e": 1.05,
			"sun_rot": Vector3(-30, 14, 0), "backdrop": Color(0.96, 0.88, 0.97), "extra_light": false},
}

## the venue's own look on top of the sky preset: court palette (shader colours), run-off rim and advertising boards
const LOOKS := {
	"day": {"court": {}, "rim": Color(0.16, 0.42, 0.40), "plinth": Color(0.15, 0.2, 0.29), "cap": Color(0.2, 0.8, 0.72), "bright": 1.0, "tint": Color(1, 1, 1)},
	"sunset": {"court": {"col_net": Vector3(1.0, 0.7, 0.4), "col_base": Vector3(0.96, 0.5, 0.42), "col_attack": Vector3(1.0, 0.7, 0.36),
				"col_free": Vector3(0.46, 0.4, 0.64), "col_free_dark": Vector3(0.37, 0.31, 0.55)},
			"rim": Color(0.3, 0.22, 0.48), "plinth": Color(0.24, 0.15, 0.3), "cap": Color(1.0, 0.62, 0.3), "bright": 0.97, "tint": Color(1.0, 0.93, 0.88)},
	"night": {"court": {"col_net": Vector3(0.45, 0.66, 0.95), "col_base": Vector3(0.3, 0.46, 0.88), "col_attack": Vector3(0.42, 0.62, 0.95),
				"col_free": Vector3(0.12, 0.24, 0.42), "col_free_dark": Vector3(0.08, 0.17, 0.33)},
			"rim": Color(0.08, 0.16, 0.3), "plinth": Color(0.06, 0.08, 0.16), "cap": Color(0.3, 0.9, 1.0), "bright": 1.25, "tint": Color(1, 1, 1)},
	"dawn": {"court": {"col_net": Vector3(1.0, 0.82, 0.88), "col_base": Vector3(0.74, 0.62, 0.92), "col_attack": Vector3(1.0, 0.8, 0.86),
				"col_free": Vector3(0.52, 0.8, 0.78), "col_free_dark": Vector3(0.42, 0.7, 0.7)},
			"rim": Color(0.3, 0.52, 0.55), "plinth": Color(0.28, 0.26, 0.4), "cap": Color(1.0, 0.7, 0.85), "bright": 1.0, "tint": Color(1.0, 0.96, 1.0)},
}


func build(p_quality := 2) -> void:
	quality = p_quality
	theme_id = String(Game.profile.equipped_item("court")["id"]) if (Game.profile != null and Game.profile_enabled) else "day"
	if Game.main != null and Game.main.dev.has("court"):
		theme_id = String(Game.main.dev["court"])
	_build_environment()
	_build_ground()
	_build_net()
	if not Game.dbg("nostands"):
		_build_stands()
	if not Game.dbg("noboards"):
		_build_boards()
	if not Game.dbg("nobackdrop"):
		_build_backdrop()


# ------------------------------------------------------------------ environment
func _build_environment() -> void:
	var T: Dictionary = THEMES.get(theme_id, THEMES["day"])
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = T["sky_top"]
	sky_mat.sky_horizon_color = T["sky_hor"]
	sky_mat.ground_horizon_color = T["gnd_hor"]
	sky_mat.ground_bottom_color = T["gnd_bot"]
	sky_mat.sky_curve = 0.18
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = T["amb"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = quality >= (2 if OS.has_feature("mobile") else 1)    # glow is a full-screen pass: too heavy for mid-range phones
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = T["sat"]
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 1.0
	env.fog_enabled = true
	env.fog_light_color = T["fog"]
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.25
	if OS.has_feature("mobile") or Game.dbg("ambient"):
		# phones: flat sky-coloured ambient light and no sky reflections (the sky radiance lookup is a per-pixel cost)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = T["amb_col"]
		env.ambient_light_energy = minf(float(T["amb"]), 0.95)
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if Game.dbg("nosky"):
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.55, 0.76, 0.96)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.82, 0.88, 0.98)
		env.ambient_light_energy = 0.95
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if Game.dbg("nofog"):
		env.fog_enabled = false
	if Game.dbg("noadjust"):
		env.adjustment_enabled = false
	if Game.dbg("notonemap"):
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = T["sun_rot"]
	sun.light_color = T["sun_col"]
	sun.light_energy = T["sun_e"]
	sun.shadow_enabled = quality >= 1 and not Game.dbg("noshadow")
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if (OS.has_feature("mobile") and quality < 2) else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.light_angular_distance = 1.2
	add_child(sun)
	if T["extra_light"]:
		# night: warm stadium floodlight (no shadows, so it costs little) keeps the court bright and readable
		var flood := DirectionalLight3D.new()
		flood.rotation_degrees = Vector3(-78, -18, 0)
		flood.light_color = Color(1.0, 0.92, 0.78)
		flood.light_energy = 0.95
		flood.shadow_enabled = false
		add_child(flood)


# ------------------------------------------------------------------ ground / court
func _build_ground() -> void:
	# wooden deck around everything
	var deck := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	deck.mesh = pm
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = _tex(ENV + "wood_deck.png")
	dm.uv1_scale = Vector3(30, 30, 1)
	dm.roughness = 0.5
	dm.metallic_specular = 0.45
	dm.albedo_color = Color(1.0, 0.95, 0.9)
	deck.material_override = dm
	deck.position.y = -0.03
	add_child(deck)

	# court + free zone (analytic shader)
	var court := MeshInstance3D.new()
	var cm := PlaneMesh.new()
	var fw := (Court.HALF_W + Court.FREE_ZONE) * 2.0
	var fd := (Court.HALF_D + Court.FREE_ZONE) * 2.0
	cm.size = Vector2(fw, fd)
	court.mesh = cm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/court_lite.gdshader" if (OS.has_feature("mobile") or Game.dbg("courtlite")) else "res://shaders/court.gdshader")
	sm.set_shader_parameter("half_size", Vector2(Court.HALF_W, Court.HALF_D))
	sm.set_shader_parameter("attack", Court.ATTACK_LINE)
	court.material_override = sm
	var look: Dictionary = LOOKS.get(theme_id, LOOKS["day"])
	for k in (look["court"] as Dictionary).keys():
		sm.set_shader_parameter(k, look["court"][k])
	if Game.dbg("nocourt"):
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.93, 0.62, 0.55)
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		court.material_override = flat
	court.position.y = 0.0
	court.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(court)

	# raised rim so the free zone reads as a platform
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = look["rim"]
	rim_mat.roughness = 0.55
	for s in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.05, fd + 0.18)
		b.mesh = bm
		b.material_override = rim_mat
		b.position = Vector3(s * (fw * 0.5 + 0.0), -0.005, 0)
		add_child(b)
		var b2 := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(fw + 0.18, 0.05, 0.18)
		b2.mesh = bm2
		b2.material_override = rim_mat
		b2.position = Vector3(0, -0.005, s * (fd * 0.5))
		add_child(b2)

	# floor lettering
	var txt := _tex(ENV + "volleyball_text.png")
	for s in [-1.0, 1.0]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(5.2, 0.98)
		q.mesh = qm
		var tm := StandardMaterial3D.new()
		tm.albedo_texture = txt
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.albedo_color = Color(1, 1, 1, 0.75)
		q.material_override = tm
		q.rotation_degrees = Vector3(-90, 0, 90 * s)
		q.position = Vector3(s * (Court.HALF_W + 2.0), 0.004, 5.0 * s)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)


# ------------------------------------------------------------------ net
func _build_net() -> void:
	net_node = Node3D.new()
	net_node.name = "Net"
	add_child(net_node)
	var width := Court.NET_X * 2.0
	var nh := 1.0
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width, nh)
	q.mesh = qm
	var nm := ShaderMaterial.new()
	nm.shader = load("res://shaders/net.gdshader")
	nm.set_shader_parameter("size", Vector2(width, nh))
	q.material_override = nm
	q.position = Vector3(0, Court.NET_TOP - nh * 0.5 + 0.02, 0)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	net_node.add_child(q)

	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.07, 0.08, 0.1)
	black.metallic = 0.5
	black.roughness = 0.32
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.72, 0.8, 0.9)
	silver.metallic = 0.85
	silver.roughness = 0.25
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.1, 0.42, 0.95)
	blue.roughness = 0.35
	blue.emission_enabled = true
	blue.emission = Color(0.1, 0.4, 1.0)
	blue.emission_energy_multiplier = 0.4
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1)
	white.roughness = 0.5
	for s in [-1.0, 1.0]:
		var base := Node3D.new()
		base.position = Vector3(s * Court.NET_X, 0, 0)
		net_node.add_child(base)
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.12
		cm.height = 2.7
		cm.radial_segments = 20
		post.mesh = cm
		post.material_override = black
		post.position.y = 1.35
		base.add_child(post)
		var cap := MeshInstance3D.new()
		var cpm := CylinderMesh.new()
		cpm.top_radius = 0.105
		cpm.bottom_radius = 0.105
		cpm.height = 0.3
		cap.mesh = cpm
		cap.material_override = silver
		cap.position.y = 2.55
		base.add_child(cap)
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.108
		bm.bottom_radius = 0.108
		bm.height = 0.1
		band.mesh = bm
		band.material_override = blue
		band.position.y = 2.33
		base.add_child(band)
		var plate := MeshInstance3D.new()
		var plm := QuadMesh.new()
		plm.size = Vector2(0.07, 0.34)
		plate.mesh = plm
		plate.material_override = white
		plate.position = Vector3(0, 1.75, 0.1) if s > 0 else Vector3(0, 1.75, 0.1)
		base.add_child(plate)
		# arm that holds the net
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.26, 0.09, 0.09)
		arm.mesh = am
		arm.material_override = black
		arm.position = Vector3(-s * 0.15, Court.NET_TOP - 0.05, 0)
		base.add_child(arm)

	# red / white antennae on the side lines
	var stripe_tex := _stripe_texture()
	var am2 := StandardMaterial3D.new()
	am2.albedo_texture = stripe_tex
	am2.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	am2.uv1_scale = Vector3(1, 7, 1)
	am2.roughness = 0.5
	for s in [-1.0, 1.0]:
		var rod := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.018
		rm.bottom_radius = 0.018
		rm.height = 1.9
		rod.mesh = rm
		rod.material_override = am2
		rod.position = Vector3(s * Court.HALF_W, Court.NET_TOP - 0.8 + 0.95, 0)
		net_node.add_child(rod)


func _stripe_texture() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0.95, 0.15, 0.15))
	img.set_pixel(1, 0, Color(0.95, 0.15, 0.15))
	img.set_pixel(0, 1, Color(1, 1, 1))
	img.set_pixel(1, 1, Color(1, 1, 1))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ stands, lights, trees (Stadium Kit)
func _kit(name: String, tex: String, pos: Vector3, rot_y := 0.0, scl := 1.0) -> Node3D:
	var scn: PackedScene = load(KIT + name + ".fbx")
	var n: Node3D = scn.instantiate()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex(KIT_TEX + tex + ".png")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 0.7
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	# the kit is authored around the field centre: re-centre on the bottom middle of its bounds
	var box := _local_aabb(n)
	var pivot := Node3D.new()
	pivot.set_meta("kit", name)
	pivot.position = pos
	pivot.rotation_degrees.y = rot_y
	pivot.scale = Vector3.ONE * scl
	n.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	pivot.add_child(n)
	add_child(pivot)
	return pivot


func _local_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var cur: Node = m
		while cur != null and cur != n:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var bb := xf * m.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _build_stands() -> void:
	var hw := Court.HALF_W + Court.FREE_ZONE
	var hd := Court.HALF_D + Court.FREE_ZONE
	# far end stand (blue) - the main backdrop
	_kit("Seating_01", "Stadium_blue", Vector3(0, 0, -hd - 7.5), 0.0, 1.0)
	_kit("Seating_01", "Stadium_blue", Vector3(-23.0, 0, -hd - 7.5), 0.0, 1.0)
	_kit("Seating_01", "Stadium_blue", Vector3(23.0, 0, -hd - 7.5), 0.0, 1.0)
	# side stands (green)
	_kit("Seating_02", "Stadium_green", Vector3(-hw - 9.5, 0, -3), 90.0, 1.0)
	_kit("Seating_02", "Stadium_green", Vector3(hw + 9.5, 0, -3), -90.0, 1.0)
	_kit("Seating_02", "Stadium_green", Vector3(-hw - 9.5, 0, 12), 90.0, 1.0)
	_kit("Seating_02", "Stadium_green", Vector3(hw + 9.5, 0, 12), -90.0, 1.0)
	# floodlights at the corners
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_kit("Stadium_Light", "Stadium_green", Vector3(sx * (hw + 3.0), 0, sz * (hd + 2.0)), 0.0 if sz < 0 else 180.0, 1.0)
	# trees in their planters, near the stands
	_kit("Stadium_Tree", "Stadium_green", Vector3(-hw - 3.0, 0, -hd - 1.0), 0.0, 0.8)
	_kit("Stadium_Tree", "Stadium_green", Vector3(hw + 3.0, 0, -hd - 1.0), 0.0, 0.8)
	_kit("Stadium_Tree", "Stadium_green", Vector3(-hw - 3.0, 0, hd + 4.0), 0.0, 0.8)
	_kit("Stadium_Tree", "Stadium_green", Vector3(hw + 3.0, 0, hd + 4.0), 0.0, 0.8)


# ------------------------------------------------------------------ advertising boards
const BOARD_H := 0.82
const BOARD_W := 2.05            # one panel (atlas cells are 2.5 : 1)


## A low LED hoarding around the run-off area, like a real venue: a dark plinth with a coloured cap and rotating sponsor panels
## (fictional brands, tools/make_ads.py). Everything is two meshes: the plinth (lit, vertex colours) and all panels (one shader).
func _build_boards() -> void:
	var look: Dictionary = LOOKS.get(theme_id, LOOKS["day"])
	var hw := Court.HALF_W + Court.FREE_ZONE + 0.45
	var hd := Court.HALF_D + Court.FREE_ZONE + 0.55
	var depth := 0.3
	# runs: centre, direction along the run, length, normal towards the court
	var runs := [
		[Vector3(-hw, 0, 0), Vector3(0, 0, 1), hd * 2.0 + depth, Vector3(1, 0, 0)],
		[Vector3(hw, 0, 0), Vector3(0, 0, 1), hd * 2.0 + depth, Vector3(-1, 0, 0)],
		[Vector3(0, 0, -hd), Vector3(1, 0, 0), hw * 2.0 - depth, Vector3(0, 0, 1)],
	]
	var plinth := SurfaceTool.new()
	plinth.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := SurfaceTool.new()
	faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body_col: Color = look["plinth"]
	var cap_col: Color = look["cap"]
	var idx := 0
	for r in runs:
		var c: Vector3 = r[0]
		var dir: Vector3 = r[1]
		var length: float = r[2]
		var n: Vector3 = r[3]
		var size := Vector3(depth, 0.96, length) if absf(dir.z) > 0.5 else Vector3(length, 0.96, depth)
		_add_box(plinth, c + Vector3(0, 0.48, 0), size, body_col)
		var cap_size := size + (Vector3(0.1, 0.0, 0.0) if absf(dir.z) > 0.5 else Vector3(0.0, 0.0, 0.1))
		cap_size.y = 0.07
		_add_box(plinth, c + Vector3(0, 0.99, 0), cap_size, cap_col)
		var count := int(floor(length / BOARD_W))
		var used := float(count) * BOARD_W
		for side in [1.0, -1.0]:                  # inner face (towards the court) and outer face (towards the stands)
			var nn: Vector3 = n * side
			var right: Vector3 = (-nn).cross(Vector3.UP)
			for i in count:
				var along := -used * 0.5 + (float(i) + 0.5) * BOARD_W
				var centre := c + dir * along + nn * (depth * 0.5 + 0.012)
				var bl := centre - right * (BOARD_W * 0.5) + Vector3(0, 0.1, 0)
				var cell := (idx * 5 + i * 3 + (1 if side > 0.0 else 7)) % 16
				_add_panel(faces, bl, right, BOARD_W, BOARD_H, cell, fposmod(float(i) * 0.37 + (0.0 if side > 0.0 else 0.5), 1.0))
		idx += 1
	plinth.generate_normals()
	var pm := MeshInstance3D.new()
	pm.mesh = plinth.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.55
	pm.material_override = mat
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pm)
	var fm := MeshInstance3D.new()
	fm.mesh = faces.commit()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/ad_board.gdshader")
	sm.set_shader_parameter("atlas", _tex(ENV + "ads.png"))
	sm.set_shader_parameter("bright", look["bright"])
	sm.set_shader_parameter("night_tint", Vector3((look["tint"] as Color).r, (look["tint"] as Color).g, (look["tint"] as Color).b))
	fm.material_override = sm
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fm)


func _add_panel(st: SurfaceTool, bl: Vector3, right: Vector3, w: float, h: float, cell: int, phase: float) -> void:
	var br := bl + right * w
	var tl := bl + Vector3(0, h, 0)
	var tr := br + Vector3(0, h, 0)
	var col := Color(float(cell) / 15.0, phase, 0.0, 1.0)
	for v in [[tl, Vector2(0, 0)], [tr, Vector2(1, 0)], [br, Vector2(1, 1)], [tl, Vector2(0, 0)], [br, Vector2(1, 1)], [bl, Vector2(0, 1)]]:
		st.set_color(col)
		st.set_uv(v[1])
		st.add_vertex(v[0])


func _add_box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	# 6 faces, vertices wound clockwise seen from outside (Godot front faces)
	var f := [
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
	]
	for face in f:
		var q: Array = face[1]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(face[0])
			st.add_vertex(c + (q[i] as Vector3))


# ------------------------------------------------------------------ backdrop
func _build_backdrop() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex(ENV + "skyline.png")
	mat.albedo_color = (THEMES.get(theme_id, THEMES["day"]) as Dictionary)["backdrop"]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	# a big half cylinder around the far side
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := 150.0
	var height := 60.0
	var segs := 24
	var a0 := deg_to_rad(-150.0)
	var a1 := deg_to_rad(-30.0)
	for i in segs:
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var t0 := lerpf(a0, a1, u0)
		var t1 := lerpf(a0, a1, u1)
		var p00 := Vector3(cos(t0) * radius, -6.0, sin(t0) * radius)
		var p10 := Vector3(cos(t1) * radius, -6.0, sin(t1) * radius)
		var p01 := Vector3(cos(t0) * radius, height - 6.0, sin(t0) * radius)
		var p11 := Vector3(cos(t1) * radius, height - 6.0, sin(t1) * radius)
		# winding so that the inside faces the court; uv.y 0 = top
		for tri in [[p00, p10, p11, Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)], [p00, p11, p01, Vector2(u0, 1), Vector2(u1, 0), Vector2(u0, 0)]]:
			st.set_uv(tri[3]); st.add_vertex(tri[0])
			st.set_uv(tri[4]); st.add_vertex(tri[1])
			st.set_uv(tri[5]); st.add_vertex(tri[2])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ helpers
func _tex(path: String) -> Texture2D:
	if _mat_cache.has(path):
		return _mat_cache[path]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_mat_cache[path] = t
	return t
