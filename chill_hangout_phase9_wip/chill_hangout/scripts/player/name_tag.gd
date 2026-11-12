class_name NameTag
extends Node3D
## Billboard username above a player's head + a speech bubble for chat messages.
## The bubble is a small SubViewport (panel + wrapped label) shown on a billboard sprite, so it has a
## real background, wraps long text, never gets huge, and disappears after `bubble_seconds`.

const MAX_BUBBLE_W := 300.0
const PIXEL_SIZE := 0.0042
const VISIBLE_RANGE := 28.0

## Base lifetime of a bubble; longer messages stay a bit longer (see show_message).
@export var bubble_seconds := 5.0

var _name_label: Label3D
var _bubble: Sprite3D
var _vp: SubViewport
var _panel: PanelContainer
var _who: Label
var _text: Label
var _timer: Timer
var _name := ""
var _head_y := 2.2
var _token := 0


func setup(display_name: String, head_y: float) -> void:
	_name = display_name
	_head_y = head_y
	position = Vector3(0, head_y, 0)
	_name_label = Label3D.new()
	_name_label.text = display_name
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.pixel_size = 0.0042
	_name_label.font_size = 54
	_name_label.outline_size = 14
	_name_label.outline_modulate = Color(0.1, 0.12, 0.2)
	_name_label.shaded = false
	_name_label.double_sided = true
	_name_label.no_depth_test = false
	_name_label.visibility_range_end = VISIBLE_RANGE
	add_child(_name_label)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_message)
	add_child(_timer)


func set_display_name(n: String) -> void:
	_name = n
	if _name_label:
		_name_label.text = n
	if _who:
		_who.text = n


func has_message() -> bool:
	return _bubble != null and _bubble.visible


func current_text() -> String:
	return _text.text if _text else ""


func show_message(text: String) -> void:
	if _bubble == null:
		_build_bubble()
	_who.text = _name
	_text.text = text
	_token += 1
	var mine := _token
	_vp.size = Vector2i(int(MAX_BUBBLE_W) + 20, 40)
	_bubble.visible = false
	# Let the layout compute, then size the viewport to the panel (one extra frame).
	await get_tree().process_frame
	if mine != _token or not is_inside_tree():
		return
	var s := _panel.get_combined_minimum_size()
	_vp.size = Vector2i(ceili(s.x), ceili(s.y))
	_panel.size = s
	_bubble.visible = true
	_bubble.position = Vector3(0, 0.22 + s.y * PIXEL_SIZE * 0.5 + 0.05, 0)
	_timer.start(clampf(bubble_seconds + text.length() * 0.04, bubble_seconds, 10.0))


func hide_message() -> void:
	_token += 1
	if _bubble:
		_bubble.visible = false


func _build_bubble() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.size = Vector2i(320, 60)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.22, 0.88)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", sb)
	_vp.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_panel.add_child(v)
	_who = Label.new()
	_who.add_theme_font_size_override("font_size", 15)
	_who.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(_who)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 20)
	_text.add_theme_color_override("font_color", UITheme.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = MAX_BUBBLE_W - 20.0
	v.add_child(_text)
	_bubble = Sprite3D.new()
	_bubble.texture = _vp.get_texture()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.pixel_size = PIXEL_SIZE
	_bubble.shaded = false
	_bubble.double_sided = true
	_bubble.transparent = true
	_bubble.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_bubble.visibility_range_end = VISIBLE_RANGE
	_bubble.visible = false
	add_child(_bubble)
