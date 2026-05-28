#!/bin/bash
# Deploy updated server files from this repo to the running CS:GO server.
# Intended to run on the VPS from the repo root.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Pulling latest ==="
cd "$REPO_ROOT"

BEFORE=$(git rev-parse HEAD)
git pull origin master
AFTER=$(git rev-parse HEAD)

CHANGED=$(git diff --name-only "$BEFORE" "$AFTER" -- csgo/cfg/ csgo/addons/ csgo/mapcycle.txt csgo/maplist.txt csgo/motd.txt csgo/gamemodes_server.txt.example 2>/dev/null)

if [ -z "$CHANGED" ]; then
  echo "=== No server files changed, skipping ==="
  exit 0
fi

echo "=== Changed: $(echo "$CHANGED" | wc -l) files ==="

echo "=== Compiling plugins ==="
cd "$REPO_ROOT/csgo/addons/sourcemod/scripting"
for src in *.sp; do
  echo "  $src"
  ./spcomp64 -iinclude "$src" -ocompiled/$(basename "$src" .sp).smx || echo "  WARNING: $src failed"
done

echo "=== Copying compiled plugins ==="
cp -f compiled/*.smx ../plugins/ 2>/dev/null || true

echo "=== Cleaning up old backups ==="
find ../plugins/ -name "*.smx.bak-*" -mtime +7 -delete 2>/dev/null || true

# Check if changes require a full restart
NEEDS_RESTART=0

if echo "$CHANGED" | grep -qE 'addons/(sourcemod|metamod)/bin/'; then
  echo "=== Core binaries changed ==="
  NEEDS_RESTART=1
fi

if echo "$CHANGED" | grep -qE 'addons/sourcemod/extensions/'; then
  echo "=== Extensions changed ==="
  NEEDS_RESTART=1
fi

if echo "$CHANGED" | grep -qE 'addons/sourcemod/gamedata/'; then
  echo "=== Gamedata changed ==="
  NEEDS_RESTART=1
fi

if [ $NEEDS_RESTART -eq 1 ]; then
  echo "=== Full restart required ==="
  systemctl restart csgo-retakes
  echo "=== Deploy complete (restarted) ==="
  exit 0
fi

# Live reload path
SMX_CHANGED=$(echo "$CHANGED" | grep '\.smx$' || true)
CFG_CHANGED=$(echo "$CHANGED" | grep '\.cfg$' || true)

if [ -n "$SMX_CHANGED" ]; then
  echo "=== Reloading changed plugins ==="
  python3 "$REPO_ROOT/scripts/rcon.py" "sm plugins refresh"
  # sm plugins refresh triggers a map restart, which re-executes server.cfg.
  # Don't send exec server.cfg separately - server is restarting.
elif [ -n "$CFG_CHANGED" ]; then
  echo "=== Reloading configs ==="
  python3 "$REPO_ROOT/scripts/rcon.py" "exec server.cfg"
fi

echo "=== Deploy complete (live reload) ==="
