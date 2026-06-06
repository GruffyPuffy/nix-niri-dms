#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SPLASH_DIR="$SCRIPT_DIR/lock-splash"
SYSTEM_SPLASH_DIR="/usr/local/share/niri-nix-dms/lock-splash"

if [ -r "$SYSTEM_SPLASH_DIR/shell.qml" ]; then
  SPLASH_DIR="$SYSTEM_SPLASH_DIR"
else
  SPLASH_DIR="$LOCAL_SPLASH_DIR"
fi

if command -v quickshell >/dev/null 2>&1 && [ -r "$SPLASH_DIR/shell.qml" ]; then
  QS_LOCK_SPLASH_TITLE="Locking session" \
    QS_LOCK_SPLASH_MESSAGE="Please wait for GDM to start" \
    QS_LOCK_SPLASH_TIMEOUT_MS="5000" \
    quickshell --path "$SPLASH_DIR" --no-duplicate --daemonize >/dev/null 2>&1 || true
else
  notify-send "Locking session" "Switching to GDM..." --urgency=low --expire-time=1500 || true
fi

exec gdmflexiserver
