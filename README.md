# Dictation (macOS + MLX)

Local macOS dictation app:
- Hold `Fn` to record
- Release `Fn` to transcribe
- Press `Fn + Space` while recording to lock recording mode; press `Fn` again to stop and transcribe
- Configure provider/cleanup/dictionary in app menu -> `Settings...`
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
open "$HOME/Applications/Dictation.app"
```

The app automatically starts and manages the Python backend process.
A local auth token file is created at `~/.dictation/asr-token` (override with `DICTATION_ASR_TOKEN_FILE`).

Grant `Dictation.app` permissions:
- Microphone
- Accessibility
- Input Monitoring
(Optional) Choose a specific microphone from the menu bar icon:
- `Microphone -> <device name>`

## Already Downloaded (normal daily use)

```bash
open "$HOME/Applications/Dictation.app"
```

The backend starts automatically with the app and restarts when you change settings.

## After Pulling Code Updates

```bash
git pull
./scripts/dictation.sh setup          # if Python deps or model defaults changed
./scripts/dictation.sh bundle --install  # if Swift code changed
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

Most users only need:
- `DICTATION_BUNDLE_ID`
- `DICTATION_CODESIGN_IDENTITY`
- `DICTATION_SETTINGS_FILE`

Advanced overrides (optional):
- `DICTATION_PROJECT_ROOT`
- `DICTATION_WHISPERKIT_ENDPOINT`
- `DICTATION_ASR_TOKEN_FILE`

All provider/cleanup/dictionary behavior should be managed in the app `Settings...` window.

Settings precedence:
1. Process environment variables (exported in shell / launch environment)
2. Settings JSON written by the app (`Settings...` window)
3. `.env` / `.env.local`
4. Built-in defaults

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

Set in `.env`:
```bash
DICTATION_ASR_PROVIDER=qwen
```
Download model:
```bash
./scripts/dictation.sh setup
```

#### Provider: WhisperKit

Set in `.env`:
```bash
DICTATION_ASR_PROVIDER=whisperkit
DICTATION_WHISPERKIT_ENDPOINT=http://127.0.0.1:50060/v1/audio/transcriptions
DICTATION_WHISPERKIT_MODEL=large-v3
```
Start WhisperKit local server separately:
```bash
whisperkit-cli serve --host 127.0.0.1 --port 50060
```
