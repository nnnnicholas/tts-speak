# tts-speak

Select text anywhere on macOS → hear it spoken aloud with a modern AI voice. Press again to stop.

Supports [Cartesia](https://cartesia.ai) (cloud, best quality) and [Kokoro](https://github.com/BoltzmannEntropy/MimikaStudio) (local, free) with automatic fallback.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/nnnnicholas/tts-speak/main/install.sh | bash
```

Then add your Cartesia API key ([get one here](https://play.cartesia.ai)):

```bash
nano ~/.config/tts-speak.env
```

## Usage

**Right-click** selected text → Services → **Speak with AI**

Or assign a keyboard shortcut:
1. System Settings → Keyboard → Keyboard Shortcuts → Services → Text
2. Find "Speak with AI" and set your preferred shortcut

### Bind to a function key (optional)

Install [Karabiner-Elements](https://karabiner-elements.pqrs.org/) and add this to `~/.config/karabiner/karabiner.json`:

```json
{
    "profiles": [{
        "name": "Default profile",
        "selected": true,
        "virtual_hid_keyboard": { "keyboard_type_v2": "ansi" },
        "fn_function_keys": [
            { "from": { "key_code": "f4" }, "to": [{ "key_code": "f4" }] }
        ],
        "complex_modifications": {
            "rules": [{
                "description": "F4 → TTS",
                "manipulators": [{
                    "type": "basic",
                    "from": { "key_code": "f4" },
                    "to": [{ "shell_command": "~/.local/bin/tts-speak-hotkey" }]
                }]
            }]
        }
    }]
}
```

## Configuration

Edit `~/.config/tts-speak.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `TTS_ENGINE` | `cartesia` | `cartesia` (cloud) or `kokoro` (local) |
| `CARTESIA_API_KEY` | — | Your Cartesia API key |
| `CARTESIA_VOICE_ID` | Alistair | Voice to use ([browse voices](https://play.cartesia.ai)) |
| `CARTESIA_SPEED` | `1.0` | Speech speed |
| `CARTESIA_EMOTION` | `calm` | Voice emotion |
| `KOKORO_URL` | `localhost:7693` | MimikaStudio backend URL |
| `KOKORO_VOICE` | `bm_george` | Kokoro voice (e.g. `bf_emma`, `bm_daniel`) |

## Requirements

- macOS 13+
- `curl`, `python3`, `afplay` (all included with macOS)
- Cartesia API key (cloud mode) or [MimikaStudio](https://github.com/BoltzmannEntropy/MimikaStudio) (local mode)
