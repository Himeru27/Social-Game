class_name MenuStyle
extends RefCounted
## Shared look for the main menu and the server screen: slanted strips, Anton font,
## white + orange on a bright sky. No red anywhere.

const FONT: Font = preload("res://assets/fonts/Anton-Regular.ttf")

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
