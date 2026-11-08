extends Node3D
func _ready() -> void:
	var m := CharacterModel.create(AppearanceData.default_for("male"))
	add_child(m)
	for id in 5:
		m.play_emote(id)
		var max_hand := -9.0
		var min_foot := 9.0
		var hand_pts := []
		for i in 120:
			m.animate(1.0 / 60.0, 0.0, false)
			max_hand = maxf(max_hand, m.get_right_hand_position().y)
			min_foot = minf(min_foot, m._knee_l.to_global(Vector3(0, -m._shin, 0)).y)
			min_foot = minf(min_foot, m._knee_r.to_global(Vector3(0, -m._shin, 0)).y)
		var head_top := m.to_global(Vector3(0, 1.1, 0)).y
		print("emote %d %s: max right hand y=%.2f (head top %.2f) lowest ankle y=%.3f active=%d" % [id, NetProtocol.EMOTES[id]["name"], max_hand, head_top, min_foot, m.get_emote()])
		m.stop_emote()
		for i in 60:
			m.animate(1.0 / 60.0, 0.0, false)
	get_tree().quit()
