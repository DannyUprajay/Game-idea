extends Node3D
## Arc électrique entre deux points (absorption d'énergie, soin, absorption de vie).
## Appeler set_points(a, b) à chaque image tant qu'il doit être visible.

const FX = preload("res://scripts/fx.gd")
const SEGMENTS := 10

var color := Color(0.5, 0.85, 1.0)

var _core: Array[MeshInstance3D] = []
var _glow: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _core_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	_core_mat = FX.emissive_material(color.lightened(0.5), 8.0)
	_glow_mat = FX.glow_material(color, 0.35)
	for i in SEGMENTS:
		_core.append(_segment(0.05, _core_mat))
		_glow.append(_segment(0.18, _glow_mat))
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 3.0
	_light.omni_range = 6.0
	add_child(_light)
	visible = false


func set_color(c: Color) -> void:
	color = c
	_core_mat.emission = c.lightened(0.5)
	_glow_mat.albedo_color = Color(c.r, c.g, c.b, 0.35)
	_light.light_color = c


func _segment(width: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(width, width, 1.0)
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Redessine l'arc avec un tracé en zigzag différent à chaque appel.
func set_points(a: Vector3, b: Vector3) -> void:
	visible = true
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		return
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var points: Array[Vector3] = []
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var p := a + dir * t
		if i > 0 and i < SEGMENTS:
			var jitter := length * 0.06 * sin(t * PI)
			p += side * randf_range(-jitter, jitter) + up * randf_range(-jitter, jitter)
		points.append(p)
	for i in SEGMENTS:
		_place(_core[i], points[i], points[i + 1])
		_place(_glow[i], points[i], points[i + 1])
	_light.global_position = b


func _place(mi: MeshInstance3D, p0: Vector3, p1: Vector3) -> void:
	var seg := p1 - p0
	var l := seg.length()
	var mid := (p0 + p1) * 0.5
	var up := Vector3.UP if absf(seg.normalized().y) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis(), mid).looking_at(p1, up)
	mi.scale = Vector3(1, 1, l)


func hide_beam() -> void:
	visible = false
