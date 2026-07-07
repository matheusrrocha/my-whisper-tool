# WhisperFlow

[![CI](https://github.com/matheusrrocha/my-whisper-tool/actions/workflows/ci.yml/badge.svg)](https://github.com/matheusrrocha/my-whisper-tool/actions/workflows/ci.yml)

A local, private [Wisprflow](https://wisprflow.ai)-style dictation app for macOS.
Hold a key, speak, release — your words are typed into whatever app you're using.
Everything runs on-device with [WhisperKit](https://github.com/argmaxinc/WhisperKit)
(Whisper as CoreML models on the Neural Engine/GPU). No audio ever leaves your Mac.

## How it works

- **Menu bar app** (no Dock icon). Idle, the icon is a ringed waveform "voice
  button"; while recording it becomes live waveform bars that move with your
  voice, and it pulses while transcribing.
- **Hold-to-talk**: hold the bound key (default **Right Option ⌥**), speak,
  release. The transcription is pasted at your cursor.
- **Any key binding**: menu → Hold Key → *Press New Shortcut…* and press what
  you want — a lone modifier (Right ⌥, Fn, …), an F-key (F13 is great if you
  have it), or a modifier combo (⌃⌥Space). Non-modifier bindings are swallowed
  system-wide while held so they don't type into your apps.
- **Pick your microphone**: menu → Input Device lists all connected mics;
  choose your dedicated one or leave it on System Default.
- Typing any other key while holding the hotkey cancels the dictation, so
  Option-key accents and shortcuts don't misfire.
- Recordings shorter than ~0.35 s are discarded (accidental taps).
- The previous clipboard is restored ~0.6 s after pasting (can be disabled).

## Building

Requires the Swift toolchain from Homebrew (the macOS 27 beta Command Line
Tools have a broken SwiftPM; on machines with a working Xcode the plain
`swift` is used automatically):

```sh
brew install swift
./scripts/make-signing-cert.sh   # once — see "Signing" below
./scripts/build-app.sh
open build/WhisperFlow.app
```

Run tests with `swift test` (uses Swift Testing).

## Signing

`scripts/make-signing-cert.sh` creates a self-signed "WhisperFlow Signing"
certificate in your login keychain, and `build-app.sh` signs with it when
present. A stable identity keeps macOS permission grants (Accessibility,
Microphone) valid across rebuilds. Without it the app is ad-hoc signed and
you must re-enable Accessibility after every rebuild.

## First run

1. **Microphone** — allow when prompted.
2. **Accessibility** — needed for the global hotkey and for pasting. Use menu →
   Permissions → Accessibility to open the right System Settings pane. The
   hotkey starts working seconds after you grant it — no relaunch needed.
3. The default model (`large-v3-turbo`, ~1.6 GB) downloads automatically on
   first launch to `~/Library/Application Support/WhisperFlow/`. The menu shows
   progress; the first load also compiles the model for the Neural Engine,
   which can take a minute or two. After that, loading is fast.

If you bind **Fn / Globe**, set System Settings → Keyboard → "Press 🌐 key
to" → **Do Nothing** so it doesn't also trigger macOS features.

## Menu options

- **Hold Key** — presets or record any shortcut.
- **Input Device** — which microphone to record from.
- **Language** — auto-detect (default) or force a language.
- **Model** — from `base` (fastest) to `large-v3-turbo` (most accurate).
  Switching models downloads them on demand.
- **Permissions** — live Microphone/Accessibility status; click to open
  System Settings.
- **Sound Feedback**, **Restore Clipboard After Paste**, **Launch at Login**.

## Development

Git flow: `main` holds releases, day-to-day work lands on `develop` (branch
feature branches off it). CI (GitHub Actions, macOS runner) builds, tests, and
uploads a packaged `WhisperFlow.app` artifact for pushes and PRs to either
branch.

```
Sources/WhisperFlow/
  App.swift                  entry point
  AppDelegate.swift          wiring + permission prompts
  DictationController.swift  idle → recording → transcribing state machine
  HotkeyMonitor.swift        CGEvent-tap hold-to-talk key monitoring
  ShortcutCapture.swift      "press new shortcut" recorder panel
  AudioRecorder.swift        AVAudioEngine capture → 16 kHz mono + level meter
  TranscriptionEngine.swift  WhisperKit download/load/transcribe
  TextInserter.swift         paste-at-cursor via clipboard + synthetic Cmd+V
  StatusItemController.swift menu bar icon, waveform animation, menu
  Settings.swift             UserDefaults-backed preferences
Tests/WhisperFlowTests/      unit tests (Swift Testing)
scripts/                     build-app.sh, make-signing-cert.sh, Info.plist
```
