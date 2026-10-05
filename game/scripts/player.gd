extends CharacterBody3D
## Le mage : marche, saute, vole et lance des pouvoirs avec ses mains.

signal health_changed(value: float, max_value: float)
signal energy_changed(value: float, max_value: float)
signal flight_changed(flying: bool)
signal damaged
signal died
## Un pouvoir pas encore débloqué a été tenté.
signal power_locked(power_name: String, level: int)

const FX = preload("res://scripts/fx.gd")
const Projectile = preload("res://scripts/projectile.gd")
const BlackHole = preload("res://scripts/black_hole.gd")
const Shockwave = preload("res://scripts/shockwave.gd")
const Beam = preload("res://scripts/beam.gd")

# --- Réglages (modifiables dans l'inspecteur) ---
@export var walk_speed := 7.0
@export var sprint_speed := 12.0
@export var jump_velocity := 9.0
@export var gravity := 24.0
@export var fly_speed := 16.0
@export var fly_boost_speed := 36.0
@export var mouse_sensitivity := 0.0025

const ENERGY_REGEN := 1.5     # très lente : il faut absorber l'électricité de la ville
const HEALTH_REGEN := 5.0
const DRAIN_RATE := 45.0      # énergie absorbée par seconde
const DRAIN_RANGE := 7.0
const HELP_RANGE := 3.5
const HELP_TIME := 1.2        # secondes pour soigner / absorber un civil
const FIREBALL_COST := 5.0
const FIREBALL_RATE := 0.16
const BLACK_HOLE_COST := 45.0
const BLACK_HOLE_COOLDOWN := 7.0
const SHOCKWAVE_COST := 30.0
const SHOCKWAVE_COOLDOWN := 3.0
## Vitesse minimale pour traverser un pilier (le turbo va jusqu'à 36).
const SMASH_SPEED := 24.0

# --- Statistiques (améliorables) ---
var max_health := 100.0
var max_energy := 100.0
var damage_mult := 1.0
var black_hole_power := 1.0
var shockwave_unlocked := false
var black_hole_unlocked := false
const SHOCKWAVE_LEVEL := 2
const BLACK_HOLE_LEVEL := 3

## Couleur des pouvoirs (change avec le karma).
var power_color := Color(1.0, 0.5, 0.15)

var health := 100.0
var energy := 60.0
var respawn_point := Vector3.ZERO
## Texte d'aide affiché quand on peut interagir (ex. « R : absorber »).
var interaction_prompt := ""
## Progression du soin / de l'absorption d'un civil (0 à 1).
var interaction_progress := 0.0
var flying := false
var black_hole_cd := 0.0
var shockwave_cd := 0.0

var _fire_timer := 0.0
var _next_hand := 0
var _arm_raise: Array[float] = [0.0, 0.0]
var _both_arms := 0.0
var _shake := 0.0
var _since_damage := 10.0
var _anim_time := 0.0
var _push := Vector3.ZERO

var _yaw: Node3D
var _pitch: Node3D
var _spring: SpringArm3D
var camera: Camera3D
var _model: Node3D
var _arms: Array[Node3D] = []
var _hand_mats: Array[StandardMaterial3D] = []
var _hand_lights: Array[OmniLight3D] = []
var _legs: Array[Node3D] = []
var _cape: Node3D
var _aura: GPUParticles3D
var _dust: GPUParticles3D
var _eye_mat: StandardMaterial3D
var _beam: Beam
var _help_target: Node3D = null
var _help_time := 0.0

## Intensité de l'effet de vitesse (0 = rien, 1 = vol à pleine vitesse).
var speed_effect := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.3
	respawn_point = global_position

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	_build_model()
	_build_camera()
	_beam = Beam.new()
	add_child(_beam)
	set_power_color(power_color)


# ---------------------------------------------------------------------------
# Construction du personnage (formes simples, pas de modèle à importer)
# ---------------------------------------------------------------------------
func _build_model() -> void:
	var cloth := FX.solid_material(Color(0.12, 0.13, 0.22), 0.7)
	var skin := FX.solid_material(Color(0.85, 0.7, 0.6), 0.6)
	var trim := FX.solid_material(Color(0.85, 0.65, 0.25), 0.3, 0.8)
	var cape_mat := FX.solid_material(Color(0.55, 0.08, 0.1), 0.8)
	cape_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Le pivot du modèle est au niveau du bassin : il penche en vol autour de ce point.
	_model = Node3D.new()
	_model.position = Vector3(0, 1.0, 0)
	add_child(_model)

	_add_part(_model, _capsule(0.27, 0.85), cloth, Vector3(0, 0.25, 0))           # buste
	_add_part(_model, _box(Vector3(0.62, 0.1, 0.32)), trim, Vector3(0, 0.55, 0))  # épaules
	_add_part(_model, _box(Vector3(0.5, 0.08, 0.3)), trim, Vector3(0, -0.12, 0))  # ceinture
	_add_part(_model, _sphere_mesh(0.19), skin, Vector3(0, 0.8, 0))                # tête
	_add_part(_model, _sphere_mesh(0.2), cloth, Vector3(0, 0.84, 0.03))            # capuche

	# Yeux lumineux.
	_eye_mat = FX.emissive_material(power_color, 6.0)
	for x in [-0.07, 0.07]:
		_add_part(_model, _sphere_mesh(0.03), _eye_mat, Vector3(x, 0.82, -0.17))

	# Bras : pivot à l'épaule, le bras pend vers le bas (-Y).
	for side in [1, -1]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.36 * side, 0.5, 0)
		_model.add_child(shoulder)
		_add_part(shoulder, _capsule(0.085, 0.72), cloth, Vector3(0, -0.32, 0))
		var hand_mat := FX.emissive_material(power_color, 1.0)
		_add_part(shoulder, _sphere_mesh(0.1), hand_mat, Vector3(0, -0.72, 0))
		var light := OmniLight3D.new()
		light.light_color = power_color
		light.light_energy = 0.0
		light.omni_range = 4.0
		light.position = Vector3(0, -0.8, 0)
		shoulder.add_child(light)
		_arms.append(shoulder)
		_hand_mats.append(hand_mat)
		_hand_lights.append(light)

	# Jambes.
	for side in [1, -1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.14 * side, -0.15, 0)
		_model.add_child(hip)
		_add_part(hip, _capsule(0.1, 0.85), cloth, Vector3(0, -0.4, 0))
		_add_part(hip, _box(Vector3(0.16, 0.1, 0.28)), trim, Vector3(0, -0.8, -0.05))
		_legs.append(hip)

	# Cape qui flotte derrière.
	_cape = Node3D.new()
	_cape.position = Vector3(0, 0.52, 0.17)
	_model.add_child(_cape)
	_add_part(_cape, _box(Vector3(0.6, 1.15, 0.03)), cape_mat, Vector3(0, -0.57, 0))

	# Aura de flammes autour du corps en vol.
	_aura = FX.particles(40, 0.6, 0.35, [Color(1, 0.8, 0.4, 0), Color(1, 0.5, 0.15, 0.8), Color(1, 0.2, 0.05, 0)], [0.0, 0.3, 1.0])
	var am := _aura.process_material as ParticleProcessMaterial
	am.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	am.emission_sphere_radius = 0.5
	am.direction = Vector3.DOWN
	am.spread = 25.0
	am.initial_velocity_min = 2.0
	am.initial_velocity_max = 4.0
	_aura.local_coords = false
	_aura.position = Vector3(0, -0.4, 0)
	_aura.emitting = false
	_model.add_child(_aura)

	# Poussière soulevée par les pieds quand on court.
	_dust = FX.particles(30, 0.7, 0.6, [Color(0.75, 0.7, 0.65, 0), Color(0.7, 0.65, 0.6, 0.45), Color(0.6, 0.55, 0.5, 0)], [0.0, 0.2, 1.0])
	((_dust.draw_pass_1 as QuadMesh).material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var dm := _dust.process_material as ParticleProcessMaterial
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(0.3, 0.05, 0.3)
	dm.direction = Vector3(0, 1, 0)
	dm.spread = 50.0
	dm.initial_velocity_min = 0.5
	dm.initial_velocity_max = 1.5
	dm.gravity = Vector3(0, 0.5, 0)
	dm.damping_min = 1.0
	dm.damping_max = 2.0
	_dust.local_coords = false
	_dust.position = Vector3(0, 0.1, 0)
	_dust.emitting = false
	add_child(_dust)


func _add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


func _sphere_mesh(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


func _build_camera() -> void:
	_yaw = Node3D.new()
	_yaw.position = Vector3(0, 1.6, 0)
	add_child(_yaw)
	_pitch = Node3D.new()
	_yaw.add_child(_pitch)
	_spring = SpringArm3D.new()
	_spring.spring_length = 5.0
	_spring.margin = 0.3
	_spring.collision_mask = 1
	_spring.position = Vector3(0.75, 0.2, 0)  # caméra par-dessus l'épaule droite
	_spring.add_excluded_object(get_rid())
	_pitch.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 1500.0
	_spring.add_child(camera)
	camera.current = true


# ---------------------------------------------------------------------------
# Entrées
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw.rotation.y -= motion.relative.x * mouse_sensitivity
		_pitch.rotation.x = clampf(_pitch.rotation.x - motion.relative.y * mouse_sensitivity, -1.35, 1.25)
	elif event.is_action_pressed("toggle_fly"):
		_set_flying(not flying)


# ---------------------------------------------------------------------------
# Boucle principale
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprint := Input.is_action_pressed("sprint")

	if flying:
		_fly(delta, input, sprint)
	else:
		_walk(delta, input, sprint)

	var pre_velocity := velocity
	velocity += _push
	move_and_slide()
	velocity -= _push
	_push = _push.lerp(Vector3.ZERO, clampf(delta * 3.0, 0.0, 1.0))
	_smash_through(pre_velocity)

	if global_position.y < -40.0:
		_respawn()

	_update_powers(delta)
	_update_interaction(delta)
	_update_regen(delta)


func _walk(delta: float, input: Vector2, sprint: bool) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_velocity
		else:
			_set_flying(true)  # sauter en l'air = s'envoler
			return
	var yaw_basis := _yaw.global_transform.basis
	var dir := yaw_basis * Vector3(input.x, 0, input.y)
	dir.y = 0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var target := dir * (sprint_speed if sprint else walk_speed)
	var accel := 12.0 if is_on_floor() else 3.0
	var w := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, target.x, w)
	velocity.z = lerpf(velocity.z, target.z, w)


func _fly(delta: float, input: Vector2, sprint: bool) -> void:
	var cam_basis := camera.global_transform.basis
	var dir := (-cam_basis.z) * -input.y + cam_basis.x * input.x
	var vertical := 0.0
	if Input.is_action_pressed("jump"):
		vertical += 1.0
	if Input.is_action_pressed("descend"):
		vertical -= 1.0
	dir += Vector3.UP * vertical
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * (fly_boost_speed if sprint else fly_speed)
	velocity = velocity.lerp(target, 1.0 - exp(-3.0 * delta))
	# Atterrir : descendre jusqu'au sol.
	if is_on_floor() and vertical < 0.0:
		_set_flying(false)


## En vol turbo, foncer dans un pilier le fait exploser et on passe à travers.
func _smash_through(pre_velocity: Vector3) -> void:
	if not flying or pre_velocity.length() < SMASH_SPEED:
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var other := hit.get_collider()
		if other != null and other.has_method("shatter"):
			other.shatter(hit.get_position(), pre_velocity)
			velocity = pre_velocity * 0.85  # on garde presque toute sa vitesse
			add_shake(0.6)
			return


func _set_flying(value: bool) -> void:
	if flying == value:
		return
	flying = value
	if flying:
		velocity.y = maxf(velocity.y, 4.0)
	_aura.emitting = flying
	flight_changed.emit(flying)


# ---------------------------------------------------------------------------
# Pouvoirs
# ---------------------------------------------------------------------------
func _update_powers(delta: float) -> void:
	_fire_timer -= delta
	black_hole_cd = maxf(black_hole_cd - delta, 0.0)
	shockwave_cd = maxf(shockwave_cd - delta, 0.0)

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if Input.is_action_pressed("fire") and _fire_timer <= 0.0 and energy >= FIREBALL_COST:
		_cast_fireball()
	if Input.is_action_just_pressed("black_hole"):
		if not black_hole_unlocked:
			power_locked.emit("Trou noir", BLACK_HOLE_LEVEL)
		elif black_hole_cd <= 0.0 and energy >= BLACK_HOLE_COST:
			_cast_black_hole()
	if Input.is_action_just_pressed("shockwave"):
		if not shockwave_unlocked:
			power_locked.emit("Onde de choc", SHOCKWAVE_LEVEL)
		elif shockwave_cd <= 0.0 and energy >= SHOCKWAVE_COST:
			_cast_shockwave()


## Point visé au centre de l'écran (ce qui est sous le viseur).
func _aim_point(max_dist := 250.0) -> Vector3:
	var center := get_viewport().get_visible_rect().size * 0.5
	var ray_dir := camera.project_ray_normal(center)
	# Le rayon part au niveau du joueur, pour ne pas toucher ce qui est derrière lui.
	var from := camera.project_ray_origin(center) + ray_dir * _spring.get_hit_length()
	var to := from + ray_dir * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	return hit["position"]


func _cast_fireball() -> void:
	_fire_timer = FIREBALL_RATE
	_use_energy(FIREBALL_COST)
	var i := _next_hand
	_next_hand = 1 - _next_hand
	_arm_raise[i] = 1.0
	_hand_lights[i].light_energy = 4.0

	var target := _aim_point()
	var shoulder := _arms[i].global_position
	var aim := (target - shoulder).normalized()
	var origin := shoulder + aim * 0.85

	var p := Projectile.new()
	p.velocity = (target - origin).normalized() * 42.0 + velocity * 0.3
	p.color = power_color
	p.damage = 18.0 * damage_mult
	p.splash_damage = 10.0 * damage_mult
	p.splash_radius = 3.5
	p.splash_impulse = 10.0
	p.collision_mask = 1 | 4 | 16
	p.target_groups = ["enemies", "civilians", "cars"]
	p.shooter = self
	get_parent().add_child(p)
	p.global_position = origin
	add_shake(0.04)


func _cast_black_hole() -> void:
	black_hole_cd = BLACK_HOLE_COOLDOWN
	_use_energy(BLACK_HOLE_COST)
	_both_arms = 1.0
	for l in _hand_lights:
		l.light_energy = 6.0

	# Placé là où on vise, entre 8 et 40 m, et jamais collé au sol.
	var from := global_position + Vector3.UP * 1.5
	var target := _aim_point(40.0)
	var offset := target - from
	var dist: float = clampf(offset.length() - 2.0, 8.0, 40.0)
	var pos := from + offset.normalized() * dist
	pos.y = maxf(pos.y, 3.0)

	var bh := BlackHole.new()
	bh.shooter = self
	bh.power = black_hole_power
	get_parent().add_child(bh)
	bh.global_position = pos


func _cast_shockwave() -> void:
	shockwave_cd = SHOCKWAVE_COOLDOWN
	_use_energy(SHOCKWAVE_COST)
	_both_arms = 1.0
	var sw := Shockwave.new()
	sw.shooter = self
	sw.color = power_color.lightened(0.2)
	sw.damage = 25.0 * damage_mult
	get_parent().add_child(sw)
	sw.global_position = global_position + Vector3.UP * 1.0


func _use_energy(amount: float) -> void:
	energy = maxf(energy - amount, 0.0)
	energy_changed.emit(energy, max_energy)


func add_energy(amount: float) -> void:
	energy = minf(energy + amount, max_energy)
	energy_changed.emit(energy, max_energy)


func _update_regen(delta: float) -> void:
	if energy < max_energy:
		add_energy(ENERGY_REGEN * delta)
	_since_damage += delta
	if _since_damage > 4.0 and health < max_health:
		health = minf(health + HEALTH_REGEN * delta, max_health)
		health_changed.emit(health, max_health)


# ---------------------------------------------------------------------------
# Interactions : absorber l'électricité, soigner ou absorber un civil blessé
# ---------------------------------------------------------------------------
func _update_interaction(delta: float) -> void:
	interaction_prompt = ""
	var hand := _arms[0].global_position + (-_model.global_transform.basis.z) * 0.6
	var busy := false

	# 1) Un civil blessé à côté : soigner (R) ou absorber sa vie (T).
	var civ := _closest_downed_civilian()
	if civ != null:
		interaction_prompt = "R (maintenir) : soigner        T (maintenir) : absorber sa vie"
		var healing := Input.is_action_pressed("drain")
		var leeching := Input.is_action_pressed("leech")
		if healing or leeching:
			busy = true
			if civ != _help_target:
				_help_target = civ
				_help_time = 0.0
			_help_time += delta
			interaction_progress = clampf(_help_time / HELP_TIME, 0.0, 1.0)
			_beam.set_color(Color(0.4, 1.0, 0.6) if healing else Color(1.0, 0.1, 0.1))
			_beam.set_points(hand, civ.global_position + Vector3.UP * 0.4)
			_arm_raise[0] = 1.0
			if _help_time >= HELP_TIME:
				if healing:
					civ.heal()
					FX.notify(get_tree(), "on_civilian_healed", [civ.global_position])
				else:
					civ.leech()
					add_energy(max_energy)
					health = max_health
					health_changed.emit(health, max_health)
					FX.notify(get_tree(), "on_civilian_leeched", [civ.global_position])
				_help_target = null
				_help_time = 0.0
				interaction_progress = 0.0

	# 2) Sinon : absorber l'électricité d'une source proche (R).
	if not busy and civ == null:
		_help_target = null
		_help_time = 0.0
		interaction_progress = 0.0
		var source := _closest_energy_source()
		if source != null:
			if energy < max_energy:
				interaction_prompt = "R (maintenir) : absorber l'électricité"
			if Input.is_action_pressed("drain") and energy < max_energy:
				busy = true
				var got: float = source.drain(DRAIN_RATE * delta)
				add_energy(got)
				_beam.set_color(power_color.lightened(0.3))
				_beam.set_points(source.get_drain_point(), hand)
				_arm_raise[0] = 1.0
				_hand_lights[0].light_energy = 5.0
				add_shake(0.01)

	if not busy:
		_beam.hide_beam()
		if civ == null:
			interaction_progress = 0.0


func _closest_downed_civilian() -> Node3D:
	var best: Node3D = null
	var best_d := HELP_RANGE
	for c in get_tree().get_nodes_in_group("civilians"):
		var n := c as Node3D
		if n == null or not n.has_method("is_downed") or not n.is_downed():
			continue
		var d := n.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _closest_energy_source() -> Node3D:
	var best: Node3D = null
	var best_d := DRAIN_RANGE
	for s in get_tree().get_nodes_in_group("energy_source"):
		var n := s as Node3D
		if n == null or not n.has_energy():
			continue
		var d := n.get_drain_point().distance_to(global_position + Vector3.UP)
		if d < best_d:
			best_d = d
			best = n
	return best


# ---------------------------------------------------------------------------
# Karma et améliorations
# ---------------------------------------------------------------------------
func set_power_color(c: Color) -> void:
	power_color = c
	if _eye_mat != null:
		_eye_mat.emission = c
	for m in _hand_mats:
		m.emission = c
	for l in _hand_lights:
		l.light_color = c
	if _aura != null:
		var am := _aura.process_material as ParticleProcessMaterial
		am.color_ramp = FX.gradient_texture([Color(c.r, c.g, c.b, 0), Color(c.r, c.g, c.b, 0.8), Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, 0)], [0.0, 0.3, 1.0])


func full_heal() -> void:
	health = max_health
	energy = max_energy
	health_changed.emit(health, max_health)
	energy_changed.emit(energy, max_energy)


# ---------------------------------------------------------------------------
# Dégâts
# ---------------------------------------------------------------------------
func take_damage(amount: float, _from: Vector3, _silent := false, _attacker: Node = null) -> void:
	health -= amount
	_since_damage = 0.0
	add_shake(0.25)
	health_changed.emit(maxf(health, 0.0), max_health)
	damaged.emit()
	if health <= 0.0:
		_respawn()


func apply_push(v: Vector3) -> void:
	_push += v * 0.3


func _respawn() -> void:
	health = max_health
	energy = max_energy
	velocity = Vector3.ZERO
	_push = Vector3.ZERO
	global_position = respawn_point
	_set_flying(false)
	health_changed.emit(health, max_health)
	energy_changed.emit(energy, max_energy)
	died.emit()


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.2)


# ---------------------------------------------------------------------------
# Animation procédurale (pas besoin de fichiers d'animation)
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_anim_time += delta
	var cam_yaw := _yaw.rotation.y
	var aim_pitch := _pitch.rotation.x
	var hvel := Vector3(velocity.x, 0, velocity.z)
	var local_vel := hvel.rotated(Vector3.UP, -cam_yaw)
	var speed := velocity.length()

	# Le personnage se tourne toujours vers où regarde la caméra.
	_model.rotation.y = lerp_angle(_model.rotation.y, cam_yaw, clampf(delta * 12.0, 0.0, 1.0))

	# Inclinaison du corps : penché en avant en vol, selon la vitesse.
	var tilt := 0.0
	var roll := 0.0
	var bob := 0.0
	if flying:
		tilt = clampf(-local_vel.z / fly_boost_speed, -0.4, 1.0) * 1.1
		roll = clampf(-local_vel.x / fly_speed, -1.0, 1.0) * 0.35
		bob = sin(_anim_time * 2.5) * 0.08
	_model.rotation.x = lerpf(_model.rotation.x, -tilt, clampf(delta * 6.0, 0.0, 1.0))
	_model.rotation.z = lerpf(_model.rotation.z, roll, clampf(delta * 6.0, 0.0, 1.0))
	_model.position.y = 1.0 + bob

	# Jambes : marche au sol, tendues vers l'arrière en vol.
	var stride := 0.0
	if not flying and is_on_floor():
		stride = sin(_anim_time * (6.0 + hvel.length())) * clampf(hvel.length() / sprint_speed, 0.0, 1.0) * 0.8
	for i in _legs.size():
		var target_leg := -0.35 + sin(_anim_time * 3.0 + i) * 0.1 if flying else stride * (1.0 if i == 0 else -1.0)
		_legs[i].rotation.x = lerpf(_legs[i].rotation.x, target_leg, clampf(delta * 10.0, 0.0, 1.0))

	# Bras : levés vers la cible quand on lance un sort, sinon ballants.
	for i in _arms.size():
		_arm_raise[i] = maxf(_arm_raise[i] - delta * 2.5, 0.0)
		var raise: float = maxf(_arm_raise[i], _both_arms)
		var idle := -0.15 + sin(_anim_time * 2.0 + i) * 0.05
		if not flying:
			idle -= stride * (1.0 if i == 0 else -1.0) * 0.6
		else:
			idle = 0.35  # bras un peu en arrière en vol
		var aimed := PI * 0.5 + aim_pitch
		var target_arm: float = lerpf(idle, aimed, clampf(raise * 1.6, 0.0, 1.0))
		_arms[i].rotation.x = lerpf(_arms[i].rotation.x, target_arm, clampf(delta * 18.0, 0.0, 1.0))
		_hand_lights[i].light_energy = maxf(_hand_lights[i].light_energy - delta * 12.0, 0.6 if raise > 0.0 else 0.0)
		_hand_mats[i].emission_energy_multiplier = 1.0 + _hand_lights[i].light_energy * 1.5
	_both_arms = maxf(_both_arms - delta * 2.0, 0.0)

	# Cape : flotte selon la vitesse.
	var cape_angle: float = clampf(speed * 0.05, 0.08, 1.35) + sin(_anim_time * 7.0) * 0.05 * clampf(speed * 0.1, 0.2, 1.0)
	_cape.rotation.x = lerpf(_cape.rotation.x, -cape_angle, clampf(delta * 8.0, 0.0, 1.0))

	# Effet de vitesse : léger en courant, fort en vol rapide.
	var target_fx := 0.0
	if flying:
		target_fx = clampf((speed - fly_speed) / (fly_boost_speed - fly_speed), 0.0, 1.0)
	elif is_on_floor() and Input.is_action_pressed("sprint"):
		target_fx = clampf((hvel.length() - walk_speed) / (sprint_speed - walk_speed), 0.0, 1.0) * 0.45
	speed_effect = lerpf(speed_effect, target_fx, clampf(delta * 5.0, 0.0, 1.0))
	_dust.emitting = not flying and is_on_floor() and hvel.length() > walk_speed + 1.0

	# Caméra : champ de vision plus large avec la vitesse + tremblement.
	camera.fov = lerpf(camera.fov, 75.0 + speed_effect * 22.0, clampf(delta * 4.0, 0.0, 1.0))
	if speed_effect > 0.6:
		_shake = maxf(_shake, (speed_effect - 0.6) * 0.5)
	_shake = maxf(_shake - delta * 2.5, 0.0)
	var s := _shake * _shake
	camera.h_offset = randf_range(-1.0, 1.0) * s * 0.6
	camera.v_offset = randf_range(-1.0, 1.0) * s * 0.6
