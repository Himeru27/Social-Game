extends Control
## Honest stand-in for screens that arrive in later phases (server browser, customization).

@export var screen_title := "COMING SOON"
@export_multiline var message := ""


func _ready() -> void:
	theme = UITheme.get_theme()
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var title := Label.new()
	title.text = screen_title
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(title)

	var body := Label.new()
	body.text = message
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 560
	box.add_child(body)

	var back := Button.new()
	back.text = "BACK TO MAIN MENU"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(func() -> void:
		AudioManager.play_click()
		SceneManager.go("main_menu"))
	back.mouse_entered.connect(AudioManager.play_hover)
	box.add_child(back)
