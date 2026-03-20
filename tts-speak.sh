#!/bin/bash

# Text-to-speech for macOS.
# Reads from stdin when provided, otherwise falls back to the clipboard.
# Press the hotkey again while a run is generating or playing to stop it.

[[ -f "${HOME}/.config/tts-speak.env" ]] && source "${HOME}/.config/tts-speak.env"

TTS_ENGINE="${TTS_ENGINE:-cartesia}"
TTS_MAX_CHARS="${TTS_MAX_CHARS:-6000}"
TTS_STATUS_UI="${TTS_STATUS_UI:-floating}"
KOKORO_URL="${KOKORO_URL:-http://localhost:7693}"
KOKORO_VOICE="${KOKORO_VOICE:-bm_george}"
KOKORO_SPEED="${KOKORO_SPEED:-1.0}"
CARTESIA_API_KEY="${CARTESIA_API_KEY:-}"
CARTESIA_VOICE_ID="${CARTESIA_VOICE_ID:-c8f7835e-28a3-4f0c-80d7-c1302ac62aae}"
CARTESIA_MODEL_ID="${CARTESIA_MODEL_ID:-sonic-3}"
CARTESIA_VERSION="${CARTESIA_VERSION:-2025-04-16}"
CARTESIA_LANGUAGE="${CARTESIA_LANGUAGE:-en}"
CARTESIA_SPEED="${CARTESIA_SPEED:-1.0}"
CARTESIA_VOLUME="${CARTESIA_VOLUME:-1.0}"
CARTESIA_EMOTION="${CARTESIA_EMOTION:-calm}"

STATE_DIR="${TMPDIR:-/tmp}/tts-speak"
LOCK_DIR="${STATE_DIR}/lock"
PID_FILE="${LOCK_DIR}/pid"
STATE_FILE="${STATE_DIR}/state"
TMP=""
CHILD_PID=""

notify() {
  local message="$1"
  osascript -e "display notification \"${message}\" with title \"TTS\"" 2>/dev/null &
}

update_state() {
  printf '%s\n' "$1" > "$STATE_FILE"
}

launch_status_indicator() {
  local status_ui
  local helper="${TTS_STATUS_HELPER:-${HOME}/.local/bin/tts-speak-status}"
  status_ui="$(printf '%s' "$TTS_STATUS_UI" | tr '[:upper:]' '[:lower:]')"

  if [[ "$status_ui" == "none" ]]; then
    return 0
  fi

  if [[ -x "$helper" ]]; then
    "$helper" --pid "$$" --state-file "$STATE_FILE" --ui "$status_ui" >/dev/null 2>&1 &
  fi
}

cleanup() {
  [[ -n "$CHILD_PID" ]] && kill "$CHILD_PID" 2>/dev/null || true
  [[ -n "$TMP" ]] && rm -f "$TMP"
  rm -f "$STATE_FILE"

  if [[ -f "$PID_FILE" ]] && [[ "$(cat "$PID_FILE" 2>/dev/null)" == "$$" ]]; then
    rm -rf "$LOCK_DIR"
  fi
}

stop_current_run() {
  [[ -n "$CHILD_PID" ]] && kill "$CHILD_PID" 2>/dev/null || true
  killall afplay 2>/dev/null || true
  exit 0
}

run_child() {
  "$@" &
  CHILD_PID=$!
  wait "$CHILD_PID"
  local status=$?
  CHILD_PID=""
  return "$status"
}

run_child_to_file() {
  local output_file="$1"
  shift

  "$@" >"$output_file" 2>/dev/null &
  CHILD_PID=$!
  wait "$CHILD_PID"
  local status=$?
  CHILD_PID=""
  return "$status"
}

acquire_lock() {
  mkdir -p "$STATE_DIR"

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$PID_FILE"
    return 0
  fi

  local existing_pid=""
  [[ -f "$PID_FILE" ]] && existing_pid="$(cat "$PID_FILE" 2>/dev/null)"

  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    kill "$existing_pid" 2>/dev/null || true
    killall afplay 2>/dev/null || true
    notify "Stopped."
    exit 0
  fi

  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
  printf '%s\n' "$$" > "$PID_FILE"
}

read_input_text() {
  local input_text=""

  if [[ ! -t 0 ]]; then
    input_text="$(cat)"
  fi

  if ! [[ "$input_text" =~ [^[:space:]] ]]; then
    input_text="$(pbpaste 2>/dev/null || true)"
  fi

  printf '%s' "$input_text"
}

generate_cartesia() {
  [[ -n "$CARTESIA_API_KEY" ]] || {
    notify "Set CARTESIA_API_KEY in ~/.config/tts-speak.env."
    return 1
  }

  local payload
  payload=$(T="$INPUT_TEXT" M="$CARTESIA_MODEL_ID" V="$CARTESIA_VOICE_ID" \
    L="$CARTESIA_LANGUAGE" SP="$CARTESIA_SPEED" VO="$CARTESIA_VOLUME" E="$CARTESIA_EMOTION" \
    python3 -c "
import json, os
print(json.dumps({
    'model_id': os.environ['M'], 'transcript': os.environ['T'],
    'voice': {'mode': 'id', 'id': os.environ['V']},
    'output_format': {'container': 'wav', 'encoding': 'pcm_s16le', 'sample_rate': 44100},
    'language': os.environ['L'],
    'generation_config': {'speed': float(os.environ['SP']), 'volume': float(os.environ['VO']), 'emotion': os.environ['E']},
}))" 2>/dev/null) || return 1

  run_child curl -sf --max-time 30 \
    -X POST "https://api.cartesia.ai/tts/bytes" \
    -H "Authorization: Bearer ${CARTESIA_API_KEY}" \
    -H "Cartesia-Version: ${CARTESIA_VERSION}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    -o "$TMP" 2>/dev/null
}

generate_kokoro() {
  local payload response_file audio_url

  payload=$(T="$INPUT_TEXT" V="$KOKORO_VOICE" S="$KOKORO_SPEED" python3 -c "
import json, os
print(json.dumps({
    'text': os.environ['T'],
    'voice': os.environ['V'],
    'speed': float(os.environ['S']),
    'output_format': 'wav'
}))" 2>/dev/null) || return 1

  response_file="$(mktemp "${TMPDIR:-/tmp}/tts-speak-kokoro.XXXXXX.json")"
  if run_child_to_file "$response_file" curl -sf \
    -X POST "${KOKORO_URL}/api/kokoro/generate" \
    -H "Content-Type: application/json" \
    -d "$payload"; then
    audio_url="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('audio_url',''))" <"$response_file" 2>/dev/null)"
  fi
  rm -f "$response_file"

  [[ -n "$audio_url" ]] || return 1

  run_child curl -sf "${KOKORO_URL}${audio_url}" -o "$TMP" 2>/dev/null
}

trap cleanup EXIT
trap stop_current_run INT TERM

acquire_lock
TMP="$(mktemp "${TMPDIR:-/tmp}/tts-speak.XXXXXX.wav")"
INPUT_TEXT="$(read_input_text)"
ENGINE="$(printf '%s' "$TTS_ENGINE" | tr '[:upper:]' '[:lower:]')"

if ! [[ "$INPUT_TEXT" =~ [^[:space:]] ]]; then
  exit 0
fi

INPUT_TEXT="$(printf '%s' "$INPUT_TEXT" | head -c "$TTS_MAX_CHARS")"

update_state "processing"
launch_status_indicator
notify "Generating speech..."

case "$ENGINE" in
  cartesia)
    generate_cartesia
    ;;
  kokoro)
    generate_kokoro
    ;;
  *)
    notify "Unknown TTS engine: ${TTS_ENGINE}"
    exit 1
    ;;
esac

if [[ ! -s "$TMP" ]]; then
  notify "TTS failed."
  exit 1
fi

update_state "playing"
notify "Playing speech..."
run_child afplay "$TMP"
