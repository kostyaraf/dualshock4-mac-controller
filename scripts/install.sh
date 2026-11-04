#!/bin/sh
# Builds ds4mouse and runs it permanently: starts at login, restarts if it crashes.
set -e
cd "$(dirname "$0")/.."
LABEL=com.ds4mouse.agent
BIN="$HOME/.local/bin/ds4mouse"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ds4mouse.log"

swift build -c release
mkdir -p "$(dirname "$BIN")" "$(dirname "$PLIST")"
cp .build/release/ds4mouse "$BIN"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Установлено и запущено. Лог: $LOG"
