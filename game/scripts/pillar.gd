extends StaticBody3D
## Pilier destructible : fonce dedans en vol turbo et il éclate en blocs.
## Régler `size`, `color` et `crown_color` avant de l'ajouter à la scène.
## La position du pilier est son centre.

const FX = preload("res://scripts/fx.gd")
const Debris = preload("res://scripts/debris.gd")
const Explosion = preload("res://scripts/explosion.gd")

## Nombre de morceaux visé quand le pilier éclate.
const PIECES := 40

var size := Vector3(6, 30, 6)
var color := Color(0.35, 0.33, 0.38)
## Liseré lumineux en haut (alpha 0 = pas de liseré).
var crown_color := Color(0, 0, 0, 0)

var _material: StandardMaterial3D
var _broken := false


func _ready() -> void:
	add_to_group("destructible")
	collision_layer = 1

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	_material = FX.solid_material(color, 0.85)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	add_child(mi)

	if crown_color.a > 0.0:
		var crown_mesh := BoxMesh.new()
		crown_mesh.size = Vector3(size.x + 0.4, 0.4, size.z + 0.4)
		var crown := MeshInstance3D.new()
		crown.mesh = crown_mesh
		crown.material_override = FX.emissive_material(crown_color, 2.5)
		crown.position = Vector3(0, size.y * 0.5, 0)
		add_child(crown)


## Fait éclater le pilier. `impact_velocity` = vitesse de ce qui l'a percuté.
func shatter(impact: Vector3, impact_velocity: Vector3) -> void:
	if _broken:
		return
	_broken = true
	# Plus de collision tout de suite : le joueur passe à travers.
	collision_layer = 0
	visible = false

	# Découpe le pilier en une grille de blocs d'environ la même taille.
	var cell := pow(size.x * size.y * size.z / float(PIECES), 1.0 / 3.0)
	var nx := clampi(roundi(size.x / cell), 1, 4)
	var ny := clampi(roundi(size.y / cell), 2, 14)
	var nz := clampi(roundi(size.z / cell), 1, 4)
	var piece := Vector3(size.x / nx, size.y / ny, size.z / nz)

	var push_dir := impact_velocity.normalized()
	var speed := impact_velocity.length()
	var reach := size.y * 0.35 + 5.0
	var parent := get_parent()

	for ix in nx:
		for iy in ny:
			for iz in nz:
				var local := Vector3(
					(ix + 0.5) * piece.x - size.x * 0.5,
					(iy + 0.5) * piece.y - size.y * 0.5,
					(iz + 0.5) * piece.z - size.z * 0.5)
				var world := global_transform * local
				var d := Debris.new()
				d.size = piece * randf_range(0.8, 0.97)
				d.material = _material
				d.life = randf_range(7.0, 11.0)
				parent.add_child(d)
				d.global_position = world
				# Les blocs proches de l'impact sont projetés fort, les autres s'écroulent.
				var near := clampf(1.0 - world.distance_to(impact) / reach, 0.0, 1.0)
				var away := (world - impact).normalized()
				d.linear_velocity = push_dir * speed * 0.6 * near + away * 8.0 * near \
					+ Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 1.5
				d.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (1.0 + near * 5.0)

	# Nuage de poussière et éclats de pierre à l'impact.
	var dust := Explosion.new()
	dust.color = Color(0.65, 0.6, 0.55)
	dust.size = 2.5
	parent.add_child(dust)
	dust.global_position = impact
	FX.shake_cameras(get_tree(), impact, 0.9)
	queue_free()
