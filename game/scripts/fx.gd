extends RefCounted
## Petites fonctions partagées : matériaux, particules, dégâts de zone, secousses.


static func solid_material(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func emissive_material(color: Color, energy := 4.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Matériau lumineux, transparent et additif (halos, ondes, flashs).
static func glow_material(color: Color, alpha := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	return m


static func sphere(radius: float, material: Material, segments := 24) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = segments / 2
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Maillage utilisé pour dessiner chaque particule : un carré toujours face caméra.
static func particle_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot_texture()
	q.material = m
	return q


static var _dot_tex: Texture2D = null


## Petit disque flou généré une seule fois, pour des particules rondes et douces.
static func _soft_dot_texture() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_dot_tex = t
	return t


static func gradient_texture(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Courbe de taille : grossit vite puis rétrécit jusqu'à zéro.
static func shrink_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func particles(amount: int, lifetime: float, quad_size: float, colors: Array, offsets: Array) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.draw_pass_1 = particle_quad(quad_size)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.color_ramp = gradient_texture(colors, offsets)
	pm.scale_curve = shrink_curve()
	p.process_material = pm
	return p


## Dégâts de zone + projection, avec une baisse selon la distance.
static func radial_damage(tree: SceneTree, center: Vector3, radius: float, damage: float,
		impulse: float, target_group: String, exclude: Node = null) -> void:
	for n in tree.get_nodes_in_group(target_group):
		if n == exclude or not (n is Node3D):
			continue
		var offset: Vector3 = (n as Node3D).global_position - center
		var d := offset.length()
		if d > radius:
			continue
		var falloff := 1.0 - d / radius
		var dir := (offset.normalized() + Vector3.UP * 0.35).normalized()
		if n.has_method("take_damage"):
			n.take_damage(damage * falloff, center)
		if n.has_method("apply_push"):
			n.apply_push(dir * impulse * falloff)
	for p in tree.get_nodes_in_group("props"):
		var body := p as RigidBody3D
		if body == null:
			continue
		var off := body.global_position - center
		var dist := off.length()
		if dist > radius:
			continue
		var f := 1.0 - dist / radius
		var push_dir := (off.normalized() + Vector3.UP * 0.5).normalized()
		body.apply_central_impulse(push_dir * impulse * f * body.mass * 0.6)


## Fait trembler la caméra du joueur selon la distance à l'explosion.
static func shake_cameras(tree: SceneTree, origin: Vector3, strength: float) -> void:
	for p in tree.get_nodes_in_group("player"):
		if p is Node3D and p.has_method("add_shake"):
			var d: float = (p as Node3D).global_position.distance_to(origin)
			p.add_shake(strength / max(1.0, d * 0.15))
