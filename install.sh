#!/usr/bin/env bash
# install.sh — put the PC state agent in place for the current user.
#
# Copies the program to ~/.local/bin, installs the systemd *user* unit and
# creates the config folder. It never overwrites an existing config.json and
# never needs root.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
CFG_DIR="$HOME/.config/jarvis-pc-agent"
UNIT_DIR="$HOME/.config/systemd/user"

say() { printf '  %s\n' "$*"; }

echo "PC state agent — installing for $USER"

# 1. the MQTT library ------------------------------------------------------
if python3 -c 'import paho.mqtt.client' 2>/dev/null; then
    say "paho-mqtt: found"
else
    say "paho-mqtt: MISSING — install it first, e.g.:"
    say "    sudo dnf install -y python3-paho-mqtt     # Fedora"
    say "    sudo apt install -y python3-paho-mqtt     # Debian/Ubuntu"
    exit 1
fi

# 2. the program -----------------------------------------------------------
mkdir -p "$BIN" "$CFG_DIR" "$UNIT_DIR"
install -m 0755 "$SRC/jarvis-pc-agent" "$BIN/jarvis-pc-agent"
say "program:  $BIN/jarvis-pc-agent"

# 3. the settings file (never clobbered) -----------------------------------
if [ -f "$CFG_DIR/config.json" ]; then
    say "config:   $CFG_DIR/config.json (kept — not overwritten)"
else
    install -m 0600 "$SRC/config.example.json" "$CFG_DIR/config.json"
    say "config:   $CFG_DIR/config.json (NEW — edit broker/username/password)"
fi

# 4. the service -----------------------------------------------------------
install -m 0644 "$SRC/jarvis-pc-agent.service" "$UNIT_DIR/jarvis-pc-agent.service"
systemctl --user daemon-reload
say "service:  $UNIT_DIR/jarvis-pc-agent.service"

cat <<'EOF'

Next:
  1. Edit ~/.config/jarvis-pc-agent/config.json  (broker, username, password)
  2. Test it:    ~/.local/bin/jarvis-pc-agent --check
  3. Start it:   systemctl --user enable --now jarvis-pc-agent
  4. Watch it:   journalctl --user -u jarvis-pc-agent -f
EOF
