extends Node3D
## Silhouette humaine simple (civils, soldats) avec une petite animation de marche.
## Régler les couleurs avant de l'ajouter à la scène. Le personnage regarde vers -Z.

const FX = preload("res://scripts/fx.gd")

var shirt_color := Color(0.4, 0.5, 0.7)
var pants_color := Color(0.2, 0.2, 0.25)
var skin_color := Color(0.85, 0.68, 0.55)
var head_color := Color(0, 0, 0, 0)  ## casque/cheveux (alpha 0 = aucun)
var eye_color := Color(0, 0, 0, 0)   ## visière lumineuse (alpha 0 = aucune)

var _body: Node3D
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _time := 0.0
var _lying := false
## Bras droit tendu vers l'avant (pour viser avec une arme).
var aiming := false
var _shirt_mat: StandardMaterial3D


func _ready() -> void:
	_shirt_mat = FX.solid_material(shirt_color, 0.8)
	var pants := FX.solid_material(pants_color, 0.85)
	var skin := FX.solid_material(skin_color, 0.7)

	_body = Node3D.new()
	_body.position = Vector3(0, 0.95, 0)
	add_child(_body)
	_part(_body, _capsule(0.24, 0.75), _shirt_mat, Vector3(0, 0.22, 0))
	_part(_body, _sphere(0.16), skin, Vector3(0, 0.72, 0))
	if head_color.a > 0.0:
		_part(_body, _sphere(0.175), FX.solid_material(head_color, 0.5, 0.3), Vector3(0, 0.76, 0.02))
	if eye_color.a > 0.0:
		var visor := MeshInstance3D.new()
		var vm := BoxMesh.new()
		vm.size = Vector3(0.24, 0.05, 0.05)
		visor.mesh = vm
		visor.material_override = FX.emissive_material(eye_color, 4.0)
		visor.position = Vector3(0, 0.74, -0.15)
		_body.add_child(visor)

	for side in [1, -1]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.31 * side, 0.45, 0)
		_body.add_child(shoulder)
		_part(shoulder, _capsule(0.075, 0.65), _shirt_mat, Vector3(0, -0.3, 0))
		_part(shoulder, _sphere(0.075), skin, Vector3(0, -0.65, 0))
		_arms.append(shoulder)

	for side in [1, -1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.12 * side, -0.12, 0)
		_body.add_child(hip)
		_part(hip, _capsule(0.09, 0.82), pants, Vector3(0, -0.4, 0))
		_legs.append(hip)


## Anime la marche selon la vitesse (m/s).
func animate(speed: float, delta: float) -> void:
	if _lying:
		return
	_time += delta * (4.0 + speed * 1.2)
	var amount := clampf(speed / 6.0, 0.0, 1.0)
	var swing := sin(_time) * 0.7 * amount
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arms[1].rotation.x = swing * 0.8
	_arms[0].rotation.x = PI * 0.45 if aiming else -swing * 0.8
	_body.position.y = 0.95 + absf(sin(_time)) * 0.05 * amount


## Allongé au sol (blessé ou mort).
func lie_down() -> void:
	if _lying:
		return
	_lying = true
	var t := create_tween()
	t.tween_property(_body, "rotation:x", PI * 0.5, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_body, "position:y", 0.25, 0.35)


func stand_up() -> void:
	if not _lying:
		return
	_lying = false
	var t := create_tween()
	t.tween_property(_body, "rotation:x", 0.0, 0.5)
	t.parallel().tween_property(_body, "position:y", 0.95, 0.5)


## Bras levés au-dessus de la tête (panique).
func panic_arms() -> void:
	for a in _arms:
		a.rotation.x = PI * 0.85 + sin(_time * 2.0) * 0.2


func flash(color: Color) -> void:
	_shirt_mat.emission_enabled = true
	_shirt_mat.emission = color
	_shirt_mat.emission_energy_multiplier = 2.0
	var t := create_tween()
	t.tween_property(_shirt_mat, "emission_energy_multiplier", 0.0, 0.25)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m
