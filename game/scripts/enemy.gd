extends CharacterBody3D
## Drone ennemi : vole autour du joueur et lui tire des orbes rouges.

signal killed

const FX = preload("res://scripts/fx.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Explosion = preload("res://scripts/explosion.gd")
const Debris = preload("res://scripts/debris.gd")

var max_health := 40.0
var health := 40.0
var speed := 7.0
var fire_interval := 3.0

var _push := Vector3.ZERO
var _fire_cd := 0.0
var _flash := 0.0
var _dead := false
var _phase := 0.0
var _orbit_side := 1.0
var _visual: Node3D
var _ring: MeshInstance3D
var _body_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _eye_light: OmniLight3D


func _ready() -> void:
	add_to_group("enemies")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1 | 4
	health = max_health
	_fire_cd = randf_range(1.5, fire_interval + 1.5)
	_phase = randf() * TAU
	_orbit_side = 1.0 if randf() < 0.5 else -1.0

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	add_child(shape)

	_visual = Node3D.new()
	add_child(_visual)

	_body_mat = FX.solid_material(Color(0.16, 0.17, 0.2), 0.35, 0.8)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(1, 1, 1)
	_body_mat.emission_energy_multiplier = 0.0
	var body := FX.sphere(0.7, _body_mat, 24)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual.add_child(body)

	# Anneau qui tourne autour du corps.
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = FX.emissive_material(Color(1.0, 0.25, 0.15), 2.5)
	_visual.add_child(_ring)

	# L'œil, face à l'avant (-Z).
	_eye_mat = FX.emissive_material(Color(1.0, 0.15, 0.1), 3.0)
	var eye := FX.sphere(0.22, _eye_mat, 16)
	eye.position = Vector3(0, 0.05, -0.6)
	_visual.add_child(eye)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(1.0, 0.2, 0.1)
	_eye_light.light_energy = 0.8
	_eye_light.omni_range = 4.0
	_eye_light.position = Vector3(0, 0, -0.9)
	_visual.add_child(_eye_light)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_phase += delta
	var player := _find_player()
	var desired := Vector3.ZERO

	if player != null:
		var target := player.global_position + Vector3.UP * (3.0 + sin(_phase * 1.3) * 1.5)
		var to_player := target - global_position
		var dist := to_player.length()
		var dir := to_player / maxf(dist, 0.01)
		if dist > 18.0:
			desired = dir
		elif dist < 9.0:
			desired = -dir
		else:
			# Tourne autour du joueur.
			desired = dir.cross(Vector3.UP).normalized() * _orbit_side + dir * 0.15
		desired.y += clampf(to_player.y * 0.2, -1.0, 1.0)

		# Regarde le joueur.
		var look_target := player.global_position + Vector3.UP * 1.2
		if global_position.distance_to(look_target) > 0.5:
			var wanted := _visual.global_transform.looking_at(look_target, Vector3.UP)
			var current := _visual.global_transform.basis.orthonormalized()
			var b := current.slerp(wanted.basis.orthonormalized(), clampf(delta * 6.0, 0.0, 1.0))
			_visual.global_transform = Transform3D(b, _visual.global_position)

		_update_shooting(delta, player, dist)

	velocity = velocity.lerp(desired * speed, clampf(delta * 2.0, 0.0, 1.0)) + _push
	_push = _push.lerp(Vector3.ZERO, clampf(delta * 2.5, 0.0, 1.0))
	if global_position.y < 1.5 and velocity.y < 0.0:
		velocity.y = absf(velocity.y) * 0.5
	move_and_slide()
	velocity -= _push

	_ring.rotate_object_local(Vector3.FORWARD, delta * 4.0)
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_body_mat.emission_energy_multiplier = _flash * 3.0


func _update_shooting(delta: float, player: Node3D, dist: float) -> void:
	_fire_cd -= delta
	# L'œil s'illumine juste avant le tir : le joueur peut anticiper.
	var charge: float = clampf(1.0 - _fire_cd / 0.8, 0.0, 1.0)
	_eye_mat.emission_energy_multiplier = 3.0 + charge * 10.0
	_eye_light.light_energy = 0.8 + charge * 4.0
	if _fire_cd > 0.0:
		return
	_fire_cd = fire_interval + randf_range(-0.5, 1.0)
	if dist > 45.0:
		return
	var origin := global_position + (-_visual.global_transform.basis.z) * 1.0
	var aim := (player.global_position + Vector3.UP * 1.0 - origin).normalized()
	var p := Projectile.new()
	p.velocity = aim * 20.0
	p.color = Color(1.0, 0.15, 0.2)
	p.radius = 0.25
	p.damage = 8.0
	p.splash_damage = 4.0
	p.splash_radius = 2.0
	p.splash_impulse = 6.0
	p.explosion_size = 0.6
	p.collision_mask = 1 | 2
	p.target_group = "player"
	p.shooter = self
	p.life = 4.0
	get_parent().add_child(p)
	p.global_position = origin


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D


func take_damage(amount: float, from: Vector3, silent := false) -> void:
	if _dead:
		return
	health -= amount
	if not silent:
		_flash = 1.0
		_push += (global_position - from).normalized() * minf(amount * 0.2, 6.0)
	if health <= 0.0:
		_die()


func apply_push(v: Vector3) -> void:
	_push += v * 0.6


func apply_pull(v: Vector3) -> void:
	_push += v


func _die() -> void:
	_dead = true
	var boom := Explosion.new()
	boom.color = Color(1.0, 0.4, 0.15)
	boom.size = 1.8
	get_parent().add_child(boom)
	boom.global_position = global_position
	_break_into_pieces()
	FX.shake_cameras(get_tree(), global_position, 0.45)
	killed.emit()
	queue_free()


## Le drone se brise : éclats de coque, morceaux de l'anneau et de l'œil.
func _break_into_pieces() -> void:
	var metal := FX.solid_material(Color(0.16, 0.17, 0.2), 0.35, 0.8)
	var glow := FX.emissive_material(Color(1.0, 0.25, 0.15), 3.0)
	var parent := get_parent()
	for i in 12:
		var d := Debris.new()
		var glowing := i < 4
		if glowing:
			d.size = Vector3(randf_range(0.1, 0.2), randf_range(0.1, 0.2), randf_range(0.3, 0.5))
		else:
			d.size = Vector3(randf_range(0.25, 0.5), randf_range(0.08, 0.16), randf_range(0.25, 0.5))
		d.material = glow if glowing else metal
		d.life = randf_range(4.0, 6.0)
		# Un éclat sur trois traîne du feu et de la fumée.
		if i % 3 == 0:
			d.trail_color = Color(1.0, 0.45, 0.1)
		parent.add_child(d)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized()
		d.global_position = global_position + dir * 0.4
		d.linear_velocity = dir * randf_range(6.0, 15.0) + Vector3.UP * 3.0 + _push * 0.5
		d.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 12.0
