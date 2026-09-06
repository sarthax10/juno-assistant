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
# The workers import numpy, onnxruntime and friends, so point them at the
# virtualenv juno-setup builds rather than the system interpreter.
for f in "$SHARE"/juno-daemon "$SHARE"/juno-stt "$SHARE"/juno-kokoro \
         "$SHARE"/juno-wake "$SHARE"/juno-enroll "$SHARE"/juno-eval \
         "$SHARE"/juno-miccheck; do
  [ -f "$f" ] && sed -i "1s|.*|#!$SHARE/venv/bin/python|" "$f"
done
sed -i "1s|.*|#!/usr/bin/env python3|" "$SHARE/juno-guard" 2>/dev/null || true
chmod +x "$SHARE"/juno-* "$HOME/.local/bin/juno"
echo "Files in place. Now run:  $SHARE/juno-setup"
