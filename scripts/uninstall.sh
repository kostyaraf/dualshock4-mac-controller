#!/bin/sh
# Stops ds4mouse and removes autostart.
LABEL=com.ds4mouse.agent
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/ds4mouse"
echo "Удалено."
