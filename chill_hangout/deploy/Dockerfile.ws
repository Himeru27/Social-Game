# Free-host build (Render, Koyeb...): WebSocket transport on the $PORT the host provides.
# The host adds TLS, so players connect to  wss://your-app.onrender.com
FROM debian:12-slim
ARG GODOT_VERSION=4.3-stable
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip -O /tmp/g.zip \
 && unzip -q /tmp/g.zip -d /opt && mv /opt/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
 && rm /tmp/g.zip && rm -rf /var/lib/apt/lists/*
WORKDIR /game
COPY . /game
RUN useradd -m game && chown -R game /game
USER game
RUN godot --headless --path /game --import || true
ENTRYPOINT ["godot", "--headless", "--path", "/game", "res://scenes/server/dedicated_server.tscn", "--"]
CMD ["--ws", "--name=Chill Hangout", "--empty-timeout=60"]
