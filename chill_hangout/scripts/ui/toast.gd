class_name ToastLayer
extends CanvasLayer
## Small pop-up notifications (top centre). Add one to a scene, then call push("text").

var _box: VBoxContainer


func _ready() -> void:
	layer = 50
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_box.offset_left = -270
	_box.offset_right = 270
	_box.offset_top = 70
	_box.add_theme_constant_override("separation", 8)
	root.add_child(_box)


func push(text: String, color: Color = UITheme.TEXT, seconds: float = 3.5) -> void:
	if _box == null:
		return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 520
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)
	_box.add_child(panel)
	while _box.get_child_count() > 4:
		_box.get_child(0).queue_free()
		_box.remove_child(_box.get_child(0))
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_interval(seconds)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)
