class_name MenuStyle
extends RefCounted
## Shared look for the main menu and the server screen: slanted strips, Anton font,
## white + orange on a bright sky. No red anywhere.

const FONT_PATH := "res://assets/fonts/Anton-Regular.ttf"
## Loaded at runtime (not preload) so the project still opens if Godot has not imported the font yet.
static var FONT: Font = _load_font()


static func _load_font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		var res: Variant = load(FONT_PATH)
		if res is Font:
			return res
	if FileAccess.file_exists(FONT_PATH):
		var f := FontFile.new()
		f.data = FileAccess.get_file_as_bytes(FONT_PATH)
		return f
	return ThemeDB.fallback_font


const ORANGE := Color("#ff9a1f")        # accent + hover
const ORANGE_DEEP := Color("#e07a00")   # pressed
const INK := Color("#0e1a24")           # button fill, outlines, text on orange
const WHITE := Color("#ffffff")
const WARN := Color("#ffd54a")          # offline / error text (yellow, not red)
const SLANT := 0.28


## Slanted strip. margins = (left, right, top, bottom) content margins.
static func strip(fill: Color, border: Color, border_w: int = 0, margins := Vector4(34, 20, 4, 4)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.skew = Vector2(SLANT, 0.0)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = margins.x
	sb.content_margin_right = margins.y
	sb.content_margin_top = margins.z
	sb.content_margin_bottom = margins.w
	return sb


## Plain (not slanted) box for inputs and pop-up panels.
static func flat(fill: Color, border: Color, border_w: int = 2, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_content_margin_all(margin)
	return sb


static func style_button(b: Button, size: int = 30, margins := Vector4(34, 20, 4, 4)) -> void:
	var base := Color(INK, 0.92)
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", strip(base, WHITE, 2, margins))
	b.add_theme_stylebox_override("hover", strip(ORANGE, WHITE, 2, margins))
	b.add_theme_stylebox_override("pressed", strip(ORANGE_DEEP, WHITE, 2, margins))
	b.add_theme_stylebox_override("focus", strip(Color(0, 0, 0, 0), ORANGE, 3, margins))
	b.add_theme_stylebox_override("disabled", strip(Color(INK, 0.55), Color(1, 1, 1, 0.35), 2, margins))
	b.add_theme_color_override("font_color", WHITE)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Small grow on hover (only touches scale, so it is safe inside containers).
	b.mouse_entered.connect(func() -> void:
		if b.disabled:
			return
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.03, 0.12))
	b.mouse_exited.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))


static func style_line_edit(le: LineEdit) -> void:
	le.add_theme_stylebox_override("normal", flat(Color(INK, 0.92), WHITE, 2, 10))
	le.add_theme_stylebox_override("focus", flat(Color(INK, 0.92), ORANGE, 3, 10))
	le.add_theme_stylebox_override("read_only", flat(Color(INK, 0.6), Color(1, 1, 1, 0.3), 2, 10))
	le.add_theme_color_override("font_color", WHITE)
	le.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.55))
	le.add_theme_color_override("caret_color", ORANGE)
	le.add_theme_color_override("selection_color", Color(ORANGE, 0.5))


static func style_option(o: OptionButton) -> void:
	o.add_theme_stylebox_override("normal", flat(Color(INK, 0.92), WHITE, 2, 10))
	o.add_theme_stylebox_override("hover", flat(ORANGE, WHITE, 2, 10))
	o.add_theme_stylebox_override("pressed", flat(ORANGE_DEEP, WHITE, 2, 10))
	o.add_theme_stylebox_override("focus", flat(Color(0, 0, 0, 0), ORANGE, 3, 10))
	o.add_theme_color_override("font_color", WHITE)
	o.add_theme_color_override("font_hover_color", INK)
	o.add_theme_color_override("font_pressed_color", INK)
	o.add_theme_color_override("font_focus_color", WHITE)


## White text with a dark outline so it stays readable on the bright sky.
static func outlined(l: Label, size: int = 18, color: Color = WHITE, outline: int = 6) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)


## Big Anton title word (used for "Vibe n'" / "Chat" and "SERVER" / "BROWSER").
static func title_word(text: String, color: Color, size: int = 92) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", int(size * 0.17))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 5)
	l.add_theme_constant_override("shadow_offset_y", 6)
	l.add_theme_constant_override("shadow_outline_size", int(size * 0.17))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


const ROW_FILL := Color("#16293a")      # settings / list rows (a touch lighter than INK)

static var _theme: Theme


## Theme for the settings screen: Anton text, slanted strips, orange accents. No red.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


static func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 20
	t.set_color("font_color", "Label", WHITE)

	# Buttons: same slanted strips as the main menu.
	var bm := Vector4(26, 16, 4, 4)
	t.set_stylebox("normal", "Button", strip(Color(INK, 0.92), WHITE, 2, bm))
	t.set_stylebox("hover", "Button", strip(ORANGE, WHITE, 2, bm))
	t.set_stylebox("pressed", "Button", strip(ORANGE_DEEP, WHITE, 2, bm))
	t.set_stylebox("focus", "Button", strip(Color(0, 0, 0, 0), ORANGE, 3, bm))
	t.set_stylebox("disabled", "Button", strip(Color(INK, 0.55), Color(1, 1, 1, 0.35), 2, bm))
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.4))

	# Drop-downs: flat boxes like the server screen inputs.
	t.set_stylebox("normal", "OptionButton", flat(Color(INK, 0.92), WHITE, 2, 10))
	t.set_stylebox("hover", "OptionButton", flat(ORANGE, WHITE, 2, 10))
	t.set_stylebox("pressed", "OptionButton", flat(ORANGE_DEEP, WHITE, 2, 10))
	t.set_stylebox("focus", "OptionButton", flat(Color(0, 0, 0, 0), ORANGE, 3, 10))
	t.set_stylebox("disabled", "OptionButton", flat(Color(INK, 0.55), Color(1, 1, 1, 0.35), 2, 10))
	t.set_color("font_color", "OptionButton", WHITE)
	t.set_color("font_hover_color", "OptionButton", INK)
	t.set_color("font_pressed_color", "OptionButton", INK)
	t.set_color("font_focus_color", "OptionButton", WHITE)
	t.set_stylebox("panel", "PopupMenu", flat(INK, WHITE, 2, 6))
	t.set_stylebox("hover", "PopupMenu", flat(ORANGE, ORANGE, 0, 4))
	t.set_color("font_color", "PopupMenu", WHITE)
	t.set_color("font_hover_color", "PopupMenu", INK)

	# Toggle: no box, just the switch, with a soft orange glow on hover.
	var clear := flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
	var glow := flat(Color(ORANGE, 0.25), Color(0, 0, 0, 0), 0, 6)
	for state in ["normal", "pressed", "disabled"]:
		t.set_stylebox(state, "CheckButton", clear)
	t.set_stylebox("hover", "CheckButton", glow)
	t.set_stylebox("hover_pressed", "CheckButton", glow)
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	# Sliders: dark track, orange fill.
	var track := flat(Color(INK, 0.95), Color(1, 1, 1, 0.55), 1, 5)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", flat(ORANGE, ORANGE, 0, 5))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(ORANGE.lightened(0.2), ORANGE, 0, 5))

	# Tabs: slanted strips, the selected one is orange.
	var tm := Vector4(30, 22, 6, 6)
	t.set_stylebox("tab_selected", "TabContainer", strip(ORANGE, ORANGE, 0, tm))
	t.set_stylebox("tab_unselected", "TabContainer", strip(Color(INK, 0.92), Color(1, 1, 1, 0.55), 1, tm))
	t.set_stylebox("tab_hovered", "TabContainer", strip(ORANGE_DEEP, ORANGE_DEEP, 0, tm))
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TabContainer", flat(Color(0.03, 0.07, 0.1, 0.55), Color(1, 1, 1, 0.25), 1, 14))
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_unselected_color", "TabContainer", WHITE)
	t.set_color("font_hovered_color", "TabContainer", INK)
	t.set_font_size("font_size", "TabContainer", 22)
	t.set_constant("h_separation", "TabContainer", 10)

	# Scroll bar.
	t.set_stylebox("scroll", "VScrollBar", flat(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber", "VScrollBar", flat(ORANGE, ORANGE, 0, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(ORANGE.lightened(0.2), ORANGE, 0, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(ORANGE_DEEP, ORANGE_DEEP, 0, 3))
	return t
