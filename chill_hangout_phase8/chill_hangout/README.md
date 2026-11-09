# Chill Hangout (working title) - Godot 4.3+

Phase 1: project foundation + main menu + settings.

## Run
1. Open Godot 4.3 or newer -> Import -> select `project.godot`.
2. Let it import (first open builds the class cache), press F5.

## Test Phase 1
- Menu fades in; low-poly diorama with a swaying camera, trees, drifting clouds, two characters (the female waves).
- PLAY / CHARACTER CUSTOMIZATION -> placeholder screens with a working BACK button (real screens come in later phases).
- SETTINGS: change every slider/option, press BACK, quit, relaunch -> values persist (`user://settings.cfg`).
  Controls tab: click a key, press a new key (Esc cancels). Conflicts swap.
- Resolution changes apply when windowed; Fullscreen toggles live.
- ABOUT opens a panel. QUIT GAME closes the app.
- Music: drop `assets/audio/music/menu_theme.ogg` and it plays automatically.

## Phase 2: character, camera, movement
Main menu -> "DEV: TEST ARENA" (visible in editor/debug builds).
- WASD move (character turns toward movement; camera does not turn it), mouse looks, Shift sprints (stamina bar drains, regenerates after 1s; at 0 you must recover to 20% before sprinting again), C toggles crouch.
- Walk under the orange lintel: only possible crouched; try standing there - it refuses.
- Camera pulls in near walls (SpringArm3D). F1 swaps male/female. Esc frees the mouse, click recaptures, Backspace returns.
- Settings: mouse/camera sensitivity and FOV apply live (open Settings from the menu, then re-enter the arena).

## Phase 3: character customization
Main menu -> CHARACTER CUSTOMIZATION. Tabs: Body (male/female presets, skin tone, height/width/thickness/arms/legs),
Hair (7 styles + colors), Face (eyes, brows, expression, nose, mouth, details), Clothing, Accessories, Name.
- Drag the preview to rotate, scroll to zoom, FACE CLOSE-UP / FULL BODY buttons.
- APPLY = use this session. SAVE = also writes `user://character.json`. RESET = defaults for current preset. BACK discards unapplied edits.
- Username is validated live (2-16 chars, letters/digits/space/-/_, blocked + reserved words). Per-server uniqueness is enforced by the server in Phase 5 (`AppearanceData.name_key`).
- The main menu character, the HUD name and the test arena use your applied/saved character.
- `AppearanceData.sanitize()` clamps any appearance dictionary - the server will run every client appearance through it.

## Phase 4: hangout room, seating, interaction
Main menu -> "DEV: HANGOUT ROOM (LOCAL)". You spawn at the entrance of a 40x30 m room.
- Zones: reception (south), central tree + bench ring, west lounge (sofas, armchairs, bookshelf), north-east cafe tables, north bar with stools, east benches.
- Walk up to any chair/stool/bench/sofa cushion and face it: "PRESS E TO SIT". Press E to sit; "PRESS E TO STAND" to get up. Each slot has one occupant.
- While seated you cannot walk; the camera still orbits. Standing picks the first free spot (front first).
- New code: `scripts/interaction/` (Interactable, Seat, InteractionDetector), `scripts/objects/furniture.gd`, `scripts/lobby/hangout_room.gd`.
- To add an interactable: extend `Interactable`, override `can_interact/get_prompt/interact`.

## Phase 5: multiplayer (servers, invitation codes, synced players)
Architecture: ONE dedicated server process (`scripts/servers/game_server.gd`) listens on a single UDP port (ENet) and hosts
many logical rooms. Each room has its own map, player list and seat occupancy. Clients connect to this "game service",
see public rooms, create public/private rooms, or join private rooms by code (`CHILL-K7QM2`). Codes are generated and
resolved on the server; players never type IPs for rooms. All RPCs live in `autoload/net.gd`; wire format in
`scripts/networking/net_protocol.gd`.

### Run it locally (development, same computer)
1. Start the server: `tools/run_server.sh /path/to/Godot` (or in the editor: open `scenes/server/dedicated_server.tscn`, F6).
   Options after `--`: `--port --bind --name --max-rooms --empty-timeout=SECONDS --max-clients`.
2. Start two or more game instances (Debug > Customize Run Instances > 2, or run the exported game twice), F5.
3. PLAY -> the browser connects to `127.0.0.1:7777` ("Game service" row). CREATE SERVER (public or private) in one
   instance; JOIN from the other (or paste the code into the invitation field, JOIN PRIVATE).
4. Test: walk (the other window sees smooth movement/sprint/crouch), sit on chairs (a taken seat shows "That seat is taken"),
   Esc > LEAVE SERVER leaves; close the server and watch the clients return to the browser with a notice.
First open in the editor: let it import once so new class names register.

### Behaviour
- 10 players per room; FULL rooms refuse joins. Empty rooms close after `--empty-timeout` (default 30 s); their code dies too.
- Username must be unique per room (look-alikes like `A1ice`/`Alice` count as the same name).
- Server validates: version, names, appearance (sanitized), map, capacity, codes (+ lock-out after 6 wrong codes/min per address),
  movement (speed budget, bounds; bad moves are rubber-banded, repeat offenders removed), sit range/occupancy, request flooding.
- State: clients send 20 Hz; the server relays 20 Hz snapshots (20 bytes/player, only changed players) to the SAME room; clients
  interpolate 130 ms behind. Movement is client-driven and server-validated (not full server simulation).
- Esc opens the pause menu (Phase 7). Backspace no longer leaves.

### Automated checks included
`tools/bot_client.tscn` (headless real-Net bots) and `tools/client_smoke.tscn` (drives the real browser/room scenes).

### Local vs LAN vs internet (be precise)
- Tested here: localhost, one server + many headless/real clients on one machine.
- LAN: run the server on one PC, set "Game service" to its LAN IP on the others, allow UDP 7777 in the firewall. Untested by me.
- Internet: needs the server on a machine with a public IP/VPS, UDP 7777 forwarded/open, and the browser's default host set to
  your domain (`GameSettings` defaults `server_host`). NOT deployed or tested over the internet yet; no TLS/auth (ENet is plain UDP).
  A real launch also needs account auth, a rate-limit per account, and a process supervisor/restart policy.

## Phase 6: social features (chat, bubbles, name tags, player list, emotes)
Protocol version is now 2 - update the server and every client together.
- **Chat**: press T (rebindable), type, Enter sends (or SEND). Esc closes the box without opening anything else.
  Messages go to the server, which validates them (max 120 chars, control characters stripped, empty ignored, word filter,
  4-message burst then 1 per 1.2 s, identical repeats within 3 s dropped) and relays them to the same room only.
  History shows the sender; recent lines stay visible a few seconds after each message, then fade.
- **Chat above the head**: a billboard bubble (wrapped, max ~300 px wide) shows over the sender and disappears after about
  5-10 s (`NameTag.bubble_seconds`); a new message replaces the old one. Usernames float above every player.
- **Player list**: hold Tab (rebindable in Settings > Controls): "PLAYERS ONLINE: n/10", you and the host are marked.
- **Emotes**: press `.` for the picker (click or keys 1-5): BRAZILIAN TIKTOK DANCE (loop), SIPPING A COFFEE (mug appears in hand), BABY'S STRANGER THINGS DANCE (loop), HI (wave + pixel text beside the head), AURA FARM (leans on the nearest wall, loop).
  Procedural poses blend over the walk/idle animation, replicate to the room (late joiners see running loops), and cancel when you
  move, crouch or sit. Emotes are refused while seated/crouching; the server rate-limits them.
- Join/leave notices appear in the chat log.
- Tests: `tools/bot_client.tscn` accepts `--say= --emote= --spam --long --empty --bad --say_late=`; `tools/client_smoke.tscn --social`
  drives the real UI; `tools/pose_test.tscn` checks emote poses numerically.

## Phase 7: menus and gameplay flow
- **Pause menu (Esc)** in an online room: RESUME, SETTINGS (the same screen as the main menu, changes apply live), JOIN SERVER,
  LEAVE SERVER, QUIT GAME. It never pauses the world: the network and other players keep running while it is open.
  Esc in chat or the emote picker only closes that box. Esc again resumes.
- JOIN SERVER fully disconnects and opens the browser on a fresh connection; LEAVE SERVER leaves the room (your seat is freed,
  others are notified) and returns to the browser; QUIT GAME disconnects cleanly, then exits.
- If the server drops while the menu is open you are returned to the browser with a notice.
- The server browser (list/refresh/create/private code/back) was built in Phase 5 and is used as-is.
- Test: `tools/client_smoke.tscn -- --pause` presses Esc through the real input path.

## Phase 8: audio, connection status, deployment, test plan
- **Audio** (all generated in code, so no asset files are required; real `.ogg` files override them):
  menu music (`assets/audio/music/menu_theme.ogg`) and lobby music (`lobby_theme.ogg`) fall back to built-in ambient pads;
  faint looping room tone in rooms; positional footsteps for every player (quieter crouching, louder sprinting);
  emote audio from `assets/audio/emotes/` (loops fade out when the emote ends); sit sound also plays for remote players. Master/Music/SFX sliders control the buses.
- **Connection status**: the HUD shows `PING n ms` under the hint line, red when above 250 ms or when the server stops answering.
- `deploy/` has a Dockerfile and systemd unit; see `DEPLOYMENT.md` (internet hosting is NOT yet tested) and `TESTING.md` for the full test plan.
