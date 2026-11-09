extends Node
## Headless smoke test of the REAL client scenes (server browser -> online room -> leave).
## godot --headless --path . res://tools/client_smoke.tscn -- --port=7777 --name=Smoke --mode=create|join --seconds=12

var a: Dictionary = {}
var _phase := "boot"
var _t := 0.0
var _room_t := 0.0
var _clicked := false


func _ready() -> void:
	if name != "SmokeDriver":
		# The harness scene is freed by the first scene change, so run from a node on the root.
		var d := Node.new()
		d.name = "SmokeDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--"):
			var kv := s.substr(2).split("=", true, 1)
			a[kv[0]] = kv[1] if kv.size() > 1 else true
	PlayerProfile.username = str(a.get("name", "Smoke"))
	PlayerProfile.appearance = AppearanceData.default_for("female")
	Net.host = "127.0.0.1"
	Net.port = int(a.get("port", 7777))
	print("SMOKE: start")
	SceneManager.go("server_browser")


func _process(delta: float) -> void:
	_t += delta
	var sc := get_tree().current_scene
	if sc == null:
		return
	match _phase:
		"boot":
			if sc.name == "MainMenu" and sc.get_browser() != null:
				_phase = "browser"
				Net.room_list_received.connect(_on_list)
		"browser":
			if Net.state == Net.State.ONLINE and not _clicked and _t > 3.0:
				_clicked = true
				print("SMOKE: browser online, server=%s" % Net.server_info.get("server_name"))
				if str(a.get("mode", "create")) == "create":
					sc.get_browser()._open_create()
					sc.get_browser()._name_edit.text = "Smoke Room"
					sc.get_browser()._on_create_confirmed()
				else:
					Net.request_room_list()
			if sc.name == "OnlineRoom":
				_phase = "room"
				print("SMOKE: entered room, remotes=%d" % sc.remotes.size())
		"room":
			if Net.state == Net.State.OFFLINE and sc.name == "OnlineRoom":
				print("SMOKE: connection lost in room; notice='%s'" % Net.pending_notice)
				_phase = "lost"
				return
			if sc.name != "OnlineRoom":
				return
			_room_t += delta
			if a.has("social"):
				_social(sc)
			if a.has("pause"):
				_pause_test(sc)
			if _room_t > float(a.get("seconds", 12.0)):
				_report(sc)
				_phase = "leaving"
				sc.leave_server()
		"lost":
			if sc.name == "MainMenu" and sc.get_browser() != null:
				await get_tree().create_timer(1.0).timeout
				var toast_count := 0
				for c in sc.get_browser()._toasts.get_children():
					toast_count += 1
				print("SMOKE: after loss we are in the browser, offline status='%s' (no crash)" % sc.get_browser()._status.text)
				print("SMOKE: DONE")
				get_tree().quit(0)
		"leaving":
			if sc.name == "MainMenu" and a.has("pause"):
				_phase = "done"
				await get_tree().create_timer(2.0).timeout
				print("SMOKE: browser after JOIN SERVER: net_state=%d status='%s'" % [Net.state, sc.get_browser()._status.text])
				print("SMOKE: DONE")
				get_tree().quit(0)
			elif sc.name == "MainMenu":
				_phase = "done"
				print("SMOKE: back in browser, in_room=%s state=%d" % [Net.in_room, Net.state])
				Net.disconnect_from_server()
				await get_tree().create_timer(0.3).timeout
				print("SMOKE: DONE")
				get_tree().quit(0)


func _on_list(rooms: Array) -> void:
	var sc := get_tree().current_scene
	if _phase == "browser" and str(a.get("mode", "create")) == "join" and not rooms.is_empty():
		print("SMOKE: listed %d room(s); joining via browser button path" % rooms.size())
		sc.get_browser()._join_public(int(rooms[0]["id"]))


func _report(sc: Node) -> void:
	print("SMOKE: remotes=%d seats=%d local_pos=%s" % [sc.remotes.size(), sc.seats.size(), sc.player.global_position])
	for id in sc.remotes:
		var p: Player = sc.remotes[id]
		var truth: Vector3 = Net.room_players[id]["pos"]
		print("SMOKE: remote %s pos=%s server_pos=%s dist=%.2f seated=%s anim_ok=%s" % [
			p.display_name, p.global_position, truth, p.global_position.distance_to(truth), p.seated, p.model != null])


var _social_step := 0


func _social(sc: Node) -> void:
	if _social_step == 0 and _room_t > 1.5:
		_social_step = 1
		sc.chat.open()
		print("SMOKE: chat open -> input_enabled=%s mouse_visible=%s" % [sc.player.input_enabled, Input.mouse_mode == Input.MOUSE_MODE_VISIBLE])
		sc.chat._edit.text = "hi from smoke [b]bbcode[/b]"
		sc.chat.submit()
		print("SMOKE: chat submitted -> open=%s input_enabled=%s" % [sc.chat.is_open, sc.player.input_enabled])
	elif _social_step == 1 and _room_t > 3.0:
		_social_step = 2
		var tag: NameTag = sc.player.name_tag
		print("SMOKE: own bubble visible=%s text='%s'" % [tag.has_message(), tag.current_text()])
		for id in sc.remotes:
			var rt: NameTag = (sc.remotes[id] as Player).name_tag
			print("SMOKE: remote %s bubble visible=%s text='%s'" % [(sc.remotes[id] as Player).display_name, rt.has_message(), rt.current_text()])
		sc.emote_menu.open()
		sc.emote_menu._choose(1)
		print("SMOKE: emote chosen -> player.emote=%d model_emote=%d" % [sc.player.emote, sc.player.model.get_emote()])
	elif _social_step == 2 and _room_t > 4.5:
		_social_step = 3
		for id in sc.remotes:
			var rp: Player = sc.remotes[id]
			print("SMOKE: remote %s emote=%d" % [rp.display_name, rp.emote])
		sc.player_list.set_shown(true)
		print("SMOKE: player list shown=%s title='%s'" % [sc.player_list.is_shown(), sc.player_list._title.text])
		sc.player.cancel_emote()
	elif _social_step == 3 and _room_t > 8.0:
		_social_step = 4
		for id in sc.remotes:
			var rt: NameTag = (sc.remotes[id] as Player).name_tag
			print("SMOKE: t=8s remote bubble visible=%s text='%s' (sent at ~t=6s of bot)" % [rt.has_message(), rt.current_text()])
		print("SMOKE: t=8s own bubble visible=%s (sent at t=1.5s, lifetime ~6s)" % sc.player.name_tag.has_message())
	elif _social_step == 4 and _room_t > 12.5:
		_social_step = 5
		print("SMOKE: t=12.5s own bubble visible=%s" % sc.player.name_tag.has_message())
		for id in sc.remotes:
			print("SMOKE: t=12.5s remote bubble visible=%s" % (sc.remotes[id] as Player).name_tag.has_message())


var _pause_step := 0


func _esc() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ESCAPE
	up.keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)


func _pause_test(sc: Node) -> void:
	if _pause_step == 0 and _room_t > 1.5:
		_pause_step = 1
		sc.chat.open()
		_esc()
	elif _pause_step == 1 and _room_t > 2.0:
		_pause_step = 2
		print("SMOKE: Esc in chat -> chat_open=%s pause_open=%s (expect false/false)" % [sc.chat.is_open, sc.pause_menu.is_open])
		_esc()
	elif _pause_step == 2 and _room_t > 2.6:
		_pause_step = 3
		print("SMOKE: Esc -> pause_open=%s input_enabled=%s tree_paused=%s" % [sc.pause_menu.is_open, sc.player.input_enabled, get_tree().paused])
		_p0 = sc.remotes.values()[0].global_position if not sc.remotes.is_empty() else Vector3.ZERO
	elif _pause_step == 3 and _room_t > 4.0:
		_pause_step = 4
		var p1: Vector3 = sc.remotes.values()[0].global_position if not sc.remotes.is_empty() else Vector3.ZERO
		print("SMOKE: while paused the other player moved %.2f m (world keeps running)" % _p0.distance_to(p1))
		_esc()
	elif _pause_step == 4 and _room_t > 4.6:
		_pause_step = 5
		print("SMOKE: Esc again -> pause_open=%s input_enabled=%s" % [sc.pause_menu.is_open, sc.player.input_enabled])
		_esc()
	elif _pause_step == 5 and _room_t > 5.2:
		_pause_step = 6
		print("SMOKE: reopened pause=%s; pressing JOIN SERVER" % sc.pause_menu.is_open)
		sc.pause_menu.join_requested.emit()
		_phase = "leaving"


var _p0 := Vector3.ZERO
