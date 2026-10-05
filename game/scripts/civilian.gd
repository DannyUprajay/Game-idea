extends CharacterBody3D
## Civil : se promène, fuit les combats. Blessé, il attend qu'on le soigne
## (karma +) ou qu'on absorbe son énergie (karma -). Le tuer fait baisser le karma.

const FX = preload("res://scripts/fx.gd")
const PersonModel = preload("res://scripts/person_model.gd")

enum State { WANDER, FLEE, DOWNED, DEAD }

var state := State.WANDER
## Apparaît déjà blessé (à soigner).
var start_downed := false
var health := 30.0

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _flee_from := Vector3.ZERO
var _flee_time := 0.0
var _repath := 0.0
var _push := Vector3.ZERO
var _model: PersonModel
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _time := 0.0

const SHIRTS := [Color(0.75, 0.3, 0.25), Color(0.25, 0.45, 0.75), Color(0.85, 0.75, 0.3),
	Color(0.3, 0.6, 0.35), Color(0.6, 0.6, 0.6), Color(0.5, 0.3, 0.6), Color(0.9, 0.5, 0.2)]


func _ready() -> void:
	add_to_group("civilians")
	collision_layer = 16
	collision_mask = 1
	_home = global_position
	_target = global_position

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.875, 0)
	add_child(col)

	_model = PersonModel.new()
	_model.shirt_color = SHIRTS[randi() % SHIRTS.size()]
	_model.pants_color = Color(randf_range(0.1, 0.35), randf_range(0.1, 0.3), randf_range(0.15, 0.4))
	_model.skin_color = Color(0.85, 0.68, 0.55).darkened(randf_range(0.0, 0.55))
	if randf() < 0.6:
		_model.head_color = Color(randf_range(0.05, 0.5), randf_range(0.03, 0.35), randf_range(0.0, 0.2))
	add_child(_model)

	# Croix verte au-dessus des blessés.
	_marker_mat = FX.emissive_material(Color(0.3, 1.0, 0.45), 3.0)
	_marker = MeshInstance3D.new()
	var plus := BoxMesh.new()
	plus.size = Vector3(0.5, 0.15, 0.15)
	_marker.mesh = plus
	_marker.material_override = _marker_mat
	var vertical := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.15, 0.5, 0.15)
	vertical.mesh = vm
	vertical.material_override = _marker_mat
	_marker.add_child(vertical)
	_marker.position = Vector3(0, 1.4, 0)
	_marker.visible = false
	add_child(_marker)

	if start_downed:
		_go_down()


func _physics_process(delta: float) -> void:
	_time += delta
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.5

	var move := Vector3.ZERO
	var speed := 0.0
	match state:
		State.WANDER:
			_repath -= delta
			var to_target := _target - global_position
			to_target.y = 0
			if to_target.length() < 1.0 or _repath <= 0.0 or is_on_wall():
				_pick_wander_target()
			move = to_target.normalized()
			speed = 1.8
		State.FLEE:
			_flee_time -= delta
			var away := global_position - _flee_from
			away.y = 0
			if is_on_wall():
				away = away.rotated(Vector3.UP, PI * 0.5)
			move = away.normalized()
			speed = 6.0
			if _flee_time <= 0.0:
				state = State.WANDER
				_home = global_position
				_pick_wander_target()
		State.DOWNED:
			_marker.visible = true
			_marker.position.y = 1.2 + sin(_time * 3.0) * 0.15
			_marker.rotation.y += delta * 2.0
		State.DEAD:
			pass

	velocity.x = move.x * speed + _push.x
	velocity.z = move.z * speed + _push.z
	if _push.y > 0.0:
		velocity.y = _push.y
	_push = _push.lerp(Vector3.ZERO, clampf(delta * 4.0, 0.0, 1.0))
	move_and_slide()

	if move.length() > 0.1:
		var yaw := atan2(-move.x, -move.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))
	_model.animate(Vector2(velocity.x, velocity.z).length(), delta)
	if state == State.FLEE:
		_model.panic_arms()


func _pick_wander_target() -> void:
	_repath = randf_range(4.0, 9.0)
	_target = _home + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))


## Appelé par les explosions proches : le civil s'enfuit.
func scare(from: Vector3, radius: float) -> void:
	if state == State.DOWNED or state == State.DEAD:
		return
	if global_position.distance_to(from) > radius:
		return
	state = State.FLEE
	_flee_from = from
	_flee_time = randf_range(4.0, 7.0)


func take_damage(amount: float, from: Vector3, silent := false, attacker: Node = null) -> void:
	if state == State.DEAD:
		return
	var by_player := attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player")
	health -= amount
	if not silent:
		_model.flash(Color(1, 0.3, 0.2))
	scare(from, 999.0)
	if health > 0.0:
		return
	if by_player:
		_die()
		FX.notify(get_tree(), "on_civilian_killed", [global_position])
	elif state != State.DOWNED:
		_go_down()


func apply_push(v: Vector3) -> void:
	if state != State.DEAD:
		_push += v * 0.5


func apply_pull(v: Vector3) -> void:
	_push += v


## Peut-on interagir avec lui (soigner / absorber) ?
func is_downed() -> bool:
	return state == State.DOWNED


func heal() -> void:
	if state != State.DOWNED:
		return
	state = State.WANDER
	health = 30.0
	_marker.visible = false
	_model.stand_up()
	_model.flash(Color(0.4, 0.8, 1.0))
	_home = global_position
	_pick_wander_target()


func leech() -> void:
	if state != State.DOWNED:
		return
	_model.flash(Color(1.0, 0.1, 0.1))
	_die()


func _go_down() -> void:
	state = State.DOWNED
	health = 0.0
	_model.lie_down()
	_marker.visible = true


func _die() -> void:
	state = State.DEAD
	_marker.visible = false
	remove_from_group("civilians")
	collision_layer = 0
	_model.lie_down()
	get_tree().create_timer(15.0).timeout.connect(queue_free)
