#!/bin/bash

# Text-to-speech for macOS — Cartesia (cloud) or Kokoro (local)
# Reads from stdin or clipboard. Press hotkey again to stop.

# Load config
[[ -f "${HOME}/.config/tts-speak.env" ]] && source "${HOME}/.config/tts-speak.env"

TTS_ENGINE="${TTS_ENGINE:-cartesia}"
TTS_MAX_CHARS="${TTS_MAX_CHARS:-6000}"
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

# Toggle: if already playing, stop
if pgrep -x afplay >/dev/null 2>&1; then
  killall afplay 2>/dev/null
  osascript -e 'display notification "Stopped." with title "TTS"' 2>/dev/null &
  exit 0
fi

# Read text from stdin
INPUT_TEXT="$(cat)"
[[ -z "${INPUT_TEXT// /}" ]] && exit 0

# Truncate if needed
INPUT_TEXT="$(echo "$INPUT_TEXT" | head -c "$TTS_MAX_CHARS")"

TMP="/tmp/tts-speak-$$.wav"
trap 'rm -f "$TMP"' EXIT

osascript -e 'display notification "Generating speech..." with title "TTS"' 2>/dev/null &

if [[ "$TTS_ENGINE" == "kokoro" ]]; then
  # Kokoro: two-step (get URL, then download)
  PAYLOAD=$(T="$INPUT_TEXT" V="$KOKORO_VOICE" S="$KOKORO_SPEED" python3 -c "
import json, os
print(json.dumps({'text': os.environ['T'], 'voice': os.environ['V'], 'speed': float(os.environ['S']), 'output_format': 'wav'}))" 2>/dev/null)

  RESP=$(curl -sf -X POST "${KOKORO_URL}/api/kokoro/generate" -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null) || RESP=""
  if [[ -n "$RESP" ]]; then
    AUDIO_URL=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('audio_url',''))" 2>/dev/null)
    [[ -n "$AUDIO_URL" ]] && curl -sf "${KOKORO_URL}${AUDIO_URL}" -o "$TMP" 2>/dev/null
  fi

  # Fall back to Cartesia if Kokoro failed
  if [[ ! -s "$TMP" && -n "$CARTESIA_API_KEY" ]]; then
    osascript -e 'display notification "Kokoro unavailable, using Cartesia..." with title "TTS"' 2>/dev/null &
    TTS_ENGINE="cartesia"
  fi
fi

if [[ "$TTS_ENGINE" == "cartesia" ]]; then
  PAYLOAD=$(T="$INPUT_TEXT" M="$CARTESIA_MODEL_ID" V="$CARTESIA_VOICE_ID" \
    L="$CARTESIA_LANGUAGE" SP="$CARTESIA_SPEED" VO="$CARTESIA_VOLUME" E="$CARTESIA_EMOTION" \
    python3 -c "
import json, os
print(json.dumps({
    'model_id': os.environ['M'], 'transcript': os.environ['T'],
    'voice': {'mode': 'id', 'id': os.environ['V']},
    'output_format': {'container': 'wav', 'encoding': 'pcm_s16le', 'sample_rate': 44100},
    'language': os.environ['L'],
    'generation_config': {'speed': float(os.environ['SP']), 'volume': float(os.environ['VO']), 'emotion': os.environ['E']},
}))" 2>/dev/null)

  curl -sf --max-time 30 \
    -X POST "https://api.cartesia.ai/tts/bytes" \
    -H "Authorization: Bearer ${CARTESIA_API_KEY}" \
    -H "Cartesia-Version: ${CARTESIA_VERSION}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    -o "$TMP" 2>/dev/null
fi

if [[ ! -s "$TMP" ]]; then
  osascript -e 'display notification "TTS failed." with title "TTS"' 2>/dev/null &
  exit 1
fi

afplay "$TMP"
