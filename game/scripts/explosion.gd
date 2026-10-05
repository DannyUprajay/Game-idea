extends Node3D
## Explosion visuelle : flash, boule de feu, étincelles, fumée et lumière.
## Se détruit toute seule. Régler `color` et `size` avant d'ajouter à la scène.

const FX = preload("res://scripts/fx.gd")

var color := Color(1.0, 0.5, 0.15)
var size := 1.0
## Petit impact (balles) : juste un flash et quelques étincelles.
var light_only := false


func _ready() -> void:
	# Les civils proches s'enfuient (la position n'est connue qu'après l'ajout).
	_scare_civilians.call_deferred()
	# Flash : une sphère lumineuse qui grossit et s'efface.
	var flash_mat := FX.glow_material(color.lightened(0.4), 0.9)
	var flash := FX.sphere(0.5 * size, flash_mat)
	add_child(flash)
	var t := create_tween().set_parallel(true)
	t.tween_property(flash, "scale", Vector3.ONE * 4.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(flash_mat, "albedo_color:a", 0.0, 0.35)

	if light_only:
		var spark := FX.particles(8, 0.3, 0.12, [Color(1, 1, 0.9, 1), color, Color(color.r, color.g, color.b, 0)], [0.0, 0.4, 1.0])
		var spm := spark.process_material as ParticleProcessMaterial
		spm.spread = 180.0
		spm.initial_velocity_min = 3.0
		spm.initial_velocity_max = 7.0
		spm.gravity = Vector3(0, -12, 0)
		_one_shot(spark)
		get_tree().create_timer(0.6).timeout.connect(queue_free)
		return

	# Lumière qui éclaire le décor puis s'éteint.
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0 * size
	light.omni_range = 8.0 * size
	add_child(light)
	t.tween_property(light, "light_energy", 0.0, 0.5)

	# Flammes : grosses particules qui partent dans tous les sens.
	var fire := FX.particles(int(28 * size) + 8, 0.55, 1.1 * size,
		[Color(1, 1, 0.8, 1), color, Color(color.r * 0.4, color.g * 0.2, 0.05, 0.0)], [0.0, 0.35, 1.0])
	var fm := fire.process_material as ParticleProcessMaterial
	fm.direction = Vector3.UP
	fm.spread = 180.0
	fm.initial_velocity_min = 2.0 * size
	fm.initial_velocity_max = 6.0 * size
	fm.damping_min = 4.0
	fm.damping_max = 8.0
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fm.emission_sphere_radius = 0.3 * size
	_one_shot(fire)

	# Étincelles : petites, rapides, retombent avec la gravité.
	var sparks := FX.particles(int(30 * size) + 10, 0.8, 0.18, [Color(1, 1, 0.9, 1), color, Color(color.r, color.g, color.b, 0)], [0.0, 0.4, 1.0])
	var sm := sparks.process_material as ParticleProcessMaterial
	sm.direction = Vector3.UP
	sm.spread = 180.0
	sm.initial_velocity_min = 8.0 * size
	sm.initial_velocity_max = 18.0 * size
	sm.gravity = Vector3(0, -14, 0)
	sm.damping_min = 1.0
	sm.damping_max = 3.0
	_one_shot(sparks)

	# Fumée sombre qui monte lentement.
	var smoke := FX.particles(int(10 * size) + 4, 1.6, 1.6 * size, [Color(0.25, 0.22, 0.2, 0.0), Color(0.18, 0.16, 0.15, 0.5), Color(0.1, 0.1, 0.1, 0.0)], [0.0, 0.2, 1.0])
	((smoke.draw_pass_1 as QuadMesh).material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var km := smoke.process_material as ParticleProcessMaterial
	km.direction = Vector3.UP
	km.spread = 60.0
	km.initial_velocity_min = 1.0
	km.initial_velocity_max = 3.0 * size
	km.gravity = Vector3(0, 1.5, 0)
	km.damping_min = 1.0
	km.damping_max = 2.0
	_one_shot(smoke)

	get_tree().create_timer(2.5).timeout.connect(queue_free)


func _one_shot(p: GPUParticles3D) -> void:
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	add_child(p)
	p.emitting = true


func _scare_civilians() -> void:
	get_tree().call_group("civilians", "scare", global_position, 18.0 * size)
