extends Node3D
## Projectile : boule de feu du joueur, orbe des drones, balle des soldats.
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
## Groupes qui subissent les dégâts de zone.
var target_groups: Array = ["enemies"]
var shooter: Node = null
## Version légère (balles) : pas de lumière ni de particules, petit impact.
var is_bullet := false

var _shape := SphereShape3D.new()
var _done := false


func _ready() -> void:
	_shape.radius = radius

	if is_bullet:
		# Balle traçante : un trait lumineux étiré dans la direction du tir.
		var tracer := FX.sphere(radius, FX.emissive_material(color, 6.0), 8)
		tracer.scale = Vector3(1, 1, 6)
		add_child(tracer)
		if velocity.length() > 0.1:
			look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
		return

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

	# Traînée laissée derrière.
	var trail := FX.particles(48, 0.45, radius * 2.4,
		[Color(1, 0.95, 0.8, 1), color, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0)], [0.0, 0.3, 1.0])
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
	# Le tireur a pu être détruit pendant que le projectile volait.
	if not is_instance_valid(shooter):
		shooter = null
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
		if is_bullet:
			queue_free()
		else:
			_explode(global_position, null)


func _explode(pos: Vector3, collider: Object) -> void:
	_done = true
	if collider != null and collider != shooter and collider.has_method("take_damage"):
		collider.take_damage(damage, pos, false, shooter)
	if splash_damage > 0.0:
		FX.radial_damage(get_tree(), pos, splash_radius, splash_damage, splash_impulse, target_groups, shooter)
	if not is_bullet:
		FX.shake_cameras(get_tree(), pos, 0.25 * explosion_size)

	var boom := Explosion.new()
	boom.color = color
	boom.size = explosion_size
	boom.light_only = is_bullet
	get_parent().add_child(boom)
	boom.global_position = pos
	queue_free()
