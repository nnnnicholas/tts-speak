# tts-speak

Select text anywhere on macOS -> hear it spoken aloud with a modern AI voice. Press again to stop.

Uses [Cartesia](https://cartesia.ai) by default and keeps [Kokoro](https://github.com/BoltzmannEntropy/MimikaStudio) available as an explicit local-only option.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/nnnnicholas/tts-speak/main/install.sh | bash
```

This will:
- Clone the repo to `~/.local/share/tts-speak`
- Symlink `tts-speak` to `~/.local/bin/`
- Create a config file at `~/.config/tts-speak.env`
- Install a macOS Quick Action for the right-click menu

The base script needs no sudo, no brew, and no dependencies beyond what macOS ships with. If `swiftc` is available, install also builds the optional native stop control locally on that Mac.

Then add your Cartesia API key ([get one here](https://play.cartesia.ai)):

```bash
nano ~/.config/tts-speak.env
```

## Usage

**Right-click** selected text → Services → **Speak with AI**

Or assign a keyboard shortcut:
1. System Settings → Keyboard → Keyboard Shortcuts → Services → Text
2. Find "Speak with AI" and set your preferred shortcut

The script shows a temporary stop control while TTS is generating or speaking. By default it uses a small floating stop button, which is more reliable if you use Bartender or another menu bar organizer. Set `TTS_STATUS_UI=menubar` if you want a menu bar icon instead, or `TTS_STATUS_UI=none` for notifications only.

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

If your top-row key does not arrive as `f4` on your keyboard, use Karabiner-EventViewer to confirm the key name and swap it in the rule above.

## Configuration

Edit `~/.config/tts-speak.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `TTS_ENGINE` | `cartesia` | `cartesia` (cloud) or `kokoro` (local) |
| `TTS_STATUS_UI` | `floating` | `floating`, `menubar`, or `none` |
| `CARTESIA_API_KEY` | — | Your Cartesia API key |
| `CARTESIA_VOICE_ID` | `c8f7835e-28a3-4f0c-80d7-c1302ac62aae` | Voice ID to use ([browse voices](https://play.cartesia.ai)) |
| `CARTESIA_SPEED` | `1.0` | Speech speed |
| `CARTESIA_EMOTION` | `calm` | Voice emotion |
| `KOKORO_URL` | `http://localhost:7693` | MimikaStudio backend URL |
| `KOKORO_VOICE` | `bm_george` | Kokoro voice (e.g. `bf_emma`, `bm_daniel`) |

## Requirements

- macOS 13+
- `curl`, `python3`, `afplay` (all included with macOS)
- Cartesia API key (cloud mode) or [MimikaStudio](https://github.com/BoltzmannEntropy/MimikaStudio) (local mode)
