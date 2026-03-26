# Voice Hotkey

**Hold Right Command. Speak. Text appears wherever your cursor is.**

System-wide push-to-talk voice input for macOS. Uses local Whisper transcription — no API calls, no cloud, instant. Works in any app: terminal, browser, Slack, Notion, anywhere.

## Demo

```
Hold Right ⌘  →  🔴 Recording...
Release      →  ⏹ Transcribing... (< 1 second)
              →  ✅ Text auto-pasted into active app
```

## Setup

### 1. Install dependencies
```bash
brew install sox whisper-cpp
```

### 2. Build
```bash
cd voice-hotkey
chmod +x build.sh
./build.sh
```

### 3. Grant permissions

macOS requires Input Monitoring access:
- System Settings → Privacy & Security → Input Monitoring → Add VoiceHotkey

### 4. Run
```bash
# Run directly
.build/release/VoiceHotkey

# Or install as a LaunchAgent (auto-start on login)
cp com.voicehotkey.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.voicehotkey.plist
```

## How It Works

1. Swift app monitors Right Command key via `NSEvent.addGlobalMonitorForEvents`
2. On press: starts `sox` recording (16kHz mono WAV)
3. On release: stops recording, runs `whisper-cli` locally
4. Copies transcription to clipboard
5. Auto-pastes via `CGEvent` (simulates Cmd+V)

Everything runs locally. No internet required. No API keys.

## Requirements

- macOS 13+ (Ventura or later)
- Apple Silicon (M1/M2/M3/M4) recommended
- `sox` — audio recording
- `whisper-cpp` — local transcription
- Xcode Command Line Tools

## Configuration

Edit `main.swift` to customize:
- **Whisper model**: Default is `ggml-tiny.en.bin` (fastest). Use `ggml-base.en.bin` for better accuracy.
- **Trigger key**: Default is Right Command. Change `keyCode == 0x36` to any key.
- **Sample rate**: Default 16kHz. Whisper works best at 16kHz.

## Troubleshooting

**"Input monitoring denied"**
→ System Settings → Privacy & Security → Input Monitoring → Add VoiceHotkey
→ If already added, run: `tccutil reset InputMonitoring`

**No audio recorded**
→ Check microphone permissions: System Settings → Privacy & Security → Microphone
→ Verify sox works: `sox -t coreaudio default test.wav` then play it back

**Slow transcription**
→ Use the tiny model (default) for speed
→ Apple Silicon runs whisper.cpp natively — Intel Macs will be slower

## License

MIT — Built by [MyndAIX](https://myndaix.com)
