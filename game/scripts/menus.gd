extends CanvasLayer
## Menus : écran titre, pause, améliorations, commandes et écran de fin.
## Fonctionne même quand le jeu est en pause.

signal start_requested
signal upgrade_requested(id: String)
signal restart_requested

enum Screen { NONE, TITLE, PAUSE, UPGRADES, CONTROLS, ENDING }

const CONTROLS_TEXT := """Déplacements
  ZQSD / WASD : se déplacer      Maj : courir (turbo en vol)
  Espace : sauter — en l'air, appuyer encore pour s'envoler
  F : voler / atterrir      Ctrl ou C : descendre

Pouvoirs
  Clic gauche (maintenir) : boules d'énergie
  E : onde de choc (niveau 2)      Clic droit : trou noir (niveau 3)
  Fonce dans les antennes et les colonnes en turbo pour les détruire !

Électricité et karma
  R (maintenir) près d'un lampadaire, d'une voiture ou d'un générateur : recharger
  R (maintenir) près d'un civil blessé : le soigner (karma héroïque)
  T (maintenir) près d'un civil blessé : absorber sa vie (karma infâme)
  Blesser des civils fait baisser le karma.

Menus
  Tab : améliorations      Échap : pause      H : aide à l'écran"""

var current := Screen.NONE
var _root: Control
var _dim: ColorRect
var _panels: Dictionary = {}
var _upgrade_list: VBoxContainer
var _points_label: Label
var _ending_title: Label
var _ending_text: Label
var _back_screen := Screen.PAUSE


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.02, 0.06, 0.72)
	_root.add_child(_dim)

	_build_title()
	_build_pause()
	_build_upgrades()
	_build_controls()
	_build_ending()
	show_screen(Screen.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match current:
			Screen.NONE:
				show_screen(Screen.PAUSE)
			Screen.PAUSE:
				show_screen(Screen.NONE)
			Screen.UPGRADES, Screen.CONTROLS:
				show_screen(_back_screen)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("upgrades"):
		if current == Screen.NONE:
			_back_screen = Screen.NONE
			show_screen(Screen.UPGRADES)
		elif current == Screen.UPGRADES:
			show_screen(_back_screen)
		get_viewport().set_input_as_handled()


func show_screen(screen: Screen) -> void:
	current = screen
	for key in _panels:
		(_panels[key] as Control).visible = key == screen
	_root.visible = screen != Screen.NONE
	get_tree().paused = screen != Screen.NONE
	if screen == Screen.NONE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if screen == Screen.UPGRADES:
		var game := get_tree().get_first_node_in_group("game")
		if game != null:
			game.refresh_upgrades()


# ---------------------------------------------------------------------------
# Écrans
# ---------------------------------------------------------------------------
func _panel(screen: Screen) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_panels[screen] = center
	return box


func _label(parent: Control, text: String, size: int, color := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 52)
	b.add_theme_font_size_override("font_size", 22)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.12, 0.2, 0.9)
	normal.border_color = Color(0.4, 0.7, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.3, 0.5, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _build_title() -> void:
	var box := _panel(Screen.TITLE)
	_label(box, "MAGE VOLANT", 84, Color(1.0, 0.8, 0.4))
	_label(box, "La ville est tombée aux mains de la Milice Rouge.\nTu es le seul à pouvoir la sauver... ou à la soumettre.", 22, Color(0.85, 0.85, 0.95))
	_label(box, "", 10)
	_button(box, "Jouer", func() -> void:
		show_screen(Screen.NONE)
		start_requested.emit())
	_button(box, "Commandes", func() -> void:
		_back_screen = Screen.TITLE
		show_screen(Screen.CONTROLS))
	_button(box, "Quitter", func() -> void: get_tree().quit())


func _build_pause() -> void:
	var box := _panel(Screen.PAUSE)
	_label(box, "PAUSE", 64)
	_button(box, "Reprendre", func() -> void: show_screen(Screen.NONE))
	_button(box, "Améliorations", func() -> void:
		_back_screen = Screen.PAUSE
		show_screen(Screen.UPGRADES))
	_button(box, "Commandes", func() -> void:
		_back_screen = Screen.PAUSE
		show_screen(Screen.CONTROLS))
	_button(box, "Recommencer", func() -> void: restart_requested.emit())
	_button(box, "Quitter", func() -> void: get_tree().quit())


func _build_upgrades() -> void:
	var box := _panel(Screen.UPGRADES)
	_label(box, "AMÉLIORATIONS", 52, Color(1.0, 0.8, 0.4))
	_points_label = _label(box, "", 22)
	_upgrade_list = VBoxContainer.new()
	_upgrade_list.add_theme_constant_override("separation", 10)
	box.add_child(_upgrade_list)
	_button(box, "Retour", func() -> void: show_screen(_back_screen))


## Remplit la liste. `upgrades` : tableau de dictionnaires
## {id, name, desc, rank, max, cost}.
func set_upgrades(upgrades: Array, points: int) -> void:
	_points_label.text = "Points disponibles : %d   (1 point par niveau gagné)" % points
	for c in _upgrade_list.get_children():
		c.queue_free()
	for u in upgrades:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		_upgrade_list.add_child(row)
		var info := Label.new()
		info.text = "%s   %s\n%s" % [u["name"], "●".repeat(int(u["rank"])) + "○".repeat(int(u["max"]) - int(u["rank"])), u["desc"]]
		info.custom_minimum_size = Vector2(560, 0)
		info.add_theme_font_size_override("font_size", 18)
		row.add_child(info)
		var b := Button.new()
		var maxed: bool = int(u["rank"]) >= int(u["max"])
		b.text = "MAX" if maxed else "Acheter"
		b.disabled = maxed or points <= 0
		b.custom_minimum_size = Vector2(140, 44)
		var id: String = u["id"]
		b.pressed.connect(func() -> void: upgrade_requested.emit(id))
		row.add_child(b)


func _build_controls() -> void:
	var box := _panel(Screen.CONTROLS)
	_label(box, "COMMANDES", 52, Color(1.0, 0.8, 0.4))
	var text := Label.new()
	text.text = CONTROLS_TEXT
	text.add_theme_font_size_override("font_size", 19)
	box.add_child(text)
	_button(box, "Retour", func() -> void: show_screen(_back_screen))


func _build_ending() -> void:
	var box := _panel(Screen.ENDING)
	_ending_title = _label(box, "", 64)
	_ending_text = _label(box, "", 22)
	_ending_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ending_text.custom_minimum_size = Vector2(900, 0)
	_button(box, "Rejouer", func() -> void: restart_requested.emit())
	_button(box, "Quitter", func() -> void: get_tree().quit())


func show_ending(title: String, text: String, color: Color) -> void:
	_ending_title.text = title
	_ending_title.add_theme_color_override("font_color", color)
	_ending_text.text = text
	show_screen(Screen.ENDING)
