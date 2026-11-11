class_name ChatUI
extends CanvasLayer
## Bottom-left chat: scrolling history + input. T opens (handled by OnlineRoom), Enter sends,
## Esc closes the input WITHOUT opening the pause/leave logic (the event is consumed here).
## Recent messages stay visible for a few seconds after they arrive, then fade.

signal opened
signal closed

const MAX_PARAGRAPHS := 80
const VISIBLE_SEC := 8.0

var is_open := false

var _panel: PanelContainer
var _log: RichTextLabel
var _row: HBoxContainer
var _edit: LineEdit
var _since_msg := 999.0
var _sb: StyleBoxFlat


func _ready() -> void:
	layer = 12
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 16
	_panel.offset_right = 500
	_panel.offset_top = -330
	_panel.offset_bottom = -76
	_sb = StyleBoxFlat.new()
	_sb.bg_color = Color(0.08, 0.1, 0.2, 0.0)
	_sb.set_corner_radius_all(12)
	_sb.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", _sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.context_menu_enabled = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size", 18)
	_log.add_theme_font_size_override("bold_font_size", 18)
	_log.add_theme_color_override("font_outline_color", UITheme.BG)
	_log.add_theme_constant_override("outline_size", 5)
	v.add_child(_log)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	_row.visible = false
	v.add_child(_row)
	_edit = LineEdit.new()
	_edit.placeholder_text = "Type a message and press Enter..."
	_edit.max_length = NetProtocol.CHAT_MAX
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_submitted.connect(func(_t: String) -> void: submit())
	_row.add_child(_edit)
	var send := Button.new()
	send.text = "SEND"
	send.custom_minimum_size = Vector2(80, 0)
	send.pressed.connect(func() -> void:
		AudioManager.play_click()
		submit())
	_row.add_child(send)
	_panel.modulate.a = 0.0


func open() -> void:
	if is_open:
		return
	is_open = true
	_row.visible = true
	_sb.bg_color.a = 0.6
	_panel.modulate.a = 1.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_edit.clear()
	_edit.grab_focus.call_deferred()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_edit.release_focus()
	_row.visible = false
	_sb.bg_color.a = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()


## Sends the typed text (empty messages are ignored) and closes the input.
func submit() -> void:
	var text := _edit.text.strip_edges()
	_edit.clear()
	if text != "":
		Net.send_chat(text.substr(0, NetProtocol.CHAT_MAX))
	close()


func add_message(sender: String, text: String, own: bool) -> void:
	_trim()
	_log.push_color(UITheme.TEAL if own else UITheme.ACCENT)
	_log.add_text(sender + ": ")
	_log.pop()
	_log.push_color(UITheme.TEXT)
	_log.add_text(text)
	_log.pop()
	_log.newline()
	_since_msg = 0.0


func add_system(text: String) -> void:
	_trim()
	_log.push_color(UITheme.MUTED)
	_log.add_text(text)
	_log.pop()
	_log.newline()
	_since_msg = 0.0


func _trim() -> void:
	while _log.get_paragraph_count() > MAX_PARAGRAPHS:
		_log.remove_paragraph(0)


func _process(delta: float) -> void:
	_since_msg += delta
	if is_open:
		return
	var want := 1.0 if _since_msg < VISIBLE_SEC else 0.0
	_panel.modulate.a = move_toward(_panel.modulate.a, want, delta * 2.0)


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
