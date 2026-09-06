#!/usr/bin/env bash
# Install Jarvis. Downloads models (~1GB) and sets up a private virtualenv.
set -euo pipefail
SHARE="$HOME/.local/share/juno"
mkdir -p "$SHARE" "$HOME/.local/bin" "$HOME/.config/juno" "$HOME/.config/systemd/user"
cp daemon/juno-* "$SHARE/"
cp daemon/juno-cli "$HOME/.local/bin/juno"
ln -sf "$HOME/.local/bin/juno" "$HOME/.local/bin/jarvis"
cp daemon/juno.service "$HOME/.config/systemd/user/"
[ -f "$HOME/.config/juno/config.json" ] || cp daemon/config.example.json "$HOME/.config/juno/config.json"
mkdir -p "$HOME/.config/omarchy/plugins/juno.assistant"
cp plugin/* "$HOME/.config/omarchy/plugins/juno.assistant/"
chmod +x "$SHARE"/juno-* "$HOME/.local/bin/juno"
echo "Files in place. Now run:  $SHARE/juno-setup"
