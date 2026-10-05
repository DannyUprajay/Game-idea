extends RigidBody3D
## Morceau de débris : vole, rebondit, puis disparaît au bout de `life` secondes.
## Régler les variables avant de l'ajouter à la scène.

const FX = preload("res://scripts/fx.gd")

var size := Vector3.ONE
var material: Material = null
var life := 8.0
## Couleur de la traînée de feu/fumée (alpha 0 = pas de traînée).
var trail_color := Color(0, 0, 0, 0)

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	add_to_group("props")  # le trou noir et les explosions les projettent aussi
	# Les débris touchent le décor et entre eux, mais pas le joueur ni les ennemis.
	collision_layer = 8
	collision_mask = 1 | 8
	mass = clampf(size.x * size.y * size.z * 2.0, 0.2, 60.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = material
	add_child(_mesh_instance)

	if trail_color.a > 0.0:
		_add_trail()

	get_tree().create_timer(life).timeout.connect(_vanish)


func _add_trail() -> void:
	var trail := FX.particles(30, 0.7, 0.5,
		[Color(1, 0.9, 0.6, 1), trail_color, Color(0.15, 0.13, 0.12, 0.5), Color(0.1, 0.1, 0.1, 0)],
		[0.0, 0.2, 0.6, 1.0])
	trail.local_coords = false
	var pm := trail.process_material as ParticleProcessMaterial
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, 1.5, 0)
	add_child(trail)
	trail.emitting = true
	# La traînée s'arrête après un moment.
	get_tree().create_timer(randf_range(1.0, 2.0)).timeout.connect(func() -> void: trail.emitting = false)


func _vanish() -> void:
	var t := create_tween()
	t.tween_property(_mesh_instance, "scale", Vector3.ONE * 0.01, 0.6)
	t.tween_callback(queue_free)
