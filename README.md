# Dictation (macOS + MLX)

Local macOS dictation app:
- Hold `Fn` to record
- Release `Fn` to transcribe
- Text is pasted into the focused text field

## Requirements

- macOS (Apple Silicon recommended)
- `uv`
- Xcode Command Line Tools
- For `whisperkit` provider: WhisperKit local server running (see section below)

## Fresh Start (first time)

```bash
cp .env.example .env
./scripts/dictation.sh setup
```

### Code signing (do this before your first build)

By default the app is ad-hoc signed, which means macOS treats every
rebuild as a new app and re-asks for permissions. To avoid this:

```bash
./scripts/codesign-create.sh
```

Then add to `.env`:
```bash
DICTATION_CODESIGN_IDENTITY=DictationDev
```

If you have an Apple Developer account you can use `Apple Development`
instead of a self-signed certificate.

To remove the certificate later:
```bash
./scripts/codesign-remove.sh
```

### Build and run

```bash
./scripts/dictation.sh bundle --install
```

1. Start backend in terminal 1:
```bash
./scripts/dictation.sh serve
```
The backend creates a local auth token file at `~/.dictation/asr-token` (override with `DICTATION_ASR_TOKEN_FILE`).
2. Start app:
```bash
open "$HOME/Applications/Dictation.app"
```
3. Grant `Dictation.app` permissions:
- Microphone
- Accessibility
- Input Monitoring
4. (Optional) Choose a specific microphone from the menu bar icon:
- `Microphone -> <device name>`

5. Quit app and reopen using same method as above.

## Already Downloaded (normal daily use)

1. Start backend:
```bash
./scripts/dictation.sh serve
```
2. Open app:
```bash
open "$HOME/Applications/Dictation.app"
```
3. (Optional) Select input device from:
- `Microphone -> <device name>`

## After Pulling Code Updates

1. Pull:
```bash
git pull
```
2. If Python dependencies or model defaults changed, run:
```bash
./scripts/dictation.sh setup
```
3. Always restart backend:
```bash
./scripts/dictation.sh serve
```
4. If Swift app code changed (`Sources/`, `Package.swift`), rebuild app:
```bash
./scripts/dictation.sh bundle --install
open "$HOME/Applications/Dictation.app"
```

## Reset Permissions (delete + re-grant)

If you need to reset permissions for any reason:

1. Quit app:
```bash
pkill -f Dictation || true
```
2. Reset TCC entries for your bundle id:
```bash
BID="$(rg '^DICTATION_BUNDLE_ID=' .env | cut -d= -f2)"
tccutil reset Accessibility "$BID"
tccutil reset ListenEvent "$BID"
tccutil reset Microphone "$BID"
```
3. Rebuild/install and reopen:
```bash
./scripts/dictation.sh bundle --install
open "$HOME/Applications/Dictation.app"
```
4. Re-enable `Dictation.app` in:
- Privacy & Security -> Accessibility
- Privacy & Security -> Input Monitoring
- Privacy & Security -> Microphone

## Uninstall

```bash
# 1. Quit the app
pkill -f Dictation || true

# 2. Remove the app
rm -rf "$HOME/Applications/Dictation.app"

# 3. Remove permissions macOS stored for the app
BID="$(grep '^DICTATION_BUNDLE_ID=' .env | cut -d= -f2)"
tccutil reset Accessibility "$BID"
tccutil reset ListenEvent "$BID"
tccutil reset Microphone "$BID"

# 4. Remove the signing certificate (if you created one)
./scripts/codesign-remove.sh

# 5. Remove downloaded models and build artifacts
rm -rf models/ dist/ .build/ .venv/ .uv-cache/
```

## Config (`.env`)

Main vars:
- `DICTATION_ASR_PROVIDER` (`qwen` or `whisperkit`, default: `qwen`)
- `DICTATION_MODEL` (default: `mlx-community/Qwen3-ASR-1.7B-8bit`)
- `DICTATION_MODEL_DIR` (default: `models/Qwen3-ASR-1.7B-8bit`)
- `DICTATION_TMP_DIR` (default: OS temp dir + `/dictation-asr`)
- `DICTATION_WHISPERKIT_ENDPOINT` (default: `http://127.0.0.1:50060/v1/audio/transcriptions`)
- `DICTATION_WHISPERKIT_MODEL` (default: `large-v3`)
- `DICTATION_WHISPERKIT_TIMEOUT_SECONDS` (default: `30`)
- `DICTATION_WHISPERKIT_LANGUAGE` (optional; e.g. `en`)
- `DICTATION_WHISPERKIT_PROMPT` (optional prompt text for transcription guidance)
- `DICTATION_LOG_TRANSCRIPTS` (default: `true`)
- `DICTATION_ASR_TOKEN_FILE` (default: `~/.dictation/asr-token`)
- `DICTATION_CLEANUP_ENABLED` (default: `false`) enables post-processing with Apple Foundation Models
- `DICTATION_CLEANUP_INSTRUCTIONS` (default: built-in cleanup prompt) controls cleanup behavior
- `DICTATION_CLEANUP_USER_DICTIONARY` (optional comma/newline-separated terms) preferred canonical spellings for cleanup correction
- `DICTATION_ASR_HOST` (default: `127.0.0.1`)
- `DICTATION_ASR_PORT` (default: `8765`)
- `DICTATION_BUNDLE_ID` (default: `com.example.dictation`)
- `DICTATION_CODESIGN_IDENTITY` (default: `-` for ad-hoc; set to a certificate name like `DictationDev` to persist permissions across rebuilds)

### Optional: Apple Foundation Model cleanup pass

To run Qwen transcription through Apple Foundation Models for cleanup:

1. Install Apple SDK locally:
```bash
uv pip install -e ./.external
```
2. In `.env`:
```bash
DICTATION_CLEANUP_ENABLED=true
```

When enabled, raw transcript text is rewritten to remove filler words, pauses, stutters, and false starts while preserving intended meaning.

### ASR provider options

#### Provider: Qwen (default)

1. Set in `.env`:
```bash
DICTATION_ASR_PROVIDER=qwen
```
2. Setup/download model:
```bash
./scripts/dictation.sh setup
```
3. Start backend:
```bash
./scripts/dictation.sh serve
```

#### Provider: WhisperKit

1. Set in `.env`:
```bash
DICTATION_ASR_PROVIDER=whisperkit
DICTATION_WHISPERKIT_ENDPOINT=http://127.0.0.1:50060/v1/audio/transcriptions
DICTATION_WHISPERKIT_MODEL=large-v3
```
2. Start WhisperKit local server separately (example):
```bash
whisperkit-cli serve --host 127.0.0.1 --port 50060
```
3. Start this backend:
```bash
./scripts/dictation.sh serve
```
