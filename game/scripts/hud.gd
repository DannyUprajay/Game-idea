extends CanvasLayer
## Interface : viseur, vie, énergie, pouvoirs, score et aide.


class Crosshair extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1, 1, 1, 0.9)
		draw_circle(c, 2.5, col)
		draw_arc(c, 11.0, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.5)


var _health_bar: ProgressBar
var _energy_bar: ProgressBar
var _score_label: Label
var _fly_label: Label
var _message: Label
var _help: Label
var _damage_overlay: ColorRect
var _ability_labels: Dictionary = {}
var _score := 0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_damage_overlay = ColorRect.new()
	_damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_overlay.color = Color(0.8, 0.0, 0.0, 0.0)
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_damage_overlay)

	var cross := Crosshair.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)

	# Barres en bas à gauche.
	var bars := VBoxContainer.new()
	_place(bars, Vector4(0, 1, 0, 1), Vector4(30, -96, 450, -30))
	bars.add_theme_constant_override("separation", 8)
	root.add_child(bars)
	_health_bar = _make_bar(bars, "VIE", Color(0.9, 0.2, 0.25))
	_energy_bar = _make_bar(bars, "ÉNERGIE", Color(0.25, 0.6, 1.0))

	# Pouvoirs en bas au centre.
	var abilities := HBoxContainer.new()
	_place(abilities, Vector4(0.5, 1, 0.5, 1), Vector4(-360, -80, 360, -24))
	abilities.alignment = BoxContainer.ALIGNMENT_CENTER
	abilities.add_theme_constant_override("separation", 14)
	root.add_child(abilities)
	_ability_labels["fire"] = _make_ability(abilities, "Clic gauche", "Boule de feu", Color(1, 0.55, 0.2))
	_ability_labels["black_hole"] = _make_ability(abilities, "Clic droit", "Trou noir", Color(0.7, 0.4, 1.0))
	_ability_labels["shockwave"] = _make_ability(abilities, "E", "Onde de choc", Color(0.4, 0.85, 1.0))

	_score_label = _make_label(root, "Drones détruits : 0", 26)
	_place(_score_label, Vector4(1, 0, 1, 0), Vector4(-430, 20, -24, 56))
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_fly_label = _make_label(root, "", 22)
	_place(_fly_label, Vector4(1, 0, 1, 0), Vector4(-430, 60, -24, 92))
	_fly_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fly_label.add_theme_color_override("font_color", Color(1, 0.75, 0.35))

	_message = _make_label(root, "", 34)
	_place(_message, Vector4(0.5, 0.3, 0.5, 0.3), Vector4(-500, 0, 500, 50))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_help = _make_label(root, "\n".join([
		"ZQSD / WASD : se déplacer      Souris : viser",
		"Espace : sauter  (en l'air : s'envoler / monter)",
		"F : voler / atterrir      Ctrl ou C : descendre",
		"Maj : courir / turbo en vol",
		"Clic gauche (maintenu) : boules de feu",
		"Clic droit : trou noir      E : onde de choc",
		"Échap : libérer la souris      H : cacher l'aide",
	]), 16)
	_place(_help, Vector4(0, 0, 0, 0), Vector4(24, 20, 600, 200))
	_help.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))

	set_flying(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible


## Place un élément : ancres (gauche, haut, droite, bas) puis marges en pixels.
func _place(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w


func _make_label(parent: Control, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _make_bar(parent: Control, title: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := _make_label(row, title, 16)
	l.custom_minimum_size = Vector2(80, 0)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(320, 20)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return bar


func _make_ability(parent: Control, key: String, title: String, color: Color) -> Label:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	var l := _make_label(panel, "%s\n%s" % [key, title], 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_meta("base_text", l.text)
	return l


func set_health(value: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = value


func set_energy(value: float, max_value: float) -> void:
	_energy_bar.max_value = max_value
	_energy_bar.value = value


func set_flying(flying: bool) -> void:
	_fly_label.text = "✦ EN VOL ✦" if flying else ""


func add_kill() -> void:
	_score += 1
	_score_label.text = "Drones détruits : %d" % _score


## Grise un pouvoir indisponible et affiche le temps restant.
func set_ability_state(id: String, available: bool, cooldown: float) -> void:
	var l: Label = _ability_labels[id]
	var base: String = l.get_meta("base_text")
	l.text = base if cooldown <= 0.0 else "%s  (%.1f s)" % [base, cooldown]
	l.modulate = Color(1, 1, 1, 1) if available else Color(1, 1, 1, 0.35)


func flash_damage() -> void:
	_damage_overlay.color.a = 0.35
	var t := create_tween()
	t.tween_property(_damage_overlay, "color:a", 0.0, 0.4)


func show_message(text: String, duration := 2.5) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(_message, "modulate:a", 0.0, 0.6)
