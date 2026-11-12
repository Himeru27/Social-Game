# Chill Hangout dedicated game service (UDP 7777). Build from the project root:
#   docker build -f deploy/Dockerfile -t chill-hangout-server .
#   docker run -d --restart unless-stopped -p 7777:7777/udp --name chill chill-hangout-server
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
# Build the class cache once so the headless server can resolve class_name scripts.
RUN godot --headless --path /game --import || true
EXPOSE 7777/udp
ENTRYPOINT ["godot", "--headless", "--path", "/game", "res://scenes/server/dedicated_server.tscn", "--"]
CMD ["--port=7777", "--name=Chill Hangout Official", "--empty-timeout=60"]
