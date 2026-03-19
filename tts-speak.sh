#!/bin/bash
set -euo pipefail

# Cartesia selected-text-to-speech for macOS Quick Actions
# Feed selected text to stdin. Press shortcut again to stop.
# Config: ~/.config/tts-speak.env

ENV_FILE="${HOME}/.config/tts-speak.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${CARTESIA_API_KEY:?Missing CARTESIA_API_KEY in ~/.config/tts-speak.env}"
: "${CARTESIA_VOICE_ID:?Missing CARTESIA_VOICE_ID in ~/.config/tts-speak.env}"

CARTESIA_MODEL_ID="${CARTESIA_MODEL_ID:-sonic-3}"
CARTESIA_VERSION="${CARTESIA_VERSION:-2025-04-16}"
CARTESIA_LANGUAGE="${CARTESIA_LANGUAGE:-en}"
CARTESIA_SPEED="${CARTESIA_SPEED:-1.0}"
CARTESIA_VOLUME="${CARTESIA_VOLUME:-1.0}"
CARTESIA_EMOTION="${CARTESIA_EMOTION:-calm}"
CARTESIA_MAX_CHARS="${CARTESIA_MAX_CHARS:-6000}"

# Toggle: if afplay is already running, kill it and exit
if pgrep -x afplay >/dev/null 2>&1; then
  killall afplay || true
  exit 0
fi

INPUT_TEXT="$(cat)"
if [[ -z "${INPUT_TEXT//[[:space:]]/}" ]]; then
  exit 0
fi

TEXT_LENGTH=$(TEXT="$INPUT_TEXT" python3 -c "import os; print(len(os.environ['TEXT']))")

if (( TEXT_LENGTH > CARTESIA_MAX_CHARS )); then
  INPUT_TEXT=$(TEXT="$INPUT_TEXT" MAX_CHARS="$CARTESIA_MAX_CHARS" python3 -c "
import os
text = os.environ['TEXT']
max_chars = int(os.environ['MAX_CHARS'])
print(text[:max_chars], end='')
")
  osascript -e 'display notification "Selection was trimmed before speaking." with title "TTS"' >/dev/null 2>&1 || true
fi

TMP_WAV="$(mktemp /tmp/cartesia-tts.XXXXXX.wav)"
cleanup() { rm -f "$TMP_WAV"; }
trap cleanup EXIT

JSON_PAYLOAD=$(TEXT="$INPUT_TEXT" \
  CARTESIA_MODEL_ID="$CARTESIA_MODEL_ID" \
  CARTESIA_VOICE_ID="$CARTESIA_VOICE_ID" \
  CARTESIA_LANGUAGE="$CARTESIA_LANGUAGE" \
  CARTESIA_SPEED="$CARTESIA_SPEED" \
  CARTESIA_VOLUME="$CARTESIA_VOLUME" \
  CARTESIA_EMOTION="$CARTESIA_EMOTION" \
  python3 -c "
import json, os
payload = {
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
}
print(json.dumps(payload, ensure_ascii=False))
")

if ! curl --fail --silent --show-error \
  --request POST "https://api.cartesia.ai/tts/bytes" \
  --header "Authorization: Bearer ${CARTESIA_API_KEY}" \
  --header "Cartesia-Version: ${CARTESIA_VERSION}" \
  --header "Content-Type: application/json" \
  --data "$JSON_PAYLOAD" \
  --output "$TMP_WAV"; then
  osascript -e 'display notification "Cartesia request failed." with title "TTS"' >/dev/null 2>&1 || true
  exit 1
fi

afplay "$TMP_WAV"
