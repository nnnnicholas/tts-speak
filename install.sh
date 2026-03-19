#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Symlink script to PATH
mkdir -p ~/.local/bin
ln -sf "$SCRIPT_DIR/tts-speak.sh" ~/.local/bin/tts-speak
chmod +x "$SCRIPT_DIR/tts-speak.sh"
echo "Linked tts-speak to ~/.local/bin/tts-speak"

# Copy env file if not already present
if [[ ! -f ~/.config/tts-speak.env ]]; then
  cp "$SCRIPT_DIR/tts-speak.env.example" ~/.config/tts-speak.env
  echo "Created ~/.config/tts-speak.env — fill in your API key and voice ID"
else
  echo "~/.config/tts-speak.env already exists, skipping"
fi

# Install Automator Quick Action
WORKFLOW_SRC="$SCRIPT_DIR/Speak with AI.workflow"
WORKFLOW_DST="$HOME/Library/Services/Speak with AI.workflow"
if [[ -d "$WORKFLOW_SRC" ]]; then
  rm -rf "$WORKFLOW_DST"
  cp -R "$WORKFLOW_SRC" "$WORKFLOW_DST"
  echo "Installed Quick Action to ~/Library/Services/"
fi

echo ""
echo "Done! To assign Option+Esc:"
echo "  1. System Settings → Keyboard → Keyboard Shortcuts → Services"
echo "  2. Find 'Speak with AI' under Text"
echo "  3. Double-click to set shortcut to ⌥⎋ (Option+Escape)"
echo "  4. Disable built-in 'Speak selection' in Accessibility → Spoken Content if needed"
