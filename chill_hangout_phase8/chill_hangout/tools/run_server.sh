#!/usr/bin/env bash
# Local development server. Usage: tools/run_server.sh [godot-binary] [extra server args]
GODOT="${1:-godot}"; shift
exec "$GODOT" --headless --path "$(dirname "$0")/.." res://scenes/server/dedicated_server.tscn -- --port=7777 "$@"
