extends CharacterBody3D
## Soldat ennemi : patrouille, puis tire des rafales sur le joueur dès qu'il le voit.

const FX = preload("res://scripts/fx.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Explosion = preload("res://scripts/explosion.gd")
const PersonModel = preload("res://scripts/person_model.gd")

var max_health := 50.0
var health := 50.0
var xp_value := 20
var sight_range := 50.0

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _repath := 0.0
var _burst_left := 0
var _burst_timer := 0.0
var _cooldown := 2.0
var _strafe := 1.0
var _push := Vector3.ZERO
var _dead := false
var _in_combat := false
var _model: PersonModel


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 4
	health = max_health
	_home = global_position
	_target = global_position
	_cooldown = randf_range(1.0, 3.0)
	_strafe = 1.0 if randf() < 0.5 else -1.0

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	_model = PersonModel.new()
	_model.shirt_color = Color(0.45, 0.08, 0.1)
	_model.pants_color = Color(0.12, 0.12, 0.14)
	_model.head_color = Color(0.15, 0.15, 0.17)
	_model.eye_color = Color(1.0, 0.2, 0.15)
	add_child(_model)

	# Arme : un petit canon tenu dans la main droite.
	var gun := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.1, 0.12, 0.6)
	gun.mesh = gm
	gun.material_override = FX.solid_material(Color(0.1, 0.1, 0.1), 0.4, 0.8)
	gun.position = Vector3(0.31, 1.25, -0.45)
	_model.add_child(gun)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.5

	var player := _find_player()
	var move := Vector3.ZERO
	var speed := 0.0
	_in_combat = false

	if player != null:
		var to_player := player.global_position - global_position
		var dist := to_player.length()
		if dist < sight_range and _can_see(player):
			_in_combat = true
			var flat := Vector3(to_player.x, 0, to_player.z).normalized()
			# Garde ses distances et se déplace sur le côté.
			if dist > 26.0:
				move = flat
			elif dist < 12.0:
				move = -flat
			else:
				move = flat.cross(Vector3.UP) * _strafe
			speed = 3.5
			if is_on_wall():
				_strafe = -_strafe
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-flat.x, -flat.z), clampf(delta * 10.0, 0.0, 1.0))
			_update_shooting(delta, player)

	if not _in_combat:
		_repath -= delta
		var to_target := _target - global_position
		to_target.y = 0
		if to_target.length() < 1.0 or _repath <= 0.0 or is_on_wall():
			_repath = randf_range(3.0, 7.0)
			_target = _home + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		move = to_target.normalized()
		speed = 1.6
		if move.length() > 0.1:
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-move.x, -move.z), clampf(delta * 6.0, 0.0, 1.0))

	velocity.x = move.x * speed + _push.x
	velocity.z = move.z * speed + _push.z
	if _push.y > 0.0:
		velocity.y = _push.y
	_push = _push.lerp(Vector3.ZERO, clampf(delta * 4.0, 0.0, 1.0))
	move_and_slide()

	_model.aiming = _in_combat
	_model.animate(Vector2(velocity.x, velocity.z).length(), delta)


func _can_see(player: Node3D) -> bool:
	var from := global_position + Vector3.UP * 1.6
	var to := player.global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _update_shooting(delta: float, player: Node3D) -> void:
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = 0.12
			_burst_left -= 1
			_fire(player)
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_cooldown = randf_range(1.6, 2.8)
		_burst_left = 3


func _fire(player: Node3D) -> void:
	var origin := global_position + Vector3.UP * 1.3 + (-_model.global_transform.basis.z) * 0.8
	var target := player.global_position + Vector3.UP * 1.0
	# Visée imparfaite : plus le joueur est loin ou rapide, plus c'est dur.
	var spread := 0.6 + player.global_position.distance_to(origin) * 0.03
	target += Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)) * spread
	var p := Projectile.new()
	p.is_bullet = true
	p.velocity = (target - origin).normalized() * 70.0
	p.color = Color(1.0, 0.75, 0.3)
	p.radius = 0.06
	p.damage = 4.0
	p.splash_damage = 0.0
	p.life = 1.5
	p.collision_mask = 1 | 2 | 16
	p.target_groups = ["player", "civilians"]
	p.shooter = self
	get_parent().add_child(p)
	p.global_position = origin


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D


func take_damage(amount: float, _from: Vector3, silent := false, _attacker: Node = null) -> void:
	if _dead:
		return
	health -= amount
	if not silent:
		_model.flash(Color(1, 1, 1))
	_in_combat = true
	if health <= 0.0:
		_die()


func apply_push(v: Vector3) -> void:
	_push += v * 0.6


func apply_pull(v: Vector3) -> void:
	_push += v


func _die() -> void:
	_dead = true
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 1
	_model.lie_down()
	var boom := Explosion.new()
	boom.color = Color(1.0, 0.3, 0.2)
	boom.size = 0.5
	boom.light_only = true
	get_parent().add_child(boom)
	boom.global_position = global_position + Vector3.UP
	FX.notify(get_tree(), "on_enemy_killed", [xp_value, global_position])
	get_tree().create_timer(8.0).timeout.connect(queue_free)
