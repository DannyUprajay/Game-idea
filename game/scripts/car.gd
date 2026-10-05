extends RigidBody3D
## Voiture garée : source d'électricité, projetable, et explose si on l'abîme trop.

const FX = preload("res://scripts/fx.gd")
const Explosion = preload("res://scripts/explosion.gd")

const COLORS := [Color(0.7, 0.1, 0.1), Color(0.1, 0.25, 0.6), Color(0.85, 0.85, 0.85),
	Color(0.12, 0.12, 0.13), Color(0.85, 0.65, 0.1), Color(0.2, 0.45, 0.25)]

var health := 60.0
var energy := 60.0
var _wrecked := false
var _paint: StandardMaterial3D
var _light_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("props")
	add_to_group("cars")
	add_to_group("energy_source")
	collision_layer = 1
	collision_mask = 1 | 2 | 4 | 8
	mass = 12.0

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.3, 4.2)
	col.shape = box
	col.position = Vector3(0, 0.75, 0)
	add_child(col)

	_paint = FX.solid_material(COLORS[randi() % COLORS.size()], 0.3, 0.6)
	_part(Vector3(2.0, 0.7, 4.2), _paint, Vector3(0, 0.55, 0))
	_part(Vector3(1.7, 0.6, 2.2), FX.solid_material(Color(0.05, 0.07, 0.1), 0.1, 0.5), Vector3(0, 1.15, 0.2))
	var tire := FX.solid_material(Color(0.05, 0.05, 0.05), 0.9)
	for x in [-0.95, 0.95]:
		for z in [-1.35, 1.35]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.38
			cyl.bottom_radius = 0.38
			cyl.height = 0.3
			wheel.mesh = cyl
			wheel.material_override = tire
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(x, 0.38, z)
			add_child(wheel)
	_light_mat = FX.emissive_material(Color(1.0, 0.95, 0.75), 3.0)
	for x in [-0.7, 0.7]:
		_part(Vector3(0.35, 0.15, 0.05), _light_mat, Vector3(x, 0.65, -2.11))
		_part(Vector3(0.35, 0.15, 0.05), FX.emissive_material(Color(1.0, 0.1, 0.05), 2.0), Vector3(x, 0.65, 2.11))


func _part(size: Vector3, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


# --- Source d'énergie --------------------------------------------------------
func has_energy() -> bool:
	return energy > 0.0 and not _wrecked


func get_drain_point() -> Vector3:
	return global_position + Vector3.UP * 1.0


func drain(amount: float) -> float:
	var taken := minf(amount, energy)
	energy -= taken
	if energy <= 0.0:
		_light_mat.emission_energy_multiplier = 0.0
	return taken


# --- Dégâts -------------------------------------------------------------------
func take_damage(amount: float, _from: Vector3, _silent := false, attacker: Node = null) -> void:
	if _wrecked:
		return
	health -= amount
	if health <= 0.0:
		_explode(attacker)


func _explode(attacker: Node) -> void:
	_wrecked = true
	energy = 0.0
	remove_from_group("cars")
	remove_from_group("energy_source")
	_paint.albedo_color = Color(0.08, 0.07, 0.06)
	_paint.metallic = 0.0
	_light_mat.emission_energy_multiplier = 0.0
	apply_central_impulse(Vector3.UP * mass * 9.0 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 2.0)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * mass * 6.0)

	var boom := Explosion.new()
	boom.color = Color(1.0, 0.45, 0.1)
	boom.size = 2.2
	get_parent().add_child(boom)
	boom.global_position = global_position + Vector3.UP
	FX.radial_damage(get_tree(), global_position, 7.0, 45.0, 18.0, ["enemies", "civilians", "player", "cars"], attacker)
	FX.shake_cameras(get_tree(), global_position, 0.7)

	# L'épave brûle encore un moment.
	var fire := FX.particles(40, 0.9, 0.9, [Color(1, 0.9, 0.5, 0), Color(1, 0.45, 0.1, 0.9), Color(0.2, 0.18, 0.16, 0.5), Color(0.1, 0.1, 0.1, 0)], [0.0, 0.2, 0.6, 1.0])
	var pm := fire.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.8, 0.3, 1.6)
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	fire.local_coords = false
	fire.position = Vector3(0, 1.0, 0)
	add_child(fire)
	fire.emitting = true
	get_tree().create_timer(12.0).timeout.connect(func() -> void: fire.emitting = false)
