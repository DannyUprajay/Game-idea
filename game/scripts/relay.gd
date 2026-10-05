extends StaticBody3D
## Relais ennemi : tour qui envoie des renforts. Objectif de mission : à détruire.

signal destroyed

const FX = preload("res://scripts/fx.gd")
const Explosion = preload("res://scripts/explosion.gd")
const Debris = preload("res://scripts/debris.gd")
const Soldier = preload("res://scripts/soldier.gd")
const Drone = preload("res://scripts/enemy.gd")

var max_health := 700.0
var health := 700.0
var relay_name := "Relais"
var xp_value := 200
var spawn_interval := 12.0
var max_spawned := 4

var _spawned: Array = []
var _spawn_timer := 3.0
var _dead := false
var _time := 0.0
var _core_mat: StandardMaterial3D
var _rings: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _label: Label3D
var _flash := 0.0


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("relays")
	collision_layer = 4
	health = max_health

	var metal := FX.solid_material(Color(0.18, 0.18, 0.2), 0.4, 0.8)
	_box_part(Vector3(7, 1.6, 7), metal, Vector3(0, 0.8, 0), true)
	_box_part(Vector3(2.2, 14, 2.2), metal, Vector3(0, 8.6, 0), true)
	for corner in [Vector3(2.8, 0, 2.8), Vector3(-2.8, 0, 2.8), Vector3(2.8, 0, -2.8), Vector3(-2.8, 0, -2.8)]:
		var strut := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.4, 0.4, 11)
		strut.mesh = sm
		strut.material_override = metal
		# Jambe de force inclinée entre le coin du socle et le haut du mât.
		var bottom: Vector3 = corner + Vector3(0, 1.5, 0)
		var top := Vector3(0, 11, 0)
		strut.transform = Transform3D(Basis(), (bottom + top) * 0.5).looking_at(top, Vector3.UP)
		add_child(strut)

	_core_mat = FX.emissive_material(Color(1.0, 0.15, 0.1), 5.0)
	var core := FX.sphere(1.6, _core_mat, 24)
	core.position = Vector3(0, 16.5, 0)
	add_child(core)
	var core_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.6
	core_shape.shape = sphere
	core_shape.position = core.position
	add_child(core_shape)

	for i in 3:
		var torus := TorusMesh.new()
		torus.inner_radius = 2.4 + i * 0.6
		torus.outer_radius = 2.6 + i * 0.6
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.material_override = FX.emissive_material(Color(1.0, 0.3, 0.15), 2.0)
		ring.position = Vector3(0, 16.5, 0)
		add_child(ring)
		_rings.append(ring)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.2, 0.1)
	_light.light_energy = 6.0
	_light.omni_range = 30.0
	_light.position = Vector3(0, 16.5, 0)
	add_child(_light)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 96
	_label.outline_size = 18
	_label.modulate = Color(1, 0.5, 0.4)
	_label.position = Vector3(0, 20.5, 0)
	add_child(_label)
	_update_label()


func _box_part(size: Vector3, mat: Material, pos: Vector3, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if solid:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		col.shape = box
		col.position = pos
		add_child(col)


func _process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	for i in _rings.size():
		_rings[i].rotation = Vector3(_time * (0.6 + i * 0.3), _time * (1.0 + i * 0.5), 0)
	_flash = maxf(_flash - delta * 5.0, 0.0)
	_core_mat.emission_energy_multiplier = 5.0 + sin(_time * 4.0) * 1.5 + _flash * 10.0
	_light.light_energy = 6.0 + sin(_time * 4.0) * 2.0

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		_try_spawn()


func _try_spawn() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player.global_position.distance_to(global_position) > 130.0:
		return
	_spawned = _spawned.filter(func(n: Node) -> bool: return is_instance_valid(n) and n.is_in_group("enemies"))
	if _spawned.size() >= max_spawned:
		return
	var e: Node3D
	if randf() < 0.65:
		e = Soldier.new()
		var angle := randf() * TAU
		e.position = global_position + Vector3(cos(angle) * 6.0, 1.7, sin(angle) * 6.0)
	else:
		e = Drone.new()
		e.position = global_position + Vector3(randf_range(-4, 4), 20.0, randf_range(-4, 4))
	get_parent().add_child(e)
	_spawned.append(e)


func _update_label() -> void:
	_label.text = "%s  %d%%" % [relay_name, ceili(health / max_health * 100.0)]


func take_damage(amount: float, _from: Vector3, _silent := false, attacker: Node = null) -> void:
	if _dead:
		return
	# Seul le joueur peut l'abîmer.
	if attacker == null or not is_instance_valid(attacker) or not attacker.is_in_group("player"):
		return
	health -= amount
	_flash = 1.0
	_update_label()
	if health <= 0.0:
		_destroy()


func _destroy() -> void:
	_dead = true
	remove_from_group("enemies")
	remove_from_group("relays")
	collision_layer = 0
	_label.visible = false
	# Série d'explosions de bas en haut.
	for i in 4:
		var timer := get_tree().create_timer(i * 0.25)
		var height := 2.0 + i * 4.5
		timer.timeout.connect(func() -> void: _boom(Vector3(0, height, 0), 1.8 + i * 0.4))
	get_tree().create_timer(1.0).timeout.connect(_scatter)
	FX.notify(get_tree(), "on_relay_destroyed", [xp_value, global_position])
	destroyed.emit()


func _boom(local: Vector3, size: float) -> void:
	var b := Explosion.new()
	b.color = Color(1.0, 0.35, 0.1)
	b.size = size
	get_parent().add_child(b)
	b.global_position = to_global(local)
	FX.shake_cameras(get_tree(), b.global_position, 0.8)


func _scatter() -> void:
	var metal := FX.solid_material(Color(0.18, 0.18, 0.2), 0.4, 0.8)
	var glow := FX.emissive_material(Color(1.0, 0.25, 0.1), 3.0)
	for i in 30:
		var d := Debris.new()
		d.size = Vector3(randf_range(0.4, 1.4), randf_range(0.3, 1.0), randf_range(0.4, 1.4))
		d.material = glow if i % 5 == 0 else metal
		d.life = randf_range(6.0, 10.0)
		if i % 4 == 0:
			d.trail_color = Color(1.0, 0.45, 0.1)
		get_parent().add_child(d)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
		d.global_position = global_position + Vector3(0, randf_range(2, 16), 0) + dir
		d.linear_velocity = dir * randf_range(8, 22)
		d.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0
	_boom(Vector3(0, 16.5, 0), 3.5)
	queue_free()
