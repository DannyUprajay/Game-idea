extends Node3D
## Point d'entrée du jeu : crée les touches, le monde, le joueur, les ennemis
## et l'interface. Tout est généré par code : aucun fichier à importer.

const FX = preload("res://scripts/fx.gd")
const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Hud = preload("res://scripts/hud.gd")
const Pillar = preload("res://scripts/pillar.gd")

const GROUND_SHADER := """
shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.16, 0.18, 0.22);
uniform vec3 line_color : source_color = vec3(0.32, 0.38, 0.48);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float grid(vec2 p, float cell) {
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) / fwidth(p / cell);
	return 1.0 - min(min(g.x, g.y), 1.0);
}
void fragment() {
	float small = grid(wpos.xz, 4.0) * 0.45;
	float big = grid(wpos.xz, 20.0);
	ALBEDO = mix(base_color, line_color, max(small, big));
	ROUGHNESS = 0.9;
}
"""

const START_ENEMIES := 4
const MAX_ENEMIES := 12

var player: Player
var hud: Hud
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 2.0
var _kills := 0


func _ready() -> void:
	_rng.seed = 1234
	_setup_inputs()
	_build_environment()
	_build_world()

	player = Player.new()
	player.position = Vector3(0, 0.1, 12)
	add_child(player)

	hud = Hud.new()
	add_child(hud)
	player.health_changed.connect(hud.set_health)
	player.energy_changed.connect(hud.set_energy)
	player.flight_changed.connect(hud.set_flying)
	player.damaged.connect(hud.flash_damage)
	player.died.connect(func() -> void: hud.show_message("K.O. ! Retour au point de départ"))
	hud.show_message("Appuie deux fois sur Espace pour t'envoler !", 4.0)

	for i in START_ENEMIES:
		_spawn_enemy()


func _process(delta: float) -> void:
	# Fait réapparaître des drones ; il y en a de plus en plus.
	var wanted: int = mini(START_ENEMIES + _kills / 4, MAX_ENEMIES)
	if get_tree().get_nodes_in_group("enemies").size() < wanted:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = 2.5
			_spawn_enemy()

	hud.set_speed_effect(player.speed_effect)
	hud.set_ability_state("fire", player.energy >= Player.FIREBALL_COST, 0.0)
	hud.set_ability_state("black_hole", player.black_hole_cd <= 0.0 and player.energy >= Player.BLACK_HOLE_COST, player.black_hole_cd)
	hud.set_ability_state("shockwave", player.shockwave_cd <= 0.0 and player.energy >= Player.SHOCKWAVE_COST, player.shockwave_cd)


func _spawn_enemy() -> void:
	var e := Enemy.new()
	e.killed.connect(_on_enemy_killed)
	add_child(e)
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(35.0, 60.0)
	var center := player.global_position if player != null else Vector3.ZERO
	e.global_position = Vector3(center.x + cos(angle) * dist, _rng.randf_range(8.0, 20.0), center.z + sin(angle) * dist)


func _on_enemy_killed() -> void:
	_kills += 1
	hud.add_kill()


# ---------------------------------------------------------------------------
# Touches (positions physiques : marche en AZERTY comme en QWERTY)
# ---------------------------------------------------------------------------
func _setup_inputs() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("descend", [KEY_CTRL, KEY_C])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("toggle_fly", [KEY_F])
	_add_keys("shockwave", [KEY_E])
	_add_keys("toggle_help", [KEY_H])
	_add_mouse("fire", MOUSE_BUTTON_LEFT)
	_add_mouse("black_hole", MOUSE_BUTTON_RIGHT)


func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------------------
# Ciel, lumière, brouillard, bloom
# ---------------------------------------------------------------------------
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.16, 0.38)
	sky_mat.sky_horizon_color = Color(0.85, 0.5, 0.4)
	sky_mat.ground_horizon_color = Color(0.5, 0.35, 0.35)
	sky_mat.ground_bottom_color = Color(0.08, 0.08, 0.12)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.45, 0.5)
	env.fog_density = 0.004

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -50, 0)
	sun.light_color = Color(1.0, 0.85, 0.7)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


# ---------------------------------------------------------------------------
# Le monde : sol, tours, îles flottantes, caisses
# ---------------------------------------------------------------------------
func _build_world() -> void:
	# Sol.
	var ground := StaticBody3D.new()
	add_child(ground)
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(600, 2, 600)
	gshape.shape = gbox
	gshape.position = Vector3(0, -1, 0)
	ground.add_child(gshape)
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var gmat := ShaderMaterial.new()
	gmat.shader = Shader.new()
	gmat.shader.code = GROUND_SHADER
	var gmesh := MeshInstance3D.new()
	gmesh.mesh = plane
	gmesh.material_override = gmat
	ground.add_child(gmesh)

	# Grandes tours de pierre : à éviter... ou à traverser en vol turbo !
	for i in 45:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(30.0, 220.0)
		var h := _rng.randf_range(10.0, 60.0)
		var w := _rng.randf_range(4.0, 10.0)
		var shade := _rng.randf_range(0.25, 0.45)
		var col := Color(shade, shade * 0.95, shade * 1.1)
		var pillar := Pillar.new()
		pillar.size = Vector3(w, h, w)
		pillar.color = col
		# Un liseré lumineux en haut de certaines tours.
		if i % 3 == 0:
			pillar.crown_color = Color(0.4, 0.8, 1.0)
		pillar.position = Vector3(cos(angle) * dist, h * 0.5, sin(angle) * dist)
		add_child(pillar)

	# Îles flottantes.
	for i in 18:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(25.0, 180.0)
		var y := _rng.randf_range(15.0, 55.0)
		var s := Vector3(_rng.randf_range(8, 18), _rng.randf_range(2, 4), _rng.randf_range(8, 18))
		_add_static_box(Vector3(cos(angle) * dist, y, sin(angle) * dist), s, Color(0.3, 0.42, 0.3))

	# Piles de caisses près du départ : à faire voler avec les pouvoirs !
	for stack in [Vector3(-10, 0, -6), Vector3(9, 0, -12), Vector3(0, 0, -25)]:
		for row in 4:
			for col in 4 - row:
				var pos: Vector3 = stack + Vector3(col * 1.25 + row * 0.62 - 1.9, 0.6 + row * 1.2, 0)
				_add_crate(pos)


func _add_static_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = FX.solid_material(color, 0.85)
	body.add_child(mi)


func _add_crate(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.add_to_group("props")
	body.mass = 2.0
	body.collision_layer = 1
	body.collision_mask = 1 | 2 | 4
	body.position = pos
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 1.2
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 1.2
	mi.mesh = mesh
	mi.material_override = FX.solid_material(Color(0.6, 0.42, 0.25), 0.9)
	body.add_child(mi)
