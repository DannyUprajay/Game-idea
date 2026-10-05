extends Node3D
## Génère la ville de nuit : rues, trottoirs, immeubles aux fenêtres éclairées,
## lampadaires, voitures, générateurs, place centrale et zones ennemies.
## Appeler build() après l'avoir ajoutée à la scène.

const FX = preload("res://scripts/fx.gd")
const Pillar = preload("res://scripts/pillar.gd")
const Car = preload("res://scripts/car.gd")
const EnergySource = preload("res://scripts/energy_source.gd")

const BLOCKS := 7          # pâtés de maisons par côté
const BLOCK_SIZE := 46.0   # taille d'un pâté
const STREET := 14.0       # largeur des rues
const PITCH := BLOCK_SIZE + STREET

const BUILDING_SHADER := """
shader_type spatial;
uniform vec3 wall_color : source_color = vec3(0.3, 0.3, 0.33);
uniform vec3 window_color : source_color = vec3(1.0, 0.8, 0.5);
uniform float seed = 0.0;
uniform float lit_ratio = 0.45;
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}
void fragment() {
	vec3 n = abs(wnorm);
	if (n.y > 0.5) {
		ALBEDO = wall_color * 0.55;
		ROUGHNESS = 0.95;
	} else {
		vec2 uv = vec2(n.x > 0.5 ? wpos.z : wpos.x, wpos.y);
		vec2 cell = uv / vec2(3.2, 3.6);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.28, f.y) * step(f.y, 0.82);
		win *= step(1.0, id.y);  // pas de fenêtres au rez-de-chaussée
		float lit = step(1.0 - lit_ratio, hash(id));
		float tint = 0.55 + hash(id + 7.0) * 0.6;
		vec3 glass = vec3(0.04, 0.05, 0.08);
		ALBEDO = mix(wall_color, glass, win);
		EMISSION = window_color * tint * win * lit * 1.4;
		ROUGHNESS = mix(0.85, 0.15, win);
		METALLIC = win * 0.3;
	}
}
"""

const GROUND_SHADER := """
shader_type spatial;
uniform float pitch = 60.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float street_dist(float x) {
	return abs(fract((x - pitch * 0.5) / pitch + 0.5) - 0.5) * pitch;
}
void fragment() {
	float dx = street_dist(wpos.x);
	float dz = street_dist(wpos.z);
	float dash_z = step(0.5, fract(wpos.z / 6.0));
	float dash_x = step(0.5, fract(wpos.x / 6.0));
	float line = max(step(dx, 0.15) * dash_z, step(dz, 0.15) * dash_x);
	float grain = fract(sin(dot(floor(wpos.xz * 4.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 asphalt = vec3(0.07, 0.07, 0.08) + grain * 0.015;
	ALBEDO = mix(asphalt, vec3(0.85, 0.7, 0.2), line);
	ROUGHNESS = 0.75;
}
"""

const WALL_COLORS := [Color(0.32, 0.3, 0.3), Color(0.25, 0.27, 0.32), Color(0.4, 0.35, 0.3),
	Color(0.22, 0.22, 0.24), Color(0.35, 0.33, 0.38), Color(0.3, 0.24, 0.22)]
const WINDOW_COLORS := [Color(1.0, 0.8, 0.5), Color(0.75, 0.85, 1.0), Color(1.0, 0.9, 0.7)]

var player_start := Vector3(0, 0.5, 12)
var relay_sites: Array[Vector3] = []
var civilian_points: Array[Vector3] = []
var patrol_points: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _building_shader: Shader
var _concrete: StandardMaterial3D


func build(seed_value: int) -> void:
	_rng.seed = seed_value
	_building_shader = Shader.new()
	_building_shader.code = BUILDING_SHADER
	_concrete = FX.solid_material(Color(0.36, 0.36, 0.37), 0.95)

	_build_ground()

	# Zones ennemies : trois coins de la ville.
	var relay_blocks := [Vector2i(0, BLOCKS - 1), Vector2i(BLOCKS - 1, BLOCKS - 2), Vector2i(BLOCKS - 2, 0)]
	var center := Vector2i(BLOCKS / 2, BLOCKS / 2)

	for bx in BLOCKS:
		for bz in BLOCKS:
			var c := _block_center(bx, bz)
			var cell := Vector2i(bx, bz)
			_add_box(Vector3(BLOCK_SIZE, 0.12, BLOCK_SIZE), Vector3(c.x, 0.06, c.z), _concrete, true)
			if cell == center:
				_build_plaza(c)
			elif cell in relay_blocks:
				_build_enemy_zone(c)
			else:
				_build_block(c)
			_add_block_lamps(c)

	_add_parked_cars()


func _block_center(bx: int, bz: int) -> Vector3:
	var offset := (BLOCKS - 1) * 0.5
	return Vector3((bx - offset) * PITCH, 0, (bz - offset) * PITCH)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	add_child(ground)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1200, 2, 1200)
	shape.shape = box
	shape.position = Vector3(0, -1, 0)
	ground.add_child(shape)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1200, 1200)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = GROUND_SHADER
	mat.set_shader_parameter("pitch", PITCH)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	ground.add_child(mi)


## Pâté normal : 2x2 parcelles avec un immeuble chacune (ou un parking).
func _build_block(c: Vector3) -> void:
	var lot := BLOCK_SIZE * 0.5
	# Les immeubles sont plus hauts vers le centre-ville.
	var centrality := 1.0 - clampf(Vector2(c.x, c.z).length() / (PITCH * BLOCKS * 0.6), 0.0, 1.0)
	for ix in 2:
		for iz in 2:
			var lc := c + Vector3((ix - 0.5) * lot, 0, (iz - 0.5) * lot)
			if _rng.randf() < 0.12:
				continue  # parcelle vide
			var w := _rng.randf_range(13.0, 18.0)
			var d := _rng.randf_range(13.0, 18.0)
			var h := _rng.randf_range(12.0, 30.0) + centrality * _rng.randf_range(10.0, 55.0)
			_add_building(lc, Vector3(w, h, d))
	# Points où les civils se promènent : le long des trottoirs.
	for i in 3:
		var side := _rng.randi_range(0, 3)
		var along := _rng.randf_range(-BLOCK_SIZE * 0.4, BLOCK_SIZE * 0.4)
		var edge := BLOCK_SIZE * 0.5 - 2.0
		var p := c
		match side:
			0: p += Vector3(along, 0.2, edge)
			1: p += Vector3(along, 0.2, -edge)
			2: p += Vector3(edge, 0.2, along)
			_: p += Vector3(-edge, 0.2, along)
		civilian_points.append(p)


func _add_building(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, size.y * 0.5, 0)
	add_child(body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)

	var mat := ShaderMaterial.new()
	mat.shader = _building_shader
	mat.set_shader_parameter("wall_color", WALL_COLORS[_rng.randi() % WALL_COLORS.size()])
	mat.set_shader_parameter("window_color", WINDOW_COLORS[_rng.randi() % WINDOW_COLORS.size()])
	mat.set_shader_parameter("seed", _rng.randf() * 100.0)
	mat.set_shader_parameter("lit_ratio", _rng.randf_range(0.25, 0.6))
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	# Toit : rebord, climatiseurs, parfois une antenne destructible.
	var top := pos.y + size.y
	_add_box(Vector3(size.x + 0.4, 0.6, size.z + 0.4), Vector3(pos.x, top + 0.3, pos.z), _concrete, false)
	for i in _rng.randi_range(1, 3):
		var ac := Vector3(_rng.randf_range(1.5, 3.0), _rng.randf_range(1.0, 2.0), _rng.randf_range(1.5, 3.0))
		var ap := Vector3(pos.x + _rng.randf_range(-size.x * 0.3, size.x * 0.3), top + ac.y * 0.5,
			pos.z + _rng.randf_range(-size.z * 0.3, size.z * 0.3))
		_add_box(ac, ap, FX.solid_material(Color(0.5, 0.5, 0.52), 0.6, 0.4), true)
	if _rng.randf() < 0.3:
		var antenna := Pillar.new()
		antenna.size = Vector3(1.2, _rng.randf_range(6.0, 14.0), 1.2)
		antenna.color = Color(0.3, 0.3, 0.33)
		antenna.crown_color = Color(1.0, 0.15, 0.1)
		antenna.position = Vector3(pos.x, top + antenna.size.y * 0.5, pos.z)
		add_child(antenna)


## Place centrale : départ du joueur, générateur, colonnes à faire exploser.
func _build_plaza(c: Vector3) -> void:
	player_start = c + Vector3(0, 0.5, 12)
	var gen := EnergySource.new()
	gen.kind = EnergySource.Kind.GENERATOR
	gen.position = c + Vector3(0, 0.12, -6)
	add_child(gen)
	# Fontaine.
	_add_box(Vector3(10, 0.8, 10), c + Vector3(0, 0.4, 6), FX.solid_material(Color(0.5, 0.5, 0.52), 0.8), true)
	var water := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(9, 0.1, 9)
	water.mesh = wm
	var water_mat := FX.solid_material(Color(0.1, 0.25, 0.4), 0.05, 0.3)
	water_mat.emission_enabled = true
	water_mat.emission = Color(0.1, 0.3, 0.5)
	water_mat.emission_energy_multiplier = 0.6
	water.material_override = water_mat
	water.position = c + Vector3(0, 0.82, 6)
	add_child(water)
	# Colonnes destructibles en cercle.
	for i in 8:
		var a := TAU * i / 8.0
		var col := Pillar.new()
		col.size = Vector3(1.6, 9.0, 1.6)
		col.color = Color(0.55, 0.52, 0.48)
		col.crown_color = Color(0.4, 0.8, 1.0) if i % 2 == 0 else Color(0, 0, 0, 0)
		col.position = c + Vector3(cos(a) * 17.0, 4.62, sin(a) * 17.0)
		add_child(col)
	for i in 6:
		civilian_points.append(c + Vector3(_rng.randf_range(-16, 16), 0.2, _rng.randf_range(-16, 16)))


## Zone ennemie : barricades autour d'un emplacement de relais.
func _build_enemy_zone(c: Vector3) -> void:
	relay_sites.append(c + Vector3(0, 0.12, 0))
	var barrier := FX.solid_material(Color(0.55, 0.5, 0.42), 0.9)
	var stripe := FX.emissive_material(Color(1.0, 0.25, 0.1), 1.5)
	for i in 14:
		var a := TAU * i / 14.0 + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(14.0, 19.0)
		var p := c + Vector3(cos(a) * r, 0.6, sin(a) * r)
		var b := StaticBody3D.new()
		b.position = p
		b.rotation.y = -a
		add_child(b)
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, 1.1, 3.5)
		col.shape = box
		b.add_child(col)
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = box.size
		mi.mesh = m
		mi.material_override = barrier
		b.add_child(mi)
		var s := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.82, 0.15, 3.52)
		s.mesh = sm
		s.material_override = stripe
		s.position = Vector3(0, 0.3, 0)
		b.add_child(s)
	for i in 4:
		patrol_points.append(c + Vector3(_rng.randf_range(-10, 10), 1.0, _rng.randf_range(-10, 10)))
	var gen := EnergySource.new()
	gen.kind = EnergySource.Kind.GENERATOR
	gen.position = c + Vector3(20, 0.12, 20)
	add_child(gen)


## Deux lampadaires par pâté, au bord du trottoir.
func _add_block_lamps(c: Vector3) -> void:
	var edge := BLOCK_SIZE * 0.5 - 0.8
	var spots := [
		[Vector3(-BLOCK_SIZE * 0.25, 0, edge), 0.0],
		[Vector3(BLOCK_SIZE * 0.25, 0, -edge), PI],
	]
	if _rng.randf() < 0.5:
		spots = [
			[Vector3(edge, 0, BLOCK_SIZE * 0.25), PI * 0.5],
			[Vector3(-edge, 0, -BLOCK_SIZE * 0.25), -PI * 0.5],
		]
	for spot in spots:
		var lamp := EnergySource.new()
		lamp.kind = EnergySource.Kind.LAMP
		lamp.position = c + (spot[0] as Vector3) + Vector3(0, 0.12, 0)
		# Le bras du lampadaire pointe vers la rue.
		lamp.rotation.y = float(spot[1]) + PI
		add_child(lamp)


## Voitures garées le long des rues.
func _add_parked_cars() -> void:
	var half := BLOCKS * PITCH * 0.5
	for i in 70:
		var along := _rng.randf_range(-half + 10.0, half - 10.0)
		var street_index := _rng.randi_range(0, BLOCKS)
		var street := (street_index - BLOCKS * 0.5) * PITCH
		var lane := (STREET * 0.5 - 2.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var car := Car.new()
		if _rng.randf() < 0.5:
			car.position = Vector3(street + lane, 0.3, along)
		else:
			car.position = Vector3(along, 0.3, street + lane)
			car.rotation.y = PI * 0.5
		add_child(car)


func _add_box(size: Vector3, pos: Vector3, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		add_child(body)
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		col.shape = box
		body.add_child(col)
		body.add_child(mi)
	else:
		mi.position = pos
		add_child(mi)
