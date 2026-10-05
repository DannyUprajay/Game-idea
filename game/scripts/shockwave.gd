extends Node3D
## Onde de choc autour du joueur : repousse et blesse tout ce qui est proche.

const FX = preload("res://scripts/fx.gd")

var radius := 12.0
var damage := 25.0
var impulse := 32.0
var color := Color(0.4, 0.85, 1.0)
var shooter: Node = null:
	get:
		return shooter if is_instance_valid(shooter) else null


func _ready() -> void:
	# Sphère qui s'étend et s'efface.
	var mat := FX.glow_material(color, 0.6)
	var bubble := FX.sphere(1.0, mat, 32)
	add_child(bubble)
	bubble.scale = Vector3.ONE * 0.5

	# Anneau au sol qui s'élargit.
	var ring_mat := FX.glow_material(color.lightened(0.3), 0.9)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 64
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.3, 1)
	add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = radius
	add_child(light)

	var t := create_tween().set_parallel(true)
	t.tween_property(bubble, "scale", Vector3.ONE * radius, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	t.tween_property(ring, "scale", Vector3(radius * 1.2, 0.3, radius * 1.2), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(ring_mat, "albedo_color:a", 0.0, 0.5)
	t.tween_property(light, "light_energy", 0.0, 0.5)

	FX.radial_damage(get_tree(), global_position, radius, damage, impulse, "enemies", shooter)
	FX.shake_cameras(get_tree(), global_position, 0.5)
	get_tree().create_timer(0.8).timeout.connect(queue_free)
