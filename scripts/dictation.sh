set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

load_env() {
  if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a
    source "$ROOT_DIR/.env"
    set +a
  fi
  if [[ -f "$ROOT_DIR/.env.local" ]]; then
    set -a
    source "$ROOT_DIR/.env.local"
    set +a
  fi
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/dictation.sh setup
  ./scripts/dictation.sh serve
  ./scripts/dictation.sh app
  ./scripts/dictation.sh bundle [--install]

Commands:
  setup   Install Python deps with uv and download model files
  serve   Run ASR service (uvicorn)
  app     Run the menu bar app in dev mode (swift run)
  bundle  Build standalone Dictation.app (optional --install to ~/Applications)
EOF
}

setup_cmd() {
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv is required. Install it first: https://docs.astral.sh/uv/getting-started/installation/"
    exit 1
  fi

  UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}" uv sync --prerelease=allow

  echo "uv environment ready."
  ASR_PROVIDER="${DICTATION_ASR_PROVIDER:-qwen}"
  if [[ "$ASR_PROVIDER" == "qwen" ]]; then
    MODEL_ID="${DICTATION_MODEL:-mlx-community/Qwen3-ASR-1.7B-6bit}"
    LOCAL_DIR="${DICTATION_MODEL_DIR:-models/Qwen3-ASR-1.7B-6bit}"
    UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}" uv run huggingface-cli download --local-dir "$LOCAL_DIR" "$MODEL_ID"
    echo "Qwen model downloaded to: $LOCAL_DIR"
  else
    echo "Skipping local model download for provider: $ASR_PROVIDER"
  fi
}

serve_cmd() {
  HOST="${DICTATION_ASR_HOST:-127.0.0.1}"
  PORT="${DICTATION_ASR_PORT:-8765}"

  UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}" exec uv run uvicorn src.main:app --host "$HOST" --port "$PORT"
}

app_cmd() {
  swift run open-whisper
}

bundle_cmd() {
  local install=0
  if [[ "${1:-}" == "--install" ]]; then
    install=1
  elif [[ -n "${1:-}" ]]; then
    echo "Unknown bundle option: $1"
    usage
    exit 1
  fi

  APP_NAME="Dictation"
  BUNDLE_ID="${DICTATION_BUNDLE_ID:-com.example.dictation}"
  APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
  BIN_SRC="$ROOT_DIR/.build/release/open-whisper"
  BIN_DST="$APP_DIR/Contents/MacOS/$APP_NAME"
  PLIST="$APP_DIR/Contents/Info.plist"

  echo "Building release binary..."
  swift build -c release

  echo "Creating app bundle at: $APP_DIR"
  rm -rf "$APP_DIR"
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

  cp "$BIN_SRC" "$BIN_DST"
  chmod +x "$BIN_DST"

  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Dictation needs microphone access to transcribe your speech.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

  SIGN_IDENTITY="${DICTATION_CODESIGN_IDENTITY:--}"
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
  fi

  if [[ "$install" == "1" ]]; then
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/${APP_NAME}.app"
    cp -R "$APP_DIR" "$INSTALL_DIR/${APP_NAME}.app"
    APP_DIR="$INSTALL_DIR/${APP_NAME}.app"
    echo "Installed to: $APP_DIR"
  fi

  echo
  echo "Done."
  echo "Open with:"
  echo "  open \"$APP_DIR\""
}

load_env

case "${1:-}" in
  setup)
    shift
    setup_cmd "$@"
    ;;
  serve)
    shift
    serve_cmd "$@"
    ;;
  app)
    shift
    app_cmd "$@"
    ;;
  bundle)
    shift
    bundle_cmd "$@"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $1"
    usage
    exit 1
    ;;
esac
