class_name NetProtocol
extends RefCounted
## Shared constants + wire encoding used by BOTH the client and the dedicated server.
## Bump PROTOCOL_VERSION whenever an RPC signature, the packet layout or a map's seat layout changes;
## the server refuses clients with a different version.

const PROTOCOL_VERSION := 3
## The official game service every player connects to. Change this ONE line if the server address changes.
const DEFAULT_HOST := "wss://social-game-t1gb.onrender.com"
const DEFAULT_PORT := 7777

const MAX_PLAYERS_PER_ROOM := 10
const SEND_RATE := 20.0               ## client -> server state packets per second (max)
const SNAPSHOT_RATE := 20.0           ## server -> client snapshots per second
const KEEPALIVE_SEC := 0.5            ## idle clients still send a state packet this often
const INTERP_DELAY := 0.13            ## remote players are rendered this far in the past (s)
const CONNECT_TIMEOUT_SEC := 8.0
const IDLE_KICK_SEC := 20.0           ## in a room but silent for this long -> removed

## Movement validation (server). Legit sprint speed is 5.8 m/s (Player.SPRINT_SPEED).
const MAX_SPEED := 7.5
const MOVE_BURST_M := 6.0             ## distance "bank" so lag bursts are not punished
const SIT_RANGE := 3.0                ## horizontal metres between player and seat when sitting
const BOUNDS_XZ := 80.0
const BOUNDS_Y_MIN := -3.0
const BOUNDS_Y_MAX := 12.0

## Chat (validated again by the server).
const CHAT_MAX := 120
const CHAT_BURST := 4.0               ## messages allowed in a burst
const CHAT_REFILL_SEC := 1.2          ## one more message allowed every N seconds
const CHAT_REPEAT_MSEC := 3000        ## identical message within this time is dropped

## The five default emotes. dur = seconds for one-shot emotes (0 for looping ones).
const EMOTE_BRAZILIAN := 0
const EMOTE_COFFEE := 1
const EMOTE_STRANGER := 2
const EMOTE_HI := 3
const EMOTE_AURA := 4
const EMOTES: Array[Dictionary] = [
	{"id": 0, "name": "BRAZILIAN TIKTOK DANCE", "loop": true, "dur": 0.0},
	{"id": 1, "name": "SIPPING A COFFEE", "loop": false, "dur": 6.0},
	{"id": 2, "name": "BABY'S STRANGER THINGS DANCE", "loop": true, "dur": 0.0},
	{"id": 3, "name": "HI", "loop": false, "dur": 2.6},
	{"id": 4, "name": "AURA FARM", "loop": true, "dur": 0.0},
]
## Beat length (s) of the two dance emotes and when the first beat lands (s after the emote starts), measured from the
## music files (Taka La Dentro from 0:08 = 89.80 bpm, Stranger Things dance = 84.76 bpm). The animation uses them so it
## moves exactly on the beat of the audio.
const EMOTE_BEAT_BRAZILIAN := 60.0 / 89.80
const EMOTE_OFFSET_BRAZILIAN := 0.64
const EMOTE_BEAT_STRANGER := 60.0 / 84.76
const EMOTE_OFFSET_STRANGER := 0.21
const EMOTE_COOLDOWN_MSEC := 300
const EMOTE_CANCEL_SPEED_Q := 40      ## server cancels an emote if the player moves faster than 2 m/s

const FLAG_CROUCH := 1
const FLAG_SPRINT := 2
const FLAG_SEATED := 4                ## set by the SERVER only

const CLIENT_STATE_BYTES := 16
const ENTRY_BYTES := 20

const ROOM_NAME_MIN := 3
const ROOM_NAME_MAX := 24

## Error codes sent in s_join_result.
enum Err {
	OK, BAD_VERSION, BAD_REQUEST, BAD_NAME, NAME_TAKEN, BAD_ROOM_NAME, BAD_MAP,
	INVALID_CODE, ROOM_UNAVAILABLE, ROOM_FULL, SERVER_FULL, RATE_LIMITED, ALREADY_IN_ROOM,
}

const ERR_TEXT := {
	Err.BAD_VERSION: "Your game version does not match the server. Please update.",
	Err.BAD_REQUEST: "The server rejected the request.",
	Err.BAD_NAME: "Your username is not allowed.",
	Err.NAME_TAKEN: "Someone in that server already uses your username. Change it in Character Customization.",
	Err.BAD_ROOM_NAME: "Invalid server name (3-24 letters, numbers, spaces, - _ ! . ').",
	Err.BAD_MAP: "That map is not available.",
	Err.INVALID_CODE: "Invalid invitation code.",
	Err.ROOM_UNAVAILABLE: "That server is no longer available.",
	Err.ROOM_FULL: "That server is full.",
	Err.SERVER_FULL: "The game service is at capacity. Try again in a moment.",
	Err.RATE_LIMITED: "Too many attempts. Wait a minute and try again.",
	Err.ALREADY_IN_ROOM: "You are already in a server.",
}


static func err_text(code: int) -> String:
	return ERR_TEXT.get(code, "Something went wrong (%d)." % code)


## Returns "" when valid, otherwise a user-facing message.
static func validate_room_name(n: String) -> String:
	if n != n.strip_edges() or n.length() < ROOM_NAME_MIN or n.length() > ROOM_NAME_MAX:
		return err_text(Err.BAD_ROOM_NAME)
	var rx := RegEx.new()
	rx.compile("^[A-Za-z0-9 _!.'-]+$")
	if rx.search(n) == null or "  " in n:
		return err_text(Err.BAD_ROOM_NAME)
	var key := AppearanceData.name_key(n)
	for w in AppearanceData.BLOCKED_WORDS:
		if w in key:
			return err_text(Err.BAD_ROOM_NAME)
	return ""


# ------------------------------------------------------------------ wire format

static func quantize_yaw(yaw: float) -> int:
	return clampi(roundi((wrapf(yaw, -PI, PI) + PI) / TAU * 65535.0), 0, 65535)


static func dequantize_yaw(q: int) -> float:
	return float(q) / 65535.0 * TAU - PI


static func quantize_speed(speed: float) -> int:
	return clampi(roundi(speed * 20.0), 0, 255)


## Client -> server: 16 bytes = x,y,z (float32) + yaw (u16) + speed (u8) + flags (u8).
static func encode_client_state(pos: Vector3, yaw: float, speed: float, flags: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(CLIENT_STATE_BYTES)
	b.encode_float(0, pos.x)
	b.encode_float(4, pos.y)
	b.encode_float(8, pos.z)
	b.encode_u16(12, quantize_yaw(yaw))
	b.encode_u8(14, quantize_speed(speed))
	b.encode_u8(15, flags & 0xFF)
	return b


## Returns {} when the packet is malformed or contains NaN/inf.
static func decode_client_state(b: PackedByteArray) -> Dictionary:
	if b.size() != CLIENT_STATE_BYTES:
		return {}
	var pos := Vector3(b.decode_float(0), b.decode_float(4), b.decode_float(8))
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return {}
	return {"pos": pos, "yaw": dequantize_yaw(b.decode_u16(12)), "speed_q": b.decode_u8(14), "flags": b.decode_u8(15)}


## Server -> client snapshot. entries = Array[RoomPlayer]. Layout: u8 count, then per player
## peer id (s32) + x,y,z (float32) + yaw (u16) + speed (u8) + flags (u8) = 20 bytes.
static func encode_snapshot(entries: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(1 + entries.size() * ENTRY_BYTES)
	b.encode_u8(0, entries.size())
	var o := 1
	for p in entries:
		b.encode_s32(o, p.id)
		b.encode_float(o + 4, p.pos.x)
		b.encode_float(o + 8, p.pos.y)
		b.encode_float(o + 12, p.pos.z)
		b.encode_u16(o + 16, quantize_yaw(p.yaw))
		b.encode_u8(o + 18, p.speed_q)
		b.encode_u8(o + 19, p.flags)
		o += ENTRY_BYTES
	return b


static func decode_snapshot(b: PackedByteArray) -> Array:
	var out: Array = []
	if b.size() < 1:
		return out
	var n := b.decode_u8(0)
	if b.size() != 1 + n * ENTRY_BYTES:
		return out
	var o := 1
	for i in n:
		out.append({
			"id": b.decode_s32(o),
			"pos": Vector3(b.decode_float(o + 4), b.decode_float(o + 8), b.decode_float(o + 12)),
			"yaw": dequantize_yaw(b.decode_u16(o + 16)),
			"speed": float(b.decode_u8(o + 18)) / 20.0,
			"flags": b.decode_u8(o + 19),
		})
		o += ENTRY_BYTES
	return out
