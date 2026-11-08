class_name GameHUD
extends CanvasLayer
## In-game HUD: smooth stamina bar, username, hint line. Call bind_player(player).

var _bar: ColorRect
var _fill: ColorRect
var _name_label: Label
var _hint: Label
var _warn: Label
var _prompt: Label
var _conn: Label
var _target := 1.0
var _shown := 1.0
var _depleted := false
var _t := 0.0

const BAR_W := 340.0
const BAR_H := 16.0


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_name_label = Label.new()
	_name_label.position = Vector2(24, 18)
	_name_label.add_theme_font_size_override("font_size", 26)
	_name_label.add_theme_color_override("font_outline_color", UITheme.BG)
	_name_label.add_theme_constant_override("outline_size", 6)
	root.add_child(_name_label)

	_hint = Label.new()
	_hint.position = Vector2(24, 56)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	_hint.add_theme_color_override("font_outline_color", UITheme.BG)
	_hint.add_theme_constant_override("outline_size", 5)
	root.add_child(_hint)

	_conn = Label.new()
	_conn.position = Vector2(24, 82)
	_conn.add_theme_font_size_override("font_size", 14)
	_conn.add_theme_color_override("font_outline_color", UITheme.BG)
	_conn.add_theme_constant_override("outline_size", 5)
	_conn.visible = false
	root.add_child(_conn)

	_bar = ColorRect.new()
	_bar.color = Color(UITheme.BG, 0.75)
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -BAR_W / 2.0
	_bar.offset_right = BAR_W / 2.0
	_bar.offset_top = -52
	_bar.offset_bottom = -52 + BAR_H + 6
	root.add_child(_bar)
	_fill = ColorRect.new()
	_fill.position = Vector2(3, 3)
	_fill.size = Vector2(BAR_W - 6, BAR_H)
	_bar.add_child(_fill)

	_warn = Label.new()
	_warn.text = "OUT OF STAMINA"
	_warn.add_theme_font_size_override("font_size", 14)
	_warn.add_theme_color_override("font_color", Color("#ff6b6b"))
	_warn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_warn.offset_left = -70
	_warn.offset_top = -78
	_warn.visible = false
	root.add_child(_warn)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_color", UITheme.TEXT)
	_prompt.add_theme_color_override("font_outline_color", UITheme.BG)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -260
	_prompt.offset_right = 260
	_prompt.offset_top = -140
	_prompt.offset_bottom = -104
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	root.add_child(_prompt)


func bind_player(p: Player) -> void:
	_name_label.text = p.display_name
	p.prompt_changed.connect(set_prompt)
	p.stamina_changed.connect(func(v: float, m: float, dep: bool) -> void:
		_target = v / m
		_depleted = dep)


## Called about once a second in online rooms with the round-trip time in ms.
func set_connection(rtt_ms: int) -> void:
	_conn.visible = true
	if rtt_ms < 0:
		_conn.text = "ONLINE"
		_conn.add_theme_color_override("font_color", UITheme.MUTED)
	elif rtt_ms == 0:
		_conn.text = "CONNECTION: waiting for server..."
		_conn.add_theme_color_override("font_color", Color("#ff6b6b"))
	elif rtt_ms > 250:
		_conn.text = "CONNECTION UNSTABLE  %d ms" % rtt_ms
		_conn.add_theme_color_override("font_color", Color("#ff6b6b"))
	else:
		_conn.text = "PING %d ms" % rtt_ms
		_conn.add_theme_color_override("font_color", UITheme.MUTED)


func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""


func set_hint(text: String) -> void:
	_hint.text = text


func _process(delta: float) -> void:
	_t += delta
	_shown = lerpf(_shown, _target, 1.0 - exp(-12.0 * delta))
	_fill.size.x = (BAR_W - 6.0) * _shown
	_warn.visible = _depleted
	if _depleted:
		_fill.color = Color("#ff6b6b")
		_fill.modulate.a = 0.6 + 0.4 * sin(_t * 10.0)
	else:
		_fill.modulate.a = 1.0
		_fill.color = UITheme.ACCENT if _shown < 0.25 else UITheme.TEAL
