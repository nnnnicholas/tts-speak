#!/bin/bash
set -euo pipefail

# Text-to-speech for macOS — Kokoro (local) or Cartesia (cloud)
# Feed selected text to stdin. Press shortcut again to stop.
# Config: ~/.config/tts-speak.env

PID_FILE="/tmp/tts-speak.pid"

ENV_FILE="${HOME}/.config/tts-speak.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

TTS_ENGINE="${TTS_ENGINE:-kokoro}"
TTS_MAX_CHARS="${TTS_MAX_CHARS:-6000}"

# Kokoro settings
KOKORO_URL="${KOKORO_URL:-http://localhost:7693}"
KOKORO_VOICE="${KOKORO_VOICE:-bm_george}"
KOKORO_SPEED="${KOKORO_SPEED:-1.0}"

# Cartesia settings (fallback)
CARTESIA_API_KEY="${CARTESIA_API_KEY:-}"
CARTESIA_VOICE_ID="${CARTESIA_VOICE_ID:-}"
CARTESIA_MODEL_ID="${CARTESIA_MODEL_ID:-sonic-3}"
CARTESIA_VERSION="${CARTESIA_VERSION:-2025-04-16}"
CARTESIA_LANGUAGE="${CARTESIA_LANGUAGE:-en}"
CARTESIA_SPEED="${CARTESIA_SPEED:-1.0}"
CARTESIA_VOLUME="${CARTESIA_VOLUME:-1.0}"
CARTESIA_EMOTION="${CARTESIA_EMOTION:-calm}"

# Kill any running tts-speak process
kill_existing() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null) || true
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    return 0
  fi
  if pgrep -x afplay >/dev/null 2>&1; then
    killall afplay || true
    return 0
  fi
  return 1
}

# Toggle: if already running, stop it
if kill_existing; then
  osascript -e 'display notification "Stopped." with title "TTS"' >/dev/null 2>&1 || true
  exit 0
fi

set -m
echo $$ > "$PID_FILE"

cleanup() {
  rm -f "$PID_FILE" /tmp/tts-speak.*.wav
  killall afplay 2>/dev/null || true
}
trap cleanup EXIT INT TERM

INPUT_TEXT="$(cat)"
if [[ -z "${INPUT_TEXT//[[:space:]]/}" ]]; then
  exit 0
fi

TEXT_LENGTH=$(TEXT="$INPUT_TEXT" python3 -c "import os; print(len(os.environ['TEXT']))")

if (( TEXT_LENGTH > TTS_MAX_CHARS )); then
  INPUT_TEXT=$(TEXT="$INPUT_TEXT" MAX_CHARS="$TTS_MAX_CHARS" python3 -c "
import os
text = os.environ['TEXT']
max_chars = int(os.environ['MAX_CHARS'])
print(text[:max_chars], end='')
")
  osascript -e 'display notification "Selection was trimmed." with title "TTS"' >/dev/null 2>&1 || true
fi

TMP_WAV="$(mktemp /tmp/tts-speak.XXXXXX.wav)"

generate_kokoro() {
  local payload response audio_url
  payload=$(TEXT="$INPUT_TEXT" VOICE="$KOKORO_VOICE" SPEED="$KOKORO_SPEED" python3 -c "
import json, os
print(json.dumps({
    'text': os.environ['TEXT'],
    'voice': os.environ['VOICE'],
    'speed': float(os.environ['SPEED']),
    'output_format': 'wav',
}, ensure_ascii=False))
")

  response=$(curl --fail --silent --show-error \
    --request POST "${KOKORO_URL}/api/kokoro/generate" \
    --header "Content-Type: application/json" \
    --data "$payload") || return 1

  audio_url=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin)['audio_url'])")
  curl --fail --silent --show-error "${KOKORO_URL}${audio_url}" --output "$TMP_WAV" || return 1
}

generate_cartesia() {
  local payload
  payload=$(TEXT="$INPUT_TEXT" \
    CARTESIA_MODEL_ID="$CARTESIA_MODEL_ID" \
    CARTESIA_VOICE_ID="$CARTESIA_VOICE_ID" \
    CARTESIA_LANGUAGE="$CARTESIA_LANGUAGE" \
    CARTESIA_SPEED="$CARTESIA_SPEED" \
    CARTESIA_VOLUME="$CARTESIA_VOLUME" \
    CARTESIA_EMOTION="$CARTESIA_EMOTION" \
    python3 -c "
import json, os
print(json.dumps({
    'model_id': os.environ['CARTESIA_MODEL_ID'],
    'transcript': os.environ['TEXT'],
    'voice': {'mode': 'id', 'id': os.environ['CARTESIA_VOICE_ID']},
    'output_format': {'container': 'wav', 'encoding': 'pcm_s16le', 'sample_rate': 44100},
    'language': os.environ['CARTESIA_LANGUAGE'],
    'generation_config': {
        'speed': float(os.environ['CARTESIA_SPEED']),
        'volume': float(os.environ['CARTESIA_VOLUME']),
        'emotion': os.environ['CARTESIA_EMOTION'],
    },
}, ensure_ascii=False))
")

  if ! curl --fail --silent --show-error \
    --request POST "https://api.cartesia.ai/tts/bytes" \
    --header "Authorization: Bearer ${CARTESIA_API_KEY}" \
    --header "Cartesia-Version: ${CARTESIA_VERSION}" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    --output "$TMP_WAV"; then
    return 1
  fi
}

osascript -e 'display notification "Generating speech..." with title "TTS"' >/dev/null 2>&1 || true

if [[ "$TTS_ENGINE" == "kokoro" ]]; then
  if ! generate_kokoro; then
    osascript -e 'display notification "Kokoro failed, trying Cartesia..." with title "TTS"' >/dev/null 2>&1 || true
    if [[ -n "$CARTESIA_API_KEY" ]]; then
      generate_cartesia || { osascript -e 'display notification "TTS failed." with title "TTS"' >/dev/null 2>&1 || true; exit 1; }
    else
      osascript -e 'display notification "Kokoro not running." with title "TTS"' >/dev/null 2>&1 || true
      exit 1
    fi
  fi
else
  generate_cartesia || { osascript -e 'display notification "Cartesia failed." with title "TTS"' >/dev/null 2>&1 || true; exit 1; }
fi

afplay "$TMP_WAV"
