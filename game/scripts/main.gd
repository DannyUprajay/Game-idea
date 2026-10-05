extends Node3D
## Gestionnaire de partie : crée le monde, les touches, le joueur, l'interface,
## et gère les missions, le karma, l'expérience et l'apparition des personnages.

const FX = preload("res://scripts/fx.gd")
const Player = preload("res://scripts/player.gd")
const Hud = preload("res://scripts/hud.gd")
const Menus = preload("res://scripts/menus.gd")
const City = preload("res://scripts/city.gd")
const Civilian = preload("res://scripts/civilian.gd")
const Soldier = preload("res://scripts/soldier.gd")
const Drone = preload("res://scripts/enemy.gd")
const Relay = preload("res://scripts/relay.gd")
const Boss = preload("res://scripts/boss.gd")

enum Stage { DRAIN, CIVILIAN, RELAYS, BOSS, DONE }

const EVIL_COLOR := Color(1.0, 0.15, 0.1)
const NEUTRAL_COLOR := Color(1.0, 0.5, 0.15)
const GOOD_COLOR := Color(0.3, 0.65, 1.0)

const UPGRADES := [
	{"id": "power", "name": "Puissance", "desc": "+25 % de dégâts pour tous les pouvoirs", "max": 3},
	{"id": "energy", "name": "Batterie", "desc": "+40 d'énergie maximum", "max": 3},
	{"id": "health", "name": "Résistance", "desc": "+40 de vie maximum", "max": 3},
	{"id": "flight", "name": "Turbo", "desc": "Vol turbo plus rapide", "max": 3},
	{"id": "black_hole", "name": "Singularité", "desc": "Trou noir plus grand et plus long", "max": 2},
]

var player: Player
var hud: Hud
var menus: Menus
var city: City

var stage := Stage.DRAIN
var karma := 0.0
var xp := 0
var level := 1
var points := 0
var ranks := {"power": 0, "energy": 0, "health": 0, "flight": 0, "black_hole": 0}

var _relays: Array = []
var _boss: Boss = null
var _tutorial_civilian: Civilian = null
var _started := false
var _spawn_timer := 4.0
var _play_time := 0.0
var _stats := {"enemies": 0, "healed": 0, "leeched": 0, "civilians_killed": 0}


func _ready() -> void:
	add_to_group("game")
	_setup_inputs()
	_build_environment()

	city = City.new()
	add_child(city)
	city.build(2024)

	player = Player.new()
	player.position = city.player_start
	add_child(player)
	player.energy = 25.0

	hud = Hud.new()
	add_child(hud)
	menus = Menus.new()
	add_child(menus)

	player.health_changed.connect(hud.set_health)
	player.energy_changed.connect(hud.set_energy)
	player.flight_changed.connect(hud.set_flying)
	player.damaged.connect(hud.flash_damage)
	player.died.connect(_on_player_died)
	player.power_locked.connect(func(power_name: String, lvl: int) -> void:
		hud.show_message("%s : débloqué au niveau %d" % [power_name, lvl], 2.0))
	menus.start_requested.connect(_start_game)
	menus.upgrade_requested.connect(_buy_upgrade)
	menus.restart_requested.connect(_restart)

	for site in city.relay_sites:
		var r := Relay.new()
		r.relay_name = "Relais %d" % (_relays.size() + 1)
		r.position = site
		add_child(r)
		_relays.append(r)
	for p in city.patrol_points:
		_spawn_soldier(p)

	_spawn_civilians(40, 8)
	_update_karma(0.0)
	_update_level_display()
	hud.set_health(player.health, player.max_health)
	hud.set_energy(player.energy, player.max_energy)
	hud.set_objective("")


func _start_game() -> void:
	if _started:
		return
	_started = true
	_set_stage(Stage.DRAIN)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Boucle
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _started:
		return
	_play_time += delta
	hud.set_speed_effect(player.speed_effect)
	hud.set_prompt(player.interaction_prompt, player.interaction_progress)
	hud.set_ability_state("fire", player.energy >= Player.FIREBALL_COST, 0.0)
	hud.set_ability_state("shockwave", player.shockwave_cd <= 0.0 and player.energy >= Player.SHOCKWAVE_COST,
		player.shockwave_cd, 0 if player.shockwave_unlocked else Player.SHOCKWAVE_LEVEL)
	hud.set_ability_state("black_hole", player.black_hole_cd <= 0.0 and player.energy >= Player.BLACK_HOLE_COST,
		player.black_hole_cd, 0 if player.black_hole_unlocked else Player.BLACK_HOLE_LEVEL)

	match stage:
		Stage.DRAIN:
			if player.energy >= player.max_energy * 0.9:
				_set_stage(Stage.CIVILIAN)
		Stage.CIVILIAN:
			if is_instance_valid(_tutorial_civilian):
				hud.set_marker(true, _tutorial_civilian.global_position + Vector3.UP, Color(0.4, 1.0, 0.5))
		Stage.RELAYS:
			_mark_nearest_relay()
		Stage.BOSS:
			if is_instance_valid(_boss):
				hud.set_marker(true, _boss.global_position, Color(1.0, 0.3, 0.2))

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 5.0
		_keep_population()


# ---------------------------------------------------------------------------
# Missions
# ---------------------------------------------------------------------------
func _set_stage(s: Stage) -> void:
	stage = s
	match s:
		Stage.DRAIN:
			hud.set_objective("Ton énergie est presque vide. Approche-toi du générateur de la place (ou d'un lampadaire, d'une voiture) et maintiens R pour absorber l'électricité.")
			hud.set_marker(true, city.player_start + Vector3(0, 3.0, -18.5), Color(0.4, 0.8, 1.0))
			hud.show_message("La ville est aux mains de la Milice Rouge.\nRecharge-toi d'abord en électricité.", 5.0)
		Stage.CIVILIAN:
			_tutorial_civilian = Civilian.new()
			_tutorial_civilian.start_downed = true
			_tutorial_civilian.position = city.player_start + Vector3(6, 0.2, 4)
			add_child(_tutorial_civilian)
			hud.set_objective("Un civil blessé gît près de la fontaine. Maintiens R pour le soigner (héros) ou T pour absorber sa vie (infâme). Ce choix compte !")
			hud.show_message("Énergie rechargée !", 2.0)
		Stage.RELAYS:
			_update_relay_objective()
			hud.show_message("La Milice Rouge contrôle 3 relais.\nDétruis-les pour libérer la ville !", 4.0)
		Stage.BOSS:
			hud.set_objective("Le Colosse est arrivé ! Détruis-le.")
			hud.show_message("LE COLOSSE ARRIVE !", 4.0)
			_boss = Boss.new()
			_boss.position = city.player_start + Vector3(0, 40, -60)
			add_child(_boss)
			_boss.health_changed.connect(hud.set_boss_health)
			hud.set_boss_health(_boss.health, _boss.max_health)
			hud.show_boss(true)
		Stage.DONE:
			hud.set_marker(false)
			hud.show_boss(false)
			get_tree().create_timer(4.0).timeout.connect(_show_ending)


func _update_relay_objective() -> void:
	var left := 0
	for r in _relays:
		if is_instance_valid(r) and r.is_in_group("relays"):
			left += 1
	hud.set_objective("Détruis les relais de la Milice Rouge : %d / 3 restants.\nIls envoient des renforts tant qu'ils sont debout." % left)
	if left == 0 and stage == Stage.RELAYS:
		_set_stage(Stage.BOSS)


func _mark_nearest_relay() -> void:
	var best: Node3D = null
	var best_d := INF
	for r in _relays:
		if not is_instance_valid(r) or not r.is_in_group("relays"):
			continue
		var n := r as Node3D
		var d := n.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = n
	if best != null:
		hud.set_marker(true, best.global_position + Vector3(0, 17, 0), Color(1.0, 0.35, 0.25))


func _show_ending() -> void:
	var minutes := int(_play_time / 60.0)
	var stats: String = "\n\nEnnemis vaincus : %d   ·   Civils soignés : %d   ·   Vies absorbées : %d   ·   Civils tués : %d\nTemps : %d min   ·   Niveau %d" % [
		_stats["enemies"], _stats["healed"], _stats["leeched"], _stats["civilians_killed"], minutes, level]
	if karma >= 20.0:
		menus.show_ending("HÉROS DE LA VILLE",
			"Le Colosse s'effondre dans un fracas de métal. Les habitants sortent dans les rues et scandent ton nom.\nGrâce à toi, la ville respire à nouveau." + stats, GOOD_COLOR)
	elif karma <= -20.0:
		menus.show_ending("LE NOUVEAU TYRAN",
			"Le Colosse est tombé... mais personne n'ose sortir. Les rues sont silencieuses.\nLa ville n'a pas été libérée : elle a simplement changé de maître." + stats, EVIL_COLOR)
	else:
		menus.show_ending("LE JUSTICIER SOLITAIRE",
			"Le Colosse est tombé. La ville ne sait pas trop quoi penser de toi : ni tout à fait un héros, ni tout à fait un monstre.\nMais elle est libre." + stats, NEUTRAL_COLOR)


# ---------------------------------------------------------------------------
# Événements envoyés par les personnages (via FX.notify)
# ---------------------------------------------------------------------------
func on_enemy_killed(amount: int, _pos: Vector3) -> void:
	_stats["enemies"] += 1
	_add_xp(amount)


func on_relay_destroyed(amount: int, _pos: Vector3) -> void:
	hud.show_message("Relais détruit !", 2.5)
	_add_xp(amount)
	# Attendre que le relais quitte le groupe avant de compter.
	_update_relay_objective.call_deferred()


func on_civilian_healed(_pos: Vector3) -> void:
	_stats["healed"] += 1
	_add_xp(30)
	_update_karma(8.0)
	hud.feed("Civil soigné   Karma +", GOOD_COLOR)
	_civilian_tutorial_done()


func on_civilian_leeched(_pos: Vector3) -> void:
	_stats["leeched"] += 1
	_add_xp(30)
	_update_karma(-10.0)
	hud.feed("Vie absorbée   Karma −", EVIL_COLOR)
	_civilian_tutorial_done()


func on_civilian_killed(_pos: Vector3) -> void:
	_stats["civilians_killed"] += 1
	_update_karma(-5.0)
	hud.feed("Civil tué   Karma −", EVIL_COLOR)


func on_boss_killed(_pos: Vector3) -> void:
	_add_xp(500)
	hud.show_message("LE COLOSSE EST VAINCU !", 4.0)
	_set_stage(Stage.DONE)


func _civilian_tutorial_done() -> void:
	if stage == Stage.CIVILIAN:
		hud.show_message("Ton karma évolue selon tes choix :\nla couleur de tes pouvoirs aussi !", 4.0)
		_set_stage(Stage.RELAYS)


func _on_player_died() -> void:
	hud.show_message("K.O. ! Tu te réveilles sur la place centrale.", 3.0)


# ---------------------------------------------------------------------------
# Karma, XP, niveaux, améliorations
# ---------------------------------------------------------------------------
func _update_karma(change: float) -> void:
	karma = clampf(karma + change, -100.0, 100.0)
	var rank := "Neutre"
	if karma <= -60.0:
		rank = "Infâme"
	elif karma <= -20.0:
		rank = "Voyou"
	elif karma >= 60.0:
		rank = "Héros"
	elif karma >= 20.0:
		rank = "Gardien"
	var color: Color
	if karma < 0.0:
		color = NEUTRAL_COLOR.lerp(EVIL_COLOR, clampf(-karma / 60.0, 0.0, 1.0))
	else:
		color = NEUTRAL_COLOR.lerp(GOOD_COLOR, clampf(karma / 60.0, 0.0, 1.0))
	player.set_power_color(color)
	hud.set_karma(karma, rank, color)


func _xp_needed() -> int:
	return 100 + (level - 1) * 75


func _add_xp(amount: int) -> void:
	xp += amount
	hud.feed("+%d XP" % amount, Color(1.0, 0.85, 0.35))
	while xp >= _xp_needed():
		xp -= _xp_needed()
		level += 1
		points += 1
		player.full_heal()
		var text := "NIVEAU %d !  (+1 point d'amélioration, touche Tab)" % level
		if level == Player.SHOCKWAVE_LEVEL:
			player.shockwave_unlocked = true
			text += "\nNouveau pouvoir : ONDE DE CHOC (E)"
		if level == Player.BLACK_HOLE_LEVEL:
			player.black_hole_unlocked = true
			text += "\nNouveau pouvoir : TROU NOIR (clic droit)"
		hud.show_message(text, 4.0)
	_update_level_display()


func _update_level_display() -> void:
	hud.set_level(level, xp, _xp_needed(), points)


func refresh_upgrades() -> void:
	var list: Array = []
	for u in UPGRADES:
		var entry: Dictionary = u.duplicate()
		entry["rank"] = ranks[u["id"]]
		list.append(entry)
	menus.set_upgrades(list, points)


func _buy_upgrade(id: String) -> void:
	var max_rank := 0
	for u in UPGRADES:
		if u["id"] == id:
			max_rank = int(u["max"])
	if points <= 0 or int(ranks[id]) >= max_rank:
		return
	points -= 1
	ranks[id] = int(ranks[id]) + 1
	match id:
		"power":
			player.damage_mult += 0.25
		"energy":
			player.max_energy += 40.0
		"health":
			player.max_health += 40.0
		"flight":
			player.fly_boost_speed += 8.0
		"black_hole":
			player.black_hole_power += 0.25
	player.full_heal()
	_update_level_display()
	refresh_upgrades()


# ---------------------------------------------------------------------------
# Population : civils et ennemis
# ---------------------------------------------------------------------------
func _spawn_civilians(count: int, downed: int) -> void:
	for i in count:
		var c := Civilian.new()
		c.start_downed = i < downed
		c.position = _random_point_far_from_player(0.0)
		add_child(c)


func _spawn_soldier(pos: Vector3) -> void:
	var s := Soldier.new()
	s.position = pos + Vector3(0, 0.5, 0)
	add_child(s)


func _random_point_far_from_player(min_dist: float) -> Vector3:
	var pts := city.civilian_points
	for attempt in 10:
		var p: Vector3 = pts[randi() % pts.size()] + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		if p.distance_to(player.global_position) >= min_dist:
			return p
	return pts[randi() % pts.size()]


## Garde la ville vivante : des civils, et des patrouilles ennemies.
func _keep_population() -> void:
	if get_tree().get_nodes_in_group("civilians").size() < 30:
		var c := Civilian.new()
		c.start_downed = randf() < 0.3
		c.position = _random_point_far_from_player(60.0)
		add_child(c)
	if stage == Stage.DONE:
		return
	var soldiers := 0
	var drones := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is CharacterBody3D:
			if e.get_script() == Soldier:
				soldiers += 1
			elif e.get_script() == Drone:
				drones += 1
	if soldiers < 10:
		_spawn_soldier(_random_point_far_from_player(70.0))
	if drones < 4 and level >= 2:
		var d := Drone.new()
		var p := _random_point_far_from_player(80.0)
		d.position = p + Vector3(0, 20, 0)
		add_child(d)


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
	_add_keys("drain", [KEY_R])
	_add_keys("leech", [KEY_T])
	_add_keys("toggle_help", [KEY_H])
	_add_keys("pause", [KEY_ESCAPE, KEY_P])
	_add_keys("upgrades", [KEY_TAB])
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
# Nuit en ville : ciel, lune, brouillard, bloom
# ---------------------------------------------------------------------------
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.03, 0.08)
	sky_mat.sky_horizon_color = Color(0.15, 0.12, 0.22)
	sky_mat.ground_horizon_color = Color(0.1, 0.08, 0.12)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_mat.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.55)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.1, 0.18)
	env.fog_density = 0.006

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, 30, 0)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 120.0
	add_child(moon)
