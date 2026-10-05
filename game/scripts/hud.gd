extends CanvasLayer
## Interface en jeu : viseur, vie, énergie, pouvoirs, karma, niveau, mission,
## marqueur d'objectif, messages, barre du boss, effets de vitesse et de dégâts.

const SPEED_LINES_SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(uv);
	float angle = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float count = 140.0;
	float id = floor(angle * count);
	float rnd = hash(id);
	float rnd2 = hash(id + 71.0);
	// Chaque ligne est un trait fin qui file vers l'extérieur.
	float cell = fract(angle * count);
	float width = 0.08 + rnd * 0.18;
	float line = 1.0 - smoothstep(0.0, width, abs(cell - 0.5));
	float seg = fract(r * (1.5 + rnd2 * 2.0) - TIME * (1.5 + rnd * 2.5) + rnd2 * 7.0);
	float streak = smoothstep(0.0, 0.25, seg) * (1.0 - smoothstep(0.55, 1.0, seg));
	float present = step(0.35 - intensity * 0.3, rnd2);
	// Le centre de l'écran reste dégagé.
	float inner = mix(0.62, 0.3, intensity) + rnd * 0.08;
	float radial = smoothstep(inner, inner + 0.22, r);
	float a = line * streak * present * radial * intensity * 0.75;
	float vignette = smoothstep(0.4, 0.9, r) * intensity * 0.35;
	float total = max(a, vignette);
	vec3 col = mix(vec3(0.0), vec3(1.0), a / max(a + vignette, 0.0001));
	COLOR = vec4(col, total);
}
"""

class Crosshair extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 2.5, Color(1, 1, 1, 0.9))
		draw_arc(c, 11.0, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.5)


## Jauge de karma : rouge (infâme) à gauche, bleu (héros) à droite.
class KarmaBar extends Control:
	const EVIL := Color(1.0, 0.2, 0.15)
	const GOOD := Color(0.35, 0.7, 1.0)
	var value := 0.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var steps := 40
		for i in steps:
			var t := float(i) / steps
			var col: Color
			if t < 0.5:
				col = EVIL.lerp(Color(0.5, 0.5, 0.5), t * 2.0)
			else:
				col = Color(0.5, 0.5, 0.5).lerp(GOOD, (t - 0.5) * 2.0)
			col.a = 0.85
			draw_rect(Rect2(w * t, 0, w / steps + 1.0, h), col)
		var x := (value + 100.0) / 200.0 * w
		draw_rect(Rect2(x - 2.0, -4.0, 4.0, h + 8.0), Color(1, 1, 1))
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.8), false, 1.5)


## Marqueur d'objectif : losange sur la cible, ou flèche au bord de l'écran.
class ObjectiveMarker extends Control:
	var active := false
	var on_screen := true
	var pos := Vector2.ZERO
	var direction := Vector2.RIGHT
	var label := ""
	var color := Color(1.0, 0.8, 0.2)

	func _draw() -> void:
		if not active:
			return
		if on_screen:
			var pts := PackedVector2Array([pos + Vector2(0, -14), pos + Vector2(10, 0), pos + Vector2(0, 14), pos + Vector2(-10, 0)])
			draw_colored_polygon(pts, Color(color.r, color.g, color.b, 0.85))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 2.0)
		else:
			var side := Vector2(-direction.y, direction.x)
			var tip := pos + direction * 16.0
			var pts2 := PackedVector2Array([tip, pos - direction * 6.0 + side * 12.0, pos - direction * 6.0 - side * 12.0])
			draw_colored_polygon(pts2, Color(color.r, color.g, color.b, 0.9))
		var font := get_theme_default_font()
		draw_string_outline(font, pos + Vector2(-40, 34), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos + Vector2(-40, 34), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, color)


var _health_bar: ProgressBar
var _energy_bar: ProgressBar
var _xp_bar: ProgressBar
var _level_label: Label
var _karma_bar: KarmaBar
var _karma_label: Label
var _fly_label: Label
var _message: Label
var _help: Label
var _objective_title: Label
var _objective_text: Label
var _prompt: Label
var _prompt_bar: ProgressBar
var _feed: VBoxContainer
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _damage_overlay: ColorRect
var _speed_lines: ColorRect
var _speed_mat: ShaderMaterial
var _marker: ObjectiveMarker
var _marker_world := Vector3.ZERO
var _ability_labels: Dictionary = {}


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

	_speed_mat = ShaderMaterial.new()
	_speed_mat.shader = Shader.new()
	_speed_mat.shader.code = SPEED_LINES_SHADER
	_speed_lines = ColorRect.new()
	_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_lines.material = _speed_mat
	_speed_lines.visible = false
	root.add_child(_speed_lines)

	var cross := Crosshair.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)

	_marker = ObjectiveMarker.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_marker)

	# --- En bas à gauche : vie et énergie ---
	var bars := VBoxContainer.new()
	_place(bars, Vector4(0, 1, 0, 1), Vector4(30, -96, 450, -30))
	bars.add_theme_constant_override("separation", 8)
	root.add_child(bars)
	_health_bar = _make_bar(bars, "VIE", Color(0.9, 0.2, 0.25), 320)
	_energy_bar = _make_bar(bars, "ÉNERGIE", Color(0.25, 0.6, 1.0), 320)

	# --- En bas au centre : pouvoirs ---
	var abilities := HBoxContainer.new()
	_place(abilities, Vector4(0.5, 1, 0.5, 1), Vector4(-380, -80, 380, -24))
	abilities.alignment = BoxContainer.ALIGNMENT_CENTER
	abilities.add_theme_constant_override("separation", 14)
	root.add_child(abilities)
	_ability_labels["fire"] = _make_ability(abilities, "Clic gauche", "Boule d'énergie", Color(1, 0.55, 0.2))
	_ability_labels["shockwave"] = _make_ability(abilities, "E", "Onde de choc", Color(0.4, 0.85, 1.0))
	_ability_labels["black_hole"] = _make_ability(abilities, "Clic droit", "Trou noir", Color(0.7, 0.4, 1.0))

	# --- En haut à droite : niveau, XP, karma ---
	var stats := VBoxContainer.new()
	_place(stats, Vector4(1, 0, 1, 0), Vector4(-360, 18, -24, 150))
	stats.add_theme_constant_override("separation", 6)
	root.add_child(stats)
	_level_label = _make_label(stats, "Niveau 1", 22)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_bar = _make_bar(stats, "XP", Color(0.95, 0.8, 0.3), 260)
	_karma_label = _make_label(stats, "Karma : Neutre", 18)
	_karma_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_karma_bar = KarmaBar.new()
	_karma_bar.custom_minimum_size = Vector2(336, 14)
	stats.add_child(_karma_bar)
	_fly_label = _make_label(stats, "", 18)
	_fly_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fly_label.add_theme_color_override("font_color", Color(1, 0.8, 0.4))

	# --- En haut à gauche : mission ---
	var mission := VBoxContainer.new()
	_place(mission, Vector4(0, 0, 0, 0), Vector4(24, 18, 560, 160))
	root.add_child(mission)
	_objective_title = _make_label(mission, "MISSION", 15)
	_objective_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_objective_text = _make_label(mission, "", 20)
	_objective_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_text.custom_minimum_size = Vector2(520, 0)

	# --- Sous le viseur : interaction ---
	var prompt_box := VBoxContainer.new()
	_place(prompt_box, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-300, 60, 300, 130))
	prompt_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(prompt_box)
	_prompt = _make_label(prompt_box, "", 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_bar = ProgressBar.new()
	_prompt_bar.custom_minimum_size = Vector2(200, 8)
	_prompt_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prompt_bar.show_percentage = false
	_prompt_bar.max_value = 1.0
	_style_bar(_prompt_bar, Color(0.4, 1.0, 0.6))
	_prompt_bar.visible = false
	prompt_box.add_child(_prompt_bar)

	# --- À droite : fil des récompenses (+XP, karma...) ---
	_feed = VBoxContainer.new()
	_place(_feed, Vector4(1, 0.5, 1, 0.5), Vector4(-320, -80, -24, 120))
	_feed.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_feed)

	# --- En haut au centre : barre du boss ---
	_boss_box = VBoxContainer.new()
	_place(_boss_box, Vector4(0.5, 0, 0.5, 0), Vector4(-320, 20, 320, 80))
	root.add_child(_boss_box)
	var boss_name := _make_label(_boss_box, "LE COLOSSE", 22)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(640, 18)
	_boss_bar.show_percentage = false
	_style_bar(_boss_bar, Color(0.9, 0.15, 0.1))
	_boss_box.add_child(_boss_bar)
	_boss_box.visible = false

	_message = _make_label(root, "", 34)
	_place(_message, Vector4(0.5, 0.28, 0.5, 0.28), Vector4(-560, 0, 560, 90))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_help = _make_label(root, "\n".join([
		"ZQSD : se déplacer   Souris : viser   Espace : sauter / s'envoler",
		"F : voler / atterrir   Ctrl : descendre   Maj : courir / turbo",
		"Clic gauche : boule d'énergie   E : onde de choc   Clic droit : trou noir",
		"R (maintenir) : absorber l'électricité / soigner un civil",
		"T (maintenir) : absorber la vie d'un civil (infâme)",
		"Tab : améliorations   Échap : pause   H : cacher cette aide",
	]), 15)
	_place(_help, Vector4(0, 1, 0, 1), Vector4(24, -250, 700, -110))
	_help.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible


func _process(_delta: float) -> void:
	_update_marker()


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------
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
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _style_bar(bar: ProgressBar, color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


func _make_bar(parent: Control, title: String, color: Color, width: float) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	parent.add_child(row)
	var l := _make_label(row, title, 16)
	l.custom_minimum_size = Vector2(66, 0)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 18)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	_style_bar(bar, color)
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


# ---------------------------------------------------------------------------
# Mises à jour appelées par le jeu
# ---------------------------------------------------------------------------
func set_health(value: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = value


func set_energy(value: float, max_value: float) -> void:
	_energy_bar.max_value = max_value
	_energy_bar.value = value


func set_flying(flying: bool) -> void:
	_fly_label.text = "✦ EN VOL ✦" if flying else ""


func set_level(level: int, xp: int, xp_next: int, points: int) -> void:
	_level_label.text = "Niveau %d" % level
	if points > 0:
		_level_label.text += "   (%d point%s — Tab)" % [points, "s" if points > 1 else ""]
	_xp_bar.max_value = xp_next
	_xp_bar.value = xp


func set_karma(value: float, rank: String, color: Color) -> void:
	_karma_bar.value = value
	_karma_bar.queue_redraw()
	_karma_label.text = "Karma : %s" % rank
	_karma_label.add_theme_color_override("font_color", color)


## Grise un pouvoir indisponible et affiche le temps restant ou le niveau requis.
func set_ability_state(id: String, available: bool, cooldown: float, locked_level := 0) -> void:
	var l: Label = _ability_labels[id]
	var base: String = l.get_meta("base_text")
	if locked_level > 0:
		l.text = "%s\n[Niveau %d]" % [base, locked_level]
		l.modulate = Color(1, 1, 1, 0.3)
		return
	l.text = base if cooldown <= 0.0 else "%s  (%.1f s)" % [base, cooldown]
	l.modulate = Color(1, 1, 1, 1) if available else Color(1, 1, 1, 0.35)


func set_objective(text: String) -> void:
	_objective_text.text = text


func set_marker(active: bool, world_pos := Vector3.ZERO, color := Color(1.0, 0.8, 0.2)) -> void:
	_marker.active = active
	_marker_world = world_pos
	_marker.color = color
	if not active:
		_marker.queue_redraw()


func _update_marker() -> void:
	if not _marker.active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var center := screen * 0.5
	var behind := cam.is_position_behind(_marker_world)
	var sp := cam.unproject_position(_marker_world)
	if behind:
		sp = screen - sp
	var margin := 60.0
	var inside := not behind and sp.x > margin and sp.x < screen.x - margin and sp.y > margin and sp.y < screen.y - margin
	_marker.on_screen = inside
	if inside:
		_marker.pos = sp
	else:
		var dir := (sp - center).normalized()
		if dir.length() < 0.01:
			dir = Vector2.DOWN
		var sx := (center.x - margin) / maxf(absf(dir.x), 0.001)
		var sy := (center.y - margin) / maxf(absf(dir.y), 0.001)
		_marker.pos = center + dir * minf(sx, sy)
		_marker.direction = dir
	var dist := cam.global_position.distance_to(_marker_world)
	_marker.label = "%d m" % int(dist)
	_marker.queue_redraw()


func set_prompt(text: String, progress: float) -> void:
	_prompt.text = text
	_prompt_bar.visible = progress > 0.0
	_prompt_bar.value = progress


## Petit message qui apparaît à droite puis s'efface (ex. « +25 XP »).
func feed(text: String, color := Color(1, 1, 1)) -> void:
	var l := _make_label(_feed, text, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_color", color)
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()


func show_boss(visible_bar: bool) -> void:
	_boss_box.visible = visible_bar


func set_boss_health(value: float, max_value: float) -> void:
	_boss_bar.max_value = max_value
	_boss_bar.value = value


func set_speed_effect(amount: float) -> void:
	_speed_lines.visible = amount > 0.02
	_speed_mat.set_shader_parameter("intensity", amount)


func flash_damage() -> void:
	_damage_overlay.color.a = 0.35
	var t := create_tween()
	t.tween_property(_damage_overlay, "color:a", 0.0, 0.4)


func show_message(text: String, duration := 3.0) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(_message, "modulate:a", 0.0, 0.6)
