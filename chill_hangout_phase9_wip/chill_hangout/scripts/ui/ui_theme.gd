class_name UITheme
extends RefCounted
## Shared low-poly-inspired UI theme, built in code so every screen matches.

const BG := Color("#1b2038")
const PANEL := Color("#262d52")
const PANEL_HI := Color("#34406f")
const ACCENT := Color("#ff8a65")
const TEAL := Color("#4dd0c4")
const TEXT := Color("#f4f1ea")
const MUTED := Color("#a9b0d0")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _box(color: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_content_margin_all(margin)
	return sb


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)

	for type_name in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type_name, _box(PANEL, 10, Color(1, 1, 1, 0.08), 2, 10))
		t.set_stylebox("hover", type_name, _box(PANEL_HI, 10, TEAL, 2, 10))
		t.set_stylebox("pressed", type_name, _box(ACCENT, 10, ACCENT, 2, 10))
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		t.set_stylebox("disabled", type_name, _box(BG, 10, Color(1, 1, 1, 0.05), 2, 10))
		t.set_color("font_color", type_name, TEXT)
		t.set_color("font_hover_color", type_name, TEXT)
		t.set_color("font_pressed_color", type_name, BG)
		t.set_color("font_focus_color", type_name, TEXT)
		t.set_color("font_disabled_color", type_name, MUTED)

	t.set_stylebox("panel", "PanelContainer", _box(Color(PANEL.r, PANEL.g, PANEL.b, 0.97), 16, Color(1, 1, 1, 0.12), 2, 8))

	t.set_stylebox("panel", "TabContainer", _box(Color(BG.r, BG.g, BG.b, 0.6), 10, Color(1, 1, 1, 0.06), 1, 14))
	t.set_stylebox("tab_selected", "TabContainer", _box(ACCENT, 8, ACCENT, 0, 8))
	t.set_stylebox("tab_unselected", "TabContainer", _box(PANEL, 8, Color(0, 0, 0, 0), 0, 8))
	t.set_stylebox("tab_hovered", "TabContainer", _box(PANEL_HI, 8, Color(0, 0, 0, 0), 0, 8))
	t.set_color("font_selected_color", "TabContainer", BG)
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_color("font_hovered_color", "TabContainer", TEXT)

	var track := _box(BG, 4, Color(1, 1, 1, 0.1), 1, 4)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _box(TEAL, 4, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(TEAL.lightened(0.2), 4, Color(0, 0, 0, 0), 0, 4))

	t.set_stylebox("normal", "LineEdit", _box(BG, 8, Color(1, 1, 1, 0.12), 2, 8))
	t.set_stylebox("focus", "LineEdit", _box(BG, 8, TEAL, 2, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	return t
