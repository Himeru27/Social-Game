class_name PlayerListPanel
extends CanvasLayer
## Hold the player-list key (default Tab) to see everyone in the server.
## Styled like the server browser rows: slanted dark strips, Anton heading.

var _title: Label
var _box: VBoxContainer
var _panel: Control


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.offset_left = -210
	col.offset_right = 210
	col.offset_top = 90
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.visible = false
	root.add_child(col)
	_panel = col

	_title = Label.new()
	_title.add_theme_font_override("font", MenuStyle.FONT)
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", MenuStyle.ORANGE)
	col.add_child(_strip(_title, 8))

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_box)


func _strip(content: Control, v_margin: int = 5) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", MenuStyle.strip(Color(MenuStyle.INK, 0.92), Color(1, 1, 1, 0.55), 1, Vector4(34, 22, v_margin, v_margin)))
	pc.add_child(content)
	return pc


func is_shown() -> bool:
	return _panel.visible


func set_shown(on: bool) -> void:
	_panel.visible = on


## entries: [{name, you, host}]
func refresh(entries: Array, max_players: int) -> void:
	_title.text = "PLAYERS ONLINE: %d/%d" % [entries.size(), max_players]
	for c in _box.get_children():
		c.queue_free()
	for e in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_l := Label.new()
		name_l.text = str(e["name"])
		name_l.add_theme_font_size_override("font_size", 20)
		name_l.add_theme_color_override("font_color", MenuStyle.WHITE)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		row.add_child(name_l)
		var tags: Array[String] = []
		if e["you"]:
			tags.append("YOU")
		if e["host"]:
			tags.append("HOST")
		if not tags.is_empty():
			var tag_l := Label.new()
			tag_l.text = "  ·  ".join(PackedStringArray(tags))
			tag_l.add_theme_font_override("font", MenuStyle.FONT)
			tag_l.add_theme_font_size_override("font_size", 17)
			tag_l.add_theme_color_override("font_color", MenuStyle.ORANGE)
			row.add_child(tag_l)
		_box.add_child(_strip(row))
