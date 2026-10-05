extends StaticBody3D
## Source d'électricité fixe : lampadaire ou générateur.
## Le joueur l'absorbe (touche R) pour recharger son énergie.

const FX = preload("res://scripts/fx.gd")

enum Kind { LAMP, GENERATOR }

var kind := Kind.LAMP
var max_energy := 40.0
var energy := 40.0
## Temps avant que la source se recharge après avoir été vidée.
var recharge_delay := 25.0

var _bulb_mat: StandardMaterial3D
var _light: OmniLight3D
var _drain_point := Vector3.ZERO
var _empty_time := 0.0


func _ready() -> void:
	add_to_group("energy_source")
	collision_layer = 1
	if kind == Kind.LAMP:
		_build_lamp()
	else:
		_build_generator()
	energy = max_energy


func _build_lamp() -> void:
	max_energy = 40.0
	recharge_delay = 25.0
	var metal := FX.solid_material(Color(0.2, 0.22, 0.25), 0.5, 0.7)
	_shape(Vector3(0.3, 6.0, 0.3), Vector3(0, 3.0, 0))
	_mesh(_cylinder(0.1, 6.0), metal, Vector3(0, 3.0, 0))
	_mesh(_box(Vector3(0.12, 0.12, 1.6)), metal, Vector3(0, 6.0, -0.7))
	_bulb_mat = FX.emissive_material(Color(1.0, 0.85, 0.55), 6.0)
	_mesh(_box(Vector3(0.5, 0.15, 0.6)), _bulb_mat, Vector3(0, 5.9, -1.4))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.55)
	_light.light_energy = 2.0
	_light.omni_range = 13.0
	_light.position = Vector3(0, 5.6, -1.4)
	add_child(_light)
	_drain_point = Vector3(0, 5.8, -1.4)


func _build_generator() -> void:
	max_energy = 200.0
	recharge_delay = 6.0
	var casing := FX.solid_material(Color(0.28, 0.3, 0.26), 0.6, 0.5)
	_shape(Vector3(3.0, 2.6, 2.2), Vector3(0, 1.3, 0))
	_mesh(_box(Vector3(3.0, 2.6, 2.2)), casing, Vector3(0, 1.3, 0))
	_bulb_mat = FX.emissive_material(Color(0.4, 0.8, 1.0), 4.0)
	for x in [-0.9, 0.0, 0.9]:
		_mesh(_cylinder(0.25, 1.2), _bulb_mat, Vector3(x, 3.2, 0))
	_light = OmniLight3D.new()
	_light.light_color = Color(0.4, 0.8, 1.0)
	_light.light_energy = 3.0
	_light.omni_range = 10.0
	_light.position = Vector3(0, 3.5, 0)
	add_child(_light)
	_drain_point = Vector3(0, 3.4, 0)


func _process(delta: float) -> void:
	if energy <= 0.0:
		_empty_time += delta
		if _empty_time >= recharge_delay:
			energy = max_energy
			_set_lit(1.0)


func has_energy() -> bool:
	return energy > 0.0


func get_drain_point() -> Vector3:
	return to_global(_drain_point)


func drain(amount: float) -> float:
	var taken := minf(amount, energy)
	energy -= taken
	# Clignote pendant qu'on l'absorbe, puis s'éteint une fois vide.
	_set_lit(randf_range(0.2, 1.0) if energy > 0.0 else 0.0)
	if energy <= 0.0:
		_empty_time = 0.0
	return taken


func _set_lit(amount: float) -> void:
	var base := 6.0 if kind == Kind.LAMP else 4.0
	_bulb_mat.emission_energy_multiplier = base * amount
	_light.light_energy = (2.0 if kind == Kind.LAMP else 3.0) * amount


func _shape(size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	add_child(col)


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cylinder(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	return m
