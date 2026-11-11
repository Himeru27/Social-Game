# Phase 8 test plan

Automated (run in a terminal; needs Godot 4.3+ on PATH as `godot`; server first):
1. `tools/run_server.sh godot --empty-timeout=5 &`
2. `godot --headless --path . res://tools/bot_client.tscn -- --say=hello --emote=0`   (also `--spam`, `--long`, `--empty`, `--bad`)
3. `godot --headless --path . res://tools/client_smoke.tscn`  then `-- --social` and `-- --pause`
4. `godot --headless --path . res://tools/pose_test.tscn`

Manual, two or more game instances (Debug > Customize Run Instances) + the server:
| Area | Steps | Expect |
|---|---|---|
| Public server | A creates public, B refreshes + joins | B sees A's avatar (gender/hair/colours/proportions), counts 2/10 on both |
| Private code | A creates private (code shown), B pastes code | joins; wrong code -> "Invalid code"; 11th player -> "full" |
| Map independence | Create two public servers | separate player lists |
| Empty timeout | Everyone leaves | room disappears after timeout; its code stops working |
| Movement sync | A walks/sprints/crouches | B sees smooth motion, no teleporting |
| Sitting | A sits; B tries same seat | B refused; A stands, B can sit; A leaves while seated -> seat freed |
| Chat | A presses T, sends text | log on both, bubble over A on B's screen, disappears in ~5-10 s; spam is throttled; Esc closes chat only |
| Emotes | `.` then 1-5 | animation + sound visible/audible to B; moving cancels; refused while sitting/crouching |
| Pause | Esc | world keeps running for others; LEAVE / JOIN / QUIT behave; Esc again resumes |
| Server death | Kill server process | clients return to browser with a notice, no crash |
| Audio (new) | Walk/sprint/crouch, sit, emote, other players nearby | footsteps (quieter crouching, positional for others), lobby music + faint room tone, menu music in menus; volume sliders work |
| Connection (new) | Look top-left under the hint line | "PING n ms"; red "CONNECTION UNSTABLE" above 250 ms |
| Performance | 10 bot clients (`bot_client`), watch FPS (Debug > Monitors) | target 60 FPS on an ordinary desktop; report if lower |

## Verified results (Godot 4.3 headless, server + bots on one machine, 2026-11-09)
Passed: project import with no script errors; `client_smoke` (default, `--social`, `--pause`); `pose_test` (all 5 emotes);
multi-bot room: create + join, snapshots flowing (~120 each), duplicate username rejected, chat relayed to the room,
spam throttled after a 4-message burst, invalid code rejected, empty rooms closed after the timeout.
Not covered by headless runs (do by hand): how it looks/feels, audio you can actually hear, real input, FPS with 10 players,
LAN/internet. The `mesh_get_surface_count` messages in headless output come from Godot's dummy renderer, not the game.
Note: "Host" is a reserved username (use another name for bots).
