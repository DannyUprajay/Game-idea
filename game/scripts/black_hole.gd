extends Node3D
## Trou noir : aspire ennemis et objets, les broie au centre,
## puis s'effondre dans une grosse explosion.

const FX = preload("res://scripts/fx.gd")
const Explosion = preload("res://scripts/explosion.gd")

const LENS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.06;
uniform vec3 rim_color : source_color = vec3(0.65, 0.35, 1.0);
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = 1.0 - facing;
	// Déforme l'image derrière la sphère : effet de lentille gravitationnelle.
	vec2 offs = NORMAL.xy * strength * facing;
	vec3 col = texture(screen_tex, SCREEN_UV + offs).rgb;
	ALBEDO = col + rim_color * pow(rim, 3.0) * 2.0;
	ALPHA = 1.0 - pow(rim, 6.0);
}
"""

const DISK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying vec3 lpos;
void vertex() {
	lpos = VERTEX;
}
void fragment() {
	float r = length(lpos.xz);
	float a = atan(lpos.z, lpos.x);
	float swirl = sin(a * 3.0 + r * 5.0 - TIME * 7.0) * 0.5 + 0.5;
	float band = smoothstep(1.2, 1.7, r) * (1.0 - smoothstep(2.5, 3.3, r));
	vec3 hot = mix(vec3(1.0, 0.6, 0.25), vec3(0.55, 0.2, 1.0), smoothstep(1.6, 3.0, r));
	ALBEDO = hot * (0.5 + swirl) * 2.5;
	ALPHA = band * (0.35 + 0.65 * swirl);
}
"""

var life := 6.0
var pull_radius := 18.0
var pull_strength := 55.0
var core_radius := 1.3
var core_dps := 45.0
var shooter: Node = null

var _age := 0.0
var _collapsing := false
var _disk: MeshInstance3D
var _disk2: MeshInstance3D
var _light: OmniLight3D


func _ready() -> void:
	# Lentille qui déforme le décor derrière.
	var lens_mat := ShaderMaterial.new()
	lens_mat.shader = Shader.new()
	lens_mat.shader.code = LENS_SHADER
	add_child(FX.sphere(2.3, lens_mat, 32))

	# Le cœur : noir absolu.
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0, 0, 0)
	add_child(FX.sphere(core_radius, black, 32))

	# Disque d'accrétion qui tourbillonne (deux disques inclinés).
	var disk_mat := ShaderMaterial.new()
	disk_mat.shader = Shader.new()
	disk_mat.shader.code = DISK_SHADER
	_disk = _make_disk(disk_mat)
	_disk.rotation_degrees = Vector3(12, 0, 8)
	_disk2 = _make_disk(disk_mat)
	_disk2.rotation_degrees = Vector3(-70, 0, 20)
	_disk2.scale = Vector3(0.8, 0.06, 0.8)

	# Particules aspirées en spirale.
	var swirl := FX.particles(160, 1.3, 0.35,
		[Color(0.6, 0.3, 1, 0), Color(0.9, 0.5, 1, 1), Color(1, 0.7, 0.3, 1), Color(1, 0.8, 0.5, 0)], [0.0, 0.2, 0.8, 1.0])
	var pm := swirl.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 9.0
	pm.radial_accel_min = -22.0
	pm.radial_accel_max = -14.0
	pm.tangential_accel_min = 8.0
	pm.tangential_accel_max = 14.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.5
	add_child(swirl)
	swirl.emitting = true

	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.3, 1.0)
	_light.light_energy = 4.0
	_light.omni_range = 14.0
	add_child(_light)

	# Apparition : grossit d'un coup.
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	FX.shake_cameras(get_tree(), global_position, 0.3)


func _make_disk(mat: Material) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 1.2
	torus.outer_radius = 3.3
	torus.rings = 48
	torus.ring_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1.0, 0.06, 1.0)
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	_age += delta
	_disk.rotate_object_local(Vector3.UP, delta * 2.5)
	_disk2.rotate_object_local(Vector3.UP, -delta * 3.5)
	_light.light_energy = 4.0 + sin(_age * 9.0) * 1.2

	if _collapsing:
		return
	if _age >= life:
		_collapse()
		return

	var center := global_position

	# Ennemis : aspirés, et broyés s'ils touchent le centre.
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node3D
		if n == null:
			continue
		var to_center := center - n.global_position
		var d := to_center.length()
		if d > pull_radius:
			continue
		var dir := to_center / max(d, 0.01)
		var tangent := dir.cross(Vector3.UP).normalized()
		var force := pull_strength * (1.0 - d / pull_radius) + 6.0
		if n.has_method("apply_pull"):
			n.apply_pull((dir + tangent * 0.35) * force * delta)
		if d < core_radius * 1.8 and n.has_method("take_damage"):
			n.take_damage(core_dps * delta, center, true)

	# Objets physiques (caisses) : attirés et mis en orbite.
	for p in get_tree().get_nodes_in_group("props"):
		var body := p as RigidBody3D
		if body == null:
			continue
		var off := center - body.global_position
		var dist := off.length()
		if dist > pull_radius:
			continue
		var pdir := off / max(dist, 0.01)
		var ptan := pdir.cross(Vector3.UP).normalized()
		var f := pull_strength * (1.0 - dist / pull_radius) + 4.0
		body.apply_central_force((pdir + ptan * 0.5) * f * body.mass)
		if dist < core_radius * 2.0:
			body.linear_velocity *= 0.92


func _collapse() -> void:
	_collapsing = true
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * 0.05, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_callback(_detonate)


func _detonate() -> void:
	var pos := global_position
	FX.radial_damage(get_tree(), pos, 11.0, 50.0, 28.0, "enemies", shooter)
	FX.shake_cameras(get_tree(), pos, 0.9)
	var boom := Explosion.new()
	boom.color = Color(0.65, 0.35, 1.0)
	boom.size = 2.6
	get_parent().add_child(boom)
	boom.global_position = pos
	queue_free()
