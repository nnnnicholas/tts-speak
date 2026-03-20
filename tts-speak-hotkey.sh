#!/bin/bash
# Hotkey wrapper for tts-speak: copy the current selection, then let the
# main script read the copied text from stdin.

export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

LOCK_DIR="${TMPDIR:-/tmp}/tts-speak/lock"
PID_FILE="${LOCK_DIR}/pid"

notify() {
  local message="$1"
  osascript -e "display notification \"${message}\" with title \"TTS\"" 2>/dev/null &
}

pasteboard_change_count() {
  osascript -l JavaScript <<'EOF' 2>/dev/null
ObjC.import('AppKit');
$.NSPasteboard.generalPasteboard.changeCount
EOF
}

copy_selected_text() {
  local initial_count current_count selection_text

  initial_count="$(pasteboard_change_count || true)"

  osascript -e 'tell application "System Events" to keystroke "c" using command down' 2>/dev/null || return 1

  if [[ -z "$initial_count" ]]; then
    sleep 0.35
    selection_text="$(pbpaste 2>/dev/null || true)"
    [[ "$selection_text" =~ [^[:space:]] ]] || return 1
    printf '%s' "$selection_text"
    return 0
  fi

  for _ in {1..20}; do
    sleep 0.05
    current_count="$(pasteboard_change_count || true)"
    if [[ -n "$current_count" && "$current_count" != "$initial_count" ]]; then
      selection_text="$(pbpaste 2>/dev/null || true)"
      [[ "$selection_text" =~ [^[:space:]] ]] || return 1
      printf '%s' "$selection_text"
      return 0
    fi
  done

  return 1
}

if [[ -f "$PID_FILE" ]]; then
  EXISTING_PID="$(cat "$PID_FILE" 2>/dev/null)"
  if [[ "$EXISTING_PID" =~ ^[0-9]+$ ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    exec "${HOME}/.local/bin/tts-speak"
  fi
fi

if ! SELECTED_TEXT="$(copy_selected_text)"; then
  notify "Could not copy the current selection. Check Accessibility permissions."
  exit 1
fi

printf '%s' "$SELECTED_TEXT" | exec "${HOME}/.local/bin/tts-speak"
