class_name EmoteMenu
extends CanvasLayer
## Emote picker (opened with the emote key, default "."). Click a button or press 1-5.
## Esc or the emote key closes it; Esc is consumed so it never reaches the pause logic.

signal selected(emote_id: int)
signal closed

var is_open := false
var _panel: PanelContainer


func _ready() -> void:
	layer = 13
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = -230
	_panel.offset_bottom = -90
	_panel.visible = false
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "EMOTES  (1-5, or click)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UITheme.MUTED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for e in NetProtocol.EMOTES:
		var id := int(e["id"])
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 100)
		b.pressed.connect(func() -> void:
			AudioManager.play_click()
			_choose(id))
		b.mouse_entered.connect(AudioManager.play_hover)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(col)
		var icon := EmoteIcon.new()
		icon.emote_id = id
		icon.custom_minimum_size = Vector2(56, 56)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(icon)
		var l := Label.new()
		l.text = "%d  %s" % [id + 1, e["name"]]
		l.add_theme_font_size_override("font_size", 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
		row.add_child(b)


func open() -> void:
	if is_open:
		return
	is_open = true
	_panel.visible = true


func close() -> void:
	if not is_open:
		return
	is_open = false
	_panel.visible = false
	closed.emit()


func _choose(id: int) -> void:
	close()
	selected.emit(id)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("emote_menu"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_5:
			_choose(k - KEY_1)
			get_viewport().set_input_as_handled()


## Tiny stick-figure pictogram for each emote (drawn, so no image files are needed).
class EmoteIcon:
	extends Control
	var emote_id := 0

	func _draw() -> void:
		var c := UITheme.TEXT
		var a := UITheme.ACCENT
		var w := 3.0
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.06), true)
		var cx := size.x * 0.5
		if emote_id == NetProtocol.EMOTE_LAUGH:
			draw_circle(Vector2(cx, 28), 20, a)
			draw_circle(Vector2(cx - 7, 22), 2.5, UITheme.BG)
			draw_circle(Vector2(cx + 7, 22), 2.5, UITheme.BG)
			draw_arc(Vector2(cx, 30), 9, 0.1, PI - 0.1, 10, UITheme.BG, 3.0)
			draw_line(Vector2(cx - 9, 31), Vector2(cx + 9, 31), UITheme.BG, 3.0)
			return
		draw_circle(Vector2(cx, 11), 6, c)
		match emote_id:
			NetProtocol.EMOTE_WAVE:
				draw_line(Vector2(cx, 18), Vector2(cx, 36), c, w)
				draw_line(Vector2(cx, 22), Vector2(cx + 14, 6), a, w)
				draw_arc(Vector2(cx + 18, 4), 5, PI, TAU, 6, a, 2.0)
				draw_line(Vector2(cx, 22), Vector2(cx - 9, 32), c, w)
				_legs(cx, 36, c, w)
			NetProtocol.EMOTE_DANCE:
				draw_line(Vector2(cx, 18), Vector2(cx, 36), c, w)
				draw_line(Vector2(cx, 22), Vector2(cx - 14, 8), a, w)
				draw_line(Vector2(cx, 22), Vector2(cx + 14, 8), a, w)
				draw_line(Vector2(cx, 36), Vector2(cx - 10, 52), c, w)
				draw_line(Vector2(cx, 36), Vector2(cx + 12, 48), c, w)
			NetProtocol.EMOTE_SIT:
				draw_line(Vector2(cx - 6, 18), Vector2(cx - 6, 38), c, w)
				draw_line(Vector2(cx - 6, 38), Vector2(cx + 14, 38), a, w)
				draw_line(Vector2(cx + 14, 38), Vector2(cx + 14, 50), a, w)
				draw_line(Vector2(cx - 6, 24), Vector2(cx + 6, 32), c, w)
			NetProtocol.EMOTE_GREETING:
				draw_line(Vector2(cx, 18), Vector2(cx, 36), c, w)
				draw_line(Vector2(cx, 22), Vector2(cx - 15, 30), a, w)
				draw_line(Vector2(cx, 22), Vector2(cx + 15, 30), a, w)
				_legs(cx, 36, c, w)

	func _legs(cx: float, y: float, c: Color, w: float) -> void:
		draw_line(Vector2(cx, y), Vector2(cx - 8, 52), c, w)
		draw_line(Vector2(cx, y), Vector2(cx + 8, 52), c, w)
