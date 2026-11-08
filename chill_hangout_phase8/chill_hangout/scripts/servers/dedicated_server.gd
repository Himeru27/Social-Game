extends Node
## Entry point of the dedicated server. Run headless:
##   godot --headless --path . res://scenes/server/dedicated_server.tscn -- --port=7777
## Options (after the `--`):  --port=N  --bind=IP  --name="My Server"  --max-rooms=N
##   --empty-timeout=SECONDS  --max-clients=N  --run-seconds=N (testing: quit after N seconds)
## One process hosts many rooms. The server is not a player: it only validates, relays and cleans up.

const DEFAULTS := {
	"port": NetProtocol.DEFAULT_PORT, "bind": "*", "name": "Chill Hangout Server", "max_rooms": 20,
	"empty_timeout": 30.0, "max_clients": 200, "run_seconds": 0.0,
}

var _gs: GameServer
var _quit_after := 0.0
var _t := 0.0
var _stats_t := 0.0


func _ready() -> void:
	var opts := _parse_args(OS.get_cmdline_user_args())
	var maps := await _load_maps()
	_gs = GameServer.new()
	_gs.name = "GameServer"
	add_child(_gs)
	_gs.setup(Net, maps, opts)
	# WebSocket mode (free web hosts): `--ws`, or automatically when the host provides a PORT variable.
	var use_ws := OS.get_cmdline_user_args().has("--ws") or OS.get_environment("PORT") != ""
	if OS.get_environment("PORT").is_valid_int():
		opts["port"] = OS.get_environment("PORT").to_int()
	var err := Net.host_dedicated(_gs, int(opts["port"]), int(opts["max_clients"]), str(opts["bind"]), use_ws)
	if err != OK:
		push_error("Could not listen on port %d (error %d). Is another server already running?" % [int(opts["port"]), err])
		get_tree().quit(1)
		return
	_quit_after = float(opts["run_seconds"])
	_gs.log_line("'%s' listening on %s %d (protocol %d, empty-room timeout %ds, max rooms %d)" % [
		opts["name"], "TCP/WebSocket" if use_ws else "UDP", int(opts["port"]), NetProtocol.PROTOCOL_VERSION, int(opts["empty_timeout"]), int(opts["max_rooms"])])
	get_tree().auto_accept_quit = false


func _process(delta: float) -> void:
	_t += delta
	_stats_t += delta
	if _stats_t >= 60.0 and _gs:
		_stats_t = 0.0
		_gs.log_line("stats: " + _gs.stats())
	if _quit_after > 0.0 and _t >= _quit_after:
		_quit_after = 0.0
		await _shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		await _shutdown()


func _shutdown() -> void:
	if _gs:
		_gs.log_line("shutting down (%s)" % _gs.stats())
	await Net.shutdown_server()
	get_tree().quit()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var o := DEFAULTS.duplicate()
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var val := ""
			if "=" in key:
				val = key.get_slice("=", 1)
				key = key.get_slice("=", 0)
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				i += 1
				val = args[i]
			key = key.replace("-", "_")
			if o.has(key):
				match typeof(o[key]):
					TYPE_INT: o[key] = val.to_int()
					TYPE_FLOAT: o[key] = val.to_float()
					_: o[key] = val
		i += 1
	return o


## Builds, for every map, the data the server needs without rendering anything: seat positions
## (with the same ids the clients compute) and spawn points. Uses the real map scene.
func _load_maps() -> Dictionary:
	var out := {}
	for id in MapRegistry.MAPS:
		var room: Node3D = (load(MapRegistry.scene_path(id)) as PackedScene).instantiate()
		add_child(room)
		await get_tree().process_frame
		var seats: Array = []
		for s in SeatTable.collect(room):
			seats.append({"pos": s.global_position, "yaw": s.facing_yaw(), "height": s.seat_height})
		var spawns: Array = []
		for sp in get_tree().get_nodes_in_group("spawn_points"):
			if room.is_ancestor_of(sp):
				spawns.append((sp as Node3D).global_position)
		out[id] = {"seats": seats, "spawns": spawns}
		print("[server] map '%s': %d seats, %d spawn points" % [id, seats.size(), spawns.size()])
		room.queue_free()
		await get_tree().process_frame
	return out
