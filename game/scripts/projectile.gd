extends Node3D
## Projectile magique (boule de feu du joueur, orbe des ennemis).
## Régler les variables avant de l'ajouter à la scène, puis placer global_position.

const FX = preload("res://scripts/fx.gd")
const Explosion = preload("res://scripts/explosion.gd")

var velocity := Vector3.ZERO
var damage := 20.0
var splash_damage := 14.0
var splash_radius := 4.0
var splash_impulse := 10.0
var color := Color(1.0, 0.45, 0.1)
var radius := 0.3
var life := 3.0
var explosion_size := 1.0
var collision_mask := 1
var target_group := "enemies"
var shooter: Node = null

var _shape := SphereShape3D.new()
var _done := false


func _ready() -> void:
	_shape.radius = radius

	# Noyau très lumineux.
	var core := FX.sphere(radius, FX.emissive_material(color.lightened(0.5), 8.0), 16)
	add_child(core)
	# Halo autour.
	add_child(FX.sphere(radius * 2.0, FX.glow_material(color, 0.35), 16))

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 6.0
	add_child(light)

	# Traînée de flammes laissée derrière.
	var trail := FX.particles(48, 0.45, radius * 2.4,
		[Color(1, 0.95, 0.7, 1), color, Color(color.r * 0.5, color.g * 0.2, 0.05, 0)], [0.0, 0.3, 1.0])
	trail.local_coords = false
	var pm := trail.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.6
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 1.2
	add_child(trail)
	trail.emitting = true


func _physics_process(delta: float) -> void:
	if _done:
		return
	life -= delta
	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := from + velocity * delta

	var exclude: Array[RID] = []
	if shooter is CollisionObject3D:
		exclude.append((shooter as CollisionObject3D).get_rid())

	# Rayon entre l'ancienne et la nouvelle position : rien ne passe au travers.
	var ray := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		_explode(hit["position"], hit["collider"])
		return

	global_position = to

	# Petite sphère autour du projectile : touche les cibles frôlées.
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis(), to)
	q.collision_mask = collision_mask
	q.exclude = exclude
	var touching := space.intersect_shape(q, 1)
	if not touching.is_empty():
		_explode(to, touching[0]["collider"])
		return

	if life <= 0.0:
		_explode(global_position, null)


func _explode(pos: Vector3, collider: Object) -> void:
	_done = true
	if collider != null and collider != shooter and collider.has_method("take_damage"):
		collider.take_damage(damage, pos)
	FX.radial_damage(get_tree(), pos, splash_radius, splash_damage, splash_impulse, target_group, shooter)
	FX.shake_cameras(get_tree(), pos, 0.25 * explosion_size)

	var boom := Explosion.new()
	boom.color = color
	boom.size = explosion_size
	get_parent().add_child(boom)
	boom.global_position = pos
	queue_free()
