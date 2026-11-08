class_name PlayerListPanel
extends CanvasLayer
## Hold the player-list key (default Tab) to see everyone in the server.

var _title: Label
var _box: VBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -190
	_panel.offset_right = 190
	_panel.offset_top = 90
	_panel.visible = false
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(_title)
	_box = VBoxContainer.new()
	v.add_child(_box)


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
		var l := Label.new()
		l.text = "%s%s%s" % [e["name"], "  (you)" if e["you"] else "", "  [host]" if e["host"] else ""]
		if e["you"]:
			l.add_theme_color_override("font_color", UITheme.TEAL)
		_box.add_child(l)
