# Deploying the game service (internet)

STATUS: nothing here has been deployed or tested over the internet. The files are a starting point.

## What you need
1. A Linux VPS (any provider) with a public IPv4 address. 1 vCPU / 1 GB RAM is plenty for several 10-player rooms.
2. UDP 7777 open in the provider firewall AND the OS firewall (`ufw allow 7777/udp`). ENet is UDP only; TCP does nothing.
3. Optional: a DNS name (e.g. `play.example.com`) pointing at the VPS so clients never need a raw IP.

## Run it
- Docker: `docker build -f deploy/Dockerfile -t chill-hangout-server .` then `docker run -d --restart unless-stopped -p 7777:7777/udp chill-hangout-server`
- or systemd: copy the project to `/opt/chill_hangout`, install Godot 4.3 at `/usr/local/bin/godot`, run `godot --headless --path /opt/chill_hangout --import` once, install `deploy/chill-hangout.service`.
- Server args (after `--`): `--port --bind --name --max-rooms --empty-timeout=SECONDS --max-clients`.

## Point clients at it
`GameSettings` default `server_host` is `127.0.0.1`. Change that default to your domain/IP before exporting the game
(players can still override it in the browser's "Game service" field). Client and server must be the same build (protocol version check).

## Verify (do this before telling anyone it works)
1. From a machine OUTSIDE the server's network: start the game, PLAY, confirm "Game service" shows connected.
2. Create a private server on machine A, join with the code on machine B on a different network.
3. Check `docker logs` / `journalctl -u chill-hangout` for the join/leave lines.

## Known gaps before a public launch
- No encryption or accounts: anyone can connect; names are not authenticated. Add account auth before real users.
- One process hosts all rooms; run several processes on different ports for scale, and put your own directory service in front.
- Rooms are in-memory; a restart drops everyone (clients return to the browser with a notice).
- Rate limits are per connection/address, not per account.

## FREE hosting (no VPS): Render free web service over WebSocket
Tested here: the WebSocket server + clients on one machine (private code join, chat, emotes, sync). NOT tested on Render itself.
1. Put this project folder (the one containing `project.godot`) in a GitHub repository, as the repository root.
2. On render.com: New > Web Service > connect the repo. It reads `render.yaml` (Docker, free plan). Deploy.
3. Render gives you `https://chill-hangout-xxxx.onrender.com`. The game address is the same with `wss://`:
   `wss://chill-hangout-xxxx.onrender.com`
4. In `autoload/game_settings.gd` set `"server_host": "wss://chill-hangout-xxxx.onrender.com"` (the port field is ignored for wss),
   then export the game. Players just press PLAY; private codes work for everyone, in any country.
Free-tier caveats (check Render's current terms): the service sleeps after ~15 min without traffic, so the first player waits up to
a minute (the browser says so, and waits 75 s); there is a monthly free-hours limit; one small CPU, so a handful of rooms.
WebSocket runs over TCP, so movement can feel slightly less smooth on poor connections than the UDP route; the HUD shows "ONLINE" instead of a ping.

## Where the server address lives
`NetProtocol.DEFAULT_HOST` in `scripts/networking/net_protocol.gd` is the one place to change it. Players never see or type an address,
and any previously saved address is ignored. (The test tools still pass `--host=` explicitly.)
