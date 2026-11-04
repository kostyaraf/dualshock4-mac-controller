#!/bin/sh
# Builds DS4Mouse.app and runs it permanently: starts at login, restarts if it crashes.
#
# Signed with your Apple Development certificate when there is one: macOS then remembers
# the Accessibility permission across rebuilds. Unsigned (ad-hoc) builds lose it every time.
set -e
cd "$(dirname "$0")/.."
LABEL=com.ds4mouse.agent
APP="$HOME/Applications/DS4Mouse.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ds4mouse.log"

swift build -c release

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -rf "$APP" "$HOME/.local/bin/ds4mouse"   # also drop the old bare-binary install
mkdir -p "$APP/Contents/MacOS" "$(dirname "$PLIST")"
cp .build/release/ds4mouse "$APP/Contents/MacOS/ds4mouse"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.ds4mouse.app</string>
  <key>CFBundleName</key><string>DS4Mouse</string>
  <key>CFBundleExecutable</key><string>ds4mouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --identifier com.ds4mouse.app -s "$IDENTITY" "$APP"
  echo "Подписано: $IDENTITY"
else
  codesign --force --identifier com.ds4mouse.app -s - "$APP"
  echo "Сертификата разработчика нет: после каждой переустановки доступ придётся выдавать заново."
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/ds4mouse</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Установлено и запущено. Лог: $LOG"
