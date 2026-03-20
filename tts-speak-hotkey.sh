#!/bin/bash
# Hotkey wrapper for tts-speak: copies selected text, pipes to TTS.
# Press again to stop. Designed for Karabiner-Elements or similar.

# Toggle off if already playing
if pgrep -x afplay >/dev/null 2>&1; then
  killall afplay
  exit 0
fi

# Try to copy selection, fall back to existing clipboard
osascript -e 'tell application "System Events" to keystroke "c" using command down'
sleep 0.3

# Pipe clipboard (either new selection or existing) to tts-speak
pbpaste | "${HOME}/.local/bin/tts-speak"
