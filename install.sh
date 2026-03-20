#!/bin/bash
set -euo pipefail

# tts-speak installer
# One-liner: curl -fsSL https://raw.githubusercontent.com/nnnnicholas/tts-speak/main/install.sh | bash

INSTALL_DIR="${HOME}/.local/share/tts-speak"
BIN_DIR="${HOME}/.local/bin"
CONFIG_FILE="${HOME}/.config/tts-speak.env"
SERVICES_DIR="${HOME}/Library/Services"

echo "=== tts-speak installer ==="
echo ""

# Clone or update repo
if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating existing installation..."
  git -C "$INSTALL_DIR" pull --quiet
else
  echo "Downloading tts-speak..."
  # If running from inside the repo, use that. Otherwise clone.
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" 2>/dev/null && pwd)" || SCRIPT_DIR=""
  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/tts-speak.sh" ]]; then
    INSTALL_DIR="$SCRIPT_DIR"
  else
    git clone --quiet https://github.com/nnnnicholas/tts-speak.git "$INSTALL_DIR"
  fi
fi

# Symlink script to PATH
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/tts-speak.sh" "$BIN_DIR/tts-speak"
chmod +x "$INSTALL_DIR/tts-speak.sh"
echo "✓ Linked tts-speak to $BIN_DIR/tts-speak"

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  echo ""
  echo "⚠ Add ~/.local/bin to your PATH. Add this to your ~/.zshrc:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
fi

# Create config
mkdir -p "$(dirname "$CONFIG_FILE")"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$INSTALL_DIR/tts-speak.env.example" "$CONFIG_FILE"
  echo "✓ Created config at $CONFIG_FILE"
  echo ""
  echo "⚠ Add your Cartesia API key:"
  echo "  \$EDITOR $CONFIG_FILE"
  echo ""
  echo "  Get a key at https://play.cartesia.ai"
  echo ""
else
  echo "✓ Config already exists at $CONFIG_FILE"
fi

# Install Automator Quick Action (right-click menu)
if [[ -d "$INSTALL_DIR/Speak with AI.workflow" ]]; then
  mkdir -p "$SERVICES_DIR"
  rm -rf "$SERVICES_DIR/Speak with AI.workflow"
  cp -R "$INSTALL_DIR/Speak with AI.workflow" "$SERVICES_DIR/"
  echo "✓ Installed 'Speak with AI' Quick Action (right-click menu)"
fi

# Install hotkey wrapper
if [[ -f "$INSTALL_DIR/tts-speak-hotkey.sh" ]]; then
  ln -sf "$INSTALL_DIR/tts-speak-hotkey.sh" "$BIN_DIR/tts-speak-hotkey"
  chmod +x "$INSTALL_DIR/tts-speak-hotkey.sh"
  echo "✓ Linked tts-speak-hotkey"
fi

# Build and install the optional menu bar status helper
if [[ -f "$INSTALL_DIR/tts-speak-status.swift" ]]; then
  if command -v swiftc >/dev/null 2>&1; then
    rm -f "$BIN_DIR/tts-speak-status"
    if swiftc "$INSTALL_DIR/tts-speak-status.swift" -o "$BIN_DIR/tts-speak-status"; then
      chmod +x "$BIN_DIR/tts-speak-status"
      echo "✓ Built optional tts-speak-status menu bar helper"
    else
      echo "⚠ Skipped optional menu bar helper: local Swift build failed."
    fi
  else
    echo "ℹ Skipped optional menu bar helper: swiftc not found."
  fi
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Usage:"
echo "  • Right-click selected text → Services → Speak with AI"
echo "  • Or assign a keyboard shortcut:"
echo "    System Settings → Keyboard → Keyboard Shortcuts → Services → Text"
echo ""
echo "Optional: Use Karabiner-Elements to bind a function key (e.g. F4)."
echo "See README for details."
