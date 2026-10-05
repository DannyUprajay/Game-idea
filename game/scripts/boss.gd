extends CharacterBody3D
## Le Colosse : drone géant, boss final. Tire des salves, des anneaux d'orbes,
## et appelle des drones en renfort.

signal health_changed(value: float, max_value: float)
signal defeated

const FX = preload("res://scripts/fx.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Explosion = preload("res://scripts/explosion.gd")
const Debris = preload("res://scripts/debris.gd")
const Drone = preload("res://scripts/enemy.gd")

var max_health := 2500.0
var health := 2500.0

var _time := 0.0
var _volley_cd := 3.0
var _ring_cd := 9.0
var _summon_cd := 14.0
var _push := Vector3.ZERO
var _dead := false
var _flash := 0.0
var _visual: Node3D
var _body_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _rings: Array[MeshInstance3D] = []
var _eyes: Array[Node3D] = []


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1
	health = max_health

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.6
	col.shape = sphere
	add_child(col)

	_visual = Node3D.new()
	add_child(_visual)
	_body_mat = FX.solid_material(Color(0.12, 0.12, 0.15), 0.3, 0.9)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(1, 1, 1)
	_body_mat.emission_energy_multiplier = 0.0
	var body := FX.sphere(3.4, _body_mat, 32)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual.add_child(body)

	# Plaques d'armure.
	for i in 6:
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(2.2, 0.4, 1.4)
		plate.mesh = pm
		plate.material_override = FX.solid_material(Color(0.3, 0.08, 0.08), 0.4, 0.7)
		var a := TAU * i / 6.0
		plate.position = Vector3(cos(a) * 3.3, 0.6 * (1 if i % 2 == 0 else -1), sin(a) * 3.3)
		plate.rotation.y = -a
		_visual.add_child(plate)

	# Trois yeux rouges à l'avant.
	_eye_mat = FX.emissive_material(Color(1.0, 0.1, 0.05), 5.0)
	for x in [-1.1, 0.0, 1.1]:
		var eye := FX.sphere(0.5 if x == 0.0 else 0.32, _eye_mat, 16)
		eye.position = Vector3(x, 0.4 if x == 0.0 else 0.0, -3.2)
		_visual.add_child(eye)
		_eyes.append(eye)

	for i in 2:
		var torus := TorusMesh.new()
		torus.inner_radius = 4.4 + i
		torus.outer_radius = 4.7 + i
		torus.rings = 64
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.material_override = FX.emissive_material(Color(1.0, 0.25, 0.1), 2.5)
		add_child(ring)
		_rings.append(ring)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.2, 0.1)
	light.light_energy = 6.0
	light.omni_range = 25.0
	add_child(light)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var desired := Vector3.ZERO
	if player != null:
		# Tourne autour du joueur à bonne distance, en hauteur.
		var orbit := Vector3(cos(_time * 0.25), 0, sin(_time * 0.25)) * 32.0
		var target := player.global_position + orbit + Vector3.UP * (18.0 + sin(_time * 0.7) * 5.0)
		desired = (target - global_position).limit_length(1.0) * 12.0
		var look_target := player.global_position + Vector3.UP
		var wanted := _visual.global_transform.looking_at(look_target, Vector3.UP)
		var b := _visual.global_transform.basis.orthonormalized().slerp(wanted.basis.orthonormalized(), clampf(delta * 2.5, 0.0, 1.0))
		_visual.global_transform = Transform3D(b, _visual.global_position)
		_attack(delta, player)

	velocity = velocity.lerp(desired, clampf(delta * 1.5, 0.0, 1.0)) + _push
	_push = _push.lerp(Vector3.ZERO, clampf(delta * 2.0, 0.0, 1.0))
	move_and_slide()
	velocity -= _push

	for i in _rings.size():
		_rings[i].rotation = Vector3(_time * (0.5 + i * 0.4), _time * 0.8, _time * 0.3 * (i + 1))
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_body_mat.emission_energy_multiplier = _flash * 2.0


func _attack(delta: float, player: Node3D) -> void:
	var rage := 1.0 if health > max_health * 0.5 else 1.6  # plus agressif à mi-vie
	_volley_cd -= delta * rage
	_ring_cd -= delta * rage
	_summon_cd -= delta * rage

	if _volley_cd <= 0.0:
		_volley_cd = 3.0
		for i in 5:
			get_tree().create_timer(i * 0.15).timeout.connect(func() -> void: _shoot_at(player))
	if _ring_cd <= 0.0:
		_ring_cd = 9.0
		for i in 16:
			var a := TAU * i / 16.0
			var dir := Vector3(cos(a), -0.25, sin(a)).normalized()
			_shoot(global_position + dir * 4.5, dir * 18.0)
	if _summon_cd <= 0.0:
		_summon_cd = 16.0
		for i in 2:
			var d := Drone.new()
			d.position = global_position + Vector3(randf_range(-6, 6), -2, randf_range(-6, 6))
			get_parent().add_child(d)


func _shoot_at(player: Node3D) -> void:
	if _dead or not is_instance_valid(player):
		return
	var eye: Node3D = _eyes[randi() % _eyes.size()]
	var origin := eye.global_position
	var aim := (player.global_position + Vector3.UP + Vector3(randf_range(-2, 2), randf_range(-1, 2), randf_range(-2, 2)) - origin).normalized()
	_shoot(origin, aim * 32.0)


func _shoot(origin: Vector3, vel: Vector3) -> void:
	var p := Projectile.new()
	p.velocity = vel
	p.color = Color(1.0, 0.15, 0.1)
	p.radius = 0.45
	p.damage = 12.0
	p.splash_damage = 8.0
	p.splash_radius = 3.0
	p.explosion_size = 0.9
	p.collision_mask = 1 | 2 | 16
	p.target_groups = ["player", "civilians"]
	p.shooter = self
	p.life = 5.0
	get_parent().add_child(p)
	p.global_position = origin


func take_damage(amount: float, _from: Vector3, silent := false, attacker: Node = null) -> void:
	if _dead:
		return
	if attacker == null or not is_instance_valid(attacker) or not attacker.is_in_group("player"):
		return
	health -= amount
	if not silent:
		_flash = 1.0
	health_changed.emit(maxf(health, 0.0), max_health)
	if health <= 0.0:
		_die()


func apply_push(v: Vector3) -> void:
	_push += v * 0.1


func apply_pull(v: Vector3) -> void:
	_push += v * 0.15


func _die() -> void:
	_dead = true
	remove_from_group("enemies")
	collision_layer = 0
	for i in 8:
		var offset := Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
		get_tree().create_timer(i * 0.2).timeout.connect(func() -> void: _boom(offset, 2.0 + randf() * 1.5))
	get_tree().create_timer(1.8).timeout.connect(_final_blast)


func _boom(offset: Vector3, size: float) -> void:
	var b := Explosion.new()
	b.color = Color(1.0, 0.4, 0.1)
	b.size = size
	get_parent().add_child(b)
	b.global_position = global_position + offset
	FX.shake_cameras(get_tree(), b.global_position, 0.6)


func _final_blast() -> void:
	_boom(Vector3.ZERO, 5.0)
	var metal := FX.solid_material(Color(0.12, 0.12, 0.15), 0.3, 0.9)
	var glow := FX.emissive_material(Color(1.0, 0.2, 0.1), 4.0)
	for i in 40:
		var d := Debris.new()
		d.size = Vector3(randf_range(0.5, 1.8), randf_range(0.3, 0.9), randf_range(0.5, 1.8))
		d.material = glow if i % 4 == 0 else metal
		d.life = randf_range(8.0, 12.0)
		if i % 3 == 0:
			d.trail_color = Color(1.0, 0.45, 0.1)
		get_parent().add_child(d)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)).normalized()
		d.global_position = global_position + dir * 2.5
		d.linear_velocity = dir * randf_range(10, 28)
		d.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 8.0
	FX.notify(get_tree(), "on_boss_killed", [global_position])
	defeated.emit()
	queue_free()
